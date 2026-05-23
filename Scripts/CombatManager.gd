## CombatManager.gd
## Спрощений UX: тап корабель → рухай стрілками або тапай верхнє поле для пострілу
## Один "▶ ЗАВЕРШИТИ ХІД" — виконує все заплановане

extends Node

signal turn_executed
signal shot_fired(coord: Vector2i)

# ── Залежності ────────────────────────────
var upper_grid:   Node2D = null
var lower_grid:   Node2D = null
var ship_mover:   Node   = null
var turn_manager: Node   = null
var all_ships:    Array  = []
var enemy_setup:  Node   = null

# ── План ходу ─────────────────────────────
# { ship, shots: Array[Vector2i] }
# Рух вже зберігається в ship.cells напряму через ShipMover
var plan: Array = []

# ── Поточний стан ─────────────────────────
var selected_ship:      Node2D = null
var shots_left:         int    = 0
var last_fired_noses:   Array[Vector2i] = []
var _nose_at_shot_time: Dictionary = {}
var _busy:              bool   = false   # true під час виконання ходу / ходу ворога

# ── UI ────────────────────────────────────
var _ui_layer:    CanvasLayer = null
var _status_lbl:  Label       = null
var _info_lbl:    Label       = null   # ліміти вибраного корабля
var _commit_btn:  Button      = null
var _undo_btn:    Button      = null
var _fleet_panel: Control     = null

const C_COMMIT = Color(0.2, 0.9, 0.4, 1.0)
const C_UNDO   = Color(0.6, 0.6, 0.6, 0.9)

# ─────────────────────────────────────────
#  Ініціалізація
# ─────────────────────────────────────────

func setup(p_upper: Node2D, p_lower: Node2D, p_mover: Node,
		p_turn: Node, p_ships: Array, p_enemy: Node = null) -> void:
	upper_grid   = p_upper
	lower_grid   = p_lower
	ship_mover   = p_mover
	turn_manager = p_turn
	all_ships    = p_ships
	enemy_setup  = p_enemy

	_ui_layer = CanvasLayer.new()
	get_parent().add_child(_ui_layer)
	_build_ui()
	_init_plan()
	_refresh_status()

func _init_plan() -> void:
	plan.clear()
	_nose_at_shot_time.clear()
	for ship in all_ships:
		if ship.is_placed:
			plan.append({ "ship": ship, "shots": [] as Array[Vector2i] })
	if _fleet_panel:
		_fleet_panel.set("plan_ref", plan)
		_fleet_panel.queue_redraw()

func _build_ui() -> void:
	var vp = get_viewport().get_visible_rect().size

	# Статус угорі
	_status_lbl = Label.new()
	_status_lbl.position = Vector2(8, 4)
	_status_lbl.size     = Vector2(vp.x - 16, 22)
	_status_lbl.add_theme_font_size_override("font_size", 12)
	_status_lbl.add_theme_color_override("font_color", Color(0.8, 0.95, 1.0))
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui_layer.add_child(_status_lbl)

	# Інфо про вибраний корабель
	_info_lbl = Label.new()
	_info_lbl.position = Vector2(8, vp.y - 100)
	_info_lbl.size     = Vector2(vp.x - 16, 22)
	_info_lbl.add_theme_font_size_override("font_size", 12)
	_info_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_lbl.visible = false
	_ui_layer.add_child(_info_lbl)

	# Скасувати останній постріл
	_undo_btn = Button.new()
	_undo_btn.text = "↩ Скасувати постріл"
	_undo_btn.size = Vector2(170, 38)
	_undo_btn.position = Vector2(8, vp.y - 52)
	_undo_btn.add_theme_font_size_override("font_size", 12)
	_undo_btn.modulate = C_UNDO
	_undo_btn.visible  = false
	_undo_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_undo_btn.pressed.connect(_on_undo_shot)
	_ui_layer.add_child(_undo_btn)

	# Єдина кнопка завершення ходу
	_commit_btn = Button.new()
	_commit_btn.text = "▶  ЗАВЕРШИТИ ХІД"
	_commit_btn.size = Vector2(180, 48)
	_commit_btn.position = Vector2(vp.x - 188, vp.y - 56)
	_commit_btn.add_theme_font_size_override("font_size", 14)
	_commit_btn.modulate = C_COMMIT
	_commit_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_commit_btn.pressed.connect(_on_execute_turn)
	_ui_layer.add_child(_commit_btn)

	# Панель флоту — ліворуч від нижнього поля
	var lg_x = lower_grid.global_position.x
	var lg_y = lower_grid.global_position.y
	var lg_h = lower_grid.cell_size * 20.0
	var fp_w = lg_x - 8.0
	if fp_w >= 40.0:
		_fleet_panel = Control.new()
		_fleet_panel.set_script(load("res://Scripts/FleetPanel.gd"))
		_fleet_panel.position = Vector2(4.0, lg_y)
		_fleet_panel.size     = Vector2(fp_w, lg_h)
		_fleet_panel.set("all_ships", all_ships)
		_fleet_panel.set("plan_ref",  plan)
		_ui_layer.add_child(_fleet_panel)

