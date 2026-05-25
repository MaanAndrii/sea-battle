## FleetPanel.gd
## Статус флоту — ліворуч від нижнього поля.
## Показує: назву корабля, здоров'я секцій (кольорові квадрати),
## мітки «рухався» і «стріляв» у поточному ході.

extends Control
const SkinManager = preload("res://Scripts/SkinManager.gd")

signal ship_clicked(ship)

var all_ships:    Array = []
var plan_ref:     Array = []
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

# Classic palette
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

# Neon palette
const N_INTACT   = Color(0.0,  1.0,  0.667, 0.85)  # #00ffaa
const N_HIT      = Color(1.0,  0.0,  0.667, 0.88)  # #ff00aa
const N_SUNK_SEC = Color(0.20, 0.20, 0.24,  0.65)
const N_BG_EVEN  = Color(0.02, 0.06, 0.10,  0.82)
const N_BG_ODD   = Color(0.04, 0.09, 0.14,  0.82)
const N_BG_SEL   = Color(0.0,  0.20, 0.22,  0.35)
const N_TEXT     = Color(0.75, 1.00, 0.90,  1.00)
const N_TEXT_DIM = Color(0.30, 0.45, 0.40,  0.70)
const N_BORDER   = Color(0.0,  1.0,  1.0,   0.35)  # #00ffff
const N_MOVED    = Color(0.0,  1.0,  0.667, 1.00)  # #00ffaa
const N_SHOT     = Color(1.0,  0.0,  0.667, 1.00)  # #ff00aa
const N_HIT_X    = Color(1.0,  0.0,  0.667, 1.00)  # #ff00aa

func _draw() -> void:
	if all_ships.is_empty(): return

	var neon   = SkinManager.current_skin() == SkinManager.SKIN_NEON
	var n      = all_ships.size()
	var row_h  = clamp(size.y / float(n), 18.0, 36.0)
	var font   = ThemeDB.fallback_font
	var fsz    = int(clamp(row_h * 0.40, 8.0, 13.0))
	var bsz    = clamp(row_h * 0.38, 5.0, 12.0)
	var bgap   = bsz + 2.5

	var intact_c  = N_INTACT   if neon else C_INTACT
	var hit_c     = N_HIT      if neon else C_HIT
	var sunk_c    = N_SUNK_SEC if neon else C_SUNK_SEC
	var hit_x_c   = N_HIT_X   if neon else C_HIT_X
	var moved_c   = N_MOVED    if neon else C_MOVED
	var shot_c    = N_SHOT     if neon else C_SHOT
	var border_c  = N_BORDER   if neon else C_BORDER

	# Background
	var bg_col = Color(0.02, 0.04, 0.08, 0.85) if neon else Color(0.03, 0.07, 0.13, 0.80)
	draw_rect(Rect2(Vector2.ZERO, size), bg_col)

	for i in range(n):
		var ship   = all_ships[i]
		var ry     = i * row_h
		var is_sel = (ship == selected_ship)
		var ds     = ship.get("damaged_sections")
		if not (ds is Array): ds = []
		var is_sunk  = not ship.is_placed
		var text_col = (N_TEXT_DIM if neon else C_TEXT_DIM) if is_sunk \
			else (N_TEXT if neon else C_TEXT)

		# Row bg
		var even_c = N_BG_EVEN if neon else C_BG_EVEN
		var odd_c  = N_BG_ODD  if neon else C_BG_ODD
		var sel_c  = N_BG_SEL  if neon else C_BG_SEL
		var row_bg = sel_c if is_sel else (odd_c if i % 2 else even_c)
		draw_rect(Rect2(0, ry, size.x, row_h - 1.0), row_bg)

		# Selection accent line in neon mode
		if is_sel and neon:
			draw_line(Vector2(0, ry), Vector2(0, ry + row_h - 1),
				Color(0.0, 1.0, 1.0, 0.80), 2.0)

		# Ship name
		var nm = ship.ship_name.left(5)
		draw_string(font,
			Vector2(5, ry + (row_h + fsz) * 0.5 - 1),
			nm, HORIZONTAL_ALIGNMENT_LEFT, 38, fsz, text_col)

		# Section health boxes
		var bx = 44.0
		var by = ry + (row_h - bsz) * 0.5
		for j in range(ship.size):
			var hit = ds.size() > j and ds[j]
			var bc  = sunk_c if is_sunk else (hit_c if hit else intact_c)
			var rx  = bx + j * bgap
			draw_rect(Rect2(rx, by, bsz, bsz), bc)
			if neon and not is_sunk and not hit:
				draw_rect(Rect2(rx, by, bsz, bsz), Color(bc.r, bc.g, bc.b, 0.50), false, 1.0)
			if hit and not is_sunk:
				var p = 1.5
				draw_line(Vector2(rx + p, by + p),
				          Vector2(rx + bsz - p, by + bsz - p), hit_x_c, 1.5)
				draw_line(Vector2(rx + bsz - p, by + p),
				          Vector2(rx + p, by + bsz - p),        hit_x_c, 1.5)

		# Icons
		var ix = bx + ship.size * bgap + 4.0
		var iy = ry + (row_h + fsz) * 0.5 - 1.0

		if ship.get("has_moved") == true:
			draw_string(font, Vector2(ix, iy), "▶", HORIZONTAL_ALIGNMENT_LEFT,
				-1, fsz, moved_c)
			ix += fsz + 3.0

		var shots_n = 0
		for entry in plan_ref:
			if entry["ship"] == ship:
				shots_n = (entry["shots"] as Array).size()
				break
		if ship.get("shoot_marked") == true or shots_n > 0:
			var lbl = ("×%d" % shots_n) if shots_n > 0 else "×"
			draw_string(font, Vector2(ix, iy), lbl, HORIZONTAL_ALIGNMENT_LEFT,
				-1, fsz, shot_c)

	# Borders
	draw_line(Vector2(0, 0),          Vector2(0, size.y),          border_c, 1.0)
	draw_line(Vector2(size.x-1, 0),   Vector2(size.x-1, size.y),   border_c, 1.0)
