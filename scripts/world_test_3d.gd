extends Node3D
## 3D-Testwelt (Hub-Prototyp, Kapitel 3 + 6 der Master-Bible):
## Boden, Licht, Spieler, AI-Pet-Begleiter und ModelLoader in einer Szene.
## Die Welt baut sich komplett in Code auf, damit die .tscn minimal bleibt.

const PlayerScene := preload("res://scenes/player.tscn")
const PetScript := preload("res://scripts/ai_pet_companion_3d.gd")
const LoaderScript := preload("res://scripts/model_loader_3d.gd")

var player: CharacterBody3D
var pet: Node3D
var loader: Node3D
var city: Node3D

# Stadt-Block aus der Asset-Pipeline (tools/ai3d/generate_buildings.py)
const BUILDINGS := [
	{"model": "house", "pos": Vector3(-9, 0, -10), "rot": 0},
	{"model": "house", "pos": Vector3(-3, 0, -10), "rot": 0},
	{"model": "house", "pos": Vector3(3, 0, -10), "rot": 0},
	{"model": "house", "pos": Vector3(9, 0, -10), "rot": 0},
	{"model": "house", "pos": Vector3(-6, 0, 10), "rot": 180},
	{"model": "house", "pos": Vector3(0, 0, 10), "rot": 180},
	{"model": "house", "pos": Vector3(6, 0, 10), "rot": 180},
	{"model": "tower", "pos": Vector3(-18, 0, -4), "rot": 90},
	{"model": "tower", "pos": Vector3(18, 0, 4), "rot": -90},
]



func _ready() -> void:
	_build_environment()
	_build_ground()

	player = PlayerScene.instantiate()
	player.position = Vector3(0, 2, 0)
	add_child(player)

	pet = PetScript.new()
	pet.name = "AIPet"
	pet.position = Vector3(1.2, 1.5, -1.0)  # Startoffset, verhindert kollineares look_at()
	pet.target_player = player
	add_child(pet)

	loader = LoaderScript.new()
	loader.name = "ModelLoader"
	add_child(loader)
	_spawn_city()

	_build_ui()


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.03, 0.08)  # Neon-Nacht-Grundton
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.25, 0.55)
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"

	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	mesh_instance.mesh = plane
	ground.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(60, 1, 60)
	collision.shape = shape
	collision.position.y = -0.5  # Oberkante bei y = 0
	ground.add_child(collision)

	add_child(ground)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var back := Button.new()
	back.text = "← Zurück zum Menü  (Maus: Esc)"
	back.position = Vector2(16, 16)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main.tscn"))
	layer.add_child(back)


## Stadt-Block: lädt Häuser/Türme aus der Asset-Pipeline inkl. Kollision.
func _spawn_city() -> void:
	var loaded_count := 0
	for building in BUILDINGS:
		var path := "res://assets/ai_models/%s.glb" % building["model"]
		var pos: Vector3 = building["pos"]
		var before := loader.get_child_count()
		if loader.load_ai_generated_3d_model(path, pos):
			var model: Node3D = loader.get_child(loader.get_child_count() - 1)
			model.rotation_degrees.y = building["rot"]
			loaded_count += 1
	print("🏙️ Stadt-Block: %d/%d Gebäude geladen" % [loaded_count, BUILDINGS.size()])
