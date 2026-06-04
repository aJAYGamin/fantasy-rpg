extends Control

## PauseMenu — opened with Esc from the overworld.
## Save + Quit + Stats + Items + Equipment + Settings are functional.

signal save_requested
signal quit_requested

# Reuses the SaveSlotMenu palette for visual consistency.
const ACCENT_COLOR := Color(0.85, 0.7, 1.0)
const PANEL_BG_COLOR := Color(0.10, 0.08, 0.16, 0.96)
const PANEL_BORDER_COLOR := Color(0.4, 0.3, 0.55, 1.0)
const TEXT_PRIMARY := Color(0.88, 0.82, 1.0)
const TEXT_SECONDARY := Color(0.7, 0.65, 0.85)
const TEXT_DANGER := Color(0.95, 0.6, 0.55)

var _cinzel: Font
var _cinzel_bold: Font
var _toast: Label = null
# Wrapper holding the main pause menu (dim + panel). Hidden while a confirm
# prompt / sub-menu is shown so they don't visually stack, then restored.
var _main_content: Control = null
# Active confirm prompt, if any. Lets Esc back out of the prompt to the pause
# menu rather than closing the whole pause menu.
var _confirm_modal: Control = null
# Active full sub-screen (e.g. the Stats screen), shown in place of the main
# menu. Like the confirm prompt, Esc backs out of it to the pause menu instead
# of closing the whole pause menu.
var _sub_view: Control = null

func _ready() -> void:
	_cinzel = load("res://fonts/Cinzel-Regular.ttf")
	_cinzel_bold = load("res://fonts/Cinzel-Bold.ttf")
	# Process while paused so the menu can receive input and animations run.
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()

func open() -> void:
	_rebuild()
	show()
	get_tree().paused = true
	# The central focus guard (GameManager, runs while paused) keeps controller
	# focus on the main list. Sub-views / confirm prompts register their own scope
	# on top, so the guard always tracks the visible layer.
	GameManager.register_focus_scope(_main_content)

func _focus_sub_view() -> void:
	# Sub-views (Stats/Items/Equipment/Settings) register their own focus scope.
	pass

func close() -> void:
	get_tree().paused = false
	hide()
	GameManager.unregister_focus_scope(_main_content)
	if _toast and is_instance_valid(_toast):
		_toast.queue_free()
		_toast = null
	if _confirm_modal and is_instance_valid(_confirm_modal):
		GameManager.unregister_focus_scope(_confirm_modal)
		_confirm_modal.queue_free()
	_confirm_modal = null
	if _sub_view and is_instance_valid(_sub_view):
		_sub_view.queue_free()
	_sub_view = null

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		# Esc backs out one layer at a time — a confirm prompt or a sub-screen
		# returns to the pause menu; only the bare pause menu closes outright.
		if _confirm_modal != null and is_instance_valid(_confirm_modal):
			_dismiss_confirm()
		elif _sub_view != null and is_instance_valid(_sub_view):
			_dismiss_sub_view()
		else:
			close()
		get_viewport().set_input_as_handled()

# Closes the active confirm prompt and restores the main pause menu.
func _dismiss_confirm() -> void:
	if _confirm_modal != null and is_instance_valid(_confirm_modal):
		GameManager.unregister_focus_scope(_confirm_modal)
		_confirm_modal.queue_free()
	_confirm_modal = null
	# Showing _main_content again lets the focus guard re-grab it automatically.
	if _main_content and is_instance_valid(_main_content):
		_main_content.show()

# Closes the active sub-screen and restores the main pause menu.
func _dismiss_sub_view() -> void:
	if _sub_view != null and is_instance_valid(_sub_view):
		_sub_view.queue_free()
	_sub_view = null
	if _main_content and is_instance_valid(_main_content):
		_main_content.show()

