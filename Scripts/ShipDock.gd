## ShipDock.gd
## Drag-and-drop розстановка. Поворот ПКМ/довгий тап. Блокування після підтвердження.

extends Control

signal all_ships_placed

const FLEET = [
	{ "name": "Авіаносець", "size": 5, "count": 1 },
	{ "name": "Лінкор",     "size": 4, "count": 2 },
	{ "name": "Фрегат",     "size": 3, "count": 3 },
	{ "name": "Корвет",     "size": 2, "count": 4 },
]

const COLOR_DOCK_BG = Color(0.06, 0.10, 0.18, 0.95)
const COLOR_BORDER  = Color(0.25, 0.45, 0.75, 0.50)

var cell_size:     float    = 16.0
var grid_model              = null
var grid_renderer: Node2D   = null

var all_ships:    Array[Node2D] = []
var placed_count: int = 0
var total_ships:  int = 0

# Чи заблоковано після підтвердження
var setup_confirmed: bool = false

# Drag
var dragging:        Node2D  = null
var drag_offset:     Vector2 = Vector2.ZERO
var drag_origin_pos: Vector2 = Vector2.ZERO
var drag_was_placed: bool    = false
var drag_origin_coord: Vector2i = Vector2i.ZERO

# Поворот — довгий тап
var long_tap_ship:  Node2D  = null
var long_tap_timer: float   = 0.0
const LONG_TAP_SEC: float   = 0.4

# Кнопка
var confirm_btn: Button = null

# ─────────────────────────────────────────

func setup(p_cell: float, p_model, p_renderer: Node2D) -> void:
	cell_size     = p_cell
	grid_model    = p_model
	grid_renderer = p_renderer
	_build()

func _build() -> void:
	for c in get_children(): c.queue_free()
	all_ships.clear()
	placed_count     = 0
	setup_confirmed  = false

	var bg = ColorRect.new()
	bg.color = COLOR_DOCK_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var brd = ColorRect.new()
	brd.color    = COLOR_BORDER
	brd.size     = Vector2(9999, 1)
	brd.position = Vector2.ZERO
	add_child(brd)

	total_ships = 0
	var x_off = 8.0
	for entry in FLEET:
		for _i in range(entry["count"]):
			total_ships += 1
			var ship = _make_ship(entry["name"], entry["size"])
			ship.position = Vector2(x_off, (size.y - cell_size) / 2.0 if size.y > 0 else 8.0)
			add_child(ship)
			all_ships.append(ship)
			x_off += cell_size * entry["size"] + 8.0

	confirm_btn = Button.new()
	confirm_btn.text    = "✓  ПІДТВЕРДИТИ РОЗСТАНОВКУ"
	confirm_btn.visible = false
	confirm_btn.add_theme_font_size_override("font_size", 13)
	confirm_btn.pressed.connect(_on_confirm)
	add_child(confirm_btn)

	# Кнопка випадкової розстановки
	var rnd_btn = Button.new()
	rnd_btn.text = "🎲 Випадково"
	rnd_btn.add_theme_font_size_override("font_size", 13)
	rnd_btn.modulate = Color(0.9, 0.7, 0.2)
	rnd_btn.pressed.connect(_on_random_place)
	add_child(rnd_btn)
	set_meta("rnd_btn", rnd_btn)

func _make_ship(p_name: String, p_size: int) -> Node2D:
	var node = Node2D.new()
	node.set_script(load("res://Scripts/Ship.gd"))
	node.call("setup", p_name, p_size, cell_size)
	return node

# ─────────────────────────────────────────
#  Input
# ─────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if setup_confirmed:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: _on_press(event.global_position)
		else:             _on_release(event.global_position)
	elif event is InputEventMouseMotion and dragging:
		_on_move(event.global_position)
	elif event is InputEventScreenTouch:
		if event.pressed: _on_press(event.position)
		else:             _on_release(event.position)
	elif event is InputEventScreenDrag and dragging:
		_on_move(event.position)

func _unhandled_input(event: InputEvent) -> void:
	if setup_confirmed:
		return

	# ПКМ — поворот (десктоп)
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		for ship in all_ships:
			if _hit(ship, event.global_position):
				_do_rotate(ship)
				return

	# Довгий тап — поворот (мобільний)
	if event is InputEventScreenTouch:
		if event.pressed:
			for ship in all_ships:
				if _hit(ship, event.position):
					long_tap_ship  = ship
					long_tap_timer = 0.0
					return
		else:
			long_tap_ship  = null
			long_tap_timer = 0.0

