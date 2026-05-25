## Ship.gd
## Ніс = cells[0], Корма = cells[last]
## Секції: damaged_sections[i]=true → секція i уражена (i=0 ніс)
## Потоплений корабель: всі секції = true → is_sunk()

extends Node2D
const SkinManager = preload("res://Scripts/SkinManager.gd")

var ship_name:        String = ""
var size:             int    = 1
var rotation_step:    int    = 0   # 0=→  1=↓  2=←  3=↑
var cells:            Array  = []
var is_placed:        bool   = false
var hover_valid:      bool   = true
var locked:           bool   = false
var setup_locked:     bool   = false
var damaged_sections: Array  = []   # Array[bool], size = size, index 0 = ніс
var shoot_marked:     bool   = false
var has_moved:        bool   = false
var is_selected:      bool   = false
var cell_size:        float  = 16.0

# ── Particle system ───────────────────────────────────────────
var _particles: Array = []  # [{pos, vel, life, max_life}]

## Є хоча б одна уражена секція
var damaged: bool:
	get:
		for d in damaged_sections:
			if d: return true
		return false

# ── Classic colours ─────────────────────────────────────────────
const C_BODY         = Color(0.20, 0.44, 0.88, 0.90)
const C_LOCKED       = Color(0.20, 0.44, 0.88, 0.90)
const C_HOVER_OK     = Color(0.22, 0.92, 0.38, 0.72)
const C_HOVER_NO     = Color(0.92, 0.20, 0.15, 0.72)
const C_SECTION_HIT  = Color(0.18, 0.05, 0.03, 0.97)
const C_HIT_MARK     = Color(1.00, 0.32, 0.06, 1.00)
const C_HIT_INNER    = Color(0.85, 0.18, 0.02, 0.40)
const C_BORDER       = Color(0.50, 0.75, 1.00, 0.85)
const C_BORDER_DMG   = Color(1.00, 0.52, 0.08, 0.92)
const C_SECTION_LINE = Color(0.08, 0.10, 0.16, 0.38)
const C_NOSE_NORMAL  = Color(0.20, 1.00, 0.35, 1.00)
const C_NOSE_SHOT    = Color(1.00, 0.18, 0.10, 1.00)
const C_STERN_LINE   = Color(0.50, 0.68, 1.00, 0.75)
const C_SELECTED_GLOW = Color(1.00, 0.95, 0.35, 0.95)

# ── Neon colours ─────────────────────────────────────────────────
const N_BODY         = Color(0.0,  1.0,  0.667, 0.88)  # #00ffaa
const N_HOVER_OK     = Color(0.0,  1.0,  0.667, 0.65)  # #00ffaa
const N_HOVER_NO     = Color(1.0,  0.243, 0.243, 0.70)  # #ff3e3e
const N_SECTION_HIT  = Color(0.05, 0.02,  0.02, 0.97)
const N_HIT_MARK     = Color(1.0,  0.0,   0.667, 1.0)   # #ff00aa
const N_HIT_INNER    = Color(1.0,  0.0,   0.4,   0.30)
const N_BORDER       = Color(0.0,  0.8,   0.55,  0.80)  # #00cc8c
const N_BORDER_DMG   = Color(1.0,  0.667, 0.0,   0.90)  # #ffaa00
const N_SECTION_LINE = Color(0.0,  0.15,  0.12,  0.50)
const N_NOSE_NORMAL  = Color(0.0,  1.0,   0.667, 1.0)   # #00ffaa
const N_NOSE_SHOT    = Color(1.0,  0.243, 0.243, 1.0)   # #ff3e3e
const N_STERN_LINE   = Color(0.0,  0.8,   0.55,  0.75)
const N_GLOW_SEL     = Color(0.0,  1.0,   1.0,   1.0)   # #00ffff selection glow
const N_PARTICLE     = Color(0.0,  1.0,   0.667, 1.0)   # #00ffaa particle

