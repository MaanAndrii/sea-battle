## ShipMover.gd — фаза руху кораблів
## Стрілки, поворот CW/CCW. Корабель рухається в реальному часі.

extends Node2D
const SkinManager = preload("res://Scripts/SkinManager.gd")

# ── Залежності ───────────────────────────
var grid_model            = null
var grid_renderer: Node2D = null
var turn_manager:  Node   = null
var all_ships:     Array  = []
var combat_manager: Node  = null

# ── Стан ─────────────────────────────────
var selected_ship: Node2D         = null
var planned_path:  Array[Vector2i] = []
var energy_spent:  int             = 0

# ── UI ───────────────────────────────────
var _ui_layer:    CanvasLayer     = null
var _arrow_btns:  Array[Button]   = []
var _rotate_cw:   Button          = null
var _rotate_ccw:  Button          = null
var _cost_label:  Label           = null

# ── Константи ────────────────────────────
const DIRS        = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
const DIR_LABELS  = ["▲", "▼", "◄", "►"]
const BTN_SIZE    = Vector2(52, 52)
const BTN_FONT    = 24

const C_ARROW_OK  = Color(0.2,  0.85, 0.3,  0.95)
const C_ARROW_NO  = Color(0.4,  0.4,  0.4,  0.5)
const C_ROTATE    = Color(0.9,  0.75, 0.2,  0.95)

# Neon variants
const N_ARROW_OK  = Color(0.0,  1.0,  0.667, 0.95)
const N_ARROW_NO  = Color(0.25, 0.25, 0.30,  0.55)
const N_ROTATE    = Color(1.0,  0.667, 0.0,  0.95)

# ─────────────────────────────────────────
#  Ініціалізація
# ─────────────────────────────────────────

func setup(p_model, p_renderer: Node2D, p_turn: Node, p_ships: Array) -> void:
	grid_model    = p_model
	grid_renderer = p_renderer
	turn_manager  = p_turn
	all_ships     = p_ships

	_ui_layer = CanvasLayer.new()
	get_parent().add_child(_ui_layer)
	_build_ui()

func _build_ui() -> void:
	# 4 стрілки
	for i in range(4):
		var btn = _make_btn(DIR_LABELS[i], BTN_SIZE, BTN_FONT)
		var idx = i
		btn.pressed.connect(func(): _on_arrow(idx))
		_ui_layer.add_child(btn)
		_arrow_btns.append(btn)

	# Поворот за/проти годинника
	_rotate_cw  = _make_btn("↻", Vector2(52, 44), 20)
	_rotate_ccw = _make_btn("↺", Vector2(52, 44), 20)
	_rotate_cw.pressed.connect(func(): _on_rotate(true))
	_rotate_ccw.pressed.connect(func(): _on_rotate(false))
	_rotate_cw.modulate  = C_ROTATE
	_rotate_ccw.modulate = C_ROTATE
	_ui_layer.add_child(_rotate_cw)
	_ui_layer.add_child(_rotate_ccw)

	# Мітка витрат
	_cost_label = Label.new()
	_cost_label.add_theme_font_size_override("font_size", 14)
	_cost_label.visible = false
	_ui_layer.add_child(_cost_label)

	_hide_all_ui()

func _make_btn(txt: String, sz: Vector2, font_sz: int) -> Button:
	var btn = Button.new()
	btn.text = txt
	btn.custom_minimum_size = sz
	btn.size = sz
	btn.add_theme_font_size_override("font_size", font_sz)
	btn.visible = false
	# Зупиняємо propagation кліку щоб GameScene._input не отримав його
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	return btn

# ─────────────────────────────────────────
#  Вибір корабля
# ─────────────────────────────────────────

