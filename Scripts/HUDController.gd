## HUDController.gd
## Панель між полями: енергія (12⚡), кнопка завершення ходу, лічильник.

extends Control

signal end_turn_pressed

var turn_manager: Node = null

const MAX_ENERGY   = 12
const COLOR_OK     = Color(0.3, 1.0, 0.5)
const COLOR_WARN   = Color(1.0, 0.85, 0.2)
const COLOR_EMPTY  = Color(1.0, 0.3, 0.2)
const COLOR_BG     = Color(0.06, 0.1, 0.18, 0.95)
const COLOR_BORDER = Color(0.25, 0.45, 0.75, 0.6)

var _fuel_bar:   HBoxContainer
var _fuel_label: Label
var _turn_label: Label
var _end_btn:    Button

func _ready() -> void:
	_build_ui()

func setup_turn_manager(tm: Node) -> void:
	turn_manager = tm
	turn_manager.energy_changed.connect(_on_energy_changed)
	_refresh(tm.energy, MAX_ENERGY, tm.turn_number)

func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var bt = ColorRect.new()
	bt.color = COLOR_BORDER
	bt.size  = Vector2(9999, 1)
	add_child(bt)

	var bb = ColorRect.new()
	bb.color = COLOR_BORDER
	bb.size  = Vector2(9999, 1)
	add_child(bb)
	set_meta("border_bot", bb)

	# Ліво — паливо
	var left = VBoxContainer.new()
	left.position = Vector2(10, 6)
	add_child(left)

	_fuel_label = Label.new()
	_fuel_label.add_theme_font_size_override("font_size", 11)
	_fuel_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	left.add_child(_fuel_label)

	_fuel_bar = HBoxContainer.new()
	_fuel_bar.add_theme_constant_override("separation", 2)
	left.add_child(_fuel_bar)

	# Центр — кнопка
	_end_btn = Button.new()
	_end_btn.text = "ЗАВЕРШИТИ ХІД"
	_end_btn.add_theme_font_size_override("font_size", 11)
	_end_btn.pressed.connect(func(): emit_signal("end_turn_pressed"))
	add_child(_end_btn)

	# Право — хід
	_turn_label = Label.new()
	_turn_label.add_theme_font_size_override("font_size", 11)
	_turn_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9))
	add_child(_turn_label)
	set_meta("turn_lbl", _turn_label)

	resized.connect(_on_resized)

func _on_resized() -> void:
	var w = size.x
	var h = size.y
	(get_meta("border_bot") as ColorRect).position.y = h - 1
	_end_btn.size     = Vector2(130, 38)
	_end_btn.position = Vector2(w / 2.0 - 65, h / 2.0 - 19)
	_turn_label.position = Vector2(w - 80, h / 2.0 - 10)

func _on_energy_changed(current: int, maximum: int) -> void:
	_refresh(current, maximum, turn_manager.turn_number if turn_manager else 1)

func _refresh(energy: int, maximum: int, turn: int) -> void:
	_fuel_label.text = "⚡ %d / %d" % [energy, maximum]
	_fuel_label.add_theme_color_override("font_color", _energy_color(energy, maximum))
	_rebuild_bar(energy, maximum)
	_turn_label.text = "ХІД %d" % turn

func _rebuild_bar(energy: int, maximum: int) -> void:
	for c in _fuel_bar.get_children(): c.queue_free()
	for i in range(maximum):
		var block = ColorRect.new()
		block.custom_minimum_size = Vector2(12, 12)
		block.color = _energy_color(energy, maximum) if i < energy else Color(0.2, 0.2, 0.3)
		_fuel_bar.add_child(block)

func _energy_color(e: int, m: int) -> Color:
	var ratio = float(e) / float(m)
	if ratio > 0.6: return COLOR_OK
	elif ratio > 0.3: return COLOR_WARN
	else: return COLOR_EMPTY
