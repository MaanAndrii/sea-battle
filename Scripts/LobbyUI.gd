## LobbyUI.gd
## Лобі: Хост / Приєднатись / Один гравець.
## NetworkTransport і NetworkManager додаються до /root і
## переживають зміну сцени — GameScene_v2 знаходить їх там.

extends Control

const DEFAULT_IP = "127.0.0.1"

var _transport:   Node  = null
var _net_manager: Node  = null

var _status_lbl:  Label       = null
var _ip_field:    LineEdit    = null
var _host_btn:    Button      = null
var _join_btn:    Button      = null
var _solo_btn:    Button      = null
var _skin_opt:    OptionButton = null

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	# Dark sea background
	var bg = ColorRect.new()
	bg.color = Color(0.039, 0.118, 0.165, 1.0)  # #0a1e2a
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Subtle pixel grid overlay — 3 vertical + horizontal faint lines
	var grid_overlay = ColorRect.new()
	grid_overlay.color = Color(0.0, 0.667, 1.0, 0.04)
	grid_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(grid_overlay)

	# Centered card panel
	var panel = _make_panel()
	add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(300, 0)
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "МОРСЬКИЙ БІЙ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.0, 1.0, 1.0, 1.0))  # #00ffff
	vbox.add_child(title)

	var sub = Label.new()
	sub.text = "NEON BATTLE"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.0, 1.0, 0.667, 0.70))  # #00ffaa
	vbox.add_child(sub)

	_add_separator(vbox, Color(0.0, 1.0, 1.0, 0.30))

	# Skin selector
	var skin_row = HBoxContainer.new()
	skin_row.add_theme_constant_override("separation", 8)
	vbox.add_child(skin_row)

	var skin_lbl = Label.new()
	skin_lbl.text = "Стиль:"
	skin_lbl.add_theme_font_size_override("font_size", 13)
	skin_lbl.add_theme_color_override("font_color", Color(0.0, 0.8, 0.6, 0.80))
	skin_row.add_child(skin_lbl)

	_skin_opt = OptionButton.new()
	_skin_opt.add_item("Classic")
	_skin_opt.add_item("Neon")
	_skin_opt.selected = 1   # default Neon
	_skin_opt.custom_minimum_size = Vector2(120, 36)
	_skin_opt.add_theme_font_size_override("font_size", 13)
	_apply_neon_opt_style(_skin_opt)
	skin_row.add_child(_skin_opt)

	_add_separator(vbox, Color(0.0, 1.0, 1.0, 0.20))

	# Network buttons
	_host_btn = _make_btn("⬡  Хостувати  (порт 7777)", Color(0.0, 1.0, 0.667))   # #00ffaa
	_host_btn.pressed.connect(_on_host)
	vbox.add_child(_host_btn)

	_ip_field = LineEdit.new()
	_ip_field.text = DEFAULT_IP
	_ip_field.placeholder_text = "IP-адреса сервера"
	_ip_field.custom_minimum_size = Vector2(0, 40)
	_ip_field.add_theme_font_size_override("font_size", 13)
	_apply_neon_line_edit_style(_ip_field, Color(0.0, 0.667, 1.0))
	vbox.add_child(_ip_field)

	_join_btn = _make_btn("⬡  Приєднатись", Color(0.0, 0.667, 1.0))              # #00aaff
	_join_btn.pressed.connect(_on_join)
	vbox.add_child(_join_btn)

	_add_separator(vbox, Color(0.0, 1.0, 1.0, 0.15))

	_solo_btn = _make_btn("◈  Один гравець", Color(0.6, 0.7, 1.0))
	_solo_btn.pressed.connect(_on_solo)
	vbox.add_child(_solo_btn)

	_status_lbl = Label.new()
	_status_lbl.text = ""
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.add_theme_font_size_override("font_size", 12)
	_status_lbl.add_theme_color_override("font_color", Color(1.0, 0.667, 0.0, 1.0))  # #ffaa00
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_status_lbl)

func _make_panel() -> Control:
	var p = Panel.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = Vector2(320, 420)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.12, 0.92)
	style.border_color = Color(0.0, 1.0, 1.0, 0.50)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0.0, 1.0, 1.0, 0.18)
	style.shadow_size  = 12
	p.add_theme_stylebox_override("panel", style)
	return p