func try_select(gpos: Vector2) -> void:
	for ship in all_ships:
		if not ship.is_placed or ship.get("locked") == true:
			continue
		var ps  = ship.call("pixel_size") as Vector2
		var loc = gpos - ship.global_position
		if loc.x >= 0 and loc.y >= 0 and loc.x <= ps.x and loc.y <= ps.y:
			if selected_ship == ship:
				_deselect()   # повторний тап — скасувати вибір
			else:
				_select(ship)
			return
	_deselect()

func _select(ship: Node2D) -> void:
	selected_ship = ship
	planned_path.clear()
	energy_spent = 0
	_refresh_all_ui()

func _deselect() -> void:
	selected_ship = null
	planned_path.clear()
	_hide_all_ui()
	_clear_highlight()
	queue_redraw()

# ─────────────────────────────────────────
#  Оновлення UI
# ─────────────────────────────────────────

func _refresh_all_ui() -> void:
	if not selected_ship:
		_hide_all_ui()
		return

	var cs        = selected_ship.cell_size
	var gr        = grid_renderer
	var grid_right = gr.global_position.x + cs * 20.0
	var grid_top   = gr.global_position.y

	# Вертикальна колонка ПРАВОРУЧ від поля
	var col_x = grid_right + 4.0
	var cy    = grid_top + 8.0

	# Мітка витрат
	_cost_label.visible  = true
	_cost_label.text     = "⚡ %d" % energy_spent
	_cost_label.position = Vector2(col_x, cy)
	var ratio = float(energy_spent) / float(turn_manager.MAX_ENERGY)
	var c_col = Color(1.0, 0.3, 0.2) if ratio > 0.7 \
		else (Color(1.0, 0.85, 0.2) if ratio > 0.4 else Color(0.3, 1.0, 0.4))
	_cost_label.add_theme_color_override("font_color", c_col)
	cy += 22.0

	# Тільки стрілки вперед/назад (перпендикулярні — ховаємо)
	var fwd_dir  = _forward_dir()
	var bwd_dir  = Vector2i(-fwd_dir.x, -fwd_dir.y)
	var mov_cost = turn_manager.move_cost(selected_ship.get("damaged") == true)
	var fwd_btn: Button = null
	var bwd_btn: Button = null
	for i in range(4):
		var btn = _arrow_btns[i]
		if   DIRS[i] == fwd_dir: fwd_btn = btn
		elif DIRS[i] == bwd_dir: bwd_btn = btn
		else: btn.visible = false

	var neon     = SkinManager.current_skin() == SkinManager.SKIN_NEON
	var ok_col   = N_ARROW_OK if neon else C_ARROW_OK
	var no_col   = N_ARROW_NO if neon else C_ARROW_NO
	var rot_col  = N_ROTATE   if neon else C_ROTATE

	if fwd_btn:
		var can      = _can_move_dir(fwd_dir) and turn_manager.can_afford(mov_cost)
		fwd_btn.visible  = true
		fwd_btn.disabled = not can
		fwd_btn.modulate = ok_col if can else no_col
		fwd_btn.position = Vector2(col_x, cy)
	cy += BTN_SIZE.y + 4.0

	# Повороти
	var rot_cost = turn_manager.rotation_cost(selected_ship.size,
		selected_ship.get("damaged") == true)
	var can_rot  = turn_manager.can_afford(rot_cost)
	_rotate_ccw.visible  = true
	_rotate_cw.visible   = true
	_rotate_ccw.disabled = not can_rot
	_rotate_cw.disabled  = not can_rot
	_rotate_ccw.modulate = rot_col if can_rot else no_col
	_rotate_cw.modulate  = rot_col if can_rot else no_col
	_rotate_ccw.position = Vector2(col_x, cy)
	cy += _rotate_ccw.size.y + 2.0
	_rotate_cw.position  = Vector2(col_x, cy)
	cy += _rotate_cw.size.y + 4.0

	if bwd_btn:
		var can      = _can_move_dir(bwd_dir) and turn_manager.can_afford(mov_cost)
		bwd_btn.visible  = true
		bwd_btn.disabled = not can
		bwd_btn.modulate = ok_col if can else no_col
		bwd_btn.position = Vector2(col_x, cy)
	cy += BTN_SIZE.y + 4.0

	queue_redraw()

