class_name PetChat
extends VBoxContainer
## Chat-Oberfläche des AI-Pets: Nachrichtenlog + Eingabefeld.
## Das UI baut sich selbst auf, damit die Szene eine reine Wurzel bleibt
## und der Chat überall (auch in anderen Lobbys) wiederverwendet ist.

signal message_sent(text: String)

const AI_Pet := preload("res://scripts/ai_pet.gd")

var _log: RichTextLabel
var _input: LineEdit
var _send_button: Button
var _ai := AI_Pet.new()


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

	_append_system("Willkommen in Lóng Chéng! 🐲 Ich bin dein Lern-Pet. Schreib „Vokabeln üben“, „Was ist eine API?“ oder „Hilfe“.")


func _on_send(text: String) -> void:
	var clean := text.strip_edges()
	if clean.is_empty():
		return
	_input.clear()
	_append_player(clean)
	message_sent.emit(clean)

	# Später: hier der REST-Call an dein Backend (Phase 1.5).
	# LLM-Antworten laufen NIE direkt aus dem Client – immer über deinen Server.
	var answer := _ai.respond(clean)
	_append_pet(answer)


func _append_player(text: String) -> void:
	_log.append_text("\n[b][color=#7ec8ff]Du:[/color][/b] %s" % text)


func _append_pet(text: String) -> void:
	_log.append_text("\n[b][color=#ffb347]Pet:[/color][/b] %s" % text)


func _append_system(text: String) -> void:
	_log.append_text("\n[i][color=#9aa5b1]%s[/color][/i]" % text)
