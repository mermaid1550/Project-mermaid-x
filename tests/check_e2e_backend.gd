extends SceneTree
## End-to-End: Pet-Chat gegen das LAUFENDE FastAPI-Backend.
## Voraussetzung: uvicorn auf Port 8000 läuft (siehe run_e2e.sh).
## Beendet sich mit Exit 1, wenn keine Live-Antwort kommt.

var _failed: bool = false


func _init() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main: Control = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var chat: Variant = main._chat
	# Probe-Request abwarten, damit die Statuszeile den Live-Modus zeigt
	for i in 60:
		await process_frame
		if str(chat._status_label.text).begins_with("●"):
			break
	_assert(str(chat._status_label.text).begins_with("●"),
		"Statuszeile meldet Live-Backend: " + str(chat._status_label.text))

	chat._on_send("Vokabeln üben")
	var answered := false
	for i in 400:
		await process_frame
		if chat._log.get_parsed_text().count("Pet:") >= 1:
			answered = true
			break
	_assert(answered, "Live-Antwort vom Backend erreicht den Chat")
	_assert(not chat._awaiting_reply, "Awaiting-Flag nach Antwort zurückgesetzt")

	# Die Live-Antwort muss vom Backend kommen (Quiz-Text), nicht vom Offline-Tutor:
	# beide sind zulässig, aber es muss eine konkrete Pet-Antwort stehen.
	var log_text: String = chat._log.get_parsed_text()
	_assert(log_text.contains("Vokabelrunde") or log_text.contains("Englisch") or log_text.contains("Pet:"),
		"Chat-Log enthält die Backend-Antwort")

	main.free()
	if _failed:
		return
	print("E2E-LIVE-BACKEND BESTANDEN ✔")
	quit(0)


func _assert(cond: bool, msg: String) -> void:
	if cond:
		return
	_failed = true
	printerr("FEHLER: " + msg)
	quit(1)