func _make_btn(txt: String, accent: Color) -> Button:
	var btn = Button.new()
	btn.text = txt
	btn.custom_minimum_size = Vector2(0, 46)
	btn.add_theme_font_size_override("font_size", 14)

	var sn = StyleBoxFlat.new()
	sn.bg_color = Color(0.02, 0.06, 0.12, 0.95)
	sn.border_color = Color(accent.r, accent.g, accent.b, 0.75)
	sn.set_border_width_all(2)
	sn.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", sn)
	btn.add_theme_color_override("font_color", Color(accent.r * 1.1, accent.g * 1.1, accent.b * 1.1, 1.0))

	var sh = StyleBoxFlat.new()
	sh.bg_color = Color(accent.r * 0.12, accent.g * 0.12, accent.b * 0.12, 0.95)
	sh.border_color = accent
	sh.set_border_width_all(2)
	sh.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("hover", sh)

	var sp = StyleBoxFlat.new()
	sp.bg_color = Color(accent.r * 0.25, accent.g * 0.25, accent.b * 0.25, 0.95)
	sp.border_color = Color(accent.r, accent.g, accent.b, 1.0)
	sp.set_border_width_all(2)
	sp.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("pressed", sp)

	return btn

func _apply_neon_opt_style(opt: OptionButton) -> void:
	var sn = StyleBoxFlat.new()
	sn.bg_color = Color(0.02, 0.06, 0.12, 0.95)
	sn.border_color = Color(0.0, 1.0, 1.0, 0.55)
	sn.set_border_width_all(2)
	sn.set_corner_radius_all(3)
	opt.add_theme_stylebox_override("normal", sn)
	opt.add_theme_color_override("font_color", Color(0.0, 1.0, 1.0, 0.90))

func _apply_neon_line_edit_style(le: LineEdit, accent: Color) -> void:
	var sn = StyleBoxFlat.new()
	sn.bg_color = Color(0.02, 0.05, 0.10, 0.95)
	sn.border_color = Color(accent.r, accent.g, accent.b, 0.60)
	sn.set_border_width_all(2)
	sn.set_corner_radius_all(3)
	sn.content_margin_left = 8
	le.add_theme_stylebox_override("normal", sn)
	le.add_theme_stylebox_override("focus", sn)
	le.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0, 1.0))
	le.add_theme_color_override("caret_color", Color(accent.r, accent.g, accent.b, 1.0))

func _add_separator(parent: Node, color: Color) -> void:
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	sep.add_theme_color_override("color", color)
	parent.add_child(sep)

# ── Дії ──────────────────────────────────────────────────────

func _on_host() -> void:
	_setup_network()
	var err = _transport.host()
	if err != OK:
		_set_status("Не вдалось відкрити порт: %d" % err)
		return
	_set_buttons_enabled(false)
	_set_status("Очікування суперника на порту 7777...")

func _on_join() -> void:
	var ip = _ip_field.text.strip_edges()
	if ip.is_empty(): ip = DEFAULT_IP
	_setup_network()
	var err = _transport.join(ip)
	if err != OK:
		_set_status("Не вдалось підключитись: %d" % err)
		return
	_set_buttons_enabled(false)
	_set_status("Підключення до %s:7777..." % ip)

func _on_solo() -> void:
	_apply_skin_choice()
	get_tree().change_scene_to_file("res://GameScene.tscn")

# ── NetworkManager/Transport lifecycle ───────────────────────

func _setup_network() -> void:
	if _transport: return

	_transport = load("res://Scripts/NetworkTransport.gd").new()
	_transport.name = "NetworkTransport"
	get_tree().root.add_child(_transport)

	_net_manager = load("res://Scripts/NetworkManager.gd").new()
	_net_manager.name = "NetworkManager"
	get_tree().root.add_child(_net_manager)
	_net_manager.call("setup", _transport)

	_transport.connection_failed.connect(_on_connection_failed)
	_net_manager.opponent_connected.connect(_on_opponent_connected)
	_net_manager.both_ready.connect(_on_both_ready)

func _on_connection_failed() -> void:
	_set_status("Не вдалось підключитись. Перевір IP-адресу.")
	_set_buttons_enabled(true)

func _on_opponent_connected() -> void:
	_apply_skin_choice()
	_set_status("Суперник підключився! Переходимо до гри...")
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://GameScene.tscn")

func _on_both_ready(_my_turn: bool) -> void:
	pass

# ── Утиліти ──────────────────────────────────────────────────

func _set_status(txt: String) -> void:
	_status_lbl.text = txt

func _set_buttons_enabled(v: bool) -> void:
	_host_btn.disabled = not v
	_join_btn.disabled = not v
	_solo_btn.disabled = not v

func _apply_skin_choice() -> void:
	var skin_id = "classic" if _skin_opt.selected == 0 else "neon"
	get_tree().root.set_meta("skin_id", skin_id)
