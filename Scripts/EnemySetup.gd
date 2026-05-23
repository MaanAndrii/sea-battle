## EnemySetup.gd
## Випадкова розстановка ворожих кораблів на верхньому полі для тестування.

extends Node

const FLEET = [
	{ "size": 5, "count": 1 },
	{ "size": 4, "count": 2 },
	{ "size": 3, "count": 3 },
	{ "size": 2, "count": 4 },
]

var upper_grid:  Node2D = null
var enemy_model          = null   # окремий GridModel для ворога

# Кожен елемент: { all_cells: Array[Vector2i], remaining: Array[Vector2i] }
# all_cells — всі клітинки корабля (для очищення поля при потопленні)
# remaining  — ще не уражені клітинки
var _ships: Array = []

var _ui_layer:  CanvasLayer = null
var _place_btn: Button      = null
var _clear_btn: Button      = null

signal enemy_placed

func setup(p_upper: Node2D) -> void:
	upper_grid  = p_upper
	enemy_model = load("res://Scripts/GridModel.gd").new()

	_ui_layer  = CanvasLayer.new()
	get_parent().add_child(_ui_layer)
	_build_ui()

func _build_ui() -> void:
	var vp = get_viewport().get_visible_rect().size

	_place_btn = Button.new()
	_place_btn.text = "🎲 Розставити ворога"
	_place_btn.size = Vector2(190, 40)
	_place_btn.position = Vector2(vp.x / 2.0 - 95, vp.y / 2.0 - 20)
	_place_btn.add_theme_font_size_override("font_size", 13)
	_place_btn.modulate = Color(1.0, 0.6, 0.2)
	_place_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_place_btn.pressed.connect(_on_place)
	_ui_layer.add_child(_place_btn)

	_clear_btn = Button.new()
	_clear_btn.text = "✕ Очистити"
	_clear_btn.size = Vector2(110, 40)
	_clear_btn.position = Vector2(vp.x / 2.0 - 55, vp.y / 2.0 + 28)
	_clear_btn.add_theme_font_size_override("font_size", 12)
	_clear_btn.modulate = Color(0.7, 0.7, 0.7)
	_clear_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_clear_btn.visible = false
	_clear_btn.pressed.connect(_on_clear)
	_ui_layer.add_child(_clear_btn)

# ── Розстановка ──────────────────────────────────────────────

func _on_place() -> void:
	_on_clear()   # скидаємо попередню

	var rng = RandomNumberGenerator.new()
	rng.randomize()

	for entry in FLEET:
		for _i in range(entry["count"]):
			var placed = false
			var attempts = 0
			while not placed and attempts < 200:
				attempts += 1
				var horiz = rng.randi() % 2 == 0
				var max_x = 20 - (entry["size"] if horiz else 1)
				var max_y = 20 - (1 if horiz else entry["size"])
				var coord = Vector2i(rng.randi_range(0, max_x),
									 rng.randi_range(0, max_y))
				if enemy_model.can_place(coord, entry["size"], horiz):
					var cells = enemy_model.place(coord, entry["size"], horiz)
					_ships.append({
						"all_cells": cells.duplicate(),
						"remaining": cells.duplicate(),
					})
					placed = true

	_render_enemy()
	_place_btn.text    = "🎲 Перегенерувати"
	_clear_btn.visible = true
	emit_signal("enemy_placed")

func _on_clear() -> void:
	enemy_model = load("res://Scripts/GridModel.gd").new()
	_ships.clear()
	for y in range(20):
		for x in range(20):
			if upper_grid.cell_state[y][x] == 1:
				upper_grid.set_cell(Vector2i(x, y), 0)
	_clear_btn.visible = false
	_place_btn.text    = "🎲 Розставити ворога"

func _render_enemy() -> void:
	for y in range(20):
		for x in range(20):
			if enemy_model.grid[y][x] == 1:
				upper_grid.set_cell(Vector2i(x, y), 1)

# ── Перевірка влучання (викликається з CombatManager) ────────
func is_hit(coord: Vector2i) -> bool:
	if not enemy_model: return false
	return enemy_model.grid[coord.y][coord.x] == 1

## Позначити клітинку як уражену; якщо всі секції знищено — потопити корабель
func mark_hit(coord: Vector2i) -> void:
	if not enemy_model:
		return
	enemy_model.grid[coord.y][coord.x] = 0
	for ship in _ships:
		var rem := ship["remaining"] as Array
		for i in range(rem.size()):
			if rem[i] == coord:
				rem.remove_at(i)
				if rem.is_empty():
					_sink_ship(ship)
				return

func _sink_ship(ship: Dictionary) -> void:
	# Замінюємо клітинки потопленого корабля на уламки ⊗
	for c in ship["all_cells"]:
		upper_grid.set_cell(c, 10)
	_ships.erase(ship)