# Opens the per-hero Stats screen as a sub-view (replaces the main menu, doesn't
# stack). Back button / Esc return here via _dismiss_sub_view.
func _open_stats() -> void:
	if GameManager.party.is_empty():
		show_toast("No party yet.", true)
		return
	if _main_content and is_instance_valid(_main_content):
		_main_content.hide()
	var screen := StatsScreen.new()
	_sub_view = screen
	screen.back_requested.connect(_dismiss_sub_view)
	add_child(screen)
	screen.setup(GameManager.party)
	call_deferred("_focus_sub_view")

# Opens the party Items screen as a sub-view (replace-don't-stack, like Stats).
func _open_items() -> void:
	if GameManager.party.is_empty():
		show_toast("No party yet.", true)
		return
	if _main_content and is_instance_valid(_main_content):
		_main_content.hide()
	var screen := ItemsScreen.new()
	_sub_view = screen
	screen.back_requested.connect(_dismiss_sub_view)
	add_child(screen)
	screen.setup(GameManager.party)
	call_deferred("_focus_sub_view")

# Opens the per-hero Equipment screen as a sub-view (replace-don't-stack).
func _open_equipment() -> void:
	if GameManager.party.is_empty():
		show_toast("No party yet.", true)
		return
	if _main_content and is_instance_valid(_main_content):
		_main_content.hide()
	var screen := EquipmentScreen.new()
	_sub_view = screen
	screen.back_requested.connect(_dismiss_sub_view)
	add_child(screen)
	screen.setup(GameManager.party)
	call_deferred("_focus_sub_view")

# Opens the Settings screen as a sub-view (replace-don't-stack). PauseMenu owns
# Esc here, so SettingsScreen is opened non-standalone.
func _open_settings() -> void:
	if _main_content and is_instance_valid(_main_content):
		_main_content.hide()
	var screen := SettingsScreen.new()
	_sub_view = screen
	screen.back_requested.connect(_dismiss_sub_view)
	add_child(screen)
	screen.setup(false)

