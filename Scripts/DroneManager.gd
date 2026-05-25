## DroneManager.gd
## Авіаносець: 3 дрони, 2 ходи кожен, 1 бомба/дрон.
## Розвідка: сигналізує про наявність корабля у 3×3 (без точних координат).
## Переміщення: +3 клітки за хід, 3 енергії.
## Скидання бомби: гравець обирає конкретну клітинку у 3×3.

extends Node

class DroneInfo:
	var id:          int      = 0
	var pos:         Vector2i = Vector2i.ZERO
	var turns_left:  int      = 2
	var bombs_left:  int      = 1
	var has_contact: bool     = false

const MAX_DRONES  = 3
const DRONE_TURNS = 2
const DRONE_BOMBS = 1
const LAUNCH_COST = 5
const MOVE_COST   = 3
const MOVE_STEP   = 3
const DIRS        = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
const DIR_LABELS  = ["▲", "▼", "◄", "►"]
const BTN_SIZE    = Vector2(44, 44)
const C_OK        = Color(0.9, 0.75, 0.2, 0.95)
const C_NO        = Color(0.4, 0.4,  0.4, 0.5)
const C_BOMB_BTN  = Color(1.0, 0.4,  0.1, 0.95)
const C_BOMB_PICK = Color(1.0, 0.6,  0.0, 0.95)
const C_SEL       = Color(0.2, 0.7,  1.0, 0.95)

var upper_grid:   Node2D = null
var lower_grid:   Node2D = null
var turn_manager: Node   = null
var carrier_ship: Node2D = null
var enemy_if              = null
var player_model          = null

var _drones:          Array  = []
var _next_id:         int    = 0
var _drones_launched: int    = 0
var selected_drone            = null

var _own_bombs:           Array[Vector2i] = []
var _opp_bombs:           Array[Vector2i] = []
var _new_bombs_this_turn: Array[Vector2i] = []

var launch_pending:   bool = false
var _carrier_ui_on:   bool = false
var _actions_enabled: bool = true
var _placing_bomb:    bool = false   # waiting for player to pick a cell in 3×3

var _ui_layer:    CanvasLayer  = null

# Right-column controls (movement)
var _move_btns:   Array[Button] = []
var _bomb_btn:    Button        = null
var _info_lbl:    Label         = null

# Left-panel controls (drone selection + launch)
var _drone_slot_btns:  Array[Button] = []
var _drone_launch_btn: Button        = null

# ─────────────────────────────────────────

func setup(p_upper, p_lower, p_turn, p_carrier, p_enemy, p_model) -> void:
	upper_grid   = p_upper
	lower_grid   = p_lower
	turn_manager = p_turn
	carrier_ship = p_carrier
	enemy_if     = p_enemy
	player_model = p_model
	_build_ui()

func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	get_parent().add_child(_ui_layer)

	# ── Left panel: drone slots + launch ─────────────────────────
	var panel_x = _panel_left()
	var panel_y = upper_grid.global_position.y
	var btn_w   = max(_panel_width() - 4.0, 40.0)

	for i in range(MAX_DRONES):
		var btn = _make_btn("---", Vector2(btn_w, 38), 11)
		btn.modulate = C_NO
		btn.disabled = true
		var slot_idx = i
		btn.pressed.connect(func(): _on_drone_slot_pressed(slot_idx))
		btn.position = Vector2(panel_x, panel_y + 4.0 + i * 42.0)
		btn.visible  = true
		_ui_layer.add_child(btn)
		_drone_slot_btns.append(btn)

	_drone_launch_btn = _make_btn("🚁 Пустити (%d)" % MAX_DRONES,
		Vector2(btn_w, 38), 11)
	_drone_launch_btn.modulate = Color(0.3, 0.9, 0.5)
	_drone_launch_btn.position = Vector2(panel_x, panel_y + 4.0 + MAX_DRONES * 42.0 + 4.0)
	_drone_launch_btn.pressed.connect(_on_begin_launch)
	_ui_layer.add_child(_drone_launch_btn)

	# ── Right column: movement controls ──────────────────────────
	for i in range(4):
		var btn = _make_btn(DIR_LABELS[i], BTN_SIZE, 18)
		var di  = i
		btn.pressed.connect(func(): _move_selected(DIRS[di]))
		_ui_layer.add_child(btn)
		_move_btns.append(btn)

	_bomb_btn = _make_btn("💣 Бомба", Vector2(110, 38), 13)
	_bomb_btn.pressed.connect(_on_drop_bomb)
	_ui_layer.add_child(_bomb_btn)

	_info_lbl = Label.new()
	_info_lbl.add_theme_font_size_override("font_size", 11)
	_info_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_info_lbl.visible = false
	_ui_layer.add_child(_info_lbl)

	_hide_drone_controls()

