extends SceneTree
## Headless-Check der Asset-Pipeline: GLB-Modelle laden (inkl. Kollision),
## Hub-Stadt spawnen, Apartment-Szene starten.

var _failed: bool = false


func _init() -> void:
	# --- 1. GLBs aus tools/ai3d/generate_buildings.py müssen existieren ---
	for name in ["house", "tower"]:
		_assert(FileAccess.file_exists("res://assets/ai_models/%s.glb" % name),
			"GLB existiert: %s.glb (python3 tools/ai3d/generate_buildings.py ausführen)" % name)
	if _failed:
		return

	# --- 2. Hub-Welt: laden, Stadt spawnen lassen ---
	var world_scene: PackedScene = load("res://scenes/world_test_3d.tscn")
	var world: Node3D = world_scene.instantiate()
	root.add_child(world)
	await process_frame
	await process_frame

	_assert(world.loader != null, "ModelLoader instanziiert")
	var loader: Node3D = world.loader
	# Jedes Gebäude erzeugt einen Modell-Knoten UNTER dem Loader
	_assert(loader.get_child_count() >= 9,
		"Alle 9 Gebäude geladen (gefunden: %d)" % loader.get_child_count())

	# Kollisionen: jedes Gebäude erzeugt eine StaticBody3D-Kollision,
	# die hängt als Geschwister-Knoten unter dem Loader.
	var collision_count := 0
	for child in loader.get_children():
		if child is StaticBody3D:
			collision_count += 1
	_assert(collision_count >= 9,
		"Kollisionen für Gebäude erzeugt (gefunden: %d)" % collision_count)

	# Spieler landet trotz Gebäude-Kollisionen auf dem Boden
	var landed := false
	for i in 300:
		await physics_frame
		if world.player.is_on_floor():
			landed = true
			break
	_assert(landed, "Spieler landet im Stadt-Layout auf dem Boden")
	world.free()
	if _failed:
		return

	# --- 3. Apartment-Szene: startet, Player + Licht + UI sind da ---
	var apt_scene: PackedScene = load("res://scenes/apartment_3d.tscn")
	var apt: Node3D = apt_scene.instantiate()
	root.add_child(apt)
	var apt_landed := false
	for i in 300:
		await physics_frame
		if apt.player != null and apt.player.is_on_floor():
			apt_landed = true
			break
	_assert(apt_landed, "Spieler landet im Apartment auf dem Boden")

	var lights := 0
	var ui_buttons := 0
	for child in apt.get_children():
		if child is OmniLight3D or child is DirectionalLight3D:
			lights += 1
		if child is CanvasLayer:
			for ui in child.get_children():
				if ui is Button:
					ui_buttons += 1
	_assert(lights >= 2, "Beleuchtung im Apartment (gefunden: %d)" % lights)
	_assert(ui_buttons >= 1, "UI-Buttons im Apartment (gefunden: %d)" % ui_buttons)

	apt.free()
	if _failed:
		return
	print("ASSET-PIPELINE-CHECKS BESTANDEN ✔")
	quit(0)


func _assert(cond: bool, msg: String) -> void:
	if cond:
		return
	_failed = true
	printerr("FEHLER: " + msg)
	quit(1)
