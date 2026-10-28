"""Lóng Chéng AI-Pet Backend (Kapitel 5 der Master-Bible).

    Godot-Client --HTTP--> FastAPI (dieser Server) --> Ollama (lokal, frei)
                                                    \--> lokaler Tutor (Fallback)

Komplett freier Stack: FastAPI (MIT), Uvicorn (BSD), Ollama mit offenen
Modellen (qwen2.5 / deepseek-r1, Apache/Llama-3-Lizenz) – keine API-Keys,
keine Kosten. Ohne laufendes Ollama übernimmt der eingebaute Offline-Tutor,
damit der Chat nie stumm ist.

Start:  uvicorn main:app --port 8000
Tests:  python3 test_backend.py
"""

from __future__ import annotations

import os
from typing import Any

import httpx
from fastapi import FastAPI
from pydantic import BaseModel

OLLAMA_URL = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "qwen2.5:3b")
OLLAMA_TIMEOUT = float(os.environ.get("OLLAMA_TIMEOUT", "20"))
SYSTEM_PROMPT = (
    "Du bist das AI-Pet aus dem Spiel Lóng Chéng (龍城): ein freundlicher "
    "Lernbegleiter. Du hilfst beim Chinesisch- und Englisch-Vokabeltraining "
    "und erklärst IT-Begriffe kurz, korrekt und auf Deutsch. Antworte knapp."
)

app = FastAPI(title="Lóng Chéng AI-Pet Backend", version="1.0")

# ---------------------------------------------------------------- Offline-Tutor
VOCAB = [
    {"cn": "你好", "pinyin": "nǐ hǎo", "en": "hello"},
    {"cn": "谢谢", "pinyin": "xiè xie", "en": "thank you"},
    {"cn": "朋友", "pinyin": "péng you", "en": "friend"},
    {"cn": "学校", "pinyin": "xué xiào", "en": "school"},
    {"cn": "城市", "pinyin": "chéng shì", "en": "city"},
    {"cn": "龙", "pinyin": "lóng", "en": "dragon"},
    {"cn": "学习", "pinyin": "xué xí", "en": "to learn"},
]

IT_TERMS = {
    "api": "API = Application Programming Interface. Ein Vertrag zwischen zwei "
    "Programmen: dein Spiel fragt, der Server antwortet (meist als JSON über HTTP).",
    "server": "Server = Ein Rechner/Programm, der Daten hält und Anfragen beantwortet. "
    "Für Lóng Chéng z.B. Spielstände, Lobbys, In-Game-Währung.",
    "client": "Client = Das, was auf dem Gerät des Spielers läuft – in unserem Fall "
    "die Godot-4-Anwendung.",
    "database": "Database = Strukturierter Datenspeicher (z.B. PostgreSQL). Hier liegen "
    "Accounts, Inventar und Level-Fortschritt.",
    "latency": "Latency = Die Verzögerung (ms) zwischen Aktion und Reaktion. Für "
    "Multiplayer-Netzwerke entscheidend – ENet misst sie für dich.",
    "multiplayer": "Multiplayer = Mehrere Spieler teilen sich einen simulierten Zustand. "
    "Godot: MultiplayerAPI/ENet synchronisiert Zustände zwischen Host und Clients.",
}

# Quiz-Zustand je user_id (in-memory; später in PostgreSQL/Supabase)
_QUIZ: dict[str, dict[str, Any]] = {}


class ChatRequest(BaseModel):
    prompt: str
    user_id: str = "player_lux"


class ChatReply(BaseModel):
    reply: str
    source: str  # "ollama" | "local"


def _local_tutor(user_id: str, prompt: str) -> str:
    t = prompt.strip().lower()
    if not t:
        return "Ich bin hier. Frag mich etwas – z. B. „Vokabeln üben“ oder „Was ist eine API?“."

    quiz = _QUIZ.get(user_id)
    if quiz:
        correct = quiz["en"]
        _QUIZ.pop(user_id, None)
        if t == correct or (len(t) > 2 and correct.find(t) >= 0):
            return (f"Richtig! ✅ „{quiz['cn']}“ = „{correct}“ ({quiz['pinyin']})\n"
                    f"Nächste Runde? Schreib einfach „Vokabeln üben“.")
        return (f"Fast! Die richtige Antwort ist „{correct}“ – „{quiz['cn']}“ "
                f"({quiz['pinyin']}). Nochmal versuchen?")

    if t in ("hi", "hallo", "hello", "hey", "moin"):
        return ("Hallo! 🐲 Ich bin dein Lóng-Pet. Ich kann Vokabeln mit dir üben "
                "(Chinesisch/Englisch) oder IT-Begriffe erklären. Was sollen wir machen?")

    if any(k in t for k in ("vokabel", "quiz", "chinesisch", "üben", "lernen", "wortschatz")):
        import random

        word = random.choice(VOCAB)
        _QUIZ[user_id] = word
        return f"Vokabelrunde! 📚\n\nWie sagt man auf Englisch: „{word['cn']}“ ({word['pinyin']})?"

    for term, text in IT_TERMS.items():
        if term in t:
            return text

    if any(k in t for k in ("hilfe", "help", "was kannst du")):
        return ("Ich kann:\n• Vokabeln üben – schreib „Vokabeln üben“\n"
                "• IT-Begriffe erklären – z.B. „Was ist eine API?“\n"
                "• Dich in die Stadt führen – schreib „Zeig die Stadt“")

    return ("Das klingt nach einer guten Frage. 🐲 Meine echte KI-Antwort kommt, "
            "sobald Ollama läuft – bis dahin üben wir Vokabeln oder IT-Begriffe. "
            "Schreib „Vokabeln üben“, wenn du starten willst.")


async def _ollama_chat(prompt: str) -> str | None:
    """Fragt das lokale Ollama-Modell; None bei jedem Fehler (dann Offline-Tutor)."""
    payload = {
        "model": OLLAMA_MODEL,
        "stream": False,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
        ],
        "options": {"temperature": 0.7},
    }
    try:
        async with httpx.AsyncClient(timeout=OLLAMA_TIMEOUT) as client:
            resp = await client.post(f"{OLLAMA_URL}/api/chat", json=payload)
            if resp.status_code == 200:
                return resp.json().get("message", {}).get("content")
    except (httpx.HTTPError, ValueError):
        return None
    return None


@app.get("/v1/pet/chat")
async def probe() -> dict[str, str]:
    """Health-Probe des Godot-Clients (Statuszeile „Live-Backend“)."""
    status = "local"
    try:
        async with httpx.AsyncClient(timeout=2.0) as client:
            if (await client.get(f"{OLLAMA_URL}/api/tags")).status_code == 200:
                status = "ollama"
    except httpx.HTTPError:
        pass
    return {"status": "ok", "ai": status}


@app.post("/v1/pet/chat", response_model=ChatReply)
async def chat(req: ChatRequest) -> ChatReply:
    reply = await _ollama_chat(req.prompt)
    if reply:
        return ChatReply(reply=reply, source="ollama")
    return ChatReply(reply=_local_tutor(req.user_id, req.prompt), source="local")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=8000)
