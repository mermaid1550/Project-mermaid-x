extends RefCounted
## AI-Pet: persönlicher Tutor-Begleiter (Phase 1 Lokal-Version).
##
## Diese Klasse ist der Austauschpunkt für dein echtes Backend:
## sobald dein Server steht, ersetze `respond()` durch einen REST-Call
## (HTTPRequest / dein eigener Proxy), damit der API-Key des LLMs
## niemals im Client liegt. Die UI muss dafür nicht geändert werden.

# Kleiner Vokabel-Schatz: Chinesisch -> Englisch (mit Pinyin).
var _vocab: Array[Dictionary] = [
	{"cn": "你好", "pinyin": "nǐ hǎo", "en": "hello"},
	{"cn": "谢谢", "pinyin": "xiè xie", "en": "thank you"},
	{"cn": "朋友", "pinyin": "péng you", "en": "friend"},
	{"cn": "学校", "pinyin": "xué xiào", "en": "school"},
	{"cn": "城市", "pinyin": "chéng shì", "en": "city"},
	{"cn": "龙", "pinyin": "lóng", "en": "dragon"},
	{"cn": "学习", "pinyin": "xué xí", "en": "to learn"},
]

# Einfache IT-Glossar-Antworten.
var _it_terms: Dictionary = {
	"api": "API = Application Programming Interface. Ein Vertrag zwischen zwei Programmen: dein Spiel fragt, der Server antwortet (meist als JSON über HTTP).",
	"server": "Server = Ein Rechner/Programm, der Daten hält und Anfragen beantwortet. Für Lóng Chéng z.B. Spielstände, Lobbys, In-Game-Währung.",
	"client": "Client = Das, was auf dem Gerät des Spielers läuft – in unserem Fall die Godot-4-Anwendung.",
	"database": "Database = Strukturierter Datenspeicher (z.B. Supabase/Postgres). Hier liegen Accounts, Inventar und Level-Fortschritt.",
	"latency": "Latency = Die Verzögerung (ms) zwischen Aktion und Reaktion. Für Multiplayer-Netzwerke entscheidend – ENet misst sie für dich.",
	"multiplayer": "Multiplayer = Mehrere Spieler teilen sich einen simulierten Zustand. Godot: MultiplayerAPI/ENet synchronisiert Zustände zwischen Host und Clients.",
}

var _quiz_word: Dictionary = {}
var _quiz_active: bool = false


## Haupt-Einstieg: Spieler-Text -> Pet-Antwort.
func respond(player_text: String) -> String:
	var t := player_text.strip_edges().to_lower()
	if t.is_empty():
		return "Ich bin hier. Frag mich etwas – z. B. „Vokabeln üben“ oder „Was ist eine API?“."

	# Quiz-Runde beantworten?
	if _quiz_active:
		return _check_quiz_answer(t)

	# Begrüßung
	if t in ["hi", "hallo", "hello", "hey", "moin"]:
		return "Hallo! 🐲 Ich bin dein Lóng-Pet. Ich kann Vokabeln mit dir üben (Chinesisch/Englisch) oder IT-Begriffe erklären. Was sollen wir machen?"

	# Vokabel-Training starten
	if _contains_any(t, ["vokabel", "quiz", "chinesisch", "üben", "uben", "lernen", "wortschatz"]):
		return _start_quiz()

	# IT-Erklärungen
	for term in _it_terms:
		if t.contains(term) and _it_terms[term] != "":
			return _it_terms[term]

	# Hilfs-Antwort
	if _contains_any(t, ["hilfe", "help", "was kannst du"]):
		return "Ich kann:\n• Vokabeln üben – schreib „Vokabeln üben“\n• IT-Begriffe erklären – z.B. „Was ist eine API?“\n• Dich in die Stadt führen – schreib „Zeig die Stadt”"

	# Lokale KI-Antwort (Platzhalter, bis dein Backend steht)
	return "Das klingt nach einer guten Frage. 🐲 Meine echte KI-Antwort kommt, sobald dein Backend mit dem LLM verbunden ist – bis dahin üben wir Vokabeln oder IT-Begriffe. Schreib „Vokabeln üben“, wenn du starten willst."


func _start_quiz() -> String:
	_quiz_word = _vocab.pick_random()
	_quiz_active = true
	return "Vokabelrunde! 📚\n\nWie sagt man auf Englisch: „%s“ (%s)?" % [_quiz_word["cn"], _quiz_word["pinyin"]]


func _check_quiz_answer(player_answer: String) -> String:
	var correct: String = _quiz_word["en"]
	_quiz_active = false
	if player_answer == correct or correct.contains(player_answer) and player_answer.length() > 2:
		return "Richtig! ✅ „%s“ = „%s“ (%s)\nNächste Runde? Schreib einfach „Vokabeln üben“." % [_quiz_word["cn"], correct, _quiz_word["pinyin"]]
	return "Fast! Die richtige Antwort ist „%s“ – „%s“ (%s). %s = %s. Nochmal versuchen?" % [
		correct, _quiz_word["cn"], _quiz_word["pinyin"], _quiz_word["cn"], correct
	]


func _contains_any(text: String, needles: Array) -> bool:
	for n in needles:
		if text.contains(n):
			return true
	return false
