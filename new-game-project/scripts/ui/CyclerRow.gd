class_name CyclerRow
extends HBoxContainer

## A settings row that steps through a short list of choices: the name, then
## `◀  [mark] value  ▶`. The mouse (or the stick cursor) clicks the arrows; with the row
## focused, left / right on the keyboard or d-pad steps it, and a held left / right keeps
## stepping (GameManager's nav repeat). It wraps both ways.
##
## The row is ONE focus stop: the arrows are click-only (tagged no-focus, so the focus
## guard never makes them reachable) and ui_left / ui_right are consumed here so focus
## never slides sideways; ui_up / ui_down still move between rows.
##
## The optional mark before the value is an icon (set_icon) or a colour dot
## (set_swatch). The row doesn't know what the choices mean: it reports the new index
## through `changed` and the screen decides what to do with it.

signal changed(index: int)

## The arrows, as in the approved mockup's gold.
const ARROW_COLOR := Color(1.0, 0.82, 0.48)
## The 1 px ring that lets a dark swatch show on the dark panel.
const RING_COLOR := Color("D9D9E6")
## The icon / dot slot before the value; an icon is fitted inside it.
const MARK_SIZE := Vector2(20, 26)
const DOT_SIZE := 14
const ARROW_SIZE := Vector2(26, 30)
## Arrows + value box + the gaps between them: the same width for every row, so the
## steppers of different rows line up.
const STEPPER_WIDTH := 240
const GAP := 14
const PAD := 8
const ROW_HEIGHT := 42

var index: int = 0
var labels := PackedStringArray()

var _name_label: Label = null
var _value_label: Label = null
var _icon: TextureRect = null
var _dot: Panel = null

## Names the row and gives it its choices. `name_width` (0 = as wide as the text) lets
## rows that sit together share a column.
func setup(label_text: String, choices: PackedStringArray, start: int, name_width := 0) -> void:
	if _name_label == null:
		_build()
	labels = choices
	index = clampi(start, 0, maxi(0, choices.size() - 1))
	_name_label.text = label_text
	_name_label.custom_minimum_size.x = name_width
	_refresh()

## Shows `tex` before the value, fitted into the slot (null hides it).
func set_icon(tex: Texture2D) -> void:
	_icon.texture = tex
	_icon.visible = tex != null
	_dot.visible = false

## Shows a colour dot before the value; `ring` outlines it for colours too dark to show
## on the panel.
func set_swatch(c: Color, ring := false) -> void:
	var style := _dot.get_theme_stylebox("panel") as StyleBoxFlat
	style.bg_color = c
	style.set_border_width_all(1 if ring else 0)
	_dot.visible = true
	_icon.visible = false

## One step round the list (-1 back, +1 forward), wrapping, then `changed`.
func step(dir: int) -> void:
	if labels.is_empty():
		return
	index = posmod(index + dir, labels.size())
	_refresh()
	changed.emit(index)

func _refresh() -> void:
	_value_label.text = labels[index] if index < labels.size() else ""

func _gui_input(event: InputEvent) -> void:
	var action := ""
	var dir := 0
	if event.is_action_pressed("ui_left", true):
		action = "ui_left"
		dir = -1
	elif event.is_action_pressed("ui_right", true):
		action = "ui_right"
		dir = 1
	if dir == 0:
		return
	# Left / right belong to the row while it has focus, or the focus guard would
	# slide sideways (or wrap round) instead. A key's own repeat is swallowed too: a
	# held direction repeats through GameManager's nav repeat, the same for every device.
	accept_event()
	if event.is_echo():
		return
	# A stick push is a stream of motion events, every one past the deadzone: only the
	# one that makes the action newly pressed steps, as in Godot's own focus navigation.
	if event is InputEventJoypadMotion and not _newly_pressed(action):
		return
	step(dir)

## True when `action` became pressed this frame. A method so a test can stand in for
## Input's frame bookkeeping: in a synchronous test run every test shares one frame, so
## an earlier press leaves an action "just pressed" for the rest of the run.
func _newly_pressed(action: String) -> bool:
	return Input.is_action_just_pressed(action)

func _draw() -> void:
	if has_focus():
		draw_style_box(BattleUITheme.focus_style(), Rect2(Vector2.ZERO, size))

func _build() -> void:
	focus_mode = Control.FOCUS_ALL
	alignment = BoxContainer.ALIGNMENT_CENTER
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER   # the focus ring hugs the row, like a button's
	add_theme_constant_override("separation", 0)
	custom_minimum_size = Vector2(0, ROW_HEIGHT)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

	add_child(_spacer(PAD))
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_override("font", BattleUITheme.font_regular())
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.add_theme_color_override("font_color", BattleUITheme.TEXT_PRIMARY)
	add_child(_name_label)
	add_child(_spacer(GAP))

	var stepper := HBoxContainer.new()
	stepper.add_theme_constant_override("separation", 3)
	stepper.custom_minimum_size = Vector2(STEPPER_WIDTH, 0)
	stepper.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(stepper)
	stepper.add_child(_arrow("◀", -1))
	stepper.add_child(_value_box())
	stepper.add_child(_arrow("▶", 1))
	add_child(_spacer(PAD))

func _spacer(width: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(width, 0)
	return s

# A themed button that steps the row. Click-only: tagged so the focus guard never
# makes it a focus stop.
func _arrow(glyph: String, dir: int) -> Button:
	var b := BattleUITheme.make_button(glyph, 12)
	b.custom_minimum_size = ARROW_SIZE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_color_override("font_color", ARROW_COLOR)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := b.get_theme_stylebox(state) as StyleBoxFlat
		sb.content_margin_left = 4
		sb.content_margin_right = 4
	b.focus_mode = Control.FOCUS_NONE
	BattleUITheme.mark_no_focus(b)
	b.pressed.connect(func(): step(dir))
	return b

# The bordered middle: [icon or dot] value.
func _value_box() -> PanelContainer:
	var box := PanelContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := BattleUITheme.panel_style(BattleUITheme.BUTTON_BORDER, BattleUITheme.BUTTON_BG, 1, 6)
	style.shadow_size = 0
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	box.add_theme_stylebox_override("panel", style)
	var inner := HBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 6)
	box.add_child(inner)

	_icon = TextureRect.new()
	_icon.custom_minimum_size = MARK_SIZE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# An icon is usually drawn much smaller than its picture (the cursor shape's is 4x the
	# art): mipmaps, where the texture has them, keep it clean instead of jagged.
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.visible = false
	inner.add_child(_icon)

	_dot = Panel.new()
	_dot.custom_minimum_size = Vector2(DOT_SIZE, DOT_SIZE)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot_style := StyleBoxFlat.new()
	dot_style.set_corner_radius_all(int(DOT_SIZE * 0.5))
	dot_style.border_color = RING_COLOR
	_dot.add_theme_stylebox_override("panel", dot_style)
	_dot.visible = false
	inner.add_child(_dot)

	_value_label = Label.new()
	_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value_label.add_theme_font_override("font", BattleUITheme.font_bold())
	_value_label.add_theme_font_size_override("font_size", 13)
	_value_label.add_theme_color_override("font_color", BattleUITheme.TEXT_PRIMARY)
	inner.add_child(_value_label)
	return box
