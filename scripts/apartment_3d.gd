extends Node3D
## Private Lobby (Cozy Friends Room, GDD-Kapitel 3.3): das Apartment.
## Komplett prozedural aufgebaut – kein externes Asset nötig – und über
## das AI-Pet die Verbindung zum Backend. Hier treffen sich Freunde.

const PetChatScript := preload("res://scripts/pet_chat.gd")

var player: CharacterBody3D


func _ready() -> void:
	_build_room()
	_build_furniture()
	_build_lighting()

	player = preload("res://scenes/player.tscn").instantiate()
	player.position = Vector3(0, 0.5, 0)
	add_child(player)

	_build_ui()


func _build_room() -> void:
	# Boden: dunkles Holz
	_add_box(Vector3(0, -0.1, 0), Vector3(8, 0.2, 8), Color(0.25, 0.16, 0.1), true)
	# Decke
	_add_box(Vector3(0, 3.1, 0), Vector3(8, 0.2, 8), Color(0.12, 0.1, 0.14), false)
	# Wände (Nord, Süd mit Türöffnung, Ost, West)
	var wall := Color(0.32, 0.26, 0.38)
	_add_box(Vector3(0, 1.5, -4), Vector3(8, 3, 0.2), wall, true)
	_add_box(Vector3(-4, 1.5, 0), Vector3(0.2, 3, 8), wall, true)
	_add_box(Vector3(4, 1.5, 0), Vector3(0.2, 3, 8), wall, true)
	# Südwand mit Fensteröffnung: drei Segmente
	_add_box(Vector3(-3, 1.5, 4), Vector3(2, 3, 0.2), wall, true)
	_add_box(Vector3(3, 1.5, 4), Vector3(2, 3, 0.2), wall, true)
	_add_box(Vector3(0, 0.5, 4), Vector3(4, 1, 0.2), wall, true)
	_add_box(Vector3(0, 2.6, 4), Vector3(4, 0.8, 0.2), wall, true)
	# Neon-Fenster: leuchtende Scheibe (Skyline-Andeutung)
	_add_box(Vector3(0, 1.8, 4.05), Vector3(3.8, 1.4, 0.05), Color(0.15, 0.85, 1.0), false, true)


func _build_furniture() -> void:
	# Sofa
	var sofa := Color(0.55, 0.15, 0.35)
	_add_box(Vector3(-2.5, 0.35, -2.5), Vector3(2.2, 0.5, 1.0), sofa, true)
	_add_box(Vector3(-2.5, 0.75, -2.9), Vector3(2.2, 0.8, 0.25), sofa, false)
	# Couchtisch
	_add_box(Vector3(-2.5, 0.3, -0.8), Vector3(1.4, 0.08, 0.8), Color(0.15, 0.12, 0.1), true)
	# TV an der Nordwand
	_add_box(Vector3(-2.5, 1.6, -3.85), Vector3(2.4, 1.3, 0.08), Color(0.05, 0.05, 0.07), false)
	_add_box(Vector3(-2.5, 1.6, -3.8), Vector3(2.2, 1.1, 0.02), Color(0.2, 0.7, 1.0), false, true)
	# Esstisch mit zwei Stühlen
	_add_box(Vector3(2.5, 0.4, 1.5), Vector3(1.8, 0.08, 1.0), Color(0.4, 0.28, 0.18), true)
	_add_box(Vector3(1.9, 0.2, 1.5), Vector3(0.45, 0.4, 0.45), Color(0.3, 0.2, 0.12), false)
	_add_box(Vector3(3.1, 0.2, 1.5), Vector3(0.45, 0.4, 0.45), Color(0.3, 0.2, 0.12), false)
	# Teppich
	_add_box(Vector3(-2.5, 0.02, -1.5), Vector3(2.8, 0.04, 2.0), Color(0.45, 0.2, 0.5), false)
	# Drachen-Statue (Pet-Andeutung) auf Regal
	_add_box(Vector3(3.8, 1.5, -2.5), Vector3(0.35, 0.5, 0.35), Color(0.9, 0.6, 0.15), false, true)


func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -200, 0)
	sun.light_energy = 0.4
	add_child(sun)

	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.6, 0)
	lamp.light_color = Color(1.0, 0.85, 0.7)
	lamp.light_energy = 1.6
	lamp.omni_range = 7.0
	add_child(lamp)

	var neon := OmniLight3D.new()
	neon.position = Vector3(0, 1.8, 3.5)
	neon.light_color = Color(0.2, 0.85, 1.0)
	neon.light_energy = 1.2
	neon.omni_range = 5.0
	add_child(neon)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.02, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.3, 0.5)
	env.ambient_light_energy = 0.5
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


## Ein Box-Teil mit Material; solid=true erzeugt Kollision (nur für große Teile).
func _add_box(pos: Vector3, size: Vector3, color: Color, solid: bool = false, emissive: bool = false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.1
	mat.roughness = 0.8
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.0
	mesh.material = mat

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	add_child(mi)

	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position = pos
		body.add_child(shape)
		add_child(body)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var chat := PetChatScript.new()
	chat.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	chat.custom_minimum_size = Vector2(380, 0)
	chat.anchor_left = 1.0
	chat.anchor_right = 1.0
	chat.offset_left = -400.0
	chat.offset_top = 16.0
	chat.offset_right = -16.0
	chat.offset_bottom = 500.0
	layer.add_child(chat)

	var back := Button.new()
	back.text = "← Zurück zum Menü  (Maus: Esc)"
	back.position = Vector2(16, 16)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main.tscn"))
	layer.add_child(back)

	var hint := Label.new()
	hint.text = "🏠 Private Lobby – hier kannst du mit Freunden abhängen (Phase 2: Multiplayer)"
	hint.position = Vector2(16, 640)
	layer.add_child(hint)
