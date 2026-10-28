extends SceneTree
## Headless-Check des Master-Pipeline-Loaders (Section C):
## 1. AI-Modell aus Blender-Pipeline laden (assets/models/machine_game.glb)
## 2. Box-Kollision erzeugt
## 3. Pet-Chat antwortet offline (kein Backend in CI), Signale feuern
## 4. WAV-Parser akzeptiert gültige Bytes und weist Müll ab

var _failed: bool = false


func _init() -> void:
	# --- 1. Blender-Export muss existieren ---
	_assert(FileAccess.file_exists("res://assets/models/machine_game.glb"),
		"Blender-Export existiert (auto_prep_asset.py ausführen)")
	if _failed:
		return

	var loader: Variant = load("res://scripts/model_and_ai_loader.gd").new()
	loader.name = "Loader"
	loader.model_path = "res://assets/models/machine_game.glb"
	loader.spawn_position = Vector3(3, 0, 3)
	var got_model: Array = []
	loader.model_loaded.connect(func(m: Node3D) -> void: got_model.append(m))
	root.add_child(loader)  # _ready lädt das Modell und feuert das Signal
	await process_frame

	_assert(not got_model.is_empty(), "Modell wurde instanziiert und Signal gefeuert")
	if _failed:
		return

	var model: Node3D = got_model[0]
	_assert(model.get_child_count() > 0, "GLTF-Unterknoten sind geladen")
	_assert(model.global_position.distance_to(Vector3(3, 0, 3)) < 0.01,
		"Spawn-Position wurde angewendet")

	# --- 2. Kollision ---
	var bodies := 0
	for child in loader.get_children():
		if child is StaticBody3D:
			bodies += 1
	_assert(bodies >= 1, "Box-Kollision erzeugt (StaticBody3D: %d)" % bodies)

	# --- 3. Offline-Chat-Fallback ---
	var replies: Array = []
	loader.pet_reply.connect(func(text: String, _source: String) -> void: replies.append(text))
	loader.ask_pet("Vokabeln üben")
	var answered := false
	for i in 60:
		await process_frame
		if replies.size() > 0:
			answered = true
			break
	_assert(answered, "Pet antwortet (Offline-Fallback ohne Backend)")
	_assert(str(replies[0]).contains("Vokabelrunde") or str(replies[0]).length() > 5,
		"Antwort ist eine echte Tutor-Antwort")
	_assert(loader.backend_online == false, "Backend als offline markiert")

	# --- 4. WAV-Parser ---
	var valid_wav := PackedByteArray()
	valid_wav.append_array("RIFF".to_ascii_buffer())
	valid_wav.append_array(PackedByteArray([0, 0, 0, 0]))
	valid_wav.append_array("WAVE".to_ascii_buffer())
	valid_wav.append_array("fmt ".to_ascii_buffer())
	valid_wav.append_array(PackedByteArray([16, 0, 0, 0]))
	valid_wav.append_array(PackedByteArray([1, 0]))       # PCM
	valid_wav.append_array(PackedByteArray([1, 0]))       # mono
	valid_wav.append_array(PackedByteArray([57, 48, 0, 0]))  # 0x3039 = 12345 Hz
	valid_wav.append_array(PackedByteArray([57, 48, 0, 0]))  # Byte-Rate
	valid_wav.append_array(PackedByteArray([2, 0]))
	valid_wav.append_array(PackedByteArray([16, 0]))
	valid_wav.append_array("data".to_ascii_buffer())
	valid_wav.append_array(PackedByteArray([4, 0, 0, 0]))
	valid_wav.append_array(PackedByteArray([0, 1, 0, 2]))
	var stream: AudioStreamWAV = loader._wav_to_audio_stream(valid_wav)
	_assert(stream != null, "WAV-Parser akzeptiert gültige PCM16-Bytes")
	if stream != null:
		_assert(stream.mix_rate == 12345, "Sample-Rate gelesen: %d" % stream.mix_rate)
		_assert(stream.data.size() == 4, "Data-Chunk-Länge gelesen: %d" % stream.data.size())

	var junk := PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])
	_assert(loader._wav_to_audio_stream(junk) == null, "WAV-Parser weist Müll ab")

	root.remove_child(loader)
	loader.free()
	if _failed:
		return
	print("MODEL-AI-LOADER CHECKS BESTANDEN ✔")
	quit(0)


func _assert(cond: bool, msg: String) -> void:
	if cond:
		return
	_failed = true
	printerr("FEHLER: " + msg)
	quit(1)
