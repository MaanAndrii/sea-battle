## DroneManager.gd
## Авіаносець: 3 дрони, 4 ходи кожен, 2 бомби/дрон.
## Розвідка 3×3, керування на верхній карті.

extends Node

class DroneInfo:
	var id:         int      = 0
	var pos:        Vector2i = Vector2i.ZERO
	var turns_left: int      = 4
	var bombs_left: int      = 2

const MAX_DRONES  = 3
const DRONE_TURNS = 4
const DRONE_BOMBS = 2
const DIRS        = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
const DIR_LABELS  = ["▲", "▼", "◄", "►"]
const BTN_SIZE    = Vector2(44, 44)
const C_OK        = Color(0.9, 0.75, 0.2, 0.95)
const C_NO        = Color(0.4, 0.4,  0.4, 0.5)
const C_BOMB_BTN  = Color(1.0, 0.4,  0.1, 0.95)

var upper_grid:   Node2D = null
var lower_grid:   Node2D = null
var turn_manager: Node   = null
var carrier_ship: Node2D = null
var enemy_if              = null   # is_hit(Vector2i)→bool, optional sink_ship_at(Vector2i)→bool
var player_model          = null   # GridModel for own-ship bomb sinking

var _drones:          Array  = []
var _next_id:         int    = 0
var _drones_launched: int    = 0
var selected_drone            = null

var _own_bombs:           Array[Vector2i] = []
var _opp_bombs:           Array[Vector2i] = []
var _new_bombs_this_turn: Array[Vector2i] = []

var launch_pending:   bool = false
var _carrier_ui_on:   bool = false

var _ui_layer:    CanvasLayer  = null
var _launch_btn:  Button       = null
var _move_btns:   Array[Button] = []
var _bomb_btn:    Button        = null
var _info_lbl:    Label         = null

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

	_launch_btn = _make_btn("🚁 Пустити дрон (3)", Vector2(140, 38), 12)
	_launch_btn.modulate = Color(0.3, 0.9, 0.5)
	_launch_btn.pressed.connect(_on_begin_launch)
	_ui_layer.add_child(_launch_btn)

	for i in range(4):
		var btn = _make_btn(DIR_LABELS[i], BTN_SIZE, 18)
		var idx = i
		btn.pressed.connect(func(): _move_selected(DIRS[idx]))
		_ui_layer.add_child(btn)
		_move_btns.append(btn)

	_bomb_btn = _make_btn("💣 Бомба", Vector2(100, 38), 13)
	_bomb_btn.pressed.connect(_on_drop_bomb)
	_ui_layer.add_child(_bomb_btn)

	_info_lbl = Label.new()
	_info_lbl.add_theme_font_size_override("font_size", 11)
	_info_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_info_lbl.visible = false
	_ui_layer.add_child(_info_lbl)

	_hide_all()

func _make_btn(txt: String, sz: Vector2, fsz: int) -> Button:
	var b = Button.new()
	b.text = txt
	b.custom_minimum_size = sz
	b.size = sz
	b.add_theme_font_size_override("font_size", fsz)
	b.visible = false
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	return b

# ── Public API ────────────────────────────────────────────────

func can_launch() -> bool:
	return carrier_ship != null and carrier_ship.is_placed \
		and _drones_launched < MAX_DRONES

## Called by CombatManager when carrier selected/deselected
func set_carrier_ui_visible(v: bool) -> void:
	_carrier_ui_on = v
	if v:
		_refresh_launch_btn()
	else:
		_launch_btn.visible = false
		if not selected_drone:
			_hide_all()

## Called from CombatManager.handle_input for upper-grid clicks.
## Returns true if click was consumed (don't treat as shot).
func handle_upper_click(coord: Vector2i) -> bool:
	if launch_pending:
		launch_pending = false
		_do_launch(coord)
		_refresh_launch_btn()
		return true
	for d in _drones:
		if d.pos == coord:
			if selected_drone == d:
				_deselect_drone()
			else:
				_select_drone(d)
			return true
	return false

func cancel_launch() -> void:
	if launch_pending:
		launch_pending = false
		_refresh_launch_btn()

func is_drone_at(coord: Vector2i) -> bool:
	for d in _drones:
		if d.pos == coord: return true
	return false

## Called at turn execution: ages drones, returns bomb data dict for network.
func on_turn_executed() -> Dictionary:
	# Check carrier alive
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
	_refresh_ui_after_age()
	return data

## Re-reveal all active drone areas (call at start of turn execution)
func reveal_all() -> void:
	if carrier_ship and not carrier_ship.is_placed:
		if _drones.size() > 0: on_carrier_sunk()
		return
	for drone in _drones:
		_reveal_area(drone.pos)

## Check own ships on opponent bombs — sink any found.
## Call at start of _on_execute_turn, before shots.
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
## Call from NetworkOpponent after updating _opponent_ships.
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
## Call at start of _on_execute_turn in single-player mode.
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

## Receive a bomb placed by opponent (display on lower_grid).
func receive_opp_bomb(pos: Vector2i) -> void:
	if pos not in _opp_bombs:
		_opp_bombs.append(pos)
		lower_grid.set_cell(pos, 12)

## Carrier was sunk: destroy all drones (bombs persist).
func on_carrier_sunk() -> void:
	for drone in _drones.duplicate():
		_expire_drone(drone)
	_carrier_ui_on = false
	_hide_all()