func _hide_all_ui() -> void:
	for btn in _arrow_btns: btn.visible = false
	if _rotate_cw:   _rotate_cw.visible  = false
	if _rotate_ccw:  _rotate_ccw.visible = false
	if _cost_label:  _cost_label.visible = false

# ─────────────────────────────────────────
#  Обробники кнопок
# ─────────────────────────────────────────

func _on_arrow(dir_idx: int) -> void:
	var dir  = DIRS[dir_idx]
	var cost = turn_manager.move_cost(selected_ship.get("damaged") == true)

	# Перевіряємо ПЕРЕД витратою енергії
	if not _can_move_dir(dir):
		return
	if not turn_manager.spend(cost):
		return

	energy_spent += cost

	# Нова носова = поточна клітинка + 1 крок
	var current_nose = Vector2i(selected_ship.cells[0].x, selected_ship.cells[0].y)
	var new_nose = current_nose + dir

	# Оновлюємо GridModel одразу
	grid_model.remove(selected_ship.cells)
	var raw = grid_model.place_from_nose(new_nose, selected_ship.size, selected_ship.rotation_step)
	var typed: Array[Vector2i] = []
	for c in raw: typed.append(Vector2i(c.x, c.y))
	selected_ship.cells = typed

	# Оновлюємо global_position корабля (лівий верхній кут)
	var cs = selected_ship.cell_size
	var top_left: Vector2i
	match selected_ship.rotation_step:
		0: top_left = Vector2i(new_nose.x - selected_ship.size + 1, new_nose.y)
		1: top_left = Vector2i(new_nose.x, new_nose.y - selected_ship.size + 1)
		_: top_left = new_nose
	selected_ship.global_position = grid_renderer.grid_to_world(top_left) \
		- Vector2(cs / 2.0, cs / 2.0)

	# Оновлюємо рендер поля — стираємо стару позицію, малюємо нову
	_refresh_grid()

	if combat_manager:
		combat_manager.call("register_step", selected_ship, dir)
	if not selected_ship: return  # ship was destroyed by a bomb mid-move
	if selected_ship.get("shoot_marked") == true:
		selected_ship.set("shoot_marked", false)
		selected_ship.set("has_moved", true)
	_clear_highlight()
	_refresh_all_ui()
	queue_redraw()

func _on_rotate(clockwise: bool) -> void:
	if not selected_ship:
		return
	var damaged = selected_ship.get("damaged") == true
	var cost    = turn_manager.rotation_cost(selected_ship.size, damaged)
	if not turn_manager.can_afford(cost):
		return

	# Отримуємо нові клітинки після повороту навколо носа
	var new_cells = selected_ship.call(
		"get_rotated_cells_cw" if clockwise else "get_rotated_cells_ccw")

	# Перевіряємо з НОВОЮ орієнтацією (після повороту)
	var new_step = (selected_ship.rotation_step + (1 if clockwise else 3)) % 4
	var nose = Vector2i(selected_ship.cells[0].x, selected_ship.cells[0].y)
	if not grid_model.can_place_excluding_nose(nose, selected_ship.size, new_step,
			selected_ship.cells):
		return   # немає місця

	if not turn_manager.spend(cost):
		return

	# Застосовуємо поворот
	if clockwise:
		selected_ship.call("rotate_cw")
	else:
		selected_ship.call("rotate_ccw")

	# Оновлюємо GridModel: знімаємо зі старої позиції, ставимо на нову
	grid_model.remove(selected_ship.cells)
	var rot_nose = Vector2i(selected_ship.cells[0].x, selected_ship.cells[0].y)
	var rot_raw = grid_model.place_from_nose(rot_nose, selected_ship.size,
		selected_ship.rotation_step)
	var rot_typed: Array[Vector2i] = []
	for c in rot_raw: rot_typed.append(Vector2i(c.x, c.y))
	selected_ship.cells = rot_typed

	# Ніс залишається на місці — оновлюємо global_position
	var rot_cs = selected_ship.cell_size
	var rot_top_left: Vector2i
	match selected_ship.rotation_step:
		0: rot_top_left = Vector2i(rot_nose.x - selected_ship.size + 1, rot_nose.y)
		1: rot_top_left = Vector2i(rot_nose.x, rot_nose.y - selected_ship.size + 1)
		_: rot_top_left = rot_nose
	selected_ship.global_position = grid_renderer.grid_to_world(rot_top_left) \
		- Vector2(rot_cs / 2.0, rot_cs / 2.0)

	energy_spent += cost

	if selected_ship.get("shoot_marked") == true:
		selected_ship.set("shoot_marked", false)
		selected_ship.set("has_moved", true)

	_refresh_grid()
	_refresh_all_ui()
	queue_redraw()

