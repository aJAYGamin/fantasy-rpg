class_name SettingsScreen
extends Control

## Settings page shared by the main menu (standalone overlay) and the pause menu
## (replace-not-stack sub-view). A category hub: the root lists Game / Controls /
## Audio / Display / Performance; each opens its own view. Controls opens a
## further Keyboard / Controller split. Fully keyboard- & controller-navigable.

signal back_requested

const ACCENT := Color(0.85, 0.7, 1.0)
const SECTION_COLOR := Color(0.78, 0.65, 0.95)
const VALUE_COLOR := Color(0.78, 0.92, 0.78)
const NOTE_COLOR := Color(0.62, 0.56, 0.72)

# When opened from the main menu we own Esc; inside the pause menu the PauseMenu
# owns Esc and backs us out at the root.
var _standalone: bool = false
var _res_option: OptionButton = null
# Current view: root / game / controls / keyboard / controller / audio / display / performance.
var _view: String = "root"

# --- Live status labels (refreshed in _process) ---
var _device_label: Label = null       # controller
var _kb_status_label: Label = null     # keyboard activity
var _mouse_status_label: Label = null  # mouse activity

# --- Remap state ---
var _kb_buttons: Dictionary = {}    # action -> Button (keyboard binding)
var _pad_buttons: Dictionary = {}   # action -> Button (controller binding)
var _listening: bool = false
var _listen_action: String = ""
var _listen_keyboard: bool = true

func setup(standalone: bool = false) -> void:
	_standalone = standalone
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	# The central focus guard maintains controller focus across view changes and
	# rebuilds; it makes sliders/dropdowns/buttons focusable in controller mode.
	GameManager.register_focus_scope(self)

func _exit_tree() -> void:
	GameManager.unregister_focus_scope(self)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	# While rebinding, capture the next key/controller input for the slot.
	if _listening:
		_capture_rebind(event)
		return
	if event.is_action_pressed("ui_cancel"):
		var parent := _parent_of(_view)
		if parent != "":
			_view = parent
			_build()
			get_viewport().set_input_as_handled()
		elif _standalone:
			# Main-menu overlay at root: we own Esc and close ourselves.
			back_requested.emit()
			get_viewport().set_input_as_handled()
		# else: pause-menu root — let PauseMenu handle Esc and dismiss us.

func _process(_dt: float) -> void:
	# Live device statuses on the relevant views.
	if _view == "keyboard":
		if is_instance_valid(_kb_status_label):
			_kb_status_label.text = GameManager.keyboard_status_text()
		if is_instance_valid(_mouse_status_label):
			_mouse_status_label.text = GameManager.mouse_status_text()
	elif _view == "controller":
		if is_instance_valid(_device_label):
			_device_label.text = GameManager.connected_controllers_text()

# Parent view for back navigation ("" means exit the Settings screen).
func _parent_of(view: String) -> String:
	match view:
		"keyboard", "controller": return "controls"
		"root": return ""
	return "root"

func _is_list_view() -> bool:
	return _view == "root" or _view == "controls"

