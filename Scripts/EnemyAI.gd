## EnemyAI.gd
## Випадкові постріли ворога по кораблях гравця.
## 12 одиниць енергії = 12 пострілів за хід.
## Індикація: влучання 💥 на нижньому полі, мітка на кораблі що отримав удар.

extends Node

const ENERGY_PER_TURN = 12

var lower_grid:   Node2D = null   # поле гравця
var player_model          = null   # GridModel гравця
var all_ships:    Array   = []

var _rng = RandomNumberGenerator.new()

# Координати куди вже стріляли
var shot_history: Array[Vector2i] = []

func setup(p_lower: Node2D, p_model, p_ships: Array) -> void:
	lower_grid   = p_lower
	player_model = p_model
	all_ships    = p_ships
	_rng.randomize()

# ── Виконати хід ворога ─────────────────────────────────────

func execute_turn() -> void:
	print("[EnemyAI] execute_turn: player_model=", player_model != null)
	if player_model:
		var count = 0
		for y in range(20):
			for x in range(20):
				if player_model.grid[y][x] == 1: count += 1
		print("[EnemyAI] клітинок кораблів: ", count)
	var energy = ENERGY_PER_TURN
	var shots_this_turn: Array[Vector2i] = []

	while energy > 0:
		var coord = _pick_target()
		if coord == Vector2i(-1, -1):
			break  # всі клітинки вже обстріляні

		shot_history.append(coord)
		shots_this_turn.append(coord)
		energy -= 1

		await get_tree().create_timer(0.12).timeout
		_resolve(coord)

func _pick_target() -> Vector2i:
	var attempts = 0
	while attempts < 400:
		attempts += 1
		var x = _rng.randi_range(0, 19)
		var y = _rng.randi_range(0, 19)
		var c = Vector2i(x, y)
		if not shot_history.has(c):
			return c
	return Vector2i(-1, -1)

func _resolve(coord: Vector2i) -> void:
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
				# Ініціалізуємо damaged_sections якщо ще не є
				var ds = ship.get("damaged_sections")
				if not (ds is Array) or ds.size() != ship.size:
					ds = []
					for _j in range(ship.size): ds.append(false)
				ds[i] = true
				ship.set("damaged_sections", ds)
				ship.set("damaged", true)
				ship.queue_redraw()
				_check_sunk(ship)
				return

func _check_sunk(ship: Node2D) -> void:
	# Перевіряємо за секціями (індексами), а не координатами —
	# щоб корабель що переміщувався після поранення вважався потопленим коректно
	var ds = ship.get("damaged_sections")
	if not (ds is Array) or ds.size() < ship.size:
		return
	for d in ds:
		if not d: return  # є неураженa секція

	# Всі секції уражені → потопити
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
