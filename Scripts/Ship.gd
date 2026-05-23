## Ship.gd
## Ніс = cells[0], Корма = cells[last]
## Поворот: ніс на місці, хвіст заноситься на 90°
## Мітка носа: зелена=норма, червона=щойно стріляв

extends Node2D

var ship_name:      String = ""
var size:           int    = 1
var rotation_step:  int    = 0   # 0=→  1=↓  2=←  3=↑
var cells:          Array  = []
var is_placed:      bool   = false
var hover_valid:    bool   = true
var locked:         bool   = false
var setup_locked:   bool   = false
var damaged:        bool   = false
var shoot_marked:   bool   = false   # щойно стріляв → ніс червоний
var has_moved:      bool   = false   # рухався після пострілу → ніс зелений
var cell_size:      float  = 16.0

# ── Кольори ─────────────────────────────
const C_BODY        = Color(0.20, 0.44, 0.88, 0.90)
const C_LOCKED      = Color(0.20, 0.44, 0.88, 0.90)  # такий самий — не затемнюємо
const C_HOVER_OK    = Color(0.22, 0.92, 0.38, 0.72)
const C_HOVER_NO    = Color(0.92, 0.20, 0.15, 0.72)
const C_DAMAGE      = Color(0.75, 0.22, 0.10, 0.80)
const C_BORDER      = Color(0.50, 0.75, 1.00, 0.85)
const C_SECTION     = Color(0.00, 0.00, 0.00, 0.18)
const C_NOSE_NORMAL = Color(0.20, 1.00, 0.35, 1.00)  # зелений ніс
const C_NOSE_SHOT   = Color(1.00, 0.18, 0.10, 1.00)  # червоний ніс після пострілу
const C_STERN_LINE  = Color(0.50, 0.68, 1.00, 0.75)  # корма — риска

func setup(p_name: String, p_size: int, p_cell_size: float) -> void:
	ship_name = p_name
	size      = p_size
	cell_size = p_cell_size
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

# ── Позиція носа після повороту навколо носа (cells[0]) ──────
## Повертає нові клітинки після повороту CW навколо носа
## Клітинки після повороту CW, ніс фіксований.
## Напрямок хвоста залежить від нового rotation_step:
## 0=→ хвіст ліворуч (nose.x+i), 1=↓ хвіст угору (nose.y+i)
## 2=← хвіст праворуч (nose.x-i), 3=↑ хвіст донизу (nose.y-i)
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

