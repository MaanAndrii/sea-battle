## GridRenderer.gd
## Малює одне поле 20×20.
## Звичайні лінії — пунктир, кожна 5-та — суцільна акцентна.
## Neon-режим: палітра #0a1e2a, #00ffaa, #ff00aa, #ffaa00, #00ffff.

extends Node2D
const SkinManager = preload("res://Scripts/SkinManager.gd")

@export var grid_color: Color = Color(0.2, 0.5, 0.9, 0.6)
@export var bg_color:   Color = Color(0.04, 0.1, 0.22, 1.0)

const GRID_SIZE: int = 20

var cell_size: float = 16.0
var cell_state: Array = []
var highlighted_cells: Array[Vector2i] = []
var alarm_cells: Array[Vector2i] = []   # drone contact zones (pulsing red)

# ── Neon palette ──────────────────────────────────────────────
const N_BG       := Color(0.039, 0.118, 0.165, 1.0)   # #0a1e2a
const N_CELL_A   := Color(0.102, 0.243, 0.290, 0.42)  # #1a3e4a tile A
const N_CELL_B   := Color(0.072, 0.180, 0.220, 0.28)  # darker tile B
const N_MISS_BG  := Color(0.04,  0.14,  0.20,  0.90)
const N_MISS_RNG := Color(0.0,   0.667, 1.0,   0.95)  # #00aaff
const N_HIT_BASE := Color(1.0,   0.0,   0.667, 0.92)  # #ff00aa
const N_PLANNED  := Color(0.0,   1.0,   1.0,   0.70)  # #00ffff
const N_DRONE    := Color(1.0,   0.667, 0.0,   0.80)  # #ffaa00
const N_BOMB     := Color(1.0,   0.667, 0.0,   1.0)   # #ffaa00
const N_NOSE     := Color(0.0,   1.0,   0.667, 0.95)  # #00ffaa
const N_WRECK_BG := Color(0.10,  0.10,  0.13,  0.88)
const N_WRECK_X  := Color(0.45,  0.45,  0.52,  0.90)
const N_WRECK_ZN := Color(0.06,  0.06,  0.10,  0.42)
const N_OLD_HIT  := Color(1.0,   0.0,   0.667, 0.22)
const N_SHIP     := Color(0.0,   1.0,   0.667, 0.55)  # #00ffaa setup
const N_LINE_MIN := Color(0.0,   0.667, 1.0,   0.18)  # #00aaff faint
const N_LINE_MAJ := Color(0.0,   1.0,   1.0,   0.65)  # #00ffff major
const N_BORDER   := Color(0.0,   1.0,   1.0,   0.90)  # #00ffff outer

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
	var neon  = SkinManager.current_skin() == SkinManager.SKIN_NEON

	# 1. Фон
	if neon:
		draw_rect(Rect2(0, 0, total, total), N_BG)
		_draw_sea_tiles()
	else:
		draw_rect(Rect2(0, 0, total, total), bg_color)

	# 2. Стан клітинок
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			if cell_state[y][x] != 0:
				_draw_cell_fill(x, y, cell_state[y][x])

	# 3. Підсвічування
	for coord in highlighted_cells:
		_draw_highlight(coord.x, coord.y)

	# 3b. Alarm zones (drone contact detection)
	for coord in alarm_cells:
		_draw_alarm(coord.x, coord.y)

	# 4. Лінії сітки
	_draw_grid_lines(total)

	# 5. Зовнішня рамка
	if neon:
		draw_rect(Rect2(-4, -4, total + 8, total + 8),
			Color(N_BORDER.r, N_BORDER.g, N_BORDER.b, 0.08), false, 1.0)
		draw_rect(Rect2(-2, -2, total + 4, total + 4),
			Color(N_BORDER.r, N_BORDER.g, N_BORDER.b, 0.22), false, 1.0)
		draw_rect(Rect2(0, 0, total, total), N_BORDER, false, 2.0)
	else:
		draw_rect(Rect2(0, 0, total, total),
			Color(grid_color.r, grid_color.g, grid_color.b, 0.8), false, 1.5)

