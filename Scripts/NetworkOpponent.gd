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

	# ⚡ Показуємо носи кораблів суперника що стріляли — на нашій прицільній карті
	for nose_arr in (turn.get("noses", []) as Array):
		var nose := Vector2i(nose_arr[0], nose_arr[1])
		if upper_grid.cell_state[nose.y][nose.x] == 0:
			upper_grid.set_cell(nose, 9)

	opponent_turn_applied.emit()

func _apply_shot(coord: Vector2i) -> void:
	if player_model.grid[coord.y][coord.x] == 1:
		player_model.grid[coord.y][coord.x] = 0
		player_model._rebuild_forbidden()
		lower_grid.set_cell(coord, 6)
		_on_hit(coord)
	else:
		lower_grid.set_cell(coord, 5)

func _on_hit(coord: Vector2i) -> void:
	for ship in all_ships:
		if not ship.is_placed: continue
		for c in ship.cells:
			if Vector2i(c.x, c.y) == coord:
				ship.set("damaged", true)
				ship.queue_redraw()
				_check_sunk(ship)
				return

func _check_sunk(ship: Node2D) -> void:
	for c in ship.cells:
		if lower_grid.cell_state[c.y][c.x] != 6:
			return

	var ship_cells: Array[Vector2i] = []
	for c in ship.cells:
		ship_cells.append(Vector2i(c.x, c.y))

	for cv in ship_cells:
		lower_grid.set_cell(cv, 10)

	var adj_cells: Array[Vector2i] = []
	for cv in ship_cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0: continue
				var nb = Vector2i(cv.x + dx, cv.y + dy)
				if lower_grid.is_valid(nb) and not ship_cells.has(nb) and not adj_cells.has(nb):
					if lower_grid.cell_state[nb.y][nb.x] != 10:
						lower_grid.set_cell(nb, 11)
					adj_cells.append(nb)

	if player_model:
		player_model.add_wreckage(ship_cells)
		player_model.add_wreckage(adj_cells)

	ship.modulate  = Color(0.6, 0.6, 0.7, 0.30)
	ship.is_placed = false

# ── Заглушка execute_turn (EnemyAI інтерфейс) ────────────────

func execute_turn() -> void:
	pass  # хід суперника приходить через мережу
