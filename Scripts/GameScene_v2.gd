## GameScene_v2.gd
extends Node2D

var screen_size: Vector2

const PADDING:      float = 6.0
const HUD_HEIGHT:   float = 64.0
const LABEL_HEIGHT: float = 24.0
const DOCK_HEIGHT:  float = 72.0

var upper_grid:     Node2D
var lower_grid:     Node2D
var hud:            Control
var upper_label:    Label
var lower_label:    Label
var ship_dock:      Control
var ship_mover:     Node2D
var combat_manager: Node

var grid_model
var turn_manager: Node
var enemy_setup:  Node
var enemy_ai:     Node

# Мережевий режим
var network_manager:  Node  = null
var network_opponent: Node  = null
var _my_turn:         bool  = true
var _pending_shots:   Array[Vector2i] = []

# Поточна фаза: "setup" | "combat"
var phase: String = "setup"

func _ready() -> void:
	screen_size = get_viewport().get_visible_rect().size

	# Перевіряємо чи запущені в мережевому режимі
	network_manager = get_tree().root.get_node_or_null("NetworkManager")

	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.14, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	upper_grid = _make_grid(Color(0.25, 0.55, 0.95, 0.65), Color(0.03, 0.08, 0.20, 1.0))
	lower_grid = _make_grid(Color(0.2,  0.85, 0.5,  0.65), Color(0.03, 0.16, 0.08, 1.0))

	ship_mover = Node2D.new()
	ship_mover.set_script(load("res://Scripts/ShipMover.gd"))
	ship_mover.visible = false
	add_child(ship_mover)

	var hud_layer = CanvasLayer.new()
	add_child(hud_layer)

	hud = Control.new()
	hud.set_script(load("res://Scripts/HUDController.gd"))
	hud_layer.add_child(hud)

	upper_label = _make_label("ПОЛЕ УДАРІВ")
	lower_label = _make_label("МОЄ ПОЛЕ")
	hud_layer.add_child(upper_label)
	hud_layer.add_child(lower_label)

	ship_dock = Control.new()
	ship_dock.set_script(load("res://Scripts/ShipDock.gd"))
	hud_layer.add_child(ship_dock)

	turn_manager = load("res://Scripts/TurnManager.gd").new()
	add_child(turn_manager)

	grid_model = load("res://Scripts/GridModel.gd").new()

	await get_tree().process_frame
	_layout()

	var cell = _calc_cell()
	ship_dock.call("setup", cell, grid_model, lower_grid)
	ship_dock.all_ships_placed.connect(_on_setup_confirmed)

	hud.call("setup_turn_manager", turn_manager)
	hud.end_turn_pressed.connect(_on_end_turn)

	if network_manager:
		# Мережевий режим: EnemySetup не потрібен, NetworkOpponent створюється
		# в _on_setup_confirmed після розстановки флоту.
		_my_turn = network_manager.my_turn_first
	else:
		# Одиночний режим: кнопка тестової розстановки ворога
		enemy_setup = Node.new()
		enemy_setup.set_script(load("res://Scripts/EnemySetup.gd"))
		add_child(enemy_setup)
		enemy_setup.call("setup", upper_grid)

func _make_grid(gc: Color, bc: Color) -> Node2D:
	var node = Node2D.new()
	node.set_script(load("res://Scripts/GridRenderer.gd"))
	node.set("grid_color", gc)
	node.set("bg_color",   bc)
	add_child(node)
	return node

func _make_label(txt: String) -> Label:
	var lbl = Label.new()
	lbl.text = txt
	return lbl

# ─────────────────────────────────────────
#  Розмітка
# ─────────────────────────────────────────

func _calc_cell() -> float:
	var aw = screen_size.x - PADDING * 2
	var ah = (screen_size.y - HUD_HEIGHT - LABEL_HEIGHT * 2 - DOCK_HEIGHT - PADDING * 6) / 2.0
	return min(aw / 20.0, ah / 20.0)

func _layout() -> void:
	screen_size = get_viewport().get_visible_rect().size
	var cell = _calc_cell()
	var gw   = cell * 20.0
	var gh   = cell * 20.0
	var gx   = PADDING + (screen_size.x - PADDING * 2 - gw) / 2.0

	var ul_y = PADDING
	var ug_y = ul_y + LABEL_HEIGHT
	upper_grid.position = Vector2(gx, ug_y)
	upper_grid.call("setup", cell)
	_style_label(upper_label, Vector2(PADDING, ul_y),
		screen_size.x - PADDING * 2, Color(0.45, 0.75, 1.0))

	var hud_y = ug_y + gh + PADDING
	hud.position = Vector2(0, hud_y)
	hud.size     = Vector2(screen_size.x, HUD_HEIGHT)

	var ll_y = hud_y + HUD_HEIGHT + PADDING
	var lg_y = ll_y + LABEL_HEIGHT
	lower_grid.position = Vector2(gx, lg_y)
	lower_grid.call("setup", cell)
	_style_label(lower_label, Vector2(PADDING, ll_y),
		screen_size.x - PADDING * 2, Color(0.35, 1.0, 0.55))

	var dock_y = lg_y + gh + PADDING
	ship_dock.position = Vector2(0, dock_y)
	ship_dock.size     = Vector2(screen_size.x, DOCK_HEIGHT)