# ── Public API ────────────────────────────────────────────────

func can_launch() -> bool:
	return carrier_ship != null and carrier_ship.is_placed \
		and _drones_launched < MAX_DRONES

func get_drone_panel_rect() -> Rect2:
	return Rect2(_panel_left() - 4.0, upper_grid.global_position.y,
		_panel_width() + 8.0, upper_grid.cell_size * 20.0)

func set_carrier_ui_visible(v: bool) -> void:
	_carrier_ui_on = v
	_refresh_drone_panel()
	if not v and not selected_drone:
		_hide_drone_controls()

func set_actions_enabled(v: bool) -> void:
	_actions_enabled = v
	if not v:
		launch_pending   = false
		_placing_bomb    = false
		_deselect_drone()
	_refresh_drone_panel()

## Returns true if the click was consumed (don't treat as shot).
func handle_upper_click(coord: Vector2i) -> bool:
	if not _actions_enabled:
		return false

	# Bomb-placement mode: player picks a cell in the 3×3 area
	if _placing_bomb and selected_drone:
		var center = selected_drone.pos
		if abs(coord.x - center.x) <= 1 and abs(coord.y - center.y) <= 1:
			_do_place_bomb(coord)
			return true
		# Click outside the zone cancels placement
		_placing_bomb = false
		_refresh_drone_controls()
		_refresh_selected_drone_highlight()
		return false

	if launch_pending:
		launch_pending = false
		_do_launch(coord)
		return true

	return false

func cancel_launch() -> void:
	if launch_pending:
		launch_pending = false
		_refresh_drone_panel()

func is_drone_at(coord: Vector2i) -> bool:
	for d in _drones:
		if d.pos == coord: return true
	return false

## Called at turn execution: ages drones, returns bomb data dict for network.
func on_turn_executed() -> Dictionary:
	if carrier_ship and not carrier_ship.is_placed and _drones.size() > 0:
		on_carrier_sunk()

	var data = {"new_bombs": _new_bombs_this_turn.map(func(b): return [b.x, b.y])}
	_new_bombs_this_turn.clear()

	var to_expire = []
	for drone in _drones:
		drone.turns_left -= 1
		if drone.turns_left <= 0:
			to_expire.append(drone)
	for drone in to_expire:
		_expire_drone(drone)

	reveal_all()
	_refresh_drone_panel()
	_refresh_ui_after_age()
	return data

## Re-scan all active drone areas.
func reveal_all() -> void:
	if carrier_ship and not carrier_ship.is_placed:
		if _drones.size() > 0: on_carrier_sunk()
		return
	for drone in _drones:
		_scan_area(drone)

## Check own ships on opponent bombs — sink any found.
func check_and_sink_own_ships_on_opp_bombs(ships: Array) -> void:
	var to_sink = []
	for ship in ships:
		if not ship.is_placed: continue
		for cell in ship.cells:
			var v = Vector2i(int(cell.x), int(cell.y))
			if v in _opp_bombs and not to_sink.has(ship):
				to_sink.append(ship)
	for ship in to_sink:
		_sink_own_ship_by_bomb(ship)

