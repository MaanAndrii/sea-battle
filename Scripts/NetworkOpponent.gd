## NetworkOpponent.gd
## Замінює EnemySetup + EnemyAI у мережевому режимі.
## Реалізує той самий інтерфейс: is_hit(), mark_hit(), execute_turn().

extends Node

signal enemy_placed           # сумісність з EnemySetup
signal opponent_turn_applied  # хід суперника застосовано → розблокуємо UI

var upper_grid:      Node2D = null
var lower_grid:      Node2D = null
var network_manager: Node   = null
var player_model             = null
var all_ships:       Array  = []

var _opponent_fleet: Array = []   # поточні позиції флоту суперника
var _opponent_fleet_ready: bool = false  # true після першого отримання флоту

func setup(p_upper: Node2D, p_lower: Node2D,
		p_net: Node, p_model, p_ships: Array) -> void:
	upper_grid      = p_upper
	lower_grid      = p_lower
	network_manager = p_net
	player_model    = p_model
	all_ships       = p_ships
	network_manager.opponent_fleet_received.connect(_on_fleet_received)
	network_manager.opponent_turn_received.connect(_on_turn_received)

# ── Флот ─────────────────────────────────────────────────────

func _on_fleet_received(fleet: Array) -> void:
	_opponent_fleet = fleet
	_opponent_fleet_ready = true
	enemy_placed.emit()

# ── Інтерфейс CombatManager (is_hit / mark_hit) ──────────────

func is_hit(coord: Vector2i) -> bool:
	for ship_data in _opponent_fleet:
		for ca in ship_data["cells"]:
			if ca[0] == coord.x and ca[1] == coord.y:
				return true
	return false

func mark_hit(coord: Vector2i) -> void:
	for ship_data in _opponent_fleet:
		var cells := ship_data["cells"] as Array
		for i in range(cells.size()):
			if cells[i][0] == coord.x and cells[i][1] == coord.y:
				cells.remove_at(i)
				return

# ── Хід суперника ─────────────────────────────────────────────

func _on_turn_received(turn: Dictionary) -> void:
	# Оновлюємо позиції флоту суперника
	var moves := turn.get("moves", []) as Array
	if moves.size() > 0:
		_opponent_fleet = moves

	# Застосовуємо постріли суперника по нашому флоту
	for shot_arr in (turn.get("shots", []) as Array):
		_apply_shot(Vector2i(shot_arr[0], shot_arr[1]))

	opponent_turn_applied.emit()

func _apply_shot(coord: Vector2i) -> void:
	if player_model.grid[coord.y][coord.x] == 1:
		player_model.grid[coord.y][coord.x] = 0
		player_model._rebuild_forbidden()
		for ship in all_ships:
			for c in ship.cells:
				if Vector2i(c.x, c.y) == coord:
					ship.set("damaged", true)
					ship.queue_redraw()
					break
		lower_grid.set_cell(coord, 6)
	else:
		lower_grid.set_cell(coord, 5)

# ── Заглушка execute_turn (EnemyAI інтерфейс) ────────────────

func execute_turn() -> void:
	pass  # хід суперника приходить через мережу
