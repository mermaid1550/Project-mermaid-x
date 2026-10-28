extends Node
## NetworkManager (Autoload): ENet-Host/-Client + Raumwechsel.
##
## Phase 1: Verbindungsaufbau (Host/Join) und Raumwechsel-Signal laufen.
## Offen für Phase 2: Auth über dein Backend, raumwechsel mit
## multiplayer.transfer_mode / eigene Szenen je Lobby-Ebene,
## und authority-Zuweisungen für Server-Autorität (nie Client-Trust).

signal connected
signal disconnected
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal room_changed(room: String)

const DEFAULT_PORT := 24565
const MAX_PLAYERS := 64  # Open-World-Hub-Grenze, Lobbys laufen darunter

var current_room: String = "hub"  # "classroom" | "private" | "hub"
var is_host: bool = false


func host(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("Host fehlgeschlagen (Fehler %d)" % err)
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	_bind_signals()
	connected.emit()
	print("Server läuft auf Port %d" % port)
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("Verbindung fehlgeschlagen (Fehler %d)" % err)
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	_bind_signals()
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	current_room = "hub"
	is_host = false
	disconnected.emit()


## Raumwechsel: lokal setzen und an alle Peers melden (nur Host darf das).
func change_room(room: String) -> void:
	if not multiplayer.multiplayer_peer is OfflineMultiplayerPeer and not is_host:
		push_warning("Nur der Host darf den Raum wechseln.")
		return
	current_room = room
	if multiplayer.multiplayer_peer is MultiplayerPeer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_sync_room.rpc(room)
	room_changed.emit(room)


@rpc("authority", "call_local", "reliable")
func _sync_room(room: String) -> void:
	current_room = room
	room_changed.emit(room)


func _bind_signals() -> void:
	if multiplayer.connected_to_server.is_connected(_on_connected):
		return
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_failed)
	multiplayer.peer_connected.connect(_on_peer_joined)
	multiplayer.peer_disconnected.connect(_on_peer_left)


func _on_connected() -> void:
	connected.emit()
	print("Mit Server verbunden.")


func _on_failed() -> void:
	leave()


func _on_peer_joined(id: int) -> void:
	peer_joined.emit(id)
	print("Spieler %d ist beigetreten." % id)


func _on_peer_left(id: int) -> void:
	peer_left.emit(id)
	print("Spieler %d hat verlassen." % id)
