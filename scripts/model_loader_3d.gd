extends Node3D
## 3D-Asset Auto-Loader (Kapitel 6.5 der Master-Bible).
## Lädt KI-generierte oder prozedurale Modelle (GLTF/GLB) in die Szene
## und erzeugt optional eine Box-Kollision aus der Bounding Box – damit
## Häuser und Türme aus der Asset-Pipeline (tools/ai3d) begehbar sind.


func load_ai_generated_3d_model(file_path: String, spawn_position: Vector3, with_collision: bool = true) -> bool:
	if not FileAccess.file_exists(file_path):
		print("⚠️ Modell nicht gefunden: ", file_path)
		return false

	var gltf_state := GLTFState.new()
	var gltf_document := GLTFDocument.new()

	var error := gltf_document.append_from_file(file_path, gltf_state)
	if error != OK:
		print("❌ Fehler beim Laden (Fehler %d): %s" % [error, file_path])
		return false

	var scene_root := gltf_document.generate_scene(gltf_state)
	scene_root.position = spawn_position
	add_child(scene_root)

	if with_collision:
		_add_box_collision(scene_root, spawn_position)

	print("✅ 3D-Modell geladen: ", file_path)
	return true


## Erzeugt eine StaticBody3D-Box aus der kombinierten AABB des Modells.
func _add_box_collision(model: Node3D, spawn_position: Vector3) -> void:
	var bounds := AABB()
	var first := true

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(model, meshes)
	for mi in meshes:
		var local_bounds := mi.get_aabb()
		for corner in 8:
			var world_corner: Vector3 = mi.global_transform * local_bounds.get_endpoint(corner)
			if first:
				bounds = AABB(world_corner, Vector3.ZERO)
				first = false
			else:
				bounds = bounds.expand(world_corner)

	if first:
		return  # kein Mesh gefunden

	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bounds.size
	shape_node.shape = box
	# bounds sind Weltkoordinaten; body hängt unter dem Loader (self),
	# daher die Weltmitte in den Lokalraum des Loaders umrechnen.
	body.position = to_local(bounds.get_center())
	body.add_child(shape_node)
	add_child(body)


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)