## Будує клітинки від носа. cells[0]=ніс, хвіст іде ПРОТИ напрямку носа.
## step=0 (→): хвіст ←,  step=1 (↓): хвіст ↑
## step=2 (←): хвіст →,  step=3 (↑): хвіст ↓
func _cells_from_nose(nose: Vector2i, step: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for i in range(size):
		match step:
			0: result.append(Vector2i(nose.x - i, nose.y))  # → ніс право, хвіст ліво
			1: result.append(Vector2i(nose.x, nose.y - i))  # ↓ ніс вниз, хвіст вгору
			2: result.append(Vector2i(nose.x + i, nose.y))  # ← ніс ліво, хвіст право
			3: result.append(Vector2i(nose.x, nose.y + i))  # ↑ ніс вгору, хвіст вниз
	return result

## Хвостова клітинка (ліва/верхня) — для передачі в GridModel.place
## GridModel.place очікує лівий/верхній кут, а не ніс
func tail_cell() -> Vector2i:
	if cells.is_empty(): return Vector2i.ZERO
	var nose = Vector2i(cells[0].x, cells[0].y)
	match rotation_step:
		0: return Vector2i(nose.x - (size - 1), nose.y)  # → хвіст ліворуч
		1: return Vector2i(nose.x, nose.y - (size - 1))  # ↓ хвіст вгору
		2: return nose                                      # ← ніс ліворуч = вже ліво
		3: return nose                                      # ↑ ніс вгору = вже верх
	return nose

## Хвіст після повороту CW/CCW
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
	var ps = pixel_size()
	var m  = 1.5

	# Тіло
	var fill = C_BODY
	if not is_placed:
		fill = C_HOVER_OK if hover_valid else C_HOVER_NO
	elif damaged:
		fill = C_DAMAGE
	draw_rect(Rect2(m, m, ps.x - m*2, ps.y - m*2), fill)

	# Секції
	for i in range(1, size):
		if is_horizontal:
			draw_line(Vector2(i*cell_size, m+1), Vector2(i*cell_size, ps.y-m-1), C_SECTION, 1.0)
		else:
			draw_line(Vector2(m+1, i*cell_size), Vector2(ps.x-m-1, i*cell_size), C_SECTION, 1.0)

	# Рамка
	draw_rect(Rect2(m, m, ps.x-m*2, ps.y-m*2), C_BORDER, false, 1.2)
	# Помаранчева рамка якщо пошкоджений
	if damaged:
		draw_rect(Rect2(m-1, m-1, ps.x-m*2+2, ps.y-m*2+2),
			Color(1.0, 0.55, 0.1, 0.9), false, 2.0)

	# Маркери ніс і корма — ЗАВЖДИ малюємо
	_draw_nose(ps)
	_draw_stern(ps)

	# Назва
	if cell_size >= 13.0:
		var fsz = max(6, int(cell_size * 0.33))
		draw_string(ThemeDB.fallback_font,
			Vector2(m + 2, ps.y * 0.5 + fsz * 0.35),
			ship_name.left(3), HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(1,1,1,0.40))

# ── Ніс: стрілка-шеврон, колір залежить від стану ──────────
func _draw_nose(ps: Vector2) -> void:
	var nc  = _nose_center(ps)
	var col = C_NOSE_SHOT if shoot_marked else C_NOSE_NORMAL
	# Розмір трикутника — займає всю ширину клітинки
	var h = cell_size * 0.48   # висота (вздовж напрямку руху)
	var w = cell_size * 0.40   # півширина (поперек)
	var pts: PackedVector2Array
	match rotation_step:
		0:  # → вершина праворуч
			pts = PackedVector2Array([nc, nc + Vector2(-h, -w), nc + Vector2(-h, w)])
		1:  # ↓ вершина донизу
			pts = PackedVector2Array([nc, nc + Vector2(-w, -h), nc + Vector2( w, -h)])
		2:  # ← вершина ліворуч
			pts = PackedVector2Array([nc, nc + Vector2( h, -w), nc + Vector2( h,  w)])
		3:  # ↑ вершина вгору
			pts = PackedVector2Array([nc, nc + Vector2(-w,  h), nc + Vector2( w,  h)])
		_:
			return
	# Заливка
	draw_colored_polygon(pts, col)
	# Рамка для чіткості
	var border = Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, 1.0)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), border, 1.0)

# ── Корма: поперечна риска ───────────────────────────────────
func _draw_stern(ps: Vector2) -> void:
	var sc = _stern_center(ps)
	var sz = max(2.5, cell_size * 0.24)
	var lw = max(1.2, cell_size * 0.11)

	match rotation_step:
		0, 2:  # горизонтальний → риска вертикальна
			draw_line(sc + Vector2(0, -sz), sc + Vector2(0, sz), C_STERN_LINE, lw)
		1, 3:  # вертикальний → риска горизонтальна
			draw_line(sc + Vector2(-sz, 0), sc + Vector2(sz, 0), C_STERN_LINE, lw)

# ─────────────────────────────────────────
#  Координати ніс/корма
# ─────────────────────────────────────────

func _nose_center(ps: Vector2) -> Vector2:
	var h = cell_size * 0.5
	match rotation_step:
		0: return Vector2(ps.x - h, h)   # → правий край
		1: return Vector2(h, ps.y - h)   # ↓ нижній край
		2: return Vector2(h, h)           # ← лівий край
		3: return Vector2(h, h)           # ↑ верхній край
	return ps * 0.5

func _stern_center(ps: Vector2) -> Vector2:
	var h = cell_size * 0.5
	match rotation_step:
		0: return Vector2(h, h)           # → ліво (корма)
		1: return Vector2(h, h)           # ↓ верх (корма)
		2: return Vector2(ps.x - h, h)   # ← право (корма)
		3: return Vector2(h, ps.y - h)   # ↑ низ (корма)
	return ps * 0.5