func setup(p_name: String, p_size: int, p_cell_size: float) -> void:
	ship_name = p_name
	size      = p_size
	cell_size = p_cell_size
	damaged_sections = []
	for _i in range(size): damaged_sections.append(false)
	queue_redraw()

# ── Поворот: ніс фіксований, хвіст заноситься ───────────────
func rotate_cw() -> void:
	rotation_step = (rotation_step + 1) % 4
	queue_redraw()

func rotate_ccw() -> void:
	rotation_step = (rotation_step + 3) % 4
	queue_redraw()

var is_horizontal: bool:
	get: return rotation_step == 0 or rotation_step == 2

func pixel_size() -> Vector2:
	return Vector2(cell_size * size, cell_size) if is_horizontal \
		else Vector2(cell_size, cell_size * size)

func _is_sunk() -> bool:
	if damaged_sections.size() < size: return false
	for d in damaged_sections:
		if not d: return false
	return true

func get_rotated_cells_cw() -> Array:
	if cells.is_empty(): return []
	var nose = Vector2i(cells[0].x, cells[0].y)
	var new_step = (rotation_step + 1) % 4
	return _cells_from_nose(nose, new_step)

func get_rotated_cells_ccw() -> Array:
	if cells.is_empty(): return []
	var nose = Vector2i(cells[0].x, cells[0].y)
	var new_step = (rotation_step + 3) % 4
	return _cells_from_nose(nose, new_step)