# ─────────────────────────────────────────
#  Input з GameScene
# ─────────────────────────────────────────

func handle_input(gpos: Vector2) -> void:
	if _busy: return
	# Тап на верхнє поле → постріл (якщо є вибраний корабель)
	var upper_coord = upper_grid.world_to_grid(gpos)
	if upper_grid.is_valid(upper_coord):
		if selected_ship != null and shots_left > 0:
			_add_shot(upper_coord)
		return

	# Тап на нижнє поле → вибір/зняття корабля для руху
	_try_select_ship(gpos)

func _try_select_ship(gpos: Vector2) -> void:
	# Якщо ShipMover активний (стрілки показані) — не перехоплюємо
	if ship_mover.get("selected_ship") != null:
		return

	for ship in all_ships:
		if not ship.is_placed: continue
		var ps  = ship.call("pixel_size") as Vector2
		var loc = gpos - ship.global_position
		if loc.x >= 0 and loc.y >= 0 and loc.x <= ps.x and loc.y <= ps.y:
			if selected_ship == ship:
				_deselect()
			else:
				_select(ship)
			return

	_deselect()

func _select(ship: Node2D) -> void:
	# Знімаємо попередній вибір
	if selected_ship and selected_ship != ship:
		ship_mover.call("_deselect")

	selected_ship = ship
	shots_left    = turn_manager.shots_for_size(ship.size) - _shots_used(ship)

	# Активуємо ShipMover для руху
	ship_mover.call("activate_for_ship", ship)

	_refresh_info()
	_refresh_status()

func _deselect() -> void:
	selected_ship = null
	shots_left    = 0
	ship_mover.call("_deselect")
	var empty: Array[Vector2i] = []
	upper_grid.set_highlight(empty)
	_info_lbl.visible = false
	_undo_btn.visible = false
	_refresh_status()

# ─────────────────────────────────────────
#  Пострілів
# ─────────────────────────────────────────

func _add_shot(coord: Vector2i) -> void:
	var entry = _get_plan(selected_ship)
	var shots = entry["shots"] as Array
	var cv    = Vector2i(coord.x, coord.y)
	# Блокуємо стрільбу по уламках
	var cell_st = upper_grid.cell_state[coord.y][coord.x]
	if cell_st == 10 or cell_st == 11:
		_set_status("⚠ Ця клітинка зайнята уламками!")
		return
	if cv in shots:
		_set_status("⚠ В цю клітинку вже заплановано постріл")
		return
	if not turn_manager.spend(1):
		_set_status("⚠ Недостатньо енергії!")
		return

	# Фіксуємо ніс в момент першого пострілу (до можливого подальшого руху)
	if shots.is_empty() and not _nose_at_shot_time.has(selected_ship):
		_nose_at_shot_time[selected_ship] = Vector2i(
			selected_ship.cells[0].x, selected_ship.cells[0].y)

	shots.append(cv)
	shots_left -= 1
	# Маркер на верхньому полі
	upper_grid.set_cell(coord, 7)
	# Мітка на носі корабля
	selected_ship.set("shoot_marked", true)
	selected_ship.queue_redraw()

	_refresh_info()
	_refresh_status()
	_undo_btn.visible = shots.size() > 0

func _on_undo_shot() -> void:
	if selected_ship == null: return
	var entry = _get_plan(selected_ship)
	var shots = entry["shots"] as Array
	if shots.is_empty(): return

	var last = shots[-1] as Vector2i
	shots.pop_back()
	upper_grid.set_cell(last, 0)
	turn_manager.spend(-1)
	shots_left += 1

	if shots.is_empty():
		selected_ship.set("shoot_marked", false)
		selected_ship.queue_redraw()
		_nose_at_shot_time.erase(selected_ship)   # скасували всі постріли → ніс не зафіксований

	_undo_btn.visible = shots.size() > 0
	_refresh_info()
	_refresh_status()

# ─────────────────────────────────────────
#  Виконання ходу
# ─────────────────────────────────────────

func _on_execute_turn() -> void:
	if _busy: return
	_busy = true
	_commit_btn.disabled = true
	_deselect()
	_set_status("⏳ Виконання ходу...")

	# 1. Старіємо маркери з минулого ходу
	_age_markers()

	# 2. Постріли; збираємо носи кораблів зафіксовані В МОМЕНТ ПОСТРІЛУ (до руху)
	last_fired_noses.clear()
	for entry in plan:
		var firing_ship := entry["ship"] as Node2D
		var shots := entry["shots"] as Array
		if shots.size() > 0 and _nose_at_shot_time.has(firing_ship):
			last_fired_noses.append(_nose_at_shot_time[firing_ship])
		for coord in shots:
			var c := coord as Vector2i
			await get_tree().create_timer(0.15).timeout
			await _resolve_shot(c)
			emit_signal("shot_fired", c)

	# 3. Очищаємо промахи цього ходу (зникають одразу після виконання)
	_clear_misses()

	# 4. Скидаємо мітки кораблів
	for entry in plan:
		var s := entry["ship"] as Node2D
		s.set("shoot_marked", false)
		s.set("has_moved",    false)
		s.queue_redraw()

	turn_manager.end_turn()
	_init_plan()
	_refresh_status()
	emit_signal("turn_executed")
	# Кнопка залишається заблокованою до виклику resume() з GameScene