# ─────────────────────────────────────────
#  Виконання ходу
# ─────────────────────────────────────────

func _on_commit() -> void:
	if selected_ship:
		selected_ship.set("shoot_marked", false)
		selected_ship.queue_redraw()
		if energy_spent > 0 and selected_ship.has_method("spawn_particles"):
			selected_ship.call("spawn_particles")
		_refresh_grid()
	_deselect()

func _refresh_grid() -> void:
	for y in range(20):
		for x in range(20):
			var gm_val = grid_model.grid[y][x]
			var cur    = grid_renderer.cell_state[y][x]
			if gm_val == 1:
				grid_renderer.set_cell(Vector2i(x, y), 1)   # корабель на місці
			elif cur == 1:
				grid_renderer.set_cell(Vector2i(x, y), 0)   # корабель відплив → очищаємо
			# Всі маркери (5,6,8,10,11…) залишаємо без змін

# ─────────────────────────────────────────
#  Рендер (лінія маршруту + фантом)
# ─────────────────────────────────────────

func _draw() -> void:
	pass  # Ship moves in real-time; no trail or ghost needed

# ─────────────────────────────────────────
#  Підсвічування
# ─────────────────────────────────────────

func _update_path_highlight() -> void:
	var nose = _current_nose()
	var cells: Array[Vector2i] = []
	for d in DIRS:
		var nc = nose + d
		if grid_renderer.is_valid(nc):
			cells.append(nc)
	grid_renderer.set_highlight(cells)

func _clear_highlight() -> void:
	var empty: Array[Vector2i] = []
	grid_renderer.set_highlight(empty)

# ─────────────────────────────────────────
#  Утиліти
# ─────────────────────────────────────────

# Напрямки вперед/назад залежно від rotation_step
func _forward_dir() -> Vector2i:
	match selected_ship.rotation_step:
		0: return Vector2i( 1,  0)  # →
		1: return Vector2i( 0,  1)  # ↓
		2: return Vector2i(-1,  0)  # ←
		3: return Vector2i( 0, -1)  # ↑
	return Vector2i(1, 0)

func _is_allowed_dir(dir: Vector2i) -> bool:
	if not selected_ship: return false
	var fwd = _forward_dir()
	# Дозволено тільки вперед або назад (протилежний)
	return dir == fwd or dir == Vector2i(-fwd.x, -fwd.y)

func _can_move_dir(dir: Vector2i) -> bool:
	if not selected_ship: return false
	if not _is_allowed_dir(dir): return false
	var new_nose = _current_nose() + dir
	return grid_model.can_place_excluding_nose(
		new_nose, selected_ship.size, selected_ship.rotation_step,
		selected_ship.cells)