func _cells_from_nose(nose: Vector2i, step: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for i in range(size):
		match step:
			0: result.append(Vector2i(nose.x - i, nose.y))
			1: result.append(Vector2i(nose.x, nose.y - i))
			2: result.append(Vector2i(nose.x + i, nose.y))
			3: result.append(Vector2i(nose.x, nose.y + i))
	return result

func tail_cell() -> Vector2i:
	if cells.is_empty(): return Vector2i.ZERO
	var nose = Vector2i(cells[0].x, cells[0].y)
	match rotation_step:
		0: return Vector2i(nose.x - (size - 1), nose.y)
		1: return Vector2i(nose.x, nose.y - (size - 1))
		2: return nose
		3: return nose
	return nose

func rotated_tail_cw() -> Vector2i:
	var nose = Vector2i(cells[0].x, cells[0].y)
	var new_step = (rotation_step + 1) % 4
	return _tail_for_step(nose, new_step)

func rotated_tail_ccw() -> Vector2i:
	var nose = Vector2i(cells[0].x, cells[0].y)
	var new_step = (rotation_step + 3) % 4
	return _tail_for_step(nose, new_step)

func _tail_for_step(nose: Vector2i, step: int) -> Vector2i:
	match step:
		0: return Vector2i(nose.x - (size - 1), nose.y)
		1: return Vector2i(nose.x, nose.y - (size - 1))
		2: return nose
		3: return nose
	return nose

# ─────────────────────────────────────────
#  Particles
# ─────────────────────────────────────────

func spawn_particles() -> void:
	if SkinManager.current_skin() != SkinManager.SKIN_NEON:
		return
	var center = pixel_size() * 0.5
	for i in range(14):
		var angle    = (float(i) / 14.0) * TAU + randf() * 0.4
		var speed    = randf_range(22.0, 72.0)
		var lifetime = randf_range(0.30, 0.58)
		_particles.append({
			"pos":      center,
			"vel":      Vector2(cos(angle), sin(angle)) * speed,
			"life":     lifetime,
			"max_life": lifetime,
		})

# ─────────────────────────────────────────
#  Рендер
# ─────────────────────────────────────────

func _draw() -> void:
	var ps   = pixel_size()
	var m    = 1.5
	var sunk = _is_sunk()
	var neon = SkinManager.current_skin() == SkinManager.SKIN_NEON

	if not is_placed and not sunk:
		# Drag mode
		var hok = N_HOVER_OK if neon else C_HOVER_OK
		var hno = N_HOVER_NO if neon else C_HOVER_NO
		draw_rect(Rect2(m, m, ps.x - m*2, ps.y - m*2),
			hok if hover_valid else hno)
	else:
		# Sections
		for i in range(size):
			var r   = _section_rect(i)
			var hit = damaged_sections.size() > i and damaged_sections[i]
			if hit:
				draw_rect(r, N_SECTION_HIT if neon else C_SECTION_HIT)
				draw_rect(Rect2(r.position + Vector2(0.5, 0.5), r.size - Vector2(1, 1)),
					N_HIT_INNER if neon else C_HIT_INNER, false, 1.0)
				_draw_section_x(r, neon)
			else:
				draw_rect(r, _body_color())

	# Section dividers
	for i in range(1, size):
		var sc = N_SECTION_LINE if neon else C_SECTION_LINE
		if is_horizontal:
			draw_line(Vector2(i*cell_size, m+1), Vector2(i*cell_size, ps.y-m-1), sc, 1.2)
		else:
			draw_line(Vector2(m+1, i*cell_size), Vector2(ps.x-m-1, i*cell_size), sc, 1.2)

	# Outer border
	var bw = 2.0 if (is_placed and damaged) else 1.2
	var bc = (N_BORDER_DMG if neon else C_BORDER_DMG) if damaged \
		else (N_BORDER if neon else C_BORDER)
	draw_rect(Rect2(m, m, ps.x-m*2, ps.y-m*2), bc, false, bw)

	# Selection glow
	if is_selected and is_placed and not sunk:
		if neon:
			var glow_a = 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.001 * TAU * 1.1)
			draw_rect(Rect2(-3, -3, ps.x+6, ps.y+6),
				Color(N_GLOW_SEL.r, N_GLOW_SEL.g, N_GLOW_SEL.b, glow_a * 0.08), false, 1.0)
			draw_rect(Rect2(-1, -1, ps.x+2, ps.y+2),
				Color(N_GLOW_SEL.r, N_GLOW_SEL.g, N_GLOW_SEL.b, glow_a * 0.25), false, 1.0)
			draw_rect(Rect2(0, 0, ps.x, ps.y),
				Color(N_GLOW_SEL.r, N_GLOW_SEL.g, N_GLOW_SEL.b, glow_a * 0.70), false, 2.0)
		else:
			draw_rect(Rect2(m-1.5, m-1.5, ps.x-(m-1.5)*2, ps.y-(m-1.5)*2),
				C_SELECTED_GLOW, false, 2.6)

	# Nose & stern
	_draw_nose(ps, neon)
	_draw_stern(ps, neon)

	# Name label
	if cell_size >= 13.0:
		var fsz = max(6, int(cell_size * 0.33))
		draw_string(ThemeDB.fallback_font,
			Vector2(m + 2, ps.y * 0.5 + fsz * 0.35),
			ship_name.left(3), HORIZONTAL_ALIGNMENT_LEFT, -1, fsz,
			Color(0.8, 1.0, 0.9, 0.45) if neon else Color(1, 1, 1, 0.40))

	# Particles (neon only)
	for p in _particles:
		var fade = p["life"] / p["max_life"]
		var ps_r = max(1.0, 3.5 * fade)
		var col  = Color(N_PARTICLE.r, N_PARTICLE.g, N_PARTICLE.b, fade * 0.9)
		draw_circle(p["pos"], ps_r, col)
		if ps_r > 1.8:
			draw_circle(p["pos"], ps_r * 1.9, Color(col.r, col.g, col.b, col.a * 0.22))

func _section_rect(i: int) -> Rect2:
	var m = 1.5
	match rotation_step:
		0: return Rect2((size-1-i)*cell_size + m, m,   cell_size - m*2, cell_size - m*2)
		1: return Rect2(m, (size-1-i)*cell_size + m,   cell_size - m*2, cell_size - m*2)
		2: return Rect2(i*cell_size + m,           m,   cell_size - m*2, cell_size - m*2)
		3: return Rect2(m, i*cell_size + m,             cell_size - m*2, cell_size - m*2)
	return Rect2(m, m, cell_size - m*2, cell_size - m*2)