# ─────────────────────────────────────────
#  Neon sea tile background
# ─────────────────────────────────────────

func _draw_sea_tiles() -> void:
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var rect  = _cell_rect(x, y)
			var shade = N_CELL_A if (x + y) % 2 == 0 else N_CELL_B
			draw_rect(rect, shade)

# ─────────────────────────────────────────
#  Лінії сітки
# ─────────────────────────────────────────

func _draw_grid_lines(total: float) -> void:
	var neon = SkinManager.current_skin() == SkinManager.SKIN_NEON
	var c    = grid_color
	var minor_color: Color
	var major_color: Color

	if neon:
		minor_color = N_LINE_MIN
		major_color = N_LINE_MAJ
	else:
		minor_color = Color(c.r, c.g, c.b, 0.18)
		major_color = Color(c.r, c.g, c.b, 0.78)

	for y in range(GRID_SIZE + 1):
		var start = Vector2(0,     y * cell_size)
		var end   = Vector2(total, y * cell_size)
		if y % 5 == 0:
			draw_line(start, end, major_color, 1.0)
		else:
			_draw_dashed(start, end, minor_color, 0.8)

	for x in range(GRID_SIZE + 1):
		var start = Vector2(x * cell_size, 0)
		var end   = Vector2(x * cell_size, total)
		if x % 5 == 0:
			draw_line(start, end, major_color, 1.0)
		else:
			_draw_dashed(start, end, minor_color, 0.8)

func _draw_dashed(from: Vector2, to: Vector2, color: Color, width: float) -> void:
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
	if SkinManager.current_skin() == SkinManager.SKIN_NEON:
		_draw_neon_cell(x, y, state, rect)
		return

	# Classic skin ───────────────────────────
	var color: Color
	match state:
		1:  color = Color(0.3,  0.6,  1.0,  0.70)
		2:  color = Color(1.0,  0.3,  0.2,  0.85)
		3:  color = Color(0.3,  0.5,  0.7,  0.40)
		4:  color = Color(1.0,  0.9,  0.2,  0.60)
		5:  color = Color(0.25, 0.35, 0.55, 0.80)
		6:  color = Color(0.85, 0.1,  0.1,  0.90)
		7:  color = Color(0.9,  0.75, 0.1,  0.60)
		8:  color = Color(0.85, 0.1,  0.1,  0.28)
		9:  color = Color(1.0,  0.85, 0.1,  0.35)
		10: color = Color(0.35, 0.35, 0.4,  0.65)
		11: color = Color(0.3,  0.3,  0.38, 0.28)
		12: color = Color(0.80, 0.45, 0.05, 0.80)
		_:  color = Color(1,    1,    1,    0.08)
	draw_rect(rect, color)

	var cx = rect.position.x + rect.size.x * 0.5
	var cy = rect.position.y + rect.size.y * 0.5
	var r  = min(rect.size.x, rect.size.y) * 0.28
	match state:
		5:
			draw_arc(Vector2(cx, cy), r, 0.0, TAU, 16, Color(0.55, 0.75, 1.0, 0.95), 1.5)
		6:
			draw_line(Vector2(cx-r, cy-r), Vector2(cx+r, cy+r), Color(1.0, 1.0, 1.0, 0.95), 2.0)
			draw_line(Vector2(cx+r, cy-r), Vector2(cx-r, cy+r), Color(1.0, 1.0, 1.0, 0.95), 2.0)
		8:
			draw_line(Vector2(cx-r, cy-r), Vector2(cx+r, cy+r), Color(1.0, 0.5, 0.5, 0.45), 1.0)
			draw_line(Vector2(cx+r, cy-r), Vector2(cx-r, cy+r), Color(1.0, 0.5, 0.5, 0.45), 1.0)
		9:
			var lc = Color(1.0, 0.95, 0.2, 0.95)
			var rr = r * 1.2
			draw_line(Vector2(cx+rr*0.35, cy-rr), Vector2(cx-rr*0.25, cy-rr*0.05), lc, 2.0)
			draw_line(Vector2(cx-rr*0.25, cy-rr*0.05), Vector2(cx+rr*0.15, cy-rr*0.05), lc, 2.0)
			draw_line(Vector2(cx+rr*0.15, cy-rr*0.05), Vector2(cx-rr*0.3, cy+rr), lc, 2.0)
		10:
			draw_line(Vector2(cx-r, cy-r), Vector2(cx+r, cy+r), Color(0.75, 0.75, 0.8, 0.85), 2.0)
			draw_line(Vector2(cx+r, cy-r), Vector2(cx-r, cy+r), Color(0.75, 0.75, 0.8, 0.85), 2.0)
			draw_rect(Rect2(cx-r*0.45, cy-r*0.45, r*0.9, r*0.9), Color(0.5, 0.5, 0.55, 0.35))
		11:
			draw_line(Vector2(cx, cy-r*0.55), Vector2(cx+r*0.55, cy),   Color(0.55, 0.55, 0.65, 0.60), 1.0)
			draw_line(Vector2(cx+r*0.55, cy), Vector2(cx, cy+r*0.55),   Color(0.55, 0.55, 0.65, 0.60), 1.0)
			draw_line(Vector2(cx, cy+r*0.55), Vector2(cx-r*0.55, cy),   Color(0.55, 0.55, 0.65, 0.60), 1.0)
			draw_line(Vector2(cx-r*0.55, cy), Vector2(cx, cy-r*0.55),   Color(0.55, 0.55, 0.65, 0.60), 1.0)
		7:
			draw_arc(Vector2(cx, cy), r, 0.0, TAU, 16, Color(1.0, 0.9, 0.2, 0.95), 1.5)
			draw_line(Vector2(cx-r*1.4, cy), Vector2(cx+r*1.4, cy),     Color(1.0, 0.9, 0.2, 0.95), 1.5)
			draw_line(Vector2(cx, cy-r*1.4), Vector2(cx, cy+r*1.4),     Color(1.0, 0.9, 0.2, 0.95), 1.5)
		12:
			draw_circle(Vector2(cx, cy+r*0.15), r*0.72, Color(0.12, 0.12, 0.12, 0.95))
			draw_line(Vector2(cx, cy-r*0.57), Vector2(cx+r*0.4, cy-r*1.15), Color(0.45, 0.35, 0.1, 0.9), 1.8)
			draw_circle(Vector2(cx+r*0.4, cy-r*1.15), r*0.28, Color(1.0, 0.85, 0.1, 0.95))