## Check opponent ships on own bombs — sink any found.
func apply_bomb_check_to_opp_ships(opp_ships: Dictionary, sink_fn: Callable) -> void:
	for idx in opp_ships:
		var entry = opp_ships[idx]
		if entry.get("marked_sunk", false): continue
		for ca in entry["current_cells"]:
			var pos = Vector2i(ca[0], ca[1])
			if pos in _own_bombs:
				entry["marked_sunk"] = true
				_own_bombs.erase(pos)
				upper_grid.set_cell(pos, 10)
				sink_fn.call(entry)
				break

## Check own bombs vs single-player enemy (EnemySetup).
func check_and_sink_enemy_on_own_bombs() -> void:
	if not enemy_if: return
	for bomb_pos in _own_bombs.duplicate():
		if enemy_if.call("is_hit", bomb_pos):
			if enemy_if.has_method("sink_ship_at"):
				enemy_if.call("sink_ship_at", bomb_pos)
			else:
				enemy_if.call("mark_hit", bomb_pos)
			_own_bombs.erase(bomb_pos)
			upper_grid.set_cell(bomb_pos, 10)

## Receive a bomb placed by opponent — track for sinking check only.
func receive_opp_bomb(pos: Vector2i) -> void:
	if pos not in _opp_bombs:
		_opp_bombs.append(pos)

## Check if any of the ship's cells land on an active opponent bomb.
## If so, immediately sink the ship and consume the bomb. Returns true if detonated.
func check_and_detonate_on_ship(ship: Node2D) -> bool:
	if not ship.is_placed: return false
	for cell in ship.cells:
		var v = Vector2i(int(cell.x), int(cell.y))
		if v in _opp_bombs:
			_sink_own_ship_by_bomb(ship)
			return true
	return false

## Carrier was sunk: destroy all drones (bombs persist).
func on_carrier_sunk() -> void:
	for drone in _drones.duplicate():
		_expire_drone(drone)
	_carrier_ui_on = false
	_hide_drone_controls()
	_refresh_drone_panel()

# ── Launch & lifecycle ────────────────────────────────────────

func _on_begin_launch() -> void:
	if not _actions_enabled: return
	launch_pending = true
	_deselect_drone()
	_drone_launch_btn.text    = "🚁 Клікніть на карті"
	_drone_launch_btn.modulate = Color(1.0, 0.85, 0.1)

func _do_launch(coord: Vector2i) -> void:
	if not can_launch(): return
	if not upper_grid.is_valid(coord): return
	if is_drone_at(coord): return
	if not turn_manager.spend(LAUNCH_COST): return
	var drone    = DroneInfo.new()
	drone.id     = _next_id
	_next_id    += 1
	drone.pos    = coord
	_drones.append(drone)
	_drones_launched += 1
	upper_grid.set_cell(coord, 4)
	_scan_area(drone)
	_select_drone(drone)
	_refresh_drone_panel()

func _expire_drone(drone) -> void:
	_clear_drone_cell(drone.pos)
	_drones.erase(drone)
	if selected_drone == drone:
		selected_drone = null
		_placing_bomb  = false
		_hide_drone_controls()
	_update_alarm_cells()
	_refresh_drone_panel()

func _clear_drone_cell(pos: Vector2i) -> void:
	# Bomb at that exact cell persists; otherwise clear to empty
	upper_grid.set_cell(pos, 12 if pos in _own_bombs else 0)

# ── Selection ─────────────────────────────────────────────────

func _select_drone(drone) -> void:
	selected_drone = drone
	_placing_bomb  = false
	_refresh_selected_drone_highlight()
	_refresh_drone_controls()
	_refresh_drone_panel()

func _deselect_drone() -> void:
	selected_drone = null
	_placing_bomb  = false
	_refresh_selected_drone_highlight()
	_hide_drone_controls()
	_refresh_drone_panel()

func _on_drone_slot_pressed(slot_idx: int) -> void:
	if not _actions_enabled: return
	if slot_idx >= _drones.size(): return
	var drone = _drones[slot_idx]
	if selected_drone == drone:
		_deselect_drone()
	else:
		_select_drone(drone)

# ── Movement ──────────────────────────────────────────────────