# --- Build ---
func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_toast = null
	_confirm_modal = null
	_sub_view = null

	# Wrapper for the main pause menu so it can be hidden as a unit while a
	# confirm prompt or (later) sub-menu is shown on top.
	_main_content = Control.new()
	_main_content.name = "MainContent"
	_main_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_main_content)

	# Full-rect dim
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_main_content.add_child(dim)

	# Centered panel
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_content.add_child(center)

	var panel = _styled_panel(360, 0)
	center.add_child(panel)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(v)

	var title = _label("— Paused —", _cinzel_bold, 20, ACCENT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(title)

	v.add_child(_menu_button("Resume", _on_resume))
	v.add_child(_menu_button("Save Game", _on_save))
	v.add_child(_menu_button("Stats", _open_stats))
	v.add_child(_menu_button("Items", _open_items))
	v.add_child(_menu_button("Equipment", _open_equipment))
	v.add_child(_menu_button("Settings", _open_settings))
	v.add_child(_menu_button("Quit to Main Menu", _on_quit, true))

# --- Actions ---
func _on_resume() -> void:
	close()

func _on_save() -> void:
	save_requested.emit()

func _on_quit() -> void:
	_show_confirm(
		"Quit to Main Menu?",
		"Any unsaved progress since your last save will be lost.",
		"Quit", true,
		func(): quit_requested.emit()
	)

# Brief floating message at the top of the pause panel. Called by OverworldScene
# after a save attempt to report success/failure.
func show_toast(text: String, is_error: bool = false) -> void:
	if _toast and is_instance_valid(_toast):
		_toast.queue_free()
	_toast = _label(text, _cinzel_bold, 16, TEXT_DANGER if is_error else ACCENT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast.offset_top = 60
	_toast.modulate.a = 0.0
	add_child(_toast)
	var t = create_tween()
	t.tween_property(_toast, "modulate:a", 1.0, 0.2)
	t.tween_interval(1.6)
	t.tween_property(_toast, "modulate:a", 0.0, 0.4)
	var toast_ref := _toast
	t.tween_callback(func():
		if is_instance_valid(toast_ref):
			toast_ref.queue_free())

# --- Themed primitives (mirrors SaveSlotMenu styling) ---
func _label(text: String, font: Font, size: int, color: Color, h_align: int) -> Label:
	var l = Label.new()
	l.text = text
	l.horizontal_alignment = h_align
	if font: l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _styled_panel(min_w: float, min_h: float) -> PanelContainer:
	var panel = PanelContainer.new()
	if min_w > 0 or min_h > 0:
		panel.custom_minimum_size = Vector2(min_w, min_h)
	var style = StyleBoxFlat.new()
	style.bg_color = PANEL_BG_COLOR
	style.border_color = PANEL_BORDER_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _styled_button(text: String, danger: bool) -> Button:
	var b = Button.new()
	b.text = text
	if _cinzel: b.add_theme_font_override("font", _cinzel)
	b.add_theme_font_size_override("font_size", 13)
	var label_color: Color = TEXT_DANGER if danger else TEXT_PRIMARY
	b.add_theme_color_override("font_color", label_color)
	b.add_theme_color_override("font_hover_color", ACCENT_COLOR)
	b.add_theme_color_override("font_pressed_color", ACCENT_COLOR)
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.06, 0.13, 0.92)
	normal.border_color = PANEL_BORDER_COLOR
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	b.add_theme_stylebox_override("normal", normal)
	var hover = normal.duplicate()
	hover.bg_color = Color(0.18, 0.10, 0.26, 0.96)
	hover.border_color = ACCENT_COLOR
	b.add_theme_stylebox_override("hover", hover)
	var pressed = normal.duplicate()
	pressed.bg_color = Color(0.22, 0.14, 0.32, 0.98)
	pressed.border_color = ACCENT_COLOR
	b.add_theme_stylebox_override("pressed", pressed)
	# Bright focus ring for keyboard/controller navigation.
	var focus = StyleBoxFlat.new()
	focus.bg_color = Color(0.85, 0.7, 1.0, 0.12)
	focus.border_color = Color(0.95, 0.85, 1.0)
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(4)
	b.add_theme_stylebox_override("focus", focus)
	return b

func _menu_button(text: String, on_pressed: Callable, danger: bool = false) -> Button:
	var b = _styled_button(text, danger)
	b.custom_minimum_size = Vector2(280, 36)
	b.pressed.connect(on_pressed)
	return b

# --- Confirm modal (same pattern as SaveSlotMenu) ---
func _show_confirm(title_text: String, message: String, confirm_text: String, danger: bool, on_confirm: Callable) -> void:
	# Hide the main pause menu so the prompt replaces it instead of stacking.
	if _main_content and is_instance_valid(_main_content):
		_main_content.hide()

	var modal = Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.process_mode = Node.PROCESS_MODE_ALWAYS
	_confirm_modal = modal

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_child(dim)

	var center_wrap = CenterContainer.new()
	center_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center_wrap)

	var panel = _styled_panel(380, 0)
	center_wrap.add_child(panel)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(_label(title_text, _cinzel_bold, 16, ACCENT_COLOR, HORIZONTAL_ALIGNMENT_CENTER))
	var msg = _label(message, _cinzel, 12, TEXT_PRIMARY, HORIZONTAL_ALIGNMENT_CENTER)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(340, 0)
	v.add_child(msg)

	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(actions)

	var cancel = _styled_button("Cancel", false)
	cancel.custom_minimum_size = Vector2(120, 30)
	# Cancel: dismiss the prompt and bring the main pause menu back.
	cancel.pressed.connect(_dismiss_confirm)
	actions.add_child(cancel)

	var ok = _styled_button(confirm_text, danger)
	ok.custom_minimum_size = Vector2(160, 30)
	# Confirm: dismiss the prompt and fire the action (e.g. quit). No need to
	# restore the main content since we're leaving the scene.
	ok.pressed.connect(func():
		_confirm_modal = null
		GameManager.unregister_focus_scope(modal)
		modal.queue_free()
		on_confirm.call())
	actions.add_child(ok)

	add_child(modal)
	# Register on top so the focus guard tracks the prompt (Cancel is added before
	# OK, so it gets first focus). Mouse mode stays click-only.
	GameManager.register_focus_scope(modal)
