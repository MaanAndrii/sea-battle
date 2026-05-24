## GridRenderer.gd
## Малює одне поле 20×20.
## Звичайні лінії — пунктир, кожна 5-та — суцільна акцентна.

extends Node2D

@export var grid_color: Color = Color(0.2, 0.5, 0.9, 0.6)
@export var bg_color:   Color = Color(0.04, 0.1, 0.22, 1.0)

const GRID_SIZE: int = 20

var cell_size: float = 16.0
var cell_state: Array = []
var highlighted_cells: Array[Vector2i] = []

# ─────────────────────────────────────────
#  Ініціалізація
# ─────────────────────────────────────────

func _ready() -> void:
	_init_state()

func setup(p_cell_size: float) -> void:
	cell_size = p_cell_size
	_init_state()
	queue_redraw()

func _init_state() -> void:
	cell_state = []
	for y in range(GRID_SIZE):
		var row = []
		for x in range(GRID_SIZE):
			row.append(0)
		cell_state.append(row)

# ─────────────────────────────────────────
#  Основний рендер
# ─────────────────────────────────────────

func _draw() -> void:
	if cell_state.size() < GRID_SIZE:
		return
	var total = cell_size * GRID_SIZE

	# 1. Фон
	draw_rect(Rect2(0, 0, total, total), bg_color)

	# 2. Стан клітинок
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			if cell_state[y][x] != 0:
				_draw_cell_fill(x, y, cell_state[y][x])

	# 3. Підсвічування
	for coord in highlighted_cells:
		_draw_highlight(coord.x, coord.y)

	# 4. Лінії сітки (пунктир + акцент)
	_draw_grid_lines(total)

	# 6. Зовнішня рамка
	draw_rect(Rect2(0, 0, total, total), Color(grid_color.r, grid_color.g, grid_color.b, 0.8), false, 1.5)

# ─────────────────────────────────────────
#  Лінії сітки
# ─────────────────────────────────────────

func _draw_grid_lines(total: float) -> void:
	var c = grid_color
	var minor_color = Color(c.r, c.g, c.b, 0.18)
	var major_color = Color(c.r, c.g, c.b, 0.78)

	for y in range(GRID_SIZE + 1):
		var start = Vector2(0,     y * cell_size)
		var end   = Vector2(total, y * cell_size)
		if y % 5 == 0:
			# Акцентна — суцільна яскрава
			draw_line(start, end, major_color, 1.0)
		else:
			# Звичайна — пунктир
			_draw_dashed(start, end, minor_color, 0.8)

	for x in range(GRID_SIZE + 1):
		var start = Vector2(x * cell_size, 0)
		var end   = Vector2(x * cell_size, total)
		if x % 5 == 0:
			draw_line(start, end, major_color, 1.0)
		else:
			_draw_dashed(start, end, minor_color, 0.8)