# ─────────────────────────────────────────
#  Neon cell renderer
# ─────────────────────────────────────────

func _draw_neon_cell(_x: int, _y: int, state: int, rect: Rect2) -> void:
	var cx = rect.position.x + rect.size.x * 0.5
	var cy = rect.position.y + rect.size.y * 0.5
	var r  = min(rect.size.x, rect.size.y) * 0.28
	var t  = Time.get_ticks_msec() * 0.001

	match state:
		1:  # Ship in setup — #00ffaa pixel block
			draw_rect(rect, Color(N_SHIP.r, N_SHIP.g, N_SHIP.b, 0.20))
			draw_rect(rect, Color(N_SHIP.r, N_SHIP.g, N_SHIP.b, 0.60), false, 1.2)

		4:  # Drone — #ffaa00 pulsing squares (pixel art)
			var pulse = 0.55 + 0.45 * sin(t * TAU * 1.3)
			var dc    = Color(N_DRONE.r, N_DRONE.g, N_DRONE.b, N_DRONE.a * pulse)
			draw_rect(rect, Color(0.20, 0.10, 0.0, 0.70))
			_draw_neon_glow(rect, Color(dc.r, dc.g, dc.b, 0.30), 2)
			# 4 pixel dots (drone silhouette)
			var ds = max(1.5, cell_size * 0.11)
			for dx in [-1, 1]:
				for dy in [-1, 1]:
					var px = cx + dx * r * 0.55 - ds * 0.5
					var py = cy + dy * r * 0.55 - ds * 0.5
					draw_rect(Rect2(px, py, ds, ds), Color(1.0, 0.85, 0.0, pulse))

		5:  # Miss — #00aaff ring on dark bg
			draw_rect(rect, N_MISS_BG)
			draw_arc(Vector2(cx, cy), r,       0.0, TAU, 12, N_MISS_RNG, 2.0)
			draw_arc(Vector2(cx, cy), r + 2.0, 0.0, TAU, 12,
				Color(N_MISS_RNG.r, N_MISS_RNG.g, N_MISS_RNG.b, 0.22), 1.5)

		6:  # Hit — #ff00aa → white explosion
			var flash    = 0.5 + 0.5 * sin(t * TAU * 0.9)
			var hit_col  = N_HIT_BASE.lerp(Color(1.0, 0.55, 0.80, 0.95), flash * 0.45)
			draw_rect(rect, Color(0.28, 0.0, 0.14, 0.90))
			_draw_neon_glow(rect, hit_col, 3)
			var lw = max(1.8, cell_size * 0.12)
			draw_line(Vector2(cx-r, cy-r), Vector2(cx+r, cy+r), Color(1.0, 1.0, 1.0, 0.95), lw)
			draw_line(Vector2(cx+r, cy-r), Vector2(cx-r, cy+r), Color(1.0, 1.0, 1.0, 0.95), lw)

		7:  # Planned shot — #00ffff crosshair, pulsing
			var plan_a  = 0.60 + 0.40 * sin(t * TAU * 1.6)
			var plan_c  = Color(N_PLANNED.r, N_PLANNED.g, N_PLANNED.b, plan_a)
			draw_rect(rect, Color(0.0, 0.18, 0.20, 0.55))
			draw_arc(Vector2(cx, cy), r,       0.0, TAU, 12, plan_c, 2.0)
			draw_arc(Vector2(cx, cy), r + 2.5, 0.0, TAU, 12,
				Color(plan_c.r, plan_c.g, plan_c.b, plan_a * 0.20), 1.5)
			draw_line(Vector2(cx-r*1.45, cy), Vector2(cx+r*1.45, cy), plan_c, 1.8)
			draw_line(Vector2(cx, cy-r*1.45), Vector2(cx, cy+r*1.45), plan_c, 1.8)

		8:  # Old hit — dim pink X
			draw_rect(rect, Color(0.18, 0.0, 0.09, 0.65))
			draw_line(Vector2(cx-r, cy-r), Vector2(cx+r, cy+r), Color(1.0, 0.3, 0.5, 0.38), 1.2)
			draw_line(Vector2(cx+r, cy-r), Vector2(cx-r, cy+r), Color(1.0, 0.3, 0.5, 0.38), 1.2)

		9:  # Nose mark — #00ffaa lightning bolt
			var lc = Color(N_NOSE.r, N_NOSE.g, N_NOSE.b, 0.95)
			draw_rect(rect, Color(0.0, 0.15, 0.10, 0.45))
			var rr = r * 1.2
			draw_line(Vector2(cx+rr*0.35, cy-rr),       Vector2(cx-rr*0.25, cy-rr*0.05), lc, 2.0)
			draw_line(Vector2(cx-rr*0.25, cy-rr*0.05),  Vector2(cx+rr*0.15, cy-rr*0.05), lc, 2.0)
			draw_line(Vector2(cx+rr*0.15, cy-rr*0.05),  Vector2(cx-rr*0.3,  cy+rr),      lc, 2.0)
			# glow on two main segments
			draw_line(Vector2(cx+rr*0.35, cy-rr),       Vector2(cx-rr*0.25, cy-rr*0.05),
				Color(lc.r, lc.g, lc.b, 0.20), 4.5)
			draw_line(Vector2(cx+rr*0.15, cy-rr*0.05),  Vector2(cx-rr*0.3,  cy+rr),
				Color(lc.r, lc.g, lc.b, 0.20), 4.5)

		10:  # Wreck — gray pixel cross
			draw_rect(rect, N_WRECK_BG)
			draw_line(Vector2(cx-r, cy-r), Vector2(cx+r, cy+r), N_WRECK_X, 2.0)
			draw_line(Vector2(cx+r, cy-r), Vector2(cx-r, cy+r), N_WRECK_X, 2.0)
			draw_rect(Rect2(cx-r*0.42, cy-r*0.42, r*0.84, r*0.84),
				Color(0.30, 0.30, 0.35, 0.28))

		11:  # Wreck zone — subtle dark
			draw_rect(rect, N_WRECK_ZN)

		12:  # Bomb — #ffaa00 pixel bomb, spark pulses
			var bp     = 0.70 + 0.30 * sin(t * TAU * 2.0)
			var bomb_c = Color(N_BOMB.r, N_BOMB.g, N_BOMB.b, N_BOMB.a * bp)
			draw_rect(rect, Color(0.12, 0.06, 0.0, 0.88))
			# Dark body
			draw_circle(Vector2(cx, cy + r * 0.12), r * 0.76, Color(0.05, 0.05, 0.07, 0.95))
			# Orange pixel highlight on bomb
			draw_rect(Rect2(cx - r*0.25, cy - r*0.25, r*0.30, r*0.28),
				Color(1.0, 0.75, 0.0, 0.45 * bp))
			# Fuse
			draw_line(Vector2(cx, cy - r*0.62), Vector2(cx + r*0.48, cy - r*1.22),
				Color(0.5, 0.35, 0.1, 0.9), 1.8)
			# Spark glow
			var spark_r = r * 0.32 * bp
			draw_circle(Vector2(cx + r*0.48, cy - r*1.22), spark_r * 1.8,
				Color(bomb_c.r, bomb_c.g, bomb_c.b, 0.25))
			draw_circle(Vector2(cx + r*0.48, cy - r*1.22), spark_r, bomb_c)