func _draw_section_x(r: Rect2, neon: bool) -> void:
	var pad = max(2.5, r.size.x * 0.17)
	var lw  = max(1.8, r.size.x * 0.13)
	var col = N_HIT_MARK if neon else C_HIT_MARK
	draw_line(r.position + Vector2(pad, pad),
	          r.position + r.size - Vector2(pad, pad), col, lw)
	draw_line(r.position + Vector2(r.size.x - pad, pad),
	          r.position + Vector2(pad, r.size.y - pad), col, lw)

func _draw_nose(ps: Vector2, neon: bool) -> void:
	var nc  = _nose_center(ps)
	var col: Color
	if neon:
		col = N_NOSE_SHOT if shoot_marked else N_NOSE_NORMAL
	else:
		col = C_NOSE_SHOT if shoot_marked else C_NOSE_NORMAL
	var h   = cell_size * 0.48
	var w   = cell_size * 0.40
	var pts: PackedVector2Array
	match rotation_step:
		0: pts = PackedVector2Array([nc, nc + Vector2(-h, -w), nc + Vector2(-h,  w)])
		1: pts = PackedVector2Array([nc, nc + Vector2(-w, -h), nc + Vector2( w, -h)])
		2: pts = PackedVector2Array([nc, nc + Vector2( h, -w), nc + Vector2( h,  w)])
		3: pts = PackedVector2Array([nc, nc + Vector2(-w,  h), nc + Vector2( w,  h)])
		_: return
	draw_colored_polygon(pts, col)
	# Glow on nose for neon
	if neon:
		draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.22))
	var border = Color(col.r * 0.55, col.g * 0.55, col.b * 0.55, 1.0)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), border, 1.0)

func _draw_stern(ps: Vector2, neon: bool) -> void:
	var sc  = _stern_center(ps)
	var sz  = max(2.5, cell_size * 0.24)
	var lw  = max(1.2, cell_size * 0.11)
	var col = N_STERN_LINE if neon else C_STERN_LINE
	match rotation_step:
		0, 2: draw_line(sc + Vector2(0, -sz), sc + Vector2(0,  sz), col, lw)
		1, 3: draw_line(sc + Vector2(-sz, 0), sc + Vector2(sz, 0),  col, lw)

func _body_color() -> Color:
	if SkinManager.current_skin() == SkinManager.SKIN_NEON:
		return N_BODY
	return C_BODY

# ─────────────────────────────────────────
#  Координати ніс/корма
# ─────────────────────────────────────────

func _nose_center(ps: Vector2) -> Vector2:
	var h = cell_size * 0.5
	match rotation_step:
		0: return Vector2(ps.x - h, h)
		1: return Vector2(h, ps.y - h)
		2: return Vector2(h, h)
		3: return Vector2(h, h)
	return ps * 0.5

func _stern_center(ps: Vector2) -> Vector2:
	var h = cell_size * 0.5
	match rotation_step:
		0: return Vector2(h, h)
		1: return Vector2(h, h)
		2: return Vector2(ps.x - h, h)
		3: return Vector2(h, ps.y - h)
	return ps * 0.5

# ─────────────────────────────────────────
#  Process — animations
# ─────────────────────────────────────────

func _process(delta: float) -> void:
	var has_particles = not _particles.is_empty()
	if has_particles:
		var live: Array = []
		for p in _particles:
			p["pos"]  += p["vel"] * delta
			p["vel"]  *= 0.90
			p["life"] -= delta
			if p["life"] > 0:
				live.append(p)
		_particles = live
		queue_redraw()
	elif is_selected and is_placed and \
			SkinManager.current_skin() == SkinManager.SKIN_NEON:
		queue_redraw()
