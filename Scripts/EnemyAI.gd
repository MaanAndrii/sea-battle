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
		# Рахуємо скільки кораблів є
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
	# Спочатку намагаємось стріляти по невідомих клітинках
	# Простий алгоритм: випадкова клітинка яку ще не обстрілювали
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
	var is_hit = player_model.grid[coord.y][coord.x] == 1

	if is_hit:
		# Пошкоджуємо клітинку в GridModel
		player_model.grid[coord.y][coord.x] = 0
		player_model._rebuild_forbidden()
		# Маркуємо корабель як пошкоджений
		_mark_ship_damaged(coord)
		lower_grid.set_cell(coord, 6)  # 💥 червоний
	else:
		lower_grid.set_cell(coord, 5)  # 🌊 синє коло

func _mark_ship_damaged(coord: Vector2i) -> void:
	for ship in all_ships:
		for c in ship.cells:
			if Vector2i(c.x, c.y) == coord:
				ship.set("damaged", true)
				# Помаранчева рамка на пошкодженому кораблі
				ship.queue_redraw()
				return