# ─────────────────────────────────────────
#  Neon glow helper — outer halos then fill
# ─────────────────────────────────────────

func _draw_neon_glow(rect: Rect2, color: Color, layers: int) -> void:
	for i in range(layers, 0, -1):
		var grow = float(i) * 2.5
		draw_rect(rect.grow(grow),
			Color(color.r, color.g, color.b, color.a * 0.14 / float(i)))
	draw_rect(rect, color)

# ─────────────────────────────────────────
#  Highlight
# ─────────────────────────────────────────

func _draw_highlight(x: int, y: int) -> void:
	var rect = _cell_rect(x, y)
	var neon = SkinManager.current_skin() == SkinManager.SKIN_NEON
	if neon:
		var t     = Time.get_ticks_msec() * 0.001
		var alpha = 0.22 + 0.18 * sin(t * TAU * 1.2)
		draw_rect(rect, Color(0.0, 1.0, 1.0, alpha))
		draw_rect(rect, Color(0.0, 1.0, 1.0, 0.75), false, 1.5)
		draw_rect(rect.grow(2.0), Color(0.0, 1.0, 1.0, 0.12), false, 1.0)
	else:
		var alpha = 0.25 + 0.15 * sin(Time.get_ticks_msec() / 300.0)
		draw_rect(rect, Color(1.0, 1.0, 0.5, alpha))
		draw_rect(rect, Color(1.0, 1.0, 0.5, 0.6), false, 1.0)

func _draw_alarm(x: int, y: int) -> void:
	var rect  = _cell_rect(x, y)
	var t     = Time.get_ticks_msec() * 0.001
	var alpha = 0.07 + 0.07 * sin(t * TAU * 1.4)
	draw_rect(rect, Color(1.0, 0.08, 0.08, alpha))
	draw_rect(rect, Color(1.0, 0.12, 0.12, alpha * 2.2), false, 1.2)

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

func set_alarm_cells(cells: Array[Vector2i]) -> void:
	alarm_cells = cells
	queue_redraw()

func _needs_animation() -> bool:
	if highlighted_cells.size() > 0 or alarm_cells.size() > 0:
		return true
	if SkinManager.current_skin() != SkinManager.SKIN_NEON:
		return false
	for row in cell_state:
		for s in row:
			if s == 4 or s == 6 or s == 7 or s == 12:
				return true
	return false

func _process(_delta: float) -> void:
	if _needs_animation():
		queue_redraw()
