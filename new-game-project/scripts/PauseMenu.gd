extends Control

## PauseMenu — opened with Esc from the overworld.
## Phase S3: Save + Quit are functional. Stats/Items/Equipment/Settings are
## stubs that show a "Coming soon" toast until their respective phases land.

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

func close() -> void:
	get_tree().paused = false
	hide()
	if _toast and is_instance_valid(_toast):
		_toast.queue_free()
		_toast = null

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# --- Build ---
func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_toast = null

	# Full-rect dim
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# Centered panel
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

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
	v.add_child(_menu_button("Stats", func(): show_toast("Coming soon")))
	v.add_child(_menu_button("Items", func(): show_toast("Coming soon")))
	v.add_child(_menu_button("Equipment", func(): show_toast("Coming soon")))
	v.add_child(_menu_button("Settings", func(): show_toast("Coming soon")))
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
	return b

func _menu_button(text: String, on_pressed: Callable, danger: bool = false) -> Button:
	var b = _styled_button(text, danger)
	b.custom_minimum_size = Vector2(280, 36)
	b.pressed.connect(on_pressed)
	return b

# --- Confirm modal (same pattern as SaveSlotMenu) ---
func _show_confirm(title_text: String, message: String, confirm_text: String, danger: bool, on_confirm: Callable) -> void:
	var modal = Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.process_mode = Node.PROCESS_MODE_ALWAYS

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
	cancel.pressed.connect(func(): modal.queue_free())
	actions.add_child(cancel)

	var ok = _styled_button(confirm_text, danger)
	ok.custom_minimum_size = Vector2(160, 30)
	ok.pressed.connect(func():
		modal.queue_free()
		on_confirm.call())
	actions.add_child(ok)

	add_child(modal)
