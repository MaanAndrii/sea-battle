## FleetPanel.gd
## Статус флоту — ліворуч від нижнього поля.
## Показує: назву корабля, здоров'я секцій (кольорові квадрати),
## мітки «рухався» і «стріляв» у поточному ході.

extends Control

signal ship_clicked(ship)

var all_ships:    Array = []
var plan_ref:     Array = []   # посилання на CombatManager.plan (той самий масив)
var selected_ship         = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton): return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT: return
	if all_ships.is_empty(): return
	var n     = all_ships.size()
	var row_h = clamp(size.y / float(n), 18.0, 36.0)
	var idx   = int(event.position.y / row_h)
	if idx < 0 or idx >= n: return
	emit_signal("ship_clicked", all_ships[idx])
	accept_event()

const C_INTACT   = Color(0.18, 0.44, 0.90, 0.85)
const C_HIT      = Color(0.72, 0.10, 0.04, 0.90)
const C_SUNK_SEC = Color(0.35, 0.35, 0.38, 0.55)
const C_BG_EVEN  = Color(0.03, 0.07, 0.13, 0.78)
const C_BG_ODD   = Color(0.05, 0.10, 0.18, 0.78)
const C_BG_SEL   = Color(0.18, 0.36, 0.72, 0.28)
const C_TEXT     = Color(0.82, 0.92, 1.00, 1.00)
const C_TEXT_DIM = Color(0.48, 0.53, 0.58, 0.75)
const C_BORDER   = Color(0.20, 0.35, 0.60, 0.40)
const C_MOVED    = Color(0.20, 0.92, 0.35, 1.00)
const C_SHOT     = Color(1.00, 0.30, 0.06, 1.00)
const C_HIT_X    = Color(1.00, 0.28, 0.04, 1.00)

func _draw() -> void:
	if all_ships.is_empty(): return

	var n      = all_ships.size()
	var row_h  = clamp(size.y / float(n), 18.0, 36.0)
	var font   = ThemeDB.fallback_font
	var fsz    = int(clamp(row_h * 0.40, 8.0, 13.0))
	var bsz    = clamp(row_h * 0.38, 5.0, 12.0)   # section box size
	var bgap   = bsz + 2.5

	# Overall background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.07, 0.13, 0.80))

	for i in range(n):
		var ship   = all_ships[i]
		var ry     = i * row_h
		var is_sel = (ship == selected_ship)
		var ds     = ship.get("damaged_sections")
		if not (ds is Array): ds = []
		var is_sunk  = not ship.is_placed
		var text_col = C_TEXT_DIM if is_sunk else C_TEXT

		# Row background
		var row_bg = C_BG_SEL if is_sel else (C_BG_ODD if i % 2 else C_BG_EVEN)
		draw_rect(Rect2(0, ry, size.x, row_h - 1.0), row_bg)

		# Ship name (up to 5 chars)
		var nm = ship.ship_name.left(5)
		draw_string(font,
			Vector2(3, ry + (row_h + fsz) * 0.5 - 1),
			nm, HORIZONTAL_ALIGNMENT_LEFT, 38, fsz, text_col)

		# Section health boxes
		var bx = 42.0
		var by = ry + (row_h - bsz) * 0.5
		for j in range(ship.size):
			var hit = ds.size() > j and ds[j]
			var bc  = C_SUNK_SEC if is_sunk else (C_HIT if hit else C_INTACT)
			var rx  = bx + j * bgap
			draw_rect(Rect2(rx, by, bsz, bsz), bc)
			if hit and not is_sunk:
				var p = 1.5
				draw_line(Vector2(rx + p, by + p),
				          Vector2(rx + bsz - p, by + bsz - p), C_HIT_X, 1.5)
				draw_line(Vector2(rx + bsz - p, by + p),
				          Vector2(rx + p, by + bsz - p),       C_HIT_X, 1.5)

		# Icons
		var ix = bx + ship.size * bgap + 4.0
		var iy = ry + (row_h + fsz) * 0.5 - 1.0

		if ship.get("has_moved") == true:
			draw_string(font, Vector2(ix, iy), "▶", HORIZONTAL_ALIGNMENT_LEFT,
				-1, fsz, C_MOVED)
			ix += fsz + 3.0

		# Count shots in plan for this ship
		var shots_n = 0
		for entry in plan_ref:
			if entry["ship"] == ship:
				shots_n = (entry["shots"] as Array).size()
				break
		if ship.get("shoot_marked") == true or shots_n > 0:
			var lbl = ("×%d" % shots_n) if shots_n > 0 else "×"
			draw_string(font, Vector2(ix, iy), lbl, HORIZONTAL_ALIGNMENT_LEFT,
				-1, fsz, C_SHOT)

	# Side borders
	draw_line(Vector2(0, 0), Vector2(0, size.y),          C_BORDER, 1.0)
	draw_line(Vector2(size.x - 1, 0), Vector2(size.x - 1, size.y), C_BORDER, 1.0)