func _process(delta: float) -> void:
	if long_tap_ship:
		long_tap_timer += delta
		if long_tap_timer >= LONG_TAP_SEC:
			_do_rotate(long_tap_ship)
			long_tap_ship  = null
			long_tap_timer = 0.0

# ─────────────────────────────────────────
#  Drag
# ─────────────────────────────────────────

func _on_press(gpos: Vector2) -> void:
	# Спершу — встановлені на полі
	for ship in all_ships:
		if ship.is_placed and _hit(ship, gpos):
			_begin_drag(ship, gpos)
			return
	# Потім — у доку
	for ship in all_ships:
		if not ship.is_placed and _hit(ship, gpos):
			_begin_drag(ship, gpos)
			return

func _begin_drag(ship: Node2D, gpos: Vector2) -> void:
	dragging        = ship
	drag_offset     = gpos - ship.global_position
	drag_origin_pos = ship.global_position
	drag_was_placed = ship.is_placed

	if ship.is_placed:
		drag_origin_coord = ship.cells[0]
		grid_model.remove(ship.cells)
		ship.cells     = []
		ship.is_placed = false
		placed_count   = max(0, placed_count - 1)
		_refresh_renderer()
		_update_confirm_btn()

func _on_move(gpos: Vector2) -> void:
	dragging.global_position = gpos - drag_offset

	var coord = grid_renderer.world_to_grid(gpos)
	if grid_renderer.is_valid(coord):
		var ok = _can_place_at(dragging, coord)
		dragging.hover_valid = ok
		dragging.queue_redraw()
		# Підсвічування: клітинки від носа
		var nose: Vector2i
		match dragging.rotation_step:
			0: nose = Vector2i(coord.x + dragging.size - 1, coord.y)
			1: nose = Vector2i(coord.x, coord.y + dragging.size - 1)
			_: nose = coord
		var preview = grid_model.cells_from_nose(nose, dragging.size, dragging.rotation_step)
		var typed: Array[Vector2i] = []
		for c in preview:
			if grid_renderer.is_valid(c): typed.append(c)
		grid_renderer.set_highlight(typed)
	else:
		dragging.hover_valid = true
		dragging.queue_redraw()
		_clear_highlight()

func _on_release(gpos: Vector2) -> void:
	if not dragging:
		return
	var ship = dragging
	dragging = null
	_clear_highlight()

	var coord = grid_renderer.world_to_grid(gpos)

	if grid_renderer.is_valid(coord) and _can_place_at(ship, coord):
		_place_ship(ship, coord)
	else:
		# Не вдалось — повертаємо на попереднє місце
		ship.global_position = drag_origin_pos
		ship.hover_valid     = true
		ship.queue_redraw()

		if drag_was_placed:
			# Повертаємо на оригінальну позицію на полі
			if grid_model.can_place(drag_origin_coord, ship.size, ship.is_horizontal):
				_place_ship(ship, drag_origin_coord)

func _place_ship(ship: Node2D, coord: Vector2i) -> void:
	# coord = місце де відпустили = ліва/верхня клітинка
	# Ніс залежить від напрямку
	var nose: Vector2i
	match ship.rotation_step:
		0: nose = Vector2i(coord.x + ship.size - 1, coord.y)
		1: nose = Vector2i(coord.x, coord.y + ship.size - 1)
		2: nose = coord
		3: nose = coord
		_: nose = coord
	# Перевіряємо що ніс в межах поля
	if nose.x < 0 or nose.x >= 20 or nose.y < 0 or nose.y >= 20:
		return
	var raw = grid_model.place_from_nose(nose, ship.size, ship.rotation_step)
	var typed: Array[Vector2i] = []
	for c in raw: typed.append(Vector2i(c.x, c.y))
	ship.cells       = typed
	ship.is_placed   = true
	ship.hover_valid = true
	# global_position = лівий верхній кут корабля
	# Рахуємо ліву/верхню клітинку від носа
	var top_left: Vector2i
	match ship.rotation_step:
		0: top_left = Vector2i(nose.x - ship.size + 1, nose.y)  # → хвіст ліворуч
		1: top_left = Vector2i(nose.x, nose.y - ship.size + 1)  # ↓ хвіст вгору
		_: top_left = nose  # ← і ↑ ніс вже зліва/вгорі
	ship.global_position = grid_renderer.grid_to_world(top_left) \
		- Vector2(cell_size / 2.0, cell_size / 2.0)
	placed_count += 1
	_refresh_renderer()
	_update_confirm_btn()

