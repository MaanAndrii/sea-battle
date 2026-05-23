## NetworkTransport.gd
## ─── ЄДИНИЙ файл що знає про ENet ───────────────────────────
## Міграція Варіант А→Б: замінити ENetMultiplayerPeer
## на WebSocketMultiplayerPeer тут. Решта коду НЕ міняється.

extends Node

signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal connected_to_server
signal connection_failed

const DEFAULT_PORT = 7777
const MAX_CLIENTS  = 1  # сервер + 1 клієнт = 2 гравці

func _ready() -> void:
	multiplayer.peer_connected.connect(func(id): peer_connected.emit(id))
	multiplayer.peer_disconnected.connect(func(id): peer_disconnected.emit(id))
	multiplayer.connected_to_server.connect(func(): connected_to_server.emit())
	multiplayer.connection_failed.connect(func(): connection_failed.emit())

func host(port: int = DEFAULT_PORT) -> Error:
	var peer = ENetMultiplayerPeer.new()   # ← swap тут для Варіанту Б
	var err  = peer.create_server(port, MAX_CLIENTS)
	if err != OK: return err
	multiplayer.multiplayer_peer = peer
	return OK

func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer = ENetMultiplayerPeer.new()   # ← swap тут для Варіанту Б
	var err  = peer.create_client(address, port)
	if err != OK: return err
	multiplayer.multiplayer_peer = peer
	return OK

func close() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null

func is_server() -> bool:
	return multiplayer.is_server()

func my_id() -> int:
	return multiplayer.get_unique_id()
