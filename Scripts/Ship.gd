## Ship.gd
## Ніс = cells[0], Корма = cells[last]
## Секції: damaged_sections[i]=true → секція i уражена (i=0 ніс)
## Потоплений корабель: всі секції = true → is_sunk()

extends Node2D

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

## Є хоча б одна уражена секція
var damaged: bool:
	get:
		for d in damaged_sections:
			if d: return true
		return false

# ── Кольори ─────────────────────────────
const C_BODY         = Color(0.20, 0.44, 0.88, 0.90)   # ціла секція — синя
const C_LOCKED       = Color(0.20, 0.44, 0.88, 0.90)
const C_HOVER_OK     = Color(0.22, 0.92, 0.38, 0.72)
const C_HOVER_NO     = Color(0.92, 0.20, 0.15, 0.72)
const C_SECTION_HIT  = Color(0.18, 0.05, 0.03, 0.97)   # уражена секція — вугільно-чорна
const C_HIT_MARK     = Color(1.00, 0.32, 0.06, 1.00)   # хрест X на ураженій секції
const C_HIT_INNER    = Color(0.85, 0.18, 0.02, 0.40)   # внутрішній обвід ураженої
const C_BORDER       = Color(0.50, 0.75, 1.00, 0.85)   # звичайна рамка
const C_BORDER_DMG   = Color(1.00, 0.52, 0.08, 0.92)   # помаранчева рамка при ушкодженнях
const C_SECTION_LINE = Color(0.08, 0.10, 0.16, 0.38)   # лінія між секціями
const C_NOSE_NORMAL  = Color(0.20, 1.00, 0.35, 1.00)
const C_NOSE_SHOT    = Color(1.00, 0.18, 0.10, 1.00)
const C_STERN_LINE   = Color(0.50, 0.68, 1.00, 0.75)
const C_SELECTED_GLOW = Color(1.00, 0.95, 0.35, 0.95)

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

## Всі секції уражені
func _is_sunk() -> bool:
	if damaged_sections.size() < size: return false
	for d in damaged_sections:
		if not d: return false
	return true

# ── Позиція носа після повороту навколо носа (cells[0]) ──────
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

## cells[0]=ніс, хвіст іде ПРОТИ напрямку носа
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
#  Рендер
# ─────────────────────────────────────────

func _draw() -> void:
	var ps     = pixel_size()
	var m      = 1.5
	var sunk   = _is_sunk()

	if not is_placed and not sunk:
		# Режим перетягування — однотонна заливка
		draw_rect(Rect2(m, m, ps.x - m*2, ps.y - m*2),
			C_HOVER_OK if hover_valid else C_HOVER_NO)
	else:
		# Секції — кожна окремо
		for i in range(size):
			var r   = _section_rect(i)
			var hit = damaged_sections.size() > i and damaged_sections[i]
			if hit:
				draw_rect(r, C_SECTION_HIT)
				draw_rect(Rect2(r.position + Vector2(0.5, 0.5), r.size - Vector2(1, 1)),
					C_HIT_INNER, false, 1.0)
				_draw_section_x(r)
			else:
				draw_rect(r, C_BODY)

	# Лінії між секціями
	for i in range(1, size):
		if is_horizontal:
			draw_line(Vector2(i*cell_size, m+1), Vector2(i*cell_size, ps.y-m-1),
				C_SECTION_LINE, 1.2)
		else:
			draw_line(Vector2(m+1, i*cell_size), Vector2(ps.x-m-1, i*cell_size),
				C_SECTION_LINE, 1.2)

	# Зовнішня рамка
	var bw = 2.0 if (is_placed and damaged) else 1.2
	draw_rect(Rect2(m, m, ps.x-m*2, ps.y-m*2),
		C_BORDER_DMG if damaged else C_BORDER, false, bw)
	if is_selected and is_placed and not sunk:
		draw_rect(Rect2(m - 1.5, m - 1.5, ps.x - (m - 1.5) * 2, ps.y - (m - 1.5) * 2),
			C_SELECTED_GLOW, false, 2.6)

	# Ніс і корма
	_draw_nose(ps)
	_draw_stern(ps)

	# Назва
	if cell_size >= 13.0:
		var fsz = max(6, int(cell_size * 0.33))
		draw_string(ThemeDB.fallback_font,
			Vector2(m + 2, ps.y * 0.5 + fsz * 0.35),
			ship_name.left(3), HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(1,1,1,0.40))

## Піксельний прямокутник секції i в локальних координатах.
## Секція 0 = ніс, розташований:
##   step=0 (→) праворуч,  step=1 (↓) знизу,
##   step=2 (←) ліворуч,   step=3 (↑) зверху.
func _section_rect(i: int) -> Rect2:
	var m = 1.5
	match rotation_step:
		0: return Rect2((size-1-i)*cell_size + m, m,   cell_size - m*2, cell_size - m*2)
		1: return Rect2(m, (size-1-i)*cell_size + m,   cell_size - m*2, cell_size - m*2)
		2: return Rect2(i*cell_size + m,           m,   cell_size - m*2, cell_size - m*2)
		3: return Rect2(m, i*cell_size + m,             cell_size - m*2, cell_size - m*2)
	return Rect2(m, m, cell_size - m*2, cell_size - m*2)

## Хрест X на ураженій секції
func _draw_section_x(r: Rect2) -> void:
	var pad = max(2.5, r.size.x * 0.17)
	var lw  = max(1.8, r.size.x * 0.13)
	draw_line(r.position + Vector2(pad, pad),
	          r.position + r.size - Vector2(pad, pad), C_HIT_MARK, lw)
	draw_line(r.position + Vector2(r.size.x - pad, pad),
	          r.position + Vector2(pad, r.size.y - pad), C_HIT_MARK, lw)

# ── Ніс: стрілка-шеврон ─────────────────────────────────────
func _draw_nose(ps: Vector2) -> void:
	var nc  = _nose_center(ps)
	var col = C_NOSE_SHOT if shoot_marked else C_NOSE_NORMAL
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
	var border = Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, 1.0)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), border, 1.0)

# ── Корма: поперечна риска ───────────────────────────────────
func _draw_stern(ps: Vector2) -> void:
	var sc = _stern_center(ps)
	var sz = max(2.5, cell_size * 0.24)
	var lw = max(1.2, cell_size * 0.11)
	match rotation_step:
		0, 2: draw_line(sc + Vector2(0, -sz), sc + Vector2(0,  sz), C_STERN_LINE, lw)
		1, 3: draw_line(sc + Vector2(-sz, 0), sc + Vector2(sz, 0),  C_STERN_LINE, lw)

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