func resume() -> void:
	_busy = false
	_commit_btn.disabled = false
	_refresh_status()

func _resolve_shot(coord: Vector2i):
	# Не стріляємо по уламках (захист від переписування стану 10/11)
	var existing = upper_grid.cell_state[coord.y][coord.x]
	if existing == 10 or existing == 11:
		await get_tree().create_timer(0.1).timeout
		return
	var is_hit = false
	if enemy_setup:
		is_hit = enemy_setup.call("is_hit", coord)
		if is_hit:
			enemy_setup.call("mark_hit", coord)
	else:
		is_hit = upper_grid.cell_state[coord.y][coord.x] == 1
	# mark_hit може виставити state 10 (уламки) якщо корабель потоплено —
	# не перекриваємо його маркером влучання/промаху
	var post = upper_grid.cell_state[coord.y][coord.x]
	if post != 10 and post != 11:
		upper_grid.set_cell(coord, 6 if is_hit else 5)
	await get_tree().create_timer(0.1).timeout

# ── Управління маркерами ──────────────────────────────────────

func _age_markers() -> void:
	# Верхнє поле (наші постріли по ворогу + маркер носа суперника)
	for y in range(20):
		for x in range(20):
			match upper_grid.cell_state[y][x]:
				8: upper_grid.set_cell(Vector2i(x, y), 0)   # старе потьмяніле → зникає
				6: upper_grid.set_cell(Vector2i(x, y), 8)   # влучання → потьмяніти
				9: upper_grid.set_cell(Vector2i(x, y), 0)   # ніс минулого ходу → зникає
	# Нижнє поле: промахи та маркери влучань ворога старіють
	for y in range(20):
		for x in range(20):
			match lower_grid.cell_state[y][x]:
				5: lower_grid.set_cell(Vector2i(x, y), 0)   # промах → зникає
				8: lower_grid.set_cell(Vector2i(x, y), 0)   # потьмяніле влучання → зникає
				6: lower_grid.set_cell(Vector2i(x, y), 8)   # влучання → потьмяніти
				# Стани 10, 11 (уламки) — ніколи не стираємо

func _clear_misses() -> void:
	for y in range(20):
		for x in range(20):
			if upper_grid.cell_state[y][x] == 5:
				upper_grid.set_cell(Vector2i(x, y), 0)

# ─────────────────────────────────────────
#  UI оновлення
# ─────────────────────────────────────────

func _refresh_status() -> void:
	if selected_ship:
		var shots_max  = turn_manager.shots_for_size(selected_ship.size)
		var shots_done = _shots_used(selected_ship)
		if shots_max > 0:
			_set_status("%s  |  ⚡ %d  |  💥 %d / %d" % [
				selected_ship.ship_name,
				turn_manager.energy,
				shots_done, shots_max])
		else:
			_set_status("%s  |  ⚡ %d  |  (не стріляє)" % [
				selected_ship.ship_name, turn_manager.energy])
	else:
		_set_status("Тапніть корабель для руху/пострілу  |  ⚡ %d" % turn_manager.energy)
	if _fleet_panel:
		_fleet_panel.set("selected_ship", selected_ship)
		_fleet_panel.queue_redraw()

func _refresh_info() -> void:
	if not selected_ship:
		_info_lbl.visible = false
		return
	var shots_max  = turn_manager.shots_for_size(selected_ship.size)
	var shots_done = _shots_used(selected_ship)
	var move_cost  = turn_manager.move_cost(selected_ship.get("damaged") == true)
	_info_lbl.text = "Рух: %d⚡/крок  |  Постріли: %d / %d  %s" % [
		move_cost, shots_done, shots_max,
		"← тапніть верхнє поле" if shots_left > 0 else ""]
	_info_lbl.visible = true

func _set_status(txt: String) -> void:
	_status_lbl.text = txt

# ─────────────────────────────────────────
#  Утиліти
# ─────────────────────────────────────────

func _shots_used(ship: Node2D) -> int:
	return (_get_plan(ship)["shots"] as Array).size()

func _get_plan(ship: Node2D) -> Dictionary:
	for entry in plan:
		if entry["ship"] == ship:
			return entry
	return {"shots": [] as Array[Vector2i]}

func is_shoot_phase() -> bool:
	return false

func get_editing_ship() -> Node2D:
	return selected_ship

# Для сумісності зі старим кодом
func _start_round() -> void:
	_init_plan()
	_refresh_status()

## No-op для сумісності з ShipMover
func register_step(_ship: Node2D, _dir: Vector2i) -> void:
	pass
