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

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.14, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(280, 0)
	vbox.add_theme_constant_override("separation", 12)
	add_child(vbox)

	var title = Label.new()
	title.text = "МОРСЬКИЙ БІЙ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	vbox.add_child(title)

	var sub = Label.new()
	sub.text = "Мережева гра"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.5, 0.6, 0.8))
	vbox.add_child(sub)

	_add_separator(vbox)

	_host_btn = _make_btn("Хостувати (порт 7777)", Color(0.2, 0.85, 0.4))
	_host_btn.pressed.connect(_on_host)
	vbox.add_child(_host_btn)

	_ip_field = LineEdit.new()
	_ip_field.text = DEFAULT_IP
	_ip_field.placeholder_text = "IP-адреса сервера"
	_ip_field.custom_minimum_size = Vector2(0, 38)
	vbox.add_child(_ip_field)

	_join_btn = _make_btn("Приєднатись", Color(0.3, 0.6, 1.0))
	_join_btn.pressed.connect(_on_join)
	vbox.add_child(_join_btn)

	_add_separator(vbox)

	_solo_btn = _make_btn("Один гравець", Color(0.6, 0.6, 0.7))
	_solo_btn.pressed.connect(_on_solo)
	vbox.add_child(_solo_btn)

	_status_lbl = Label.new()
	_status_lbl.text = ""
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.add_theme_font_size_override("font_size", 12)
	_status_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_status_lbl)

func _make_btn(txt: String, col: Color) -> Button:
	var btn = Button.new()
	btn.text = txt
	btn.custom_minimum_size = Vector2(0, 44)
	btn.add_theme_font_size_override("font_size", 14)
	btn.modulate = col
	return btn

func _add_separator(parent: Node) -> void:
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
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
	_set_status("Суперник підключився! Переходимо до гри...")

func _on_both_ready(_my_turn: bool) -> void:
	get_tree().change_scene_to_file("res://GameScene.tscn")

# ── Утиліти ──────────────────────────────────────────────────

func _set_status(txt: String) -> void:
	_status_lbl.text = txt

func _set_buttons_enabled(v: bool) -> void:
	_host_btn.disabled = not v
	_join_btn.disabled = not v
	_solo_btn.disabled = not v
