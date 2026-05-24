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

# Поточний флот суперника — використовується тільки для is_hit/mark_hit
# Структура: { fleet_idx → { "size", "current_cells": [[x,y],...], "hit_sections": Array[bool] } }
# Ключ fleet_idx — стабільний індекс з _serialize_fleet, унікальний для кожного корабля
# незалежно від однакових назв (2×Лінкор, 3×Фрегат, 4×Корвет).
var _opponent_ships: Dictionary = {}
var _opponent_fleet_ready: bool = false
var _opponent_turn_ready:  bool = false

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
	_opponent_ships.clear()
	for ship_data in fleet:
		var idx: int     = ship_data.get("fleet_idx", -1)
		if idx < 0: continue
		var cells: Array = ship_data.get("cells", [])
		var sz: int      = cells.size()
		var hit_sec: Array = []
		for _i in range(sz): hit_sec.append(false)
		_opponent_ships[idx] = {
			"size":          sz,
			"current_cells": cells.duplicate(true),
			"hit_sections":  hit_sec,
		}
	_opponent_fleet_ready = true
	enemy_placed.emit()

# ── Інтерфейс CombatManager (is_hit / mark_hit) ──────────────

func is_hit(coord: Vector2i) -> bool:
	for idx in _opponent_ships:
		for ca in _opponent_ships[idx]["current_cells"]:
			if ca[0] == coord.x and ca[1] == coord.y:
				return true
	return false

func mark_hit(coord: Vector2i) -> void:
	for idx in _opponent_ships:
		var entry   = _opponent_ships[idx]
		var cells   = entry["current_cells"] as Array
		var hit_sec = entry["hit_sections"]  as Array
		for i in range(cells.size()):
			if cells[i][0] == coord.x and cells[i][1] == coord.y:
				hit_sec[i] = true
				# Перевіряємо чи потоплений
				var all_hit := true
				for d in hit_sec:
					if not d: all_hit = false; break
				if all_hit:
					entry["marked_sunk"] = true
					_sink_opponent_ship(entry)
				return

func _sink_opponent_ship(entry: Dictionary) -> void:
	var cells    = entry["current_cells"] as Array
	var ship_cvs: Array[Vector2i] = []
	for ca in cells:
		ship_cvs.append(Vector2i(ca[0], ca[1]))

	# Позначаємо на верхньому полі (прицільна карта) — стан 10 (уламки)
	for cv in ship_cvs:
		upper_grid.set_cell(cv, 10)

	# Суміжні клітинки — стан 11 (заблокована зона)
	var adj: Array[Vector2i] = []
	for cv in ship_cvs:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0: continue
				var nb = Vector2i(cv.x + dx, cv.y + dy)
				if upper_grid.is_valid(nb) and not ship_cvs.has(nb) and not adj.has(nb):
					if upper_grid.cell_state[nb.y][nb.x] != 10:
						upper_grid.set_cell(nb, 11)
					adj.append(nb)

# ── Хід суперника ─────────────────────────────────────────────

func _on_turn_received(turn: Dictionary) -> void:
	# Оновлюємо поточні позиції кораблів суперника
	var moves := turn.get("moves", []) as Array
	for ship_data in moves:
		var idx: int = ship_data.get("fleet_idx", -1)
		if idx < 0 or not _opponent_ships.has(idx):
			continue
		# Оновлюємо поточні клітинки; hit_sections залишаються незмінними
		var new_cells: Array = ship_data.get("cells", [])
		_opponent_ships[idx]["current_cells"] = new_cells.duplicate(true)
		var sz: int        = new_cells.size()
		var hit_sec: Array = _opponent_ships[idx]["hit_sections"]
		if hit_sec.size() != sz:
			while hit_sec.size() < sz: hit_sec.append(false)
		# Авторитетне підтвердження потоплення від суперника
		if ship_data.get("sunk", false) and not _opponent_ships[idx].get("marked_sunk", false):
			_opponent_ships[idx]["marked_sunk"] = true
			_sink_opponent_ship(_opponent_ships[idx])

	# Застосовуємо постріли суперника по нашому флоту
	for shot_arr in (turn.get("shots", []) as Array):
		_apply_shot(Vector2i(shot_arr[0], shot_arr[1]))

	# Показуємо носи кораблів суперника на нашій прицільній карті
	for nose_arr in (turn.get("noses", []) as Array):
		var nose := Vector2i(nose_arr[0], nose_arr[1])
		if upper_grid.cell_state[nose.y][nose.x] == 0:
			upper_grid.set_cell(nose, 9)

	_opponent_turn_ready = true
	opponent_turn_applied.emit()

func _apply_shot(coord: Vector2i) -> void:
	if player_model.grid[coord.y][coord.x] == 1:
		player_model.grid[coord.y][coord.x] = 0
		player_model._rebuild_forbidden()
		lower_grid.set_cell(coord, 6)
		_on_hit(coord)
	else:
		var existing = lower_grid.cell_state[coord.y][coord.x]
		if existing != 10 and existing != 11:
			lower_grid.set_cell(coord, 5)

func _on_hit(coord: Vector2i) -> void:
	for ship in all_ships:
		if not ship.is_placed: continue
		for i in range(ship.cells.size()):
			if Vector2i(ship.cells[i].x, ship.cells[i].y) == coord:
				var ds = ship.get("damaged_sections")
				if not (ds is Array) or ds.size() != ship.size:
					ds = []
					for _j in range(ship.size): ds.append(false)
				ds[i] = true
				ship.set("damaged_sections", ds)
				ship.queue_redraw()
				_check_sunk(ship)
				return

func _check_sunk(ship: Node2D) -> void:
	var ds = ship.get("damaged_sections")
	if not (ds is Array) or ds.size() < ship.size:
		return
	for d in ds:
		if not d: return

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
	ship.queue_redraw()

# ── Заглушка execute_turn (EnemyAI інтерфейс) ────────────────

func execute_turn() -> void:
	pass  # хід суперника приходить через мережу
