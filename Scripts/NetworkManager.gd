## NetworkManager.gd
## Ігровий протокол: обмін флотами і ходами.
## ─────────────────────────────────────────────────────────────
## Міграція Варіант А→Б: замінити @rpc-виклики на
## send_json()/on_message() через WebSocket.
## Всі сигнали (both_ready, opponent_turn_received...) НЕ міняються.

extends Node

signal opponent_connected
signal both_ready(my_turn_first: bool)
signal opponent_fleet_received(fleet: Array)
signal opponent_turn_received(turn: Dictionary)

var transport: Node = null

var _my_fleet:       Array = []
var _opponent_fleet: Array = []
var _my_fleet_sent:   bool = false
var _opp_fleet_rcvd:  bool = false
var _opponent_id:     int  = 0

## Читається GameScene після зміни сцени
var my_turn_first: bool = true
var _game_started: bool = false

func setup(p_transport: Node) -> void:
	transport = p_transport
	transport.peer_connected.connect(_on_peer_connected)
	transport.connected_to_server.connect(_on_connected_to_server)

func _on_peer_connected(id: int) -> void:
	_opponent_id = id
	opponent_connected.emit()   # SERVER: клієнт підключився

func _on_connected_to_server() -> void:
	_opponent_id = 1
	opponent_connected.emit()   # CLIENT: ми підключились до сервера

# ── Розстановка ───────────────────────────────────────────────

func send_my_fleet(ships: Array) -> void:
	_my_fleet = _serialize_fleet(ships)
	_my_fleet_sent = true
	rpc("_rpc_receive_fleet", _my_fleet)
	if transport.is_server(): _check_both_ready()

@rpc("any_peer", "reliable")
func _rpc_receive_fleet(fleet_data: Array) -> void:
	_opponent_fleet = fleet_data
	_opp_fleet_rcvd = true
	opponent_fleet_received.emit(fleet_data)
	if transport.is_server(): _check_both_ready()

func _check_both_ready() -> void:
	if _my_fleet_sent and _opp_fleet_rcvd:
		rpc("_rpc_game_start", transport.my_id())

@rpc("call_local", "reliable")
func _rpc_game_start(first_id: int) -> void:
	my_turn_first = (transport.my_id() == first_id)
	_game_started = true
	both_ready.emit(my_turn_first)

# ── Хід ──────────────────────────────────────────────────────

func send_turn(shots: Array[Vector2i], ships: Array, noses: Array = []) -> void:
	var data := {
		"shots": shots.map(func(c): return [c.x, c.y]),
		"moves": _serialize_fleet(ships),
		"noses": noses.map(func(c): return [c.x, c.y]),
	}
	rpc_id(_opponent_id, "_rpc_receive_turn", data)

@rpc("any_peer", "reliable")
func _rpc_receive_turn(turn: Dictionary) -> void:
	opponent_turn_received.emit(turn)

# ── Флот для локальної перевірки влучань ─────────────────────

func get_opponent_fleet() -> Array:
	return _opponent_fleet

# ── Серіалізація ──────────────────────────────────────────────

func _serialize_fleet(ships: Array) -> Array:
	var result := []
	for i in range(ships.size()):
		var ship = ships[i]
		if not ship.is_placed: continue
		result.append({
			"fleet_idx":     i,          # стабільний індекс — унікальний навіть для однойменних кораблів
			"name":          ship.ship_name,
			"size":          ship.size,
			"rotation_step": ship.rotation_step,
			"cells":         ship.cells.map(func(c): return [c.x, c.y]),
		})
	return result