func _build() -> void:
	# Detach old children IMMEDIATELY (not just queue_free, which is deferred):
	# the previous full-rect dim/center use MOUSE_FILTER_STOP, so if they lingered
	# one frame on top of the freshly-built panel they would swallow clicks aimed
	# at the new Back button.
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_kb_buttons.clear()
	_pad_buttons.clear()
	_listening = false
	_listen_action = ""
	_device_label = null
	_kb_status_label = null
	_mouse_status_label = null
	_res_option = null

	# Pin the dim + centering container to the viewport so the panel centers even
	# when this control's own rect is (0,0).
	var screen_size := get_viewport_rect().size

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.custom_minimum_size = screen_size
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.custom_minimum_size = screen_size
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(center)

	var panel := BattleUITheme.make_panel()
	panel.custom_minimum_size = Vector2(540, 0)
	var pstyle := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if pstyle:
		pstyle.content_margin_left = 24
		# List views are centered (symmetric margins); detail views give the
		# scrollbar a tight right margin and the rows their gap via a MarginContainer.
		pstyle.content_margin_right = 24 if _is_list_view() else 8
		pstyle.content_margin_top = 18
		pstyle.content_margin_bottom = 18
	center.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)

	outer.add_child(_label("✦  %s  ✦" % _view_title(), BattleUITheme.font_bold(), 22, BattleUITheme.TEXT_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	outer.add_child(_divider())

	if _view == "root":
		_build_root(outer)
	elif _view == "controls":
		_build_controls_menu(outer)
	else:
		# Scrollable content area for a single detail view.
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.custom_minimum_size = Vector2(0, clampf(screen_size.y - 240.0, 200.0, 520.0))
		_style_scrollbar(scroll.get_v_scroll_bar())
		outer.add_child(scroll)
		var pad := MarginContainer.new()
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pad.add_theme_constant_override("margin_right", 18)
		scroll.add_child(pad)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 12)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pad.add_child(v)
		match _view:
			"game": _build_game(v)
			"keyboard": _build_keyboard(v)
			"controller": _build_controller(v)
			"audio": _build_audio(v)
			"display": _build_display(v)
			"performance": _build_performance(v)

	outer.add_child(_divider())
	var back := BattleUITheme.make_button("← Back", 13)
	back.custom_minimum_size = Vector2(0, 38)
	back.pressed.connect(_on_back)
	outer.add_child(back)
	# Focus is handled by the central guard (GameManager); it makes the controls
	# focusable in controller mode and re-grabs after this rebuild.

func _view_title() -> String:
	match _view:
		"game": return "Game"
		"controls": return "Controls"
		"keyboard": return "Keyboard"
		"controller": return "Controller"
		"audio": return "Audio"
		"display": return "Display"
		"performance": return "Performance"
	return "Settings"

func _on_back() -> void:
	var parent := _parent_of(_view)
	if parent == "":
		back_requested.emit()
	else:
		_view = parent
		_build()

# Root view: the category buttons, in the requested order.
func _build_root(outer: VBoxContainer) -> void:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	outer.add_child(list)
	var cats := [
		["game", "Game"],
		["controls", "Controls"],
		["audio", "Audio"],
		["display", "Display"],
		["performance", "Performance"],
	]
	for cat in cats:
		var key: String = cat[0]
		var b := BattleUITheme.make_button(cat[1], 15)
		b.custom_minimum_size = Vector2(0, 44)
		b.pressed.connect(func(): _open_category(key))
		list.add_child(b)

# Controls hub: Keyboard / Controller buttons.
func _build_controls_menu(outer: VBoxContainer) -> void:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	outer.add_child(list)
	for cat in [["keyboard", "Keyboard"], ["controller", "Controller"]]:
		var key: String = cat[0]
		var b := BattleUITheme.make_button(cat[1], 15)
		b.custom_minimum_size = Vector2(0, 44)
		b.pressed.connect(func(): _open_category(key))
		list.add_child(b)

func _open_category(cat: String) -> void:
	_view = cat
	_build()

# --- Category content builders -----------------------------------------------
func _build_audio(v: VBoxContainer) -> void:
	var s: SettingsModel = GameManager.settings
	v.add_child(_volume_row("Master", s.volume_master, func(val): s.volume_master = val))
	v.add_child(_volume_row("Music", s.volume_music, func(val): s.volume_music = val))
	v.add_child(_volume_row("Sound FX", s.volume_sfx, func(val): s.volume_sfx = val))

func _build_display(v: VBoxContainer) -> void:
	var s: SettingsModel = GameManager.settings
	var mode_opt := _make_option(
		PackedStringArray(["Fullscreen", "Borderless", "Windowed"]),
		s.window_mode,
		func(i: int):
			s.window_mode = i
			if _res_option != null:
				_res_option.disabled = i != SettingsModel.WindowMode.WINDOWED
			GameManager.apply_display_and_save())
	v.add_child(_labeled_row("Window Mode", mode_opt))
	_res_option = _make_option(_resolution_labels(), s.window_size_index,
		func(i: int):
			s.window_size_index = i
			GameManager.apply_display_and_save())
	_res_option.disabled = s.window_mode != SettingsModel.WindowMode.WINDOWED
	v.add_child(_labeled_row("Resolution", _res_option))

func _build_performance(v: VBoxContainer) -> void:
	var s: SettingsModel = GameManager.settings
	var fps_opt := _make_option(_fps_labels(), _fps_index(s.fps_cap),
		func(i: int):
			s.fps_cap = SettingsModel.FPS_OPTIONS[i]
			GameManager.apply_performance_and_save())
	v.add_child(_labeled_row("Max FPS", fps_opt))
	v.add_child(_toggle_row("V-Sync", s.vsync_enabled, func(on): s.vsync_enabled = on, GameManager.apply_performance_and_save))
	v.add_child(_toggle_row("Show FPS Counter", s.show_fps, func(on): s.show_fps = on, GameManager.apply_fps_overlay_and_save))

func _build_game(v: VBoxContainer) -> void:
	var s: SettingsModel = GameManager.settings
	var diff_opt := _make_option(
		PackedStringArray(["Easy", "Normal", "Hard"]),
		s.difficulty,
		func(i: int):
			s.difficulty = i
			GameManager.save_settings())
	v.add_child(_labeled_row("Difficulty", diff_opt))
	v.add_child(_toggle_row("Auto-Save", s.autosave_enabled, func(on): s.autosave_enabled = on, GameManager.save_settings))

func _build_keyboard(v: VBoxContainer) -> void:
	# Live keyboard + mouse activity status.
	_kb_status_label = _status_value(GameManager.keyboard_status_text())
	v.add_child(_status_row("Keyboard", _kb_status_label))
	_mouse_status_label = _status_value(GameManager.mouse_status_text())
	v.add_child(_status_row("Mouse", _mouse_status_label))

	v.add_child(_divider())
	v.add_child(_label("Click a binding, then press a key. Esc cancels.", BattleUITheme.font_regular(), 11, NOTE_COLOR))
	for meta in InputMapConfig.ACTIONS:
		v.add_child(_kb_remap_row(meta["action"], meta["label"]))

	var reset_all := BattleUITheme.make_button("Reset Keyboard to Defaults", 12)
	reset_all.custom_minimum_size = Vector2(0, 34)
	reset_all.pressed.connect(_on_reset_keyboard)
	v.add_child(reset_all)

func _build_controller(v: VBoxContainer) -> void:
	var s: SettingsModel = GameManager.settings
	_device_label = _status_value(GameManager.connected_controllers_text())
	v.add_child(_status_row("Controller", _device_label))

	v.add_child(_divider())
	v.add_child(_sens_row("Left Stick Sensitivity", s.stick_sensitivity_left, func(val): s.stick_sensitivity_left = val))
	v.add_child(_sens_row("Right Stick Sensitivity", s.stick_sensitivity_right, func(val): s.stick_sensitivity_right = val))
	v.add_child(_label("Right stick is reserved for future camera control.", BattleUITheme.font_regular(), 11, NOTE_COLOR))

	v.add_child(_divider())
	v.add_child(_label("Click a binding, then press a controller button/stick. Esc cancels.", BattleUITheme.font_regular(), 11, NOTE_COLOR))
	for meta in InputMapConfig.ACTIONS:
		v.add_child(_pad_remap_row(meta["action"], meta["label"]))

	var reset_all := BattleUITheme.make_button("Reset Controller to Defaults", 12)
	reset_all.custom_minimum_size = Vector2(0, 34)
	reset_all.pressed.connect(_on_reset_controller)
	v.add_child(reset_all)

# --- Rows ---------------------------------------------------------------------
func _volume_row(label_text: String, initial: float, on_set: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var name_label := _label(label_text, BattleUITheme.font_regular(), 15, BattleUITheme.TEXT_PRIMARY)
	name_label.custom_minimum_size = Vector2(140, 0)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(240, 24)
	_style_slider(slider)
	row.add_child(slider)
	var pct := _label(_pct(initial), BattleUITheme.font_bold(), 14, VALUE_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	pct.custom_minimum_size = Vector2(52, 0)
	row.add_child(pct)
	slider.value_changed.connect(func(val: float):
		on_set.call(val)
		pct.text = _pct(val)
		GameManager.apply_audio_and_save())
	return row

func _toggle_row(label_text: String, initial: bool, on_set: Callable, commit: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var name_label := _label(label_text, BattleUITheme.font_regular(), 15, BattleUITheme.TEXT_PRIMARY)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var toggle := CheckButton.new()
	toggle.button_pressed = initial
	toggle.add_theme_color_override("font_color", BattleUITheme.TEXT_PRIMARY)
	toggle.add_theme_color_override("font_hover_color", ACCENT)
	toggle.toggled.connect(func(pressed: bool):
		on_set.call(pressed)
		commit.call())
	row.add_child(toggle)
	return row

func _labeled_row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var name_label := _label(label_text, BattleUITheme.font_regular(), 15, BattleUITheme.TEXT_PRIMARY)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(control)
	return row

func _status_value(text: String) -> Label:
	return _label(text, BattleUITheme.font_bold(), 13, VALUE_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)

func _status_row(name_text: String, value_label: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var n := _label(name_text, BattleUITheme.font_regular(), 15, BattleUITheme.TEXT_PRIMARY)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(n)
	row.add_child(value_label)
	return row

func _sens_row(label_text: String, initial: float, on_set: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var name_label := _label(label_text, BattleUITheme.font_regular(), 15, BattleUITheme.TEXT_PRIMARY)
	name_label.custom_minimum_size = Vector2(190, 0)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = SettingsModel.SENS_MIN
	slider.max_value = SettingsModel.SENS_MAX
	slider.step = 0.05
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(170, 24)
	_style_slider(slider)
	row.add_child(slider)
	var val := _label("%.2f×" % initial, BattleUITheme.font_bold(), 14, VALUE_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	val.custom_minimum_size = Vector2(56, 0)
	row.add_child(val)
	slider.value_changed.connect(func(v: float):
		on_set.call(v)
		val.text = "%.2f×" % v
		GameManager.save_settings())
	return row

# Keyboard-only remap row: label + keyboard binding + reset.
func _kb_remap_row(action: String, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_label := _label(label_text, BattleUITheme.font_regular(), 14, BattleUITheme.TEXT_PRIMARY)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var kb := BattleUITheme.make_button(InputMapConfig.describe_keyboard(action), 11)
	kb.custom_minimum_size = Vector2(150, 30)
	kb.pressed.connect(func(): _start_listening(action, true))
	_kb_buttons[action] = kb
	row.add_child(kb)
	var rst := BattleUITheme.make_button("↺", 12)
	rst.custom_minimum_size = Vector2(32, 30)
	rst.pressed.connect(func(): _reset_kb_one(action))
	row.add_child(rst)
	return row

# Controller-only remap row: label + controller binding + reset.
func _pad_remap_row(action: String, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_label := _label(label_text, BattleUITheme.font_regular(), 14, BattleUITheme.TEXT_PRIMARY)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var pad := BattleUITheme.make_button(InputMapConfig.describe_controller(action), 11)
	pad.custom_minimum_size = Vector2(150, 30)
	pad.pressed.connect(func(): _start_listening(action, false))
	_pad_buttons[action] = pad
	row.add_child(pad)
	var rst := BattleUITheme.make_button("↺", 12)
	rst.custom_minimum_size = Vector2(32, 30)
	rst.pressed.connect(func(): _reset_pad_one(action))
	row.add_child(rst)
	return row

# --- Rebind listening ---------------------------------------------------------
func _start_listening(action: String, keyboard: bool) -> void:
	_refresh_controls_labels()
	_listening = true
	_listen_action = action
	_listen_keyboard = keyboard
	# Suspend the focus guard so the next button press is captured as a binding
	# rather than navigating focus.
	GameManager.unregister_focus_scope(self)
	var btn: Button = (_kb_buttons.get(action) if keyboard else _pad_buttons.get(action))
	if btn != null:
		btn.text = "Press…"

func _capture_rebind(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_stop_listening()
		get_viewport().set_input_as_handled()
		return
	if _listen_keyboard:
		if event is InputEventKey and event.pressed and not event.echo:
			var ek := InputEventKey.new()
			ek.physical_keycode = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			InputMapConfig.rebind_keyboard(_listen_action, ek)
			_finish_rebind()
	else:
		if event is InputEventJoypadButton and event.pressed:
			var eb := InputEventJoypadButton.new()
			eb.button_index = event.button_index
			InputMapConfig.rebind_controller(_listen_action, eb)
			_finish_rebind()
		elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.6:
			var em := InputEventJoypadMotion.new()
			em.axis = event.axis
			em.axis_value = 1.0 if event.axis_value >= 0.0 else -1.0
			InputMapConfig.rebind_controller(_listen_action, em)
			_finish_rebind()

func _finish_rebind() -> void:
	GameManager.save_input_config()
	_stop_listening()
	get_viewport().set_input_as_handled()

func _stop_listening() -> void:
	_listening = false
	_listen_action = ""
	_refresh_controls_labels()
	# Resume the focus guard.
	GameManager.register_focus_scope(self)

func _refresh_controls_labels() -> void:
	for action in _kb_buttons:
		var b: Button = _kb_buttons[action]
		if is_instance_valid(b):
			b.text = InputMapConfig.describe_keyboard(action)
	for action in _pad_buttons:
		var b2: Button = _pad_buttons[action]
		if is_instance_valid(b2):
			b2.text = InputMapConfig.describe_controller(action)

func _reset_kb_one(action: String) -> void:
	InputMapConfig.reset_keyboard_action(action)
	GameManager.save_input_config()
	_refresh_controls_labels()

func _reset_pad_one(action: String) -> void:
	InputMapConfig.reset_controller_action(action)
	GameManager.save_input_config()
	_refresh_controls_labels()

func _on_reset_keyboard() -> void:
	InputMapConfig.reset_all_keyboard()
	GameManager.save_input_config()
	_refresh_controls_labels()

func _on_reset_controller() -> void:
	InputMapConfig.reset_all_controller()
	GameManager.save_input_config()
	_refresh_controls_labels()

# --- Themed primitives --------------------------------------------------------
func _make_option(options: PackedStringArray, selected: int, on_select: Callable) -> OptionButton:
	var ob := OptionButton.new()
	for i in options.size():
		ob.add_item(options[i], i)
	ob.selected = clampi(selected, 0, maxi(0, options.size() - 1))
	ob.custom_minimum_size = Vector2(210, 34)
	BattleUITheme.style_button(ob, 13)
	_style_popup(ob.get_popup())
	ob.item_selected.connect(func(idx: int): on_select.call(idx))
	return ob

func _style_popup(popup: PopupMenu) -> void:
	popup.add_theme_stylebox_override("panel", BattleUITheme.panel_style(BattleUITheme.PANEL_BORDER, BattleUITheme.PANEL_BG, 1, 6))
	var hover := StyleBoxFlat.new()
	hover.bg_color = BattleUITheme.BUTTON_HOVER_BG
	hover.set_corner_radius_all(4)
	popup.add_theme_stylebox_override("hover", hover)
	var f := BattleUITheme.font_regular()
	if f: popup.add_theme_font_override("font", f)
	popup.add_theme_font_size_override("font_size", 13)
	popup.add_theme_color_override("font_color", BattleUITheme.TEXT_PRIMARY)
	popup.add_theme_color_override("font_hover_color", ACCENT)
	popup.add_theme_color_override("font_separator_color", SECTION_COLOR)

func _style_scrollbar(sb: ScrollBar) -> void:
	if sb == null:
		return
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.06, 0.04, 0.10, 0.55)
	track.set_corner_radius_all(4)
	track.content_margin_left = 4
	track.content_margin_right = 4
	sb.add_theme_stylebox_override("scroll", track)
	var grab := StyleBoxFlat.new()
	grab.bg_color = BattleUITheme.PANEL_BORDER
	grab.set_corner_radius_all(4)
	sb.add_theme_stylebox_override("grabber", grab)
	var grab_hi := grab.duplicate()
	grab_hi.bg_color = ACCENT
	sb.add_theme_stylebox_override("grabber_highlight", grab_hi)
	sb.add_theme_stylebox_override("grabber_pressed", grab_hi)

func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = BattleUITheme.SUBPANEL_BG
	track.border_color = BattleUITheme.BUTTON_BORDER
	track.set_border_width_all(1)
	track.set_corner_radius_all(4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	s.add_theme_stylebox_override("slider", track)
	var area := StyleBoxFlat.new()
	area.bg_color = ACCENT
	area.set_corner_radius_all(4)
	s.add_theme_stylebox_override("grabber_area", area)
	s.add_theme_stylebox_override("grabber_area_highlight", area)

func _resolution_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for r in SettingsModel.RESOLUTIONS:
		out.append("%d × %d" % [r.x, r.y])
	return out

func _fps_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for f in SettingsModel.FPS_OPTIONS:
		out.append("Uncapped" if f == 0 else str(f))
	return out

func _fps_index(cap: int) -> int:
	var idx := SettingsModel.FPS_OPTIONS.find(cap)
	return idx if idx >= 0 else 0

func _divider() -> Control:
	var line := ColorRect.new()
	line.color = Color(0.40, 0.30, 0.55, 0.6)
	line.custom_minimum_size = Vector2(0, 1)
	return line

func _label(text: String, font: Font, size: int, color: Color, h_align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = h_align
	if font: l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _pct(linear: float) -> String:
	return "%d%%" % roundi(linear * 100.0)
