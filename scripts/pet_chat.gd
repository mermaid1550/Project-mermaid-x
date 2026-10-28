class_name PetChat
extends VBoxContainer
## Chat-Oberfläche des AI-Pets: Nachrichtenlog + Eingabefeld.
## Das UI baut sich selbst auf, damit die Szene eine reine Wurzel bleibt
## und der Chat überall (auch in anderen Lobbys) wiederverwendet ist.
##
## Antwort-Quelle (Kapitel 5 der Master-Bible):
##   1. Lokaler FastAPI-Server (→ Ollama DeepSeek/Qwen), sobald er läuft
##   2. Lokale Offline-Logik (ai_pet.gd) als Fallback – Chat nie stumm
## Der LLM-API-Key lebt ausschließlich im Python-Backend, nie im Client.

signal message_sent(text: String)

const AI_Pet := preload("res://scripts/ai_pet.gd")
const AI_BACKEND_URL := "http://127.0.0.1:8000/v1/pet/chat"

var _log: RichTextLabel
var _input: LineEdit
var _send_button: Button
var _status_label: Label
var _http: HTTPRequest
var _ai := AI_Pet.new()
var _awaiting_reply: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(420, 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = "🐲 AI-Pet · Lóng-Begleiter"
	add_child(title)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size = Vector2(0, 300)
	add_child(_log)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 8)
	add_child(input_row)

	_input = LineEdit.new()
	_input.placeholder_text = "Frag dein Pet… (z.B. „Vokabeln üben“)"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(_on_send)
	input_row.add_child(_input)

	_send_button = Button.new()
	_send_button.text = "Senden"
	_send_button.pressed.connect(func() -> void: _on_send(_input.text))
	input_row.add_child(_send_button)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.66))
	add_child(_status_label)

	_http = HTTPRequest.new()
	_http.timeout = 15.0
	add_child(_http)
	_http.request_completed.connect(_on_ai_response_received)

	_probe_backend()
	_append_system("Willkommen in Lóng Chéng! 🐲 Ich bin dein Lern-Pet. Schreib „Vokabeln üben“, „Was ist eine API?“ oder „Hilfe“.")


func _on_send(text: String) -> void:
	var clean := text.strip_edges()
	if clean.is_empty():
		return
	_input.clear()
	_append_player(clean)
	message_sent.emit(clean)

	var body := JSON.stringify({"prompt": clean, "user_id": "player_lux"})
	var headers := PackedStringArray(["Content-Type: application/json"])
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		# Probe läuft noch oder Vorgänger-Request hängt → nicht blockieren
		_append_pet(_ai.respond(clean))
		return
	_awaiting_reply = true
	var err := _http.request(AI_BACKEND_URL, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_awaiting_reply = false
		# Request gar nicht startbar → sofort Offline-Logik
		_append_pet(_ai.respond(clean))


func _on_ai_response_received(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var ok := result == HTTPRequest.RESULT_SUCCESS and response_code == 200
	_set_backend_status(ok)

	if not _awaiting_reply:
		# Antwort auf den Probe-Call: nur Status, keine Chat-Nachricht.
		return
	_awaiting_reply = false

	if ok:
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary and json.data.has("reply"):
			_append_pet(str(json.data["reply"]))
			return
	# Server weg oder kaputte Antwort → Offline-Logik antwortet statt Schweigen.
	_append_pet(_ai.respond(_last_player_message()))


func _probe_backend() -> void:
	# Kleiner HEAD-Check, damit die Statuszeile den Echtzeit-Modus anzeigt.
	var err := _http.request(AI_BACKEND_URL, PackedStringArray(), HTTPClient.METHOD_GET)
	if err != OK:
		_set_backend_status(false)


func _set_backend_status(online: bool) -> void:
	if online:
		_status_label.text = "● Live-Backend verbunden (Ollama-Modell)"
		_status_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
	else:
		_status_label.text = "○ Offline-Tutor aktiv – starte FastAPI-Backend für die echte KI"
		_status_label.add_theme_color_override("font_color", Color(0.75, 0.65, 0.4))


func _last_player_message() -> String:
	# Letzte "[Du]"-Zeile aus dem RichText-Log zurückgewinnen.
	var lines := _log.get_parsed_text().split("\n")
	for i in range(lines.size() - 1, -1, -1):
		if lines[i].begins_with("Du:"):
			return lines[i].substr(4).strip_edges()
	return ""


func _append_player(text: String) -> void:
	_log.append_text("\n[b][color=#7ec8ff]Du:[/color][/b] %s" % text)


func _append_pet(text: String) -> void:
	_log.append_text("\n[b][color=#ffb347]Pet:[/color][/b] %s" % text)


func _append_system(text: String) -> void:
	_log.append_text("\n[i][color=#9aa5b1]%s[/color][/i]" % text)
