extends Control
## Haupt-Szene: Drei-Ebenen-Lobby-Auswahl + AI-Pet-Chat.
## Baut das komplette UI in Code auf, damit die .tscn minimal bleibt.

const PetChatScript := preload("res://scripts/pet_chat.gd")
const NetworkManagerScript := preload("res://scripts/network_manager.gd")

enum Lobby { CLASSROOM, PRIVATE_ROOM, OPEN_WORLD }

var _status: Label
var _chat: PetChat
var _net: Node


func _ready() -> void:
	_net = NetworkManagerScript.new()
	_net.name = "NetworkManager"
	add_child(_net)
	_net.room_changed.connect(_on_room_changed)
	_net.connected.connect(func() -> void: _set_status("🟢 Verbunden"))
	_net.disconnected.connect(func() -> void: _set_status("🔴 Getrennt"))

	_build_ui()
	_set_status("Lokaler Prototyp – noch kein Server")


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	margin.add_child(columns)

	# --- Linke Spalte: Lobby-Auswahl ---
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(460, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(left)

	var title := Label.new()
	title.text = "龍城  Lóng Chéng"
	title.add_theme_font_size_override("font_size", 34)
	left.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Virtuelle Schule · Open World · AI-Pet"
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	left.add_child(subtitle)

	left.add_child(HSeparator.new())

	_status = Label.new()
	left.add_child(_status)

	var lobby_buttons := {
		Lobby.CLASSROOM: ["🏫  Schul-Klasse (Lernen)", "Ruhiger Raum für Vokabeln & Hausaufgaben"],
		Lobby.PRIVATE_ROOM: ["🏠  Private Lobby", "Deine Wohnung für Freunde, Musik & Minispiele"],
		Lobby.OPEN_WORLD: ["🌆  Open World · Lóng Chéng Hub", "Hunderte Spieler, Chats, Minigames, Kosmetik"],
	}

	for lobby_id in lobby_buttons:
		var info: Array = lobby_buttons[lobby_id]
		var btn := Button.new()
		btn.text = info[0]
		btn.custom_minimum_size = Vector2(0, 56)
		btn.pressed.connect(_on_lobby_pressed.bind(lobby_id))
		left.add_child(btn)

		var desc := Label.new()
		desc.text = "     " + info[1]
		desc.add_theme_color_override("font_color", Color(0.55, 0.6, 0.66))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left.add_child(desc)

		left.add_child(VSeparator.new())

	var hint := Label.new()
	hint.text = "Netzwerk (Phase 1): Host/Join über ENet – das NetworkManager-Autoload ist vorbereitet."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
	left.add_child(hint)

	var world_button := Button.new()
	world_button.text = "🌆 3D-Testwelt betreten (Prototyp)"
	world_button.custom_minimum_size = Vector2(0, 48)
	world_button.pressed.connect(_open_world_3d)
	left.add_child(world_button)

	# --- Rechte Spalte: AI-Pet-Chat ---
	_chat = PetChatScript.new()
	columns.add_child(_chat)


func _on_lobby_pressed(lobby: int) -> void:
	var room := ""
	match lobby:
		Lobby.CLASSROOM:
			room = "classroom"
		Lobby.PRIVATE_ROOM:
			room = "private"
		Lobby.OPEN_WORLD:
			room = "hub"
	_net.change_room(room)


func _on_room_changed(room: String) -> void:
	var names := {"classroom": "🏫 Schul-Klasse", "private": "🏠 Private Lobby", "hub": "🌆 Open World Hub"}
	var label: String = names.get(room, room)
	_set_status("Aktueller Raum: " + label)
	_chat._append_system("→ Raum gewechselt: %s" % label)


func _set_status(text: String) -> void:
	_status.text = text


func _open_world_3d() -> void:
	get_tree().change_scene_to_file("res://scenes/world_test_3d.tscn")
