extends SceneTree
## Temporärer Headless-Check der AI-Pet-Logik. Wird nach dem Lauf gelöscht.

func _init() -> void:
	var pet: Object = load("res://scripts/ai_pet.gd").new()

	var greet: String = pet.respond("hallo")
	_assert(greet.contains("Lóng-Pet"), "Begrüßung enthält Pet-Namen: " + greet)

	var quiz: String = pet.respond("Vokabeln üben")
	_assert(quiz.contains("Englisch"), "Quiz startet auf Englisch-Frage: " + quiz)

	# Richtige Antwort ermitteln, um den Quiz-Zustand zu prüfen
	var word_en: String = ""
	for w in pet._vocab:
		if quiz.contains(w["cn"]):
			word_en = w["en"]
			break
	_assert(word_en != "", "Quiz-Wort im Vokabel-Array gefunden")

	var right: String = pet.respond(word_en)
	_assert(right.contains("Richtig"), "Korrekte Antwort erkannt: " + right)

	var it: String = pet.respond("Was ist eine API?")
	_assert(it.contains("Application Programming Interface"), "IT-Erklärung API: " + it)

	var help: String = pet.respond("Hilfe")
	_assert(help.contains("Vokabeln üben"), "Hilfe-Text: " + help)

	# Hauptszene laden und Lobby-Wechsel testen
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main: Control = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var chat: Variant = main._chat
	_assert(chat != null, "PetChat wurde instanziiert")
	_assert(main._net != null, "NetworkManager wurde instanziiert")
	main._on_lobby_pressed(main.Lobby.CLASSROOM)
	_assert(main._net.current_room == "classroom", "Raumwechsel -> classroom: " + str(main._net.current_room))
	_assert(main._status.text.contains("Schul-Klasse"), "Status zeigt neuen Raum: " + main._status.text)
	main._on_lobby_pressed(main.Lobby.OPEN_WORLD)
	_assert(main._net.current_room == "hub", "Raumwechsel -> hub: " + str(main._net.current_room))
	# Chat-Komplettdurchlauf über das UI
	chat._on_send("Vokabeln üben")
	var log_text: String = chat._log.get_parsed_text()
	_assert(log_text.contains("Pet:"), "Pet-Antwort im Chat-Log: " + log_text)
	_assert(log_text.contains("Du:"), "Spieler-Nachricht im Chat-Log")
	print("HAUPTSZENE: ALLE CHECKS BESTANDEN ✔")

	print("ALLE CHECKS BESTANDEN ✔")
	quit(0)


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FEHLER: " + msg)
		quit(1)