# ─────────────────────────────────────────
#  Поворот за годинниковою стрілкою
# ─────────────────────────────────────────

func _do_rotate(ship: Node2D) -> void:
	if ship.is_placed:
		var nose = Vector2i(ship.cells[0].x, ship.cells[0].y)
		grid_model.remove(ship.cells)
		ship.cells     = []
		ship.is_placed = false
		placed_count   = max(0, placed_count - 1)

		# Пробуємо всі 4 повороти поки не знайдемо вільне місце
		var rotated = false
		for _attempt in range(4):
			ship.call("rotate_cw")
			if grid_model.can_place(nose, ship.size, ship.is_horizontal):
				_place_ship(ship, nose)
				rotated = true
				break

		if not rotated:
			# Нікуди не влазить — ставимо назад без повороту
			ship.call("rotate_cw")  # повертаємо до початкового
			_place_ship(ship, nose)
	else:
		# У доку — просто крутимо
		ship.call("rotate_cw")

# ─────────────────────────────────────────
#  Підтвердження
# ─────────────────────────────────────────

func _update_confirm_btn() -> void:
	var done = placed_count >= total_ships
	confirm_btn.visible = done
	if done:
		confirm_btn.size     = Vector2(270, 44)
		confirm_btn.position = Vector2(size.x / 2.0 - 135, size.y / 2.0 - 22)

func _on_random_place() -> void:
	# Знімаємо всі кораблі з поля
	for ship in all_ships:
		if ship.is_placed:
			grid_model.remove(ship.cells)
			ship.cells     = []
			ship.is_placed = false
			ship.hover_valid = true
			ship.queue_redraw()
	placed_count = 0
	_refresh_renderer()

	# Розставляємо випадково
	var rng = RandomNumberGenerator.new()
	rng.randomize()

	for ship in all_ships:
		var placed = false
		var attempts = 0
		while not placed and attempts < 300:
			attempts += 1
			# Випадкова орієнтація
			var target_step = rng.randi_range(0, 3)
			while ship.rotation_step != target_step:
				ship.call("rotate_cw")
			var horiz = ship.is_horizontal
			# Генеруємо випадковий ніс в межах поля
			var nose = Vector2i(rng.randi_range(0, 19), rng.randi_range(0, 19))
			if grid_model.can_place_from_nose(nose, ship.size, target_step):
				# Рахуємо coord (ліва/верхня) для _place_ship
				var coord: Vector2i
				match target_step:
					0: coord = Vector2i(nose.x - ship.size + 1, nose.y)
					1: coord = Vector2i(nose.x, nose.y - ship.size + 1)
					_: coord = nose
				if coord.x >= 0 and coord.y >= 0:
					_place_ship(ship, coord)
					placed = true
	_update_confirm_btn()

func _on_confirm() -> void:
	setup_confirmed = true
	confirm_btn.visible = false

	# Блокуємо і змінюємо вигляд усіх кораблів
	for ship in all_ships:
		ship.setup_locked = true
		ship.queue_redraw()

	emit_signal("all_ships_placed")

# ─────────────────────────────────────────
#  Утиліти
# ─────────────────────────────────────────

func _can_place_at(ship: Node2D, coord: Vector2i) -> bool:
	# coord = ліва/верхня клітинка, рахуємо nose
	var nose: Vector2i
	match ship.rotation_step:
		0: nose = Vector2i(coord.x + ship.size - 1, coord.y)
		1: nose = Vector2i(coord.x, coord.y + ship.size - 1)
		2: nose = coord
		3: nose = coord
		_: nose = coord
	if nose.x < 0 or nose.x >= 20 or nose.y < 0 or nose.y >= 20:
		return false
	return grid_model.can_place_from_nose(nose, ship.size, ship.rotation_step)

func _hit(ship: Node2D, gpos: Vector2) -> bool:
	var ps  = ship.call("pixel_size") as Vector2
	var loc = gpos - ship.global_position
	return loc.x >= 0 and loc.y >= 0 and loc.x <= ps.x and loc.y <= ps.y

func _clear_highlight() -> void:
	var empty: Array[Vector2i] = []
	grid_renderer.set_highlight(empty)

func _refresh_renderer() -> void:
	for y in range(20):
		for x in range(20):
			var st = grid_model.grid[y][x]
			grid_renderer.set_cell(Vector2i(x, y), 1 if st == 1 else 0)
