"""Headless-Test des AI-Pet-Backends – ohne pytest, nur Standardbibliothek.

Startet den Server in einem Subprozess, prüft Probe + Chat-Fallback und
beendet ihn wieder:

    python3 test_backend.py
"""

from __future__ import annotations

import json
import subprocess
import sys
import time
import urllib.request

BASE = "http://127.0.0.1:8000"


def post(path: str, payload: dict) -> dict:
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=25) as resp:
        return json.loads(resp.read())


def get(path: str) -> dict:
    with urllib.request.urlopen(BASE + path, timeout=10) as resp:
        return json.loads(resp.read())


def main() -> int:
    server = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "main:app", "--port", "8000"],
        cwd=".",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        # Warten, bis der Server antwortet
        for _ in range(60):
            time.sleep(0.5)
            try:
                get("/v1/pet/chat")
                break
            except OSError:
                continue
        else:
            print("FEHLER: Server startet nicht")
            return 1

        # 1. Probe
        probe = get("/v1/pet/chat")
        assert probe["status"] == "ok", f"Probe: {probe}"
        assert probe["ai"] in ("ollama", "local"), f"ai-Quelle: {probe}"
        print(f"OK Probe: {probe}")

        # 2. Chat-Antwort kommt (Ollama oder Offline-Tutor)
        answer = post("/v1/pet/chat", {"prompt": "Vokabeln üben", "user_id": "t1"})
        assert answer["reply"], "leere Antwort"
        assert answer["source"] in ("ollama", "local"), answer
        print(f"OK Chat ({answer['source']}): {answer['reply'][:60]}...")

        # 3. Quiz-Zustand pro user_id: Antwort korrekt prüfen
        if answer["source"] == "local":
            assert "Englisch" in answer["reply"], answer
            # zweite Runde mit falscher Antwort → Korrektur
            followup = post("/v1/pet/chat", {"prompt": "wronganswer", "user_id": "t1"})
            assert "richtige Antwort" in followup["reply"], followup
            print("OK Quiz-Zustand + Korrektur")

        # 4. IT-Erklärung (nur Offline-Tutor, Ollama antwortet frei)
        if answer["source"] == "local":
            it = post("/v1/pet/chat", {"prompt": "Was ist eine API?", "user_id": "t2"})
            assert "Application Programming Interface" in it["reply"], it
            print("OK IT-Glossar")

        # 5. user_id-Isolation: t2 hat keinen offenen Quiz-Zustand von t1
        if answer["source"] == "local":
            iso = post("/v1/pet/chat", {"prompt": "wronganswer", "user_id": "t2"})
            assert "Englisch" not in iso["reply"], iso
            print("OK User-Isolation")

        print("BACKEND-CHECKS BESTANDEN ✔")
        return 0
    finally:
        server.terminate()
        server.wait(timeout=10)


if __name__ == "__main__":
    sys.exit(main())