func _style_label(lbl: Label, pos: Vector2, w: float, color: Color) -> void:
	lbl.position = pos
	lbl.size     = Vector2(w, LABEL_HEIGHT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", color)

# ─────────────────────────────────────────
#  Фаза SETUP → COMBAT
# ─────────────────────────────────────────

func _on_setup_confirmed() -> void:
	phase = "combat"

	# Переносимо кораблі з ShipDock → GameScene до того як ховаємо dock
	var ships_ref = ship_dock.all_ships.duplicate()
	for ship in ships_ref:
		var wp = ship.global_position
		ship.reparent(self)
		ship.global_position = wp
		ship.setup_locked = false   # знімаємо lock щоб кольори були нормальні
		ship.is_placed    = true
		ship.queue_redraw()

	ship_dock.visible = false

	# ShipMover
	ship_mover.call("setup", grid_model, lower_grid, turn_manager, ships_ref)
	ship_mover.visible = true

	if network_manager:
		# ── Мережевий режим ──────────────────────────────────────
		# NetworkOpponent замінює EnemySetup і EnemyAI
		network_opponent = Node.new()
		network_opponent.set_script(load("res://Scripts/NetworkOpponent.gd"))
		add_child(network_opponent)
		network_opponent.call("setup", upper_grid, lower_grid,
				network_manager, grid_model, ships_ref)

		# CombatManager з network_opponent як p_enemy
		combat_manager = Node.new()
		combat_manager.set_script(load("res://Scripts/CombatManager.gd"))
		add_child(combat_manager)
		combat_manager.call("setup", upper_grid, lower_grid,
				ship_mover, turn_manager, ships_ref, network_opponent)
		combat_manager.turn_executed.connect(_on_turn_executed)
		combat_manager.shot_fired.connect(_on_shot_fired)

		ship_mover.set("combat_manager", combat_manager)

		var hud_btn = hud.get("_end_btn")
		if hud_btn:
			hud_btn.visible = false

		# Надсилаємо наш флот супернику та чекаємо підтвердження
		_my_turn = network_manager.my_turn_first
		network_manager.send_my_fleet(ships_ref)
		lower_label.text = "МОЄ ПОЛЕ  [Очікуємо суперника...]"

		# Якщо флот суперника вже отримано (гонка: він надіслав раніше) —
		# enemy_placed вже спрацював, але блокування UI через _my_turn достатньо.
		# Якщо ні — чекаємо сигналу network_opponent.enemy_placed.
		if not network_opponent.get("_opponent_fleet_ready"):
			await network_opponent.enemy_placed

		lower_label.text = "МОЄ ПОЛЕ  [Фаза бою]"
	else:
		# ── Одиночний режим ──────────────────────────────────────
		# CombatManager
		combat_manager = Node.new()
		combat_manager.set_script(load("res://Scripts/CombatManager.gd"))
		add_child(combat_manager)
		combat_manager.call("setup", upper_grid, lower_grid,
				ship_mover, turn_manager, ships_ref, enemy_setup)
		combat_manager.turn_executed.connect(_on_turn_executed)
		combat_manager.shot_fired.connect(_on_shot_fired)

		# Зв'язуємо ShipMover з CombatManager
		ship_mover.set("combat_manager", combat_manager)

		# Ховаємо кнопку HUD
		var hud_btn = hud.get("_end_btn")
		if hud_btn:
			hud_btn.visible = false

		# EnemyAI — постріли ворога
		enemy_ai = Node.new()
		enemy_ai.set_script(load("res://Scripts/EnemyAI.gd"))
		add_child(enemy_ai)
		enemy_ai.call("setup", lower_grid, grid_model, ships_ref)

		lower_label.text = "МОЄ ПОЛЕ  [Фаза бою]"

# ─────────────────────────────────────────
#  Input — маршрутизація за фазою
# ─────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if phase != "combat":
		return

	# У мережевому режимі блокуємо ввід якщо зараз не наш хід
	if network_manager and not _my_turn:
		return

	var pos: Vector2   = Vector2.ZERO
	var pressed: bool  = false

	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pos     = event.global_position
		pressed = true
	elif event is InputEventScreenTouch and event.pressed:
		pos     = event.position
		pressed = true

	if not pressed:
		return

	if _click_on_ui(pos):
		return

	# Делегуємо в CombatManager
	# ShipMover кнопки мають пріоритет — перевіряємо чи клік не на них
	combat_manager.call("handle_input", pos)

func _click_on_ui(pos: Vector2) -> bool:
	for layer in [ship_mover.get("_ui_layer"), combat_manager.get("_ui_layer")]:
		if not layer:
			continue
		for child in layer.get_children():
			if child is Button and child.visible:
				if Rect2(child.position, child.size).has_point(pos):
					return true
	return false

# ─────────────────────────────────────────
#  Події
# ─────────────────────────────────────────

func _on_turn_executed() -> void:
	if network_manager and network_opponent:
		# ── Мережевий режим ──────────────────────────────────────
		# Надсилаємо хід (постріли + позиції кораблів) супернику
		var ships_ref = []
		for child in get_children():
			if child.get_script() and child.is_placed if child.has_method("is_placed") else false:
				ships_ref.append(child)
		# Збираємо кораблі через combat_manager
		var cm_ships = combat_manager.get("all_ships") as Array
		network_manager.send_turn(_pending_shots, cm_ships if cm_ships else [])
		_pending_shots.clear()
		_my_turn = false
		lower_label.text = "МОЄ ПОЛЕ  [Хід суперника...]"
		# Чекаємо поки суперник відповість своїм ходом
		await network_opponent.opponent_turn_applied
		_my_turn = true
		lower_label.text = "МОЄ ПОЛЕ  [Фаза бою]"
	else:
		# ── Одиночний режим ──────────────────────────────────────
		if enemy_ai:
			await enemy_ai.call("execute_turn")

func _on_shot_fired(coord: Vector2i) -> void:
	# Накопичуємо постріли для надсилання мережею в кінці ходу
	_pending_shots.append(coord)

func _on_end_turn() -> void:
	# Ручне завершення ходу через HUD
	turn_manager.end_turn()
	if combat_manager:
		pass  # CombatManager сам скидається після execute

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_layout()