func _cells_are_free(new_cells: Array, own_cells: Array) -> bool:
	if new_cells.is_empty(): return false
	var nose = Vector2i(new_cells[0].x, new_cells[0].y)
	var new_step: int
	if new_cells.size() > 1:
		var second = Vector2i(new_cells[1].x, new_cells[1].y)
		var dx = second.x - nose.x
		var dy = second.y - nose.y
		if dx < 0: new_step = 0   # хвіст ліворуч → ніс →
		elif dy < 0: new_step = 1  # хвіст вгору → ніс ↓
		elif dx > 0: new_step = 2  # хвіст праворуч → ніс ←
		else: new_step = 3         # хвіст вниз → ніс ↑
	else:
		new_step = selected_ship.rotation_step
	return grid_model.can_place_excluding_nose(
		nose, selected_ship.size, new_step, own_cells)


func _nose_to_grid_coord_step(nose: Vector2i, sz: int, cells_arr: Array) -> Vector2i:
	if cells_arr.is_empty(): return nose
	# Знаходимо мінімальний x і y серед клітинок
	var min_x = cells_arr[0].x
	var min_y = cells_arr[0].y
	for c in cells_arr:
		min_x = min(min_x, c.x)
		min_y = min(min_y, c.y)
	return Vector2i(min_x, min_y)

func _current_nose() -> Vector2i:
	if not selected_ship or selected_ship.cells.is_empty():
		return Vector2i.ZERO
	# cells оновлюються в реальному часі — planned_path не потрібен
	return Vector2i(selected_ship.cells[0].x, selected_ship.cells[0].y)

func _current_cells() -> Array:
	if not selected_ship:
		return []
	return _cells_at(_current_nose(), selected_ship.size, selected_ship.is_horizontal)

func _cells_at(nose: Vector2i, sz: int, horiz: bool) -> Array:
	var res = []
	for i in range(sz):
		res.append(Vector2i(nose.x + i, nose.y) if horiz \
			else Vector2i(nose.x, nose.y + i))
	return res

func _current_center_px() -> Vector2:
	var ps = selected_ship.call("pixel_size") as Vector2
	return selected_ship.global_position + ps / 2.0

# ─────────────────────────────────────────
#  API для CombatManager
# ─────────────────────────────────────────

## Активувати режим руху для конкретного корабля (без UI вибору)
func activate_for_ship(ship: Node2D) -> void:
	_select(ship)

## Виконати запланований рух
func execute_move() -> void:
	_on_commit()

## Скасувати поточний рух
func cancel_move() -> void:
	if combat_manager and selected_ship:
		combat_manager.call("clear_moves", selected_ship)
	_deselect()

## Застосувати запланований рух до GridModel (без анімації — для execute)
func apply_planned_move_to_model(ship: Node2D, final_nose: Vector2i) -> void:
	if not grid_model.can_place_excluding_nose(final_nose, ship.size,
			ship.rotation_step, ship.cells):
		return
	grid_model.remove(ship.cells)
	var raw = grid_model.place_from_nose(final_nose, ship.size, ship.rotation_step)
	var typed: Array[Vector2i] = []
	for c in raw: typed.append(Vector2i(c.x, c.y))
	ship.cells = typed
	# Оновлюємо рендер (зберігаємо маркери)
	for y in range(20):
		for x in range(20):
			var gm_val = grid_model.grid[y][x]
			var cur    = grid_renderer.cell_state[y][x]
			if gm_val == 1:
				grid_renderer.set_cell(Vector2i(x, y), 1)
			elif cur == 1:
				grid_renderer.set_cell(Vector2i(x, y), 0)

## Конвертує ніс корабля в координату для GridModel.place (ліва/верхня клітинка)
func _nose_to_grid_coord(nose: Vector2i, sz: int, step: int) -> Vector2i:
	match step:
		0: return Vector2i(nose.x - (sz - 1), nose.y)  # → хвіст ліворуч
		1: return Vector2i(nose.x, nose.y - (sz - 1))  # ↓ хвіст вгору
		2: return nose                                   # ← ніс вже ліворуч
		3: return nose                                   # ↑ ніс вже вгорі
	return nose
