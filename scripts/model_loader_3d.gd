extends Node3D
## 3D-Asset Auto-Loader (Kapitel 6.5 der Master-Bible).
## Lädt KI-generierte Modelle (GLTF/GLB) aus deiner lokalen
## TripoSR/Hunyuan3D-Pipeline in die Szene.


func load_ai_generated_3d_model(file_path: String, spawn_position: Vector3) -> bool:
	if not FileAccess.file_exists(file_path):
		print("⚠️ Modell nicht gefunden: ", file_path)
		return false

	var gltf_state := GLTFState.new()
	var gltf_document := GLTFDocument.new()

	var error := gltf_document.append_from_file(file_path, gltf_state)
	if error == OK:
		var scene_root := gltf_document.generate_scene(gltf_state)
		scene_root.position = spawn_position
		add_child(scene_root)
		print("✅ 3D-AI-Modell geladen: ", file_path)
		return true

	print("❌ Fehler beim Laden (Fehler %d): %s" % [error, file_path])
	return false