func _move_selected(dir: Vector2i) -> void:
	if not _actions_enabled: return
	if not selected_drone: return
	if _placing_bomb: return  # must resolve bomb placement first
	var new_pos = selected_drone.pos + dir * MOVE_STEP
	if not upper_grid.is_valid(new_pos): return
	if is_drone_at(new_pos): return
	if not turn_manager.spend(MOVE_COST): return
	_clear_drone_cell(selected_drone.pos)
	selected_drone.pos = new_pos
	upper_grid.set_cell(new_pos, 4)
	_scan_area(selected_drone)
	_refresh_selected_drone_highlight()
	_refresh_drone_controls()

# ── Bomb ──────────────────────────────────────────────────────

func _on_drop_bomb() -> void:
	if not _actions_enabled: return
	if not selected_drone: return
	if _placing_bomb:
		# Second press = cancel
		_placing_bomb = false
		_refresh_drone_controls()
		_refresh_selected_drone_highlight()
		return
	if selected_drone.bombs_left <= 0: return
	# Enter placement mode: player clicks a cell in the 3×3 area
	_placing_bomb = true
	_refresh_drone_controls()
	_refresh_selected_drone_highlight()

func _do_place_bomb(coord: Vector2i) -> void:
	if coord in _own_bombs: return
	selected_drone.bombs_left -= 1
	_own_bombs.append(coord)
	_new_bombs_this_turn.append(coord)
	upper_grid.set_cell(coord, 12)
	_placing_bomb = false
	_refresh_drone_controls()
	_refresh_selected_drone_highlight()

# ── Reconnaissance ────────────────────────────────────────────

## Scan 3×3 around drone — sets has_contact if any enemy ship present.
## Does NOT reveal exact positions.
func _scan_area(drone) -> void:
	drone.has_contact = false
	if enemy_if:
		var center = drone.pos
		for dy in range(-1, 2):
			if drone.has_contact: break
			for dx in range(-1, 2):
				var cell = Vector2i(center.x + dx, center.y + dy)
				if not upper_grid.is_valid(cell): continue
				if enemy_if.call("is_hit", cell):
					drone.has_contact = true
					break
	_update_alarm_cells()

## Rebuild the alarm-cells list from all drones with contacts.
func _update_alarm_cells() -> void:
	var cells: Array[Vector2i] = []
	for drone in _drones:
		if not drone.has_contact: continue
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c = Vector2i(drone.pos.x + dx, drone.pos.y + dy)
				if upper_grid.is_valid(c) and c not in cells:
					cells.append(c)
	upper_grid.set_alarm_cells(cells)

# ── Own-ship bomb destruction ─────────────────────────────────

func _sink_own_ship_by_bomb(ship: Node2D) -> void:
	var ds: Array = []
	for _i in range(ship.size): ds.append(true)
	ship.set("damaged_sections", ds)

	var ship_cells: Array[Vector2i] = []
	for c in ship.cells:
		ship_cells.append(Vector2i(int(c.x), int(c.y)))

	if player_model:
		for cv in ship_cells:
			if player_model.grid[cv.y][cv.x] == 1:
				player_model.grid[cv.y][cv.x] = 0
		player_model._rebuild_forbidden()
		player_model.add_wreckage(ship_cells)

	for cv in ship_cells:
		lower_grid.set_cell(cv, 10)

	var adj: Array[Vector2i] = []
	for cv in ship_cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0: continue
				var nb = Vector2i(cv.x + dx, cv.y + dy)
				if lower_grid.is_valid(nb) and not ship_cells.has(nb) and not adj.has(nb):
					if lower_grid.cell_state[nb.y][nb.x] != 10:
						lower_grid.set_cell(nb, 11)
					adj.append(nb)
	if player_model:
		player_model.add_wreckage(adj)

	ship.modulate  = Color(0.6, 0.6, 0.7, 0.30)
	ship.is_placed = false
	ship.queue_redraw()

	for cv in ship_cells:
		_opp_bombs.erase(cv)

# ── UI ────────────────────────────────────────────────────────

