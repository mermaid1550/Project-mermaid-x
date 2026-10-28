class_name ModelAndAILoader
extends Node3D
## Section C der Master-Pipeline: lädt exportierte AI-Modelle (.gltf/.glb)
## zur Laufzeit in die Szene und verbindet sie mit dem lokalen
## FastAPI-AI-Pet-Backend (Ollama + Coqui TTS).
##
## Verwendung in einer Szene:
##   var loader := ModelAndAILoader.new()
##   loader.model_path = "res://assets/models/machine_game.glb"
##   loader.spawn_position = Vector3(4, 0, 2)
##   add_child(loader)          # lädt automatisch in _ready
##   loader.ask_pet("Erklär mir APIs")   # Chat ans Backend
##
## Signale (für UI/Spielelogik):
##   model_loaded(model)  backend_status(online)  pet_reply(text, source)
##   pet_failed(reason)   tts_ready(stream)

signal model_loaded(model: Node3D)
signal model_failed(path: String, reason: String)
signal backend_status(online: bool)
signal pet_reply(text: String, source: String)
signal pet_failed(reason: String)
signal tts_ready(stream: AudioStream)

## Pfad zum exportierten AI-Modell (Ausgabe von auto_prep_asset.py).
@export var model_path: String = "res://assets/models/"
## Spawn-Position in Weltkoordinaten.
@export var spawn_position: Vector3 = Vector3.ZERO
## Box-Kollision aus der Bounding Box erzeugen (begehbar/stehbar).
@export var with_collision: bool = true
## AI-Pet antwortet mit Text-to-Speech (Coqui über das Backend).
@export var tts_enabled: bool = false
## Ohne Backend antwortet der Offline-Tutor (ai_pet.gd) – Chat nie stumm.
@export var offline_fallback: bool = true
## User-ID für Backend-Kontext (später: Accounts via SQLite/Supabase).
@export var user_id: String = "player_lux"

const AI_BACKEND_URL := "http://127.0.0.1:8000/v1/pet/chat"
const AI_TTS_URL := "http://127.0.0.1:8000/v1/pet/tts"
const AI_Pet := preload("res://scripts/ai_pet.gd")

var backend_online: bool = false
var _chat_http: HTTPRequest
var _tts_http: HTTPRequest
var _audio_player: AudioStreamPlayer3D
var _awaiting_reply: bool = false
var _last_prompt: String = ""
var _ai := AI_Pet.new()


func _ready() -> void:
	_chat_http = HTTPRequest.new()
	_chat_http.timeout = 20.0
	add_child(_chat_http)
	_chat_http.request_completed.connect(_on_chat_response)

	if tts_enabled:
		_tts_http = HTTPRequest.new()
		_tts_http.timeout = 30.0
		add_child(_tts_http)
		_tts_http.request_completed.connect(_on_tts_response)
		_audio_player = AudioStreamPlayer3D.new()
		_audio_player.unit_size = 12.0
		add_child(_audio_player)

	_probe_backend()
	_load_model()


# ------------------------------------------------------------------ Modell
func _load_model() -> void:
	if not FileAccess.file_exists(model_path):
		model_failed.emit(model_path, "Datei nicht gefunden")
		push_warning("ModelAndAILoader: Datei fehlt: " + model_path)
		return

	var state := GLTFState.new()
	var document := GLTFDocument.new()
	var error := document.append_from_file(model_path, state)
	if error != OK:
		model_failed.emit(model_path, "GLTF-Fehler %d" % error)
		return

	var model := document.generate_scene(state)
	model.position = spawn_position
	add_child(model)

	if with_collision:
		_add_box_collision(model)

	model_loaded.emit(model)


## Box-Kollision aus der kombinierten AABB – Häuser/Türme werden begehbar.
func _add_box_collision(model: Node3D) -> void:
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
		return

	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bounds.size
	shape_node.shape = box
	body.position = to_local(bounds.get_center())
	body.add_child(shape_node)
	add_child(body)


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)


# ------------------------------------------------------------------- Chat
## Frage ans AI-Pet-Backend (Ollama → Offline-Tutor als Fallback).
func ask_pet(prompt: String) -> bool:
	var clean := prompt.strip_edges()
	if clean.is_empty():
		return false
	_last_prompt = clean

	if _chat_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		# Request läuft – Offline direkt beantworten, nicht blockieren.
		_reply_offline(clean)
		return true

	var body := JSON.stringify({"prompt": clean, "user_id": user_id})
	var headers := PackedStringArray(["Content-Type: application/json"])
	_awaiting_reply = true
	var error := _chat_http.request(AI_BACKEND_URL, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		_awaiting_reply = false
		_reply_offline(clean)
	return true


func _on_chat_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var ok := result == HTTPRequest.RESULT_SUCCESS and response_code == 200
	if ok != backend_online:
		backend_online = ok
		backend_status.emit(ok)

	if not _awaiting_reply:
		return  # Antwort auf den Probe-Call
	_awaiting_reply = false

	if ok:
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary and json.data.has("reply"):
			var reply := str(json.data["reply"])
			pet_reply.emit(reply, str(json.data.get("source", "backend")))
			_speak(reply)
			return

	if offline_fallback:
		_reply_offline(_last_prompt)
	else:
		pet_failed.emit("Backend-Antwort unbrauchbar (HTTP %d)" % response_code)


func _reply_offline(prompt: String) -> void:
	var reply := _ai.respond(prompt)
	pet_reply.emit(reply, "local")
	backend_online = false
	backend_status.emit(false)
	_speak(reply)


func _probe_backend() -> void:
	var err := _chat_http.request(AI_BACKEND_URL, PackedStringArray(), HTTPClient.METHOD_GET)
	if err != OK:
		backend_status.emit(false)


# -------------------------------------------------------------------- TTS
## Holt Audio vom Coqui-TTS-Endpoint; keine Antwort = stummer Betrieb.
func _speak(text: String) -> void:
	if not tts_enabled or _tts_http == null:
		return
	if _tts_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	var body := JSON.stringify({"text": text, "user_id": user_id})
	var headers := PackedStringArray(["Content-Type: application/json"])
	var error := _tts_http.request(AI_TTS_URL, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		push_warning("TTS-Request fehlgeschlagen (Fehler %d)" % error)


func _on_tts_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or body.is_empty():
		return  # Kein TTS verfügbar – Spiel läuft stumm weiter
	var stream := _wav_to_audio_stream(body)
	if stream == null:
		return
	tts_ready.emit(stream)
	_audio_player.stream = stream
	_audio_player.play()


## Parst WAV-Bytes (PCM 16-Bit) zu einem AudioStreamWAV.
func _wav_to_audio_stream(bytes: PackedByteArray) -> AudioStreamWAV:
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false

	# fmt-Chunk auslesen (Sample-Rate, Kanäle)
	var pos := 12
	while pos + 8 <= bytes.size():
		var chunk_id := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var chunk_size := bytes.decode_u32(pos + 4)
		if chunk_id == "fmt ":
			var channels := bytes.decode_u16(pos + 10)
			var mix_rate := bytes.decode_u32(pos + 12)
			stream.stereo = channels == 2
			stream.mix_rate = mix_rate
		elif chunk_id == "data":
			stream.data = bytes.slice(pos + 8, pos + 8 + chunk_size)
			return stream
		pos += 8 + chunk_size
	return null
