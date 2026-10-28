extends SceneTree
## Headless-Check der Bible-Integration: HTTP-Fallback im Pet-Chat,
## 3D-Welt mit Spieler/Pet-Follow, ModelLoader-Rückgabewert.

var _failed: bool = false


func _init() -> void:
	# --- 1. Pet-Chat: Offline-Fallback muss antworten, wenn kein Backend läuft ---
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main: Control = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var chat: Variant = main._chat
	chat._on_send("Vokabeln üben")
	# HTTP-Request ins Leere braucht Frames zum Fehlschlagen → auf Pet-Antwort warten
	var answered := false
	for i in 300:
		await process_frame
		if chat._log.get_parsed_text().count("Pet:") >= 1:
			answered = true
			break
	_assert(answered, "Offline-Fallback antwortet, wenn kein Backend läuft")
	_assert(not chat._awaiting_reply, "Awaiting-Flag ist nach Antwort zurückgesetzt")
	main.free()
	if _failed:
		return

	# --- 2. 3D-Welt: laden, Simulation laufen lassen ---
	var world_scene: PackedScene = load("res://scenes/world_test_3d.tscn")
	var world: Node3D = world_scene.instantiate()
	root.add_child(world)
	# Warten, bis der Spieler tatsächlich gelandet ist (Fall ab y=2 kann > 30 Frames dauern)
	var landed := false
	for i in 300:
		await physics_frame
		if world.player.is_on_floor():
			landed = true
			break

	_assert(world.player != null, "Spieler wurde instanziiert")
	_assert(world.pet != null, "AI-Pet wurde instanziiert")
	_assert(world.loader != null, "ModelLoader wurde instanziiert")
	if _failed:
		world.free()
		return
	_assert(landed, "Spieler landet auf dem Boden")
	if _failed:
		world.free()
		return

	# --- 3. Bewegung simulieren: ui_up gedrückt halten ---
	var start_pos: Vector3 = world.player.global_position
	Input.action_press("ui_up")
	for i in 30:
		await physics_frame
	Input.action_release("ui_up")
	var moved: float = world.player.global_position.distance_to(start_pos)
	_assert(moved > 1.0, "Spieler bewegt sich bei gehaltener Eingabe (weg: %.2f)" % moved)

	# --- 4. Pet folgt dem Spieler ---
	var pet_to_player: float = world.pet.global_position.distance_to(world.player.global_position)
	_assert(pet_to_player < 6.0, "Pet folgt in Nähe des Spielers (Distanz: %.2f)" % pet_to_player)

	# --- 5. ModelLoader meldet fehlende Datei sauber über Rückgabewert ---
	var loaded: bool = world.loader.load_ai_generated_3d_model("res://assets/ai_models/existing.glb", Vector3.ZERO)
	_assert(loaded == false, "ModelLoader gibt false bei fehlender Datei zurück")

	world.free()
	if _failed:
		return
	print("PHASE-2-CHECKS BESTANDEN ✔")
	quit(0)


func _assert(cond: bool, msg: String) -> void:
	if cond:
		return
	_failed = true
	printerr("FEHLER: " + msg)
	quit(1)