func _refresh_drone_panel() -> void:
	for i in range(MAX_DRONES):
		var btn = _drone_slot_btns[i]
		if i < _drones.size():
			var drone = _drones[i]
			var contact_icon = " 🔴" if drone.has_contact else ""
			btn.text     = "🚁 #%d  ⏳%d  💣%d%s" % [
				drone.id + 1, drone.turns_left, drone.bombs_left, contact_icon]
			btn.disabled = false
			btn.modulate = C_SEL if (selected_drone == drone) else C_OK
		else:
			btn.text     = "---"
			btn.disabled = true
			btn.modulate = C_NO

	var can = _carrier_ui_on and can_launch()
	if not _actions_enabled:
		can = false
	_drone_launch_btn.visible = can
	if can and not launch_pending:
		_drone_launch_btn.text    = "🚁 Пустити (%d)" % (MAX_DRONES - _drones_launched)
		_drone_launch_btn.modulate = Color(0.3, 0.9, 0.5)

func _refresh_drone_controls() -> void:
	if not selected_drone:
		_hide_drone_controls()
		return

	var cy = 0.0

	# Info label
	_info_lbl.visible = true
	var contact_str = "  🔴 КОНТАКТ" if selected_drone.has_contact else ""
	if _placing_bomb:
		_info_lbl.text = "💣 Клікніть на 3×3 (або кнопку щоб скасувати)"
		_info_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1))
	else:
		_info_lbl.text = "🚁 #%d  ⏳%d  💣%d%s" % [
			selected_drone.id + 1, selected_drone.turns_left,
			selected_drone.bombs_left, contact_str]
		_info_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_info_lbl.position = _col_pos(cy)
	cy += 18.0

	# Movement buttons — disabled during bomb placement
	var pos = selected_drone.pos
	for i in range(4):
		var new_pos = pos + DIRS[i] * MOVE_STEP
		var can_m   = not _placing_bomb \
			and upper_grid.is_valid(new_pos) \
			and not is_drone_at(new_pos) \
			and turn_manager.can_afford(MOVE_COST)
		_move_btns[i].visible  = true
		_move_btns[i].disabled = not can_m
		_move_btns[i].modulate = C_OK if can_m else C_NO
		_move_btns[i].position = _col_pos(cy)
		cy += BTN_SIZE.y + 2.0

	# Bomb button
	var has_bomb = selected_drone.bombs_left > 0
	if _placing_bomb:
		_bomb_btn.text     = "❌ Скасувати"
		_bomb_btn.disabled = false
		_bomb_btn.modulate = C_NO
	else:
		_bomb_btn.text     = "💣 Бомба"
		_bomb_btn.disabled = not has_bomb
		_bomb_btn.modulate = C_BOMB_BTN if has_bomb else C_NO
	_bomb_btn.visible  = true
	_bomb_btn.position = _col_pos(cy)

func _refresh_ui_after_age() -> void:
	_refresh_selected_drone_highlight()
	if selected_drone:
		_refresh_drone_controls()

func _hide_drone_controls() -> void:
	for btn in _move_btns: btn.visible = false
	_bomb_btn.visible = false
	_info_lbl.visible = false

func _refresh_selected_drone_highlight() -> void:
	if selected_drone:
		var area: Array[Vector2i] = []
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c = Vector2i(selected_drone.pos.x + dx, selected_drone.pos.y + dy)
				if upper_grid.is_valid(c):
					area.append(c)
		upper_grid.set_highlight(area)
	else:
		var empty: Array[Vector2i] = []
		upper_grid.set_highlight(empty)

# ── Positioning ───────────────────────────────────────────────

func _panel_left() -> float:
	return 4.0

func _panel_width() -> float:
	return max(upper_grid.global_position.x - 8.0, 40.0)

func _col_pos(offset_y: float) -> Vector2:
	var cs = upper_grid.cell_size
	return Vector2(upper_grid.global_position.x + cs * 20.0 + 4.0,
				   upper_grid.global_position.y + 4.0 + offset_y)

func _make_btn(txt: String, sz: Vector2, fsz: int) -> Button:
	var b = Button.new()
	b.text = txt
	b.custom_minimum_size = sz
	b.size = sz
	b.add_theme_font_size_override("font_size", fsz)
	b.visible = false
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	return b