# ── Launch & lifecycle ────────────────────────────────────────

func _on_begin_launch() -> void:
	launch_pending = true
	_deselect_drone()
	_launch_btn.text    = "🚁 Клікніть на карті суперника"
	_launch_btn.modulate = Color(1.0, 0.85, 0.1)

func _do_launch(coord: Vector2i) -> void:
	if not can_launch(): return
	if not upper_grid.is_valid(coord): return
	if is_drone_at(coord): return
	var drone    = DroneInfo.new()
	drone.id     = _next_id
	_next_id    += 1
	drone.pos    = coord
	_drones.append(drone)
	_drones_launched += 1
	upper_grid.set_cell(coord, 4)
	_reveal_area(coord)
	_select_drone(drone)

func _expire_drone(drone) -> void:
	_clear_drone_cell(drone.pos)
	_drones.erase(drone)
	if selected_drone == drone:
		selected_drone = null
		_hide_drone_controls()

func _clear_drone_cell(pos: Vector2i) -> void:
	upper_grid.set_cell(pos, 12 if pos in _own_bombs else 0)

# ── Selection ─────────────────────────────────────────────────

func _select_drone(drone) -> void:
	selected_drone = drone
	_refresh_drone_controls()

func _deselect_drone() -> void:
	selected_drone = null
	_hide_drone_controls()

# ── Movement ──────────────────────────────────────────────────

func _move_selected(dir: Vector2i) -> void:
	if not selected_drone: return
	var new_pos = selected_drone.pos + dir
	if not upper_grid.is_valid(new_pos): return
	if is_drone_at(new_pos): return
	if not turn_manager.spend(1): return
	_clear_drone_cell(selected_drone.pos)
	selected_drone.pos = new_pos
	upper_grid.set_cell(new_pos, 4)
	_reveal_area(new_pos)
	_refresh_drone_controls()

# ── Bomb ──────────────────────────────────────────────────────

func _on_drop_bomb() -> void:
	if not selected_drone or selected_drone.bombs_left <= 0: return
	var pos = selected_drone.pos
	if pos in _own_bombs: return
	selected_drone.bombs_left -= 1
	_own_bombs.append(pos)
	_new_bombs_this_turn.append(pos)
	_refresh_drone_controls()

# ── Reconnaissance ────────────────────────────────────────────

func _reveal_area(center: Vector2i) -> void:
	if not enemy_if: return
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell = Vector2i(center.x + dx, center.y + dy)
			if not upper_grid.is_valid(cell): continue
			var st = upper_grid.cell_state[cell.y][cell.x]
			if st in [4, 6, 7, 8, 9, 10, 11, 12]: continue
			if st == 1: upper_grid.set_cell(cell, 0)   # clear stale intel
			if enemy_if.call("is_hit", cell):
				upper_grid.set_cell(cell, 1)

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

func _refresh_launch_btn() -> void:
	if not _carrier_ui_on:
		_launch_btn.visible = false
		return
	var remaining = MAX_DRONES - _drones_launched
	_launch_btn.visible  = can_launch()
	_launch_btn.text     = "🚁 Пустити дрон (%d)" % remaining
	_launch_btn.modulate = Color(0.3, 0.9, 0.5) if can_launch() else C_NO
	_launch_btn.position = _col_pos(0.0)

func _refresh_drone_controls() -> void:
	if not selected_drone:
		_hide_drone_controls()
		_refresh_launch_btn()
		return

	var cy = 0.0
	if _carrier_ui_on and can_launch():
		cy = 46.0   # below launch button

	_info_lbl.visible = true
	_info_lbl.text    = "🚁 #%d  ⏳%d  💣%d" % [
		selected_drone.id + 1,
		selected_drone.turns_left,
		selected_drone.bombs_left
	]
	_info_lbl.position = _col_pos(cy)
	cy += 18.0

	var pos = selected_drone.pos
	for i in range(4):
		var can_m = upper_grid.is_valid(pos + DIRS[i]) \
				and not is_drone_at(pos + DIRS[i]) \
				and turn_manager.can_afford(1)
		_move_btns[i].visible  = true
		_move_btns[i].disabled = not can_m
		_move_btns[i].modulate = C_OK if can_m else C_NO
		_move_btns[i].position = _col_pos(cy)
		cy += BTN_SIZE.y + 2.0

	var can_bomb = selected_drone.bombs_left > 0 and pos not in _own_bombs
	_bomb_btn.visible  = true
	_bomb_btn.disabled = not can_bomb
	_bomb_btn.modulate = C_BOMB_BTN if can_bomb else C_NO
	_bomb_btn.position = _col_pos(cy)

	_refresh_launch_btn()

func _refresh_ui_after_age() -> void:
	if selected_drone:
		_refresh_drone_controls()
	else:
		_refresh_launch_btn()

func _hide_drone_controls() -> void:
	for btn in _move_btns: btn.visible = false
	_bomb_btn.visible = false
	_info_lbl.visible = false

func _hide_all() -> void:
	_hide_drone_controls()
	_launch_btn.visible = false

func _col_pos(offset_y: float) -> Vector2:
	var cs = upper_grid.cell_size
	return Vector2(upper_grid.global_position.x + cs * 20.0 + 4.0,
				   upper_grid.global_position.y + 4.0 + offset_y)