## Пунктирна лінія: штрих/проміжок залежить від розміру клітинки
func _draw_dashed(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	# Дуже дрібний пунктир щоб чітко читалась саме 1×1 сітка,
	# без візуального ефекту "кроку 2×2".
	var dash      = max(1.0, cell_size * 0.10)
	var gap       = max(1.0, cell_size * 0.10)
	var dir       = (to - from).normalized()
	var remaining = from.distance_to(to)
	var cur       = from
	var drawing   = true

	while remaining > 0.01:
		var seg = min(dash if drawing else gap, remaining)
		if drawing:
			draw_line(cur, cur + dir * seg, color, width)
		cur       += dir * seg
		remaining -= seg
		drawing    = !drawing

# ─────────────────────────────────────────
#  Заповнення клітинок
# ─────────────────────────────────────────

func _draw_cell_fill(x: int, y: int, state: int) -> void:
	var rect = _cell_rect(x, y)
	var color: Color
	match state:
		1: color = Color(0.3,  0.6,  1.0,  0.70)  # корабель
		2: color = Color(1.0,  0.3,  0.2,  0.85)  # влучання (legacy)
		3: color = Color(0.3,  0.5,  0.7,  0.40)  # промах (legacy)
		4: color = Color(1.0,  0.9,  0.2,  0.60)  # дрон
		5: color = Color(0.25, 0.35, 0.55, 0.80)  # промах 🌊
		6: color = Color(0.85, 0.1,  0.1,  0.90)  # влучання 💥
		7: color = Color(0.9,  0.75, 0.1,  0.60)  # запланований постріл ⊕
		8: color = Color(0.85, 0.1,  0.1,  0.28)  # потьмяніле влучання (тур назад)
		9: color = Color(1.0,  0.85, 0.1,  0.35)  # ніс корабля ⚡ (радар ворога)
		10: color = Color(0.35, 0.35, 0.4,  0.65)  # уламки ⊗
		11: color = Color(0.3,  0.3,  0.38, 0.28)  # зона уламків (сусідні клітинки)
		12: color = Color(0.80, 0.45, 0.05, 0.80)  # бомба 💣
		_: color = Color(1,    1,    1,    0.08)
	draw_rect(rect, color)

	# Символьні маркери поверх заливки
	var cx  = rect.position.x + rect.size.x * 0.5
	var cy  = rect.position.y + rect.size.y * 0.5
	var r   = min(rect.size.x, rect.size.y) * 0.28
	match state:
		5:  # Промах — коло
			draw_arc(Vector2(cx, cy), r, 0.0, TAU, 16,
				Color(0.55, 0.75, 1.0, 0.95), 1.5)
		6:  # Влучання — хрест ✕
			draw_line(Vector2(cx-r, cy-r), Vector2(cx+r, cy+r),
				Color(1.0, 1.0, 1.0, 0.95), 2.0)
			draw_line(Vector2(cx+r, cy-r), Vector2(cx-r, cy+r),
				Color(1.0, 1.0, 1.0, 0.95), 2.0)
		8:  # Потьмяніле влучання — тонкий хрест
			draw_line(Vector2(cx-r, cy-r), Vector2(cx+r, cy+r),
				Color(1.0, 0.5, 0.5, 0.45), 1.0)
			draw_line(Vector2(cx+r, cy-r), Vector2(cx-r, cy+r),
				Color(1.0, 0.5, 0.5, 0.45), 1.0)
		9:  # Ніс корабля ⚡ — блискавка
			var lc = Color(1.0, 0.95, 0.2, 0.95)
			var rr = r * 1.2
			# верхня частина: праворуч-зверху → ліворуч-центр
			draw_line(Vector2(cx + rr * 0.35, cy - rr), Vector2(cx - rr * 0.25, cy - rr * 0.05), lc, 2.0)
			# перекладина: ліворуч → праворуч (центр)
			draw_line(Vector2(cx - rr * 0.25, cy - rr * 0.05), Vector2(cx + rr * 0.15, cy - rr * 0.05), lc, 2.0)
			# нижня частина: праворуч-центр → ліворуч-знизу
			draw_line(Vector2(cx + rr * 0.15, cy - rr * 0.05), Vector2(cx - rr * 0.3, cy + rr), lc, 2.0)
		10:  # Уламки — сірий хрест ⊗
			draw_line(Vector2(cx - r, cy - r), Vector2(cx + r, cy + r),
				Color(0.75, 0.75, 0.8, 0.85), 2.0)
			draw_line(Vector2(cx + r, cy - r), Vector2(cx - r, cy + r),
				Color(0.75, 0.75, 0.8, 0.85), 2.0)
			draw_rect(Rect2(cx - r * 0.45, cy - r * 0.45, r * 0.9, r * 0.9),
				Color(0.5, 0.5, 0.55, 0.35))
		11:  # Зона уламків — маленький сірий ромб
			draw_line(Vector2(cx, cy - r * 0.55), Vector2(cx + r * 0.55, cy),
				Color(0.55, 0.55, 0.65, 0.60), 1.0)
			draw_line(Vector2(cx + r * 0.55, cy), Vector2(cx, cy + r * 0.55),
				Color(0.55, 0.55, 0.65, 0.60), 1.0)
			draw_line(Vector2(cx, cy + r * 0.55), Vector2(cx - r * 0.55, cy),
				Color(0.55, 0.55, 0.65, 0.60), 1.0)
			draw_line(Vector2(cx - r * 0.55, cy), Vector2(cx, cy - r * 0.55),
				Color(0.55, 0.55, 0.65, 0.60), 1.0)
		7:  # Запланований — прицільник ⊕
			draw_arc(Vector2(cx, cy), r, 0.0, TAU, 16,
				Color(1.0, 0.9, 0.2, 0.95), 1.5)
			draw_line(Vector2(cx - r * 1.4, cy), Vector2(cx + r * 1.4, cy),
				Color(1.0, 0.9, 0.2, 0.95), 1.5)
			draw_line(Vector2(cx, cy - r * 1.4), Vector2(cx, cy + r * 1.4),
				Color(1.0, 0.9, 0.2, 0.95), 1.5)
		12:  # Bomb
			draw_circle(Vector2(cx, cy + r*0.15), r * 0.72, Color(0.12, 0.12, 0.12, 0.95))
			draw_line(Vector2(cx, cy - r*0.57), Vector2(cx + r*0.4, cy - r*1.15), Color(0.45, 0.35, 0.1, 0.9), 1.8)
			draw_circle(Vector2(cx + r*0.4, cy - r*1.15), r * 0.28, Color(1.0, 0.85, 0.1, 0.95))

func _draw_highlight(x: int, y: int) -> void:
	var rect  = _cell_rect(x, y)
	var alpha = 0.25 + 0.15 * sin(Time.get_ticks_msec() / 300.0)
	draw_rect(rect, Color(1.0, 1.0, 0.5, alpha))
	draw_rect(rect, Color(1.0, 1.0, 0.5, 0.6), false, 1.0)


# ─────────────────────────────────────────
#  Утиліти
# ─────────────────────────────────────────

func _cell_rect(x: int, y: int) -> Rect2:
	var m = 0.5
	return Rect2(x * cell_size + m, y * cell_size + m,
				 cell_size - m * 2,  cell_size - m * 2)

func world_to_grid(world_pos: Vector2) -> Vector2i:
	var lp = world_pos - global_position
	return Vector2i(int(lp.x / cell_size), int(lp.y / cell_size))

func grid_to_world(coord: Vector2i) -> Vector2:
	return global_position + Vector2(
		coord.x * cell_size + cell_size / 2.0,
		coord.y * cell_size + cell_size / 2.0)

func is_valid(coord: Vector2i) -> bool:
	return coord.x >= 0 and coord.x < GRID_SIZE \
	   and coord.y >= 0 and coord.y < GRID_SIZE

func set_cell(coord: Vector2i, state: int) -> void:
	if is_valid(coord):
		cell_state[coord.y][coord.x] = state
		queue_redraw()

func set_highlight(cells: Array[Vector2i]) -> void:
	highlighted_cells = cells
	queue_redraw()

func _process(_delta: float) -> void:
	if highlighted_cells.size() > 0:
		queue_redraw()
