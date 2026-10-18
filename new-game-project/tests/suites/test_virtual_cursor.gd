extends TestSuite

## The virtual cursor (VirtualCursor): the hook that re-delivers every mouse event at
## the drawn cursor's position, passes keyboard and controller input through
## untouched, and draws the themed cursor (over an open dropdown list too), glowing
## over anything clickable.
##
## Headless can't install the hook, so these call route_os_event exactly as the OS
## would. Each test's controls sit on a high CanvasLayer under GameManager (the root
## is busy while the runner sets up) over a full-screen backstop: screens that
## earlier suites queue_free()d stay in the tree until the frame ends, and no click
## here may land on one of them.

func suite_name() -> String:
	return "VirtualCursor"

## Reads input in _input, the way LevelUpScreen and DialogueBox read clicks.
class InputReader extends Node:
	var presses := 0
	var releases := 0
	var cancels := 0
	var last: InputEvent = null
	var last_motion: InputEventMouseMotion = null
	var last_motion_mask := -1
	## VirtualCursor.pad_click as each left press and release arrived.
	var pad_on_press: Array = []
	var pad_on_release: Array = []

	func _input(ev: InputEvent) -> void:
		last = ev
		if ev is InputEventMouseButton:
			if ev.pressed:
				presses += 1
			else:
				releases += 1
			if ev.button_index == MOUSE_BUTTON_LEFT:
				(pad_on_press if ev.pressed else pad_on_release).append(GameManager.virtual_cursor.pad_click)
		elif ev is InputEventMouseMotion:
			last_motion = ev
			last_motion_mask = ev.button_mask
		if ev.is_action_pressed("ui_cancel"):
			cancels += 1
			get_viewport().set_input_as_handled()   # a menu backing out consumes it

# --- Setup ---------------------------------------------------------------------

var _layer: CanvasLayer
var _saved := {}

func _vc() -> VirtualCursor:
	return GameManager.virtual_cursor

func _window_scale() -> Vector2:
	return GameManager.get_tree().root.get_final_transform().get_scale()

## Snapshots everything a test may change and returns a fresh top layer for its
## controls, with the backstop at the bottom.
func _begin() -> CanvasLayer:
	var s := GameManager.settings
	_saved = {
		"pointer": _vc().pointer_pos,
		"shown": _vc().shown,
		"sensitivity": s.mouse_sensitivity,
		"shape": s.cursor_shape,
		"colour": s.cursor_colour,
		"controller": GameManager._controller_mode,
		"keyboard": GameManager._keyboard_nav,
		"kb_ms": GameManager._last_kb_ms,
		"mouse_ms": GameManager._last_mouse_ms,
		"stick": s.stick_sensitivity_right,
		"passthrough": GameManager.raw_input_passthrough,
		"cursor_click": InputMap.action_get_events("cursor_click"),
		"window_mode": s.window_mode,
		"hold": _vc().hold,
		"app_focused": _vc()._app_focused,
		"window_focused": _vc()._window_focused,
	}
	s.mouse_sensitivity = 1.0   # the moves below assume 1.00x
	s.stick_sensitivity_right = 1.0   # and the stick's speeds assume 1.00x too
	# Nothing lets go at an edge unless a test says so. Set directly: apply_display would
	# change the real window.
	s.window_mode = SettingsModel.WindowMode.FULLSCREEN
	_vc().hold = CursorHold.new()   # held, with no push counted
	_vc()._app_focused = true
	_vc()._window_focused = true
	_vc()._swallow_release = false
	GameManager.raw_input_passthrough = false
	_bind_cursor_click(JOY_BUTTON_RIGHT_STICK)   # the default, whatever the player has set
	_layer = CanvasLayer.new()
	_layer.layer = 150
	GameManager.add_child(_layer)
	var backstop := Control.new()
	backstop.size = GameManager.get_tree().root.get_visible_rect().size
	_layer.add_child(backstop)
	return _layer

func _end() -> void:
	_layer.free()
	var s := GameManager.settings
	s.mouse_sensitivity = _saved["sensitivity"]
	s.stick_sensitivity_right = _saved["stick"]
	GameManager.raw_input_passthrough = _saved["passthrough"]
	InputMap.action_erase_events("cursor_click")
	for ev: InputEvent in _saved["cursor_click"]:
		InputMap.action_add_event("cursor_click", ev)
	_vc()._click_down = false
	_vc()._click_held = false
	_vc()._buttons = 0
	s.window_mode = _saved["window_mode"]
	_vc().hold = _saved["hold"]
	_vc()._app_focused = _saved["app_focused"]
	_vc()._window_focused = _saved["window_focused"]
	_vc()._swallow_release = false
	s.cursor_shape = _saved["shape"]
	s.cursor_colour = _saved["colour"]
	_vc().refresh_style()
	_vc().pointer_pos = _saved["pointer"]
	_vc().shown = _saved["shown"]
	_vc().update_glow()   # the test's controls are gone; don't leave the glow lit
	GameManager._apply_input_mode(_saved["controller"], _saved["keyboard"])
	GameManager._last_kb_ms = _saved["kb_ms"]
	GameManager._last_mouse_ms = _saved["mouse_ms"]

# --- Input, as the OS would send it ----------------------------------------------

## A mouse move that takes the cursor to `target` at 1.00x. Like the OS, it says
## nothing useful about where the mouse is: a held mouse reports a fixed spot.
func _motion_to(target: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = (target - _vc().pointer_pos) * _window_scale()
	ev.velocity = ev.relative * 60.0   # a real move carries the mouse's speed
	ev.position = Vector2(576, 324)
	_vc().route_os_event(ev)

## A mouse move of `step` base pixels at 1.00x.
func _push(step: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = step * _window_scale()
	ev.velocity = ev.relative * 60.0
	ev.position = Vector2(576, 324)
	_vc().route_os_event(ev)

## A left press or release where the visible system pointer is, at `spot` in base pixels:
## the OS reports it in window pixels.
func _left_at(spot: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = GameManager.get_tree().root.get_final_transform() * spot
	_vc().route_os_event(ev)

func _button(index: int, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = index
	ev.pressed = pressed
	ev.position = Vector2(576, 324)
	_vc().route_os_event(ev)

func _click() -> void:
	_button(MOUSE_BUTTON_LEFT, true)
	_button(MOUSE_BUTTON_LEFT, false)

func _action(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	_vc().route_os_event(ev)

func _key(keycode: Key, pressed: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = pressed
	_vc().route_os_event(ev)
	return ev

func _pad_button(index: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = index
	ev.pressed = pressed
	_vc().route_os_event(ev)
	return ev

func _pad_motion(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	_vc().route_os_event(ev)
	return ev

## A frame lays containers out on a deferred call and none runs inside a test, so sort
## them here, top-down, the way the engine would.
func _lay_out(node: Node) -> void:
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child in node.get_children():
		_lay_out(child)

## Makes `button` the whole of Cursor Click's binding.
func _bind_cursor_click(button: JoyButton) -> void:
	InputMap.action_erase_events("cursor_click")
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event("cursor_click", ev)

## Makes a pull of `axis` the whole of Cursor Click's binding.
func _bind_cursor_click_axis(axis: JoyAxis) -> void:
	InputMap.action_erase_events("cursor_click")
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = 1.0
	InputMap.action_add_event("cursor_click", ev)

## Presses and lets go of the right stick, which is Cursor Click by default.
func _stick_click() -> void:
	_pad_button(JOY_BUTTON_RIGHT_STICK, true)
	_pad_button(JOY_BUTTON_RIGHT_STICK, false)

## Holds the right stick at `axis` for `seconds`, one 60 fps frame at a time (the cursor
## counts no frame longer than 1/30 s, so a long delta in one call wouldn't be the whole time).
func _tilt(axis: Vector2, seconds: float) -> void:
	for i in roundi(seconds * 60.0):
		_vc().step_stick(axis, 1.0 / 60.0)

# --- Controls ------------------------------------------------------------------

func _make_button(parent: Node, rect: Rect2) -> Button:
	var b := Button.new()
	b.text = "Test"
	b.position = rect.position
	b.size = rect.size
	parent.add_child(b)
	return b

## A ScrollContainer holding 20 rows, laid out now (no frame runs inside a test, and
## the scrollbar only learns its range when the container sorts its children).
func _make_list(parent: Node, rect: Rect2) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.position = rect.position
	scroll.size = rect.size
	var rows := VBoxContainer.new()
	for i in 20:
		var row := Label.new()
		row.text = "Row %d" % (i + 1)
		row.custom_minimum_size = Vector2(0, 30)
		rows.add_child(row)
	scroll.add_child(rows)
	parent.add_child(scroll)
	scroll.notification(Container.NOTIFICATION_SORT_CHILDREN)
	return scroll

## The cursor's copy inside an open popup, or null.
func _mirror_in(popup: Window) -> Sprite2D:
	for child in popup.get_children(true):
		if child is CanvasLayer and (child as CanvasLayer).layer == VirtualCursor.LAYER:
			for grandchild in child.get_children():
				if grandchild is Sprite2D:
					return grandchild
	return null

# --- Tests ---------------------------------------------------------------------

func test_a_click_lands_where_the_cursor_is_not_where_the_mouse_reports() -> void:
	var layer := _begin()
	var b := _make_button(layer, Rect2(100, 100, 120, 40))
	var presses := [0]
	b.pressed.connect(func() -> void: presses[0] += 1)
	_motion_to(Vector2(160, 120))
	assert_true(b.get_global_rect().has_point(_vc().pointer_pos), "the cursor is over the button")
	assert_false(b.get_global_rect().has_point(Vector2(576, 324)), "the mouse's own report is nowhere near it")
	_click()
	assert_eq(presses[0], 1, "one click at the cursor presses the button once")
	_end()

func test_hover_reaches_controls() -> void:
	var layer := _begin()
	var b := _make_button(layer, Rect2(400, 100, 120, 40))
	var entered := [0]
	b.mouse_entered.connect(func() -> void: entered[0] += 1)
	_motion_to(Vector2(380, 60))
	assert_eq(entered[0], 0, "not over the button yet")
	_motion_to(Vector2(460, 120))
	assert_eq(entered[0], 1, "moving onto a button fires its mouse_entered (the hover sound hangs off this)")
	_end()

func test_the_wheel_scrolls_what_the_cursor_is_over() -> void:
	var layer := _begin()
	var scroll := _make_list(layer, Rect2(600, 100, 200, 200))
	_motion_to(Vector2(700, 200))
	for i in 3:
		_button(MOUSE_BUTTON_WHEEL_DOWN, true)
		_button(MOUSE_BUTTON_WHEEL_DOWN, false)
	assert_true(scroll.scroll_vertical > 0, "three wheel-downs under the cursor scroll the list (at %d)" % scroll.scroll_vertical)
	_end()

func test_a_trackpad_scroll_scrolls_what_the_cursor_is_over() -> void:
	# A Mac trackpad's two-finger scroll arrives as a pan gesture, placed like a click.
	var layer := _begin()
	var scroll := _make_list(layer, Rect2(600, 100, 200, 200))
	_motion_to(Vector2(700, 200))
	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(0, 4)
	pan.position = Vector2(576, 324)
	_vc().route_os_event(pan)
	assert_true(scroll.scroll_vertical > 0, "a two-finger scroll under the cursor scrolls the list (at %d)" % scroll.scroll_vertical)
	_end()

func test_a_trackpad_gesture_counts_as_using_the_mouse() -> void:
	# The menus switch from the focus highlight to the mouse on any mouse input, and a
	# trackpad's pan or pinch is mouse input: the cursor shows with it, so the highlight
	# must not stay up beside it.
	_begin()
	GameManager._last_mouse_ms = -100000
	for gesture: InputEventGesture in [InputEventPanGesture.new(), InputEventMagnifyGesture.new()]:
		for mode in [[false, true], [true, false]]:   # keyboard highlight, then controller highlight
			GameManager._apply_input_mode(mode[0], mode[1])
			_vc().shown = false
			assert_true(GameManager.focus_nav_active(), "starting on the highlight (%s)" % gesture.get_class())
			gesture.position = Vector2(576, 324)
			_vc().route_os_event(gesture)
			assert_true(_vc().shown, "the gesture shows the cursor (%s)" % gesture.get_class())
			assert_false(GameManager.focus_nav_active(), "and the menus go to the mouse (%s)" % gesture.get_class())
	assert_eq(GameManager.mouse_status_text(), "Mouse detected", "and Settings sees a mouse in use")
	_end()

func test_dragging_a_slider_follows_the_cursor() -> void:
	var layer := _begin()
	var slider := HSlider.new()
	slider.position = Vector2(100, 300)
	slider.size = Vector2(300, 24)
	slider.max_value = 100.0
	slider.value = 0.0
	layer.add_child(slider)
	var reader := InputReader.new()
	layer.add_child(reader)
	_motion_to(Vector2(104, 312))
	_button(MOUSE_BUTTON_LEFT, true)
	for i in 4:
		_motion_to(Vector2(104 + 50 * (i + 1), 312))
	assert_eq(reader.last_motion_mask, int(MOUSE_BUTTON_MASK_LEFT), "a move with the button held says the button is held")
	_button(MOUSE_BUTTON_LEFT, false)
	assert_true(slider.value > 0.0, "dragging right moved the slider (to %s)" % slider.value)
	_motion_to(Vector2(320, 340))
	assert_eq(reader.last_motion_mask, 0, "after the release, moves carry no held button")
	_end()

func test_a_dropdown_item_is_chosen_by_clicking_it_and_the_cursor_shows_over_the_list() -> void:
	var layer := _begin()
	var opt := OptionButton.new()
	for item in ["One", "Two", "Three", "Four"]:
		opt.add_item(item)
	opt.position = Vector2(700, 100)
	opt.size = Vector2(160, 31)
	layer.add_child(opt)
	var popup := opt.get_popup()
	_motion_to(Vector2(780, 115))
	_click()
	assert_true(popup.visible, "clicking the dropdown opens its list")
	# The middle of the third of four equal rows.
	_motion_to(Vector2(popup.position) + Vector2(popup.size.x * 0.5, popup.size.y * 2.5 / 4.0))
	assert_eq(popup.get_focused_item(), 2, "the row under the cursor lights up")
	_vc().update_mirrors()
	var mirror := _mirror_in(popup)
	assert_true(mirror != null, "the cursor is drawn inside the open list (dropdowns draw above every layer)")
	if mirror != null:
		var expected := (_vc().pointer_pos - Vector2(popup.position)) / popup.content_scale_factor
		assert_true(mirror.position.is_equal_approx(expected), "the copy sits at the cursor (got %s, expected %s)" % [mirror.position, expected])
		assert_true(mirror.visible, "the copy is showing")
		assert_eq(mirror.texture, _vc().sprite.texture, "the copy wears the cursor's style")
	_click()
	assert_eq(opt.selected, 2, "clicking the third row chooses it")
	assert_false(popup.visible, "and the list closes")
	_end()

func test_a_physical_click_reaches_input_readers_exactly_once() -> void:
	# LevelUpScreen and DialogueBox read clicks in _input: a second copy of one click
	# would skip a level-up spin or a line of dialogue.
	var layer := _begin()
	var reader := InputReader.new()
	layer.add_child(reader)
	_motion_to(Vector2(300, 500))
	_click()
	assert_eq(reader.presses, 1, "one press and release reach _input as one press")
	_end()

func test_keyboard_and_controller_pass_through_unchanged() -> void:
	var layer := _begin()
	var b := _make_button(layer, Rect2(100, 100, 120, 40))
	var presses := [0]
	b.pressed.connect(func() -> void: presses[0] += 1)
	b.grab_focus()
	var reader := InputReader.new()
	layer.add_child(reader)
	_action("ui_accept", true)
	_action("ui_accept", false)
	assert_eq(presses[0], 1, "ui_accept (Enter / controller A) presses the focused button")
	var key := _key(KEY_F11, true)
	assert_true(reader.last == key, "a key reaches _input as the very event the OS sent")
	_key(KEY_F11, false)
	var pad := _pad_button(JOY_BUTTON_X, true)
	assert_true(reader.last == pad, "so does a controller button")
	_pad_button(JOY_BUTTON_X, false)
	_action("ui_cancel", true)
	assert_eq(reader.cancels, 1, "ui_cancel reaches _input readers, so Back still works")
	_action("ui_cancel", false)
	_end()

func test_the_cursor_shows_for_the_mouse_and_hides_for_keys() -> void:
	_begin()
	_vc().shown = false
	_motion_to(Vector2(300, 300))
	assert_true(_vc().shown, "moving the mouse shows the cursor")
	var spot := _vc().pointer_pos
	_key(KEY_F11, true)
	_key(KEY_F11, false)
	assert_false(_vc().shown, "a key press hides it")
	var still := InputEventMouseMotion.new()
	still.position = Vector2(576, 324)
	_vc().route_os_event(still)
	assert_true(_vc().shown, "touching the mouse again shows it")
	assert_eq(_vc().pointer_pos, spot, "where it was, not somewhere new")
	_pad_button(JOY_BUTTON_DPAD_DOWN, true)
	_pad_button(JOY_BUTTON_DPAD_DOWN, false)
	assert_false(_vc().shown, "a controller button hides it too")
	_click()
	assert_true(_vc().shown, "a click shows it")
	var wobble := InputEventJoypadMotion.new()
	wobble.axis = JOY_AXIS_LEFT_X
	wobble.axis_value = 0.1
	_vc().route_os_event(wobble)
	assert_true(_vc().shown, "a resting stick's jitter doesn't hide it")
	var push := InputEventJoypadMotion.new()
	push.axis = JOY_AXIS_LEFT_X
	push.axis_value = 0.9
	_vc().route_os_event(push)
	push.axis_value = 0.0
	_vc().route_os_event(push)
	assert_false(_vc().shown, "pushing the left stick hides it, like the menus switching to the highlight")
	_end()

func test_the_cursor_wears_the_chosen_style_and_points_with_its_tip() -> void:
	_begin()
	GameManager.settings.cursor_shape = "AV"
	GameManager.settings.cursor_colour = "rose"
	_vc().refresh_style()
	var sprite := _vc().sprite
	assert_eq(sprite.texture, CursorArt.texture("AV", "rose"), "the Low-Poly Arrow in Rose")
	assert_eq(sprite.offset, -CursorArt.hotspot("AV") * CursorArt.RENDER_SCALE, "drawn so its tip is the point it stands on")
	assert_false(sprite.centered, "offset from the texture's corner, not its middle")
	assert_eq(sprite.scale, Vector2.ONE / CursorArt.RENDER_SCALE, "one symbol unit is one base pixel")
	var layer := sprite.get_parent() as CanvasLayer
	assert_true(layer != null and layer.layer == VirtualCursor.LAYER, "drawn on the cursor's own layer")
	assert_true(VirtualCursor.LAYER > 128, "above the FPS overlay (layer 128) and everything else")
	_end()

func test_the_cursor_survives_scene_changes_and_pauses() -> void:
	var vc := _vc()
	assert_true(vc != null and vc.is_inside_tree(), "GameManager made the cursor at launch")
	assert_eq(vc.get_parent(), GameManager, "it lives under the autoload, so scene changes leave it alone")
	assert_eq(vc.process_mode, Node.PROCESS_MODE_ALWAYS, "it keeps drawing while the game is paused")

func test_the_hook_is_not_installed_headless() -> void:
	_vc().install()
	assert_false(_vc().installed, "install() leaves the test runner's input alone")
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "and doesn't take the mouse")

# --- The hover glow ----------------------------------------------------------------

## The glow's shader material on the cursor's sprite, or null.
func _glow_material(sprite: Sprite2D) -> ShaderMaterial:
	return sprite.material as ShaderMaterial

func test_what_counts_as_clickable() -> void:
	var b := Button.new()
	assert_true(VirtualCursor.is_clickable(b, Vector2.ZERO), "a button")
	b.disabled = true
	assert_false(VirtualCursor.is_clickable(b, Vector2.ZERO), "not a greyed button")
	var check := CheckBox.new()
	assert_true(VirtualCursor.is_clickable(check, Vector2.ZERO), "a check box is a button too")
	var slider := HSlider.new()
	assert_true(VirtualCursor.is_clickable(slider, Vector2.ZERO), "a slider")
	slider.editable = false
	assert_false(VirtualCursor.is_clickable(slider, Vector2.ZERO), "not a slider that can't be moved")
	var bar := VScrollBar.new()
	bar.max_value = 100.0
	bar.page = 20.0
	assert_true(VirtualCursor.is_clickable(bar, Vector2.ZERO), "a scrollbar with something to scroll")
	bar.page = 100.0
	assert_false(VirtualCursor.is_clickable(bar, Vector2.ZERO), "not a scrollbar that has nothing to scroll")
	var line := LineEdit.new()
	assert_true(VirtualCursor.is_clickable(line, Vector2.ZERO), "a text field")
	line.editable = false
	assert_false(VirtualCursor.is_clickable(line, Vector2.ZERO), "not a read-only text field")
	assert_false(VirtualCursor.is_clickable(Label.new(), Vector2.ZERO), "not a label")
	var panel := Panel.new()
	assert_false(VirtualCursor.is_clickable(panel, Vector2.ZERO), "not a plain panel")
	var hand := Control.new()
	hand.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	assert_true(VirtualCursor.is_clickable(hand, Vector2.ZERO), "a control that asks for the pointing hand (the glow keeps that rule for any that does)")
	for c: Control in [b, check, slider, bar, line, panel, hand]:
		c.free()

func test_the_cursor_glows_over_a_button_and_not_over_empty_space() -> void:
	var layer := _begin()
	GameManager.settings.cursor_shape = "A"
	GameManager.settings.cursor_colour = "rose"
	_vc().refresh_style()
	var mat := _glow_material(_vc().sprite)
	assert_true(mat != null, "the cursor is drawn through the glow shader")
	if mat == null:
		_end()
		return
	var b := _make_button(layer, Rect2(100, 100, 120, 40))
	_motion_to(Vector2(400, 400))
	_vc().update_glow()
	assert_false(_vc().glowing, "plain, over empty space")
	assert_false(mat.get_shader_parameter("glowing"), "and the shader is off")
	_motion_to(Vector2(160, 120))
	_vc().update_glow()
	assert_true(_vc().glowing, "glowing over a button")
	assert_true(mat.get_shader_parameter("glowing"), "and the shader is on")
	var rose := CursorArt.glow_colours("rose")
	assert_eq(mat.get_shader_parameter("glow1"), rose[0], "the light glow is Rose's")
	assert_eq(mat.get_shader_parameter("glow2"), rose[1], "the mid glow is Rose's")
	b.disabled = true
	_vc().update_glow()
	assert_false(_vc().glowing, "a greyed-out button doesn't glow")
	b.disabled = false
	_vc().update_glow()
	assert_true(_vc().glowing, "an enabled one does again")
	_vc().shown = false
	_vc().update_glow()
	assert_false(_vc().glowing, "a hidden cursor has nothing to glow")
	_vc().shown = true
	_motion_to(Vector2(400, 400))
	_vc().update_glow()
	assert_false(_vc().glowing, "moving off the button puts it out")
	assert_false(mat.get_shader_parameter("glowing"), "in the shader too")
	_end()

func test_the_glow_wears_the_chosen_colour() -> void:
	_begin()
	var mat := _glow_material(_vc().sprite)
	GameManager.settings.cursor_colour = "lunar"
	_vc().refresh_style()
	assert_eq(mat.get_shader_parameter("glow1"), Color("#FFFFFF"), "Lunar glows white")
	assert_eq(mat.get_shader_parameter("glow2"), Color("#B9C0D4"), "and silver")
	GameManager.settings.cursor_colour = "ember"
	_vc().refresh_style()
	var ember := CursorArt.glow_colours("ember")
	assert_eq(mat.get_shader_parameter("glow1"), ember[0], "changing the colour changes the glow's")
	assert_eq(mat.get_shader_parameter("glow2"), ember[1], "both tones")
	_end()

func test_the_cursor_glows_over_an_open_dropdown_list_and_so_does_its_copy() -> void:
	var layer := _begin()
	var opt := OptionButton.new()
	for item in ["One", "Two", "Three", "Four"]:
		opt.add_item(item)
	opt.position = Vector2(700, 100)
	opt.size = Vector2(160, 31)
	layer.add_child(opt)
	var popup := opt.get_popup()
	_motion_to(Vector2(780, 115))
	_vc().update_glow()
	assert_true(_vc().glowing, "glowing over the dropdown button")
	_click()
	assert_true(popup.visible, "clicking it opens the list")
	_motion_to(Vector2(popup.position) + Vector2(popup.size.x * 0.5, popup.size.y * 0.6))
	_vc().update_mirrors()
	_vc().update_glow()
	assert_true(_vc().glowing, "glowing over an item in the list")
	var mirror := _mirror_in(popup)
	assert_true(mirror != null, "the cursor is drawn inside the open list")
	if mirror != null:
		var mat := _glow_material(mirror)
		assert_true(mat != null and mat.get_shader_parameter("glowing"), "the copy in the list glows too")
		assert_eq(mirror.material, _vc().sprite.material, "it shares the cursor's glow, colours and all")
	_click()
	assert_false(popup.visible, "choosing an item closes the list")
	_end()

# --- The right stick and Cursor Click ----------------------------------------------

func test_the_right_stick_moves_the_cursor() -> void:
	_begin()
	_vc().pointer_pos = Vector2(500, 300)
	_vc().shown = false
	_tilt(Vector2(1, 0), 0.5)
	assert_near(_vc().pointer_pos.x, 500.0 + 384.0, 0.01, "half a second at full tilt and 1.00x is 384 base pixels")
	assert_eq(_vc().pointer_pos.y, 300.0, "straight right doesn't drift up or down")
	assert_true(_vc().shown, "moving the stick shows the cursor")
	_tilt(Vector2(0, -1), 0.25)
	assert_near(_vc().pointer_pos.y, 300.0 - 192.0, 0.01, "up is up")
	GameManager.settings.stick_sensitivity_right = 0.5
	var before := _vc().pointer_pos
	_tilt(Vector2(-1, 0), 0.5)
	assert_near(before.x - _vc().pointer_pos.x, 192.0, 0.01, "Right Stick Sensitivity scales the speed")
	_end()

func test_a_long_frame_cannot_jump_the_cursor() -> void:
	# A hitch with the stick held (a load, dragging the window) hands _process a delta of a
	# second or more. The cursor must not cross the screen in that one step.
	var layer := _begin()
	var reader := InputReader.new()
	layer.add_child(reader)
	_vc().pointer_pos = Vector2(100, 300)
	_vc().step_stick(Vector2(1, 0), 1.0)
	var jump := _vc().pointer_pos.x - 100.0
	assert_true(jump > 0.0, "the stick still moves it (by %s)" % jump)
	assert_true(jump <= CursorMotion.STICK_FULL_SPEED / 30.0 + 0.01,
			"a one-second frame moves it no further than a 30 fps frame would (%s px)" % jump)
	assert_true(reader.last_motion != null and reader.last_motion.relative.x <= CursorMotion.STICK_FULL_SPEED / 30.0 + 0.01,
			"and the mouse move it pushes carries that step, not the whole second")
	_vc().pointer_pos = Vector2(100, 300)
	_vc().step_stick(Vector2(1, 0), 1.0 / 60.0)
	assert_near(_vc().pointer_pos.x - 100.0, CursorMotion.STICK_FULL_SPEED / 60.0, 0.01, "an ordinary frame is not shortened")
	_end()

func test_a_resting_stick_leaves_the_cursor_alone() -> void:
	var layer := _begin()
	var reader := InputReader.new()
	layer.add_child(reader)
	_vc().pointer_pos = Vector2(500, 300)
	_vc().shown = false
	_vc().step_stick(Vector2(0.1, -0.15), 1.0)
	assert_eq(_vc().pointer_pos, Vector2(500, 300), "jitter inside the dead zone doesn't creep")
	assert_false(_vc().shown, "and doesn't bring a hidden cursor back")
	assert_true(reader.last_motion == null, "and pushes no mouse move")
	_end()

func test_a_drifting_stick_leaves_a_hidden_cursor_and_the_highlight_alone() -> void:
	# A worn stick resting past the dead zone used to bring the cursor back every frame,
	# and its mouse moves took the menus off the d-pad's highlight.
	var layer := _begin()
	var reader := InputReader.new()
	layer.add_child(reader)
	GameManager._apply_input_mode(true, false)   # on the d-pad: highlight up, cursor hidden
	_vc().pointer_pos = Vector2(500, 300)
	_vc().shown = false
	_tilt(Vector2(0.4, 0.1), 1.0)
	assert_eq(_vc().pointer_pos, Vector2(500, 300), "a second of drift at 0.41 doesn't move a hidden cursor")
	assert_false(_vc().shown, "or show it")
	assert_true(reader.last_motion == null, "and pushes no mouse move")
	assert_true(GameManager.focus_nav_active(), "so the highlight stays up")
	_end()

func test_a_firm_push_brings_a_hidden_cursor_back() -> void:
	_begin()
	_vc().pointer_pos = Vector2(500, 300)
	_vc().shown = false
	_vc().step_stick(Vector2(0.6, 0), 1.0 / 60.0)
	assert_true(_vc().shown, "past half tilt the stick brings the cursor back")
	assert_true(_vc().pointer_pos.x > 500.0, "and moves it")
	_end()

func test_a_showing_cursor_moves_from_the_dead_zone_up() -> void:
	_begin()
	_vc().pointer_pos = Vector2(500, 300)
	_vc().shown = true
	_vc().step_stick(Vector2(0.35, 0), 1.0)
	var expected := CursorMotion.stick_velocity(Vector2(0.35, 0), 1.0).x / 30.0
	assert_true(expected > 0.0, "0.35 is past the dead zone")
	assert_near(_vc().pointer_pos.x - 500.0, expected, 0.01, "a gentle tilt moves a cursor that is showing")
	_end()

func test_the_stick_never_leaves_the_window() -> void:
	_begin()
	var bounds := GameManager.get_tree().root.get_visible_rect().size
	_vc().pointer_pos = bounds - Vector2(5, 5)
	_tilt(Vector2(1, 1), 2.0)
	assert_eq(_vc().pointer_pos, bounds - Vector2.ONE, "stopped at the bottom-right corner")
	_vc().pointer_pos = Vector2(5, 5)
	_tilt(Vector2(-1, -1), 2.0)
	assert_eq(_vc().pointer_pos, Vector2.ZERO, "and at the top-left one")
	_end()

func test_stick_motion_is_a_mouse_move_with_a_speed() -> void:
	# A dropdown list ignores a move with no speed when it lights up the row under it.
	var layer := _begin()
	var reader := InputReader.new()
	layer.add_child(reader)
	_vc().pointer_pos = Vector2(500, 300)
	_vc().step_stick(Vector2(1, 0), 1.0 / 60.0)
	var mm := reader.last_motion
	assert_true(mm != null, "the stick pushes a mouse move into the scene")
	if mm != null:
		assert_eq(mm.position, _vc().pointer_pos, "at the cursor's tip")
		assert_near(mm.relative.x, CursorMotion.STICK_FULL_SPEED / 60.0, 0.01, "carrying this frame's step")
		assert_near(mm.velocity.x, CursorMotion.STICK_FULL_SPEED, 0.01, "and the stick's speed in base pixels a second")
		assert_eq(mm.button_mask, 0, "with no button held")
	_end()

func test_the_stick_press_clicks_where_the_cursor_points() -> void:
	var layer := _begin()
	var b := _make_button(layer, Rect2(100, 100, 120, 40))
	var presses := [0]
	b.pressed.connect(func() -> void: presses[0] += 1)
	_vc().pointer_pos = Vector2(160, 120)
	_vc().shown = true
	_pad_button(JOY_BUTTON_RIGHT_STICK, true)
	assert_eq(presses[0], 0, "a button waits for the release, like a mouse click")
	_pad_button(JOY_BUTTON_RIGHT_STICK, false)
	assert_eq(presses[0], 1, "pressing and letting go of the right stick presses the button under the cursor")
	_end()

func test_a_stick_press_while_hidden_only_brings_the_cursor_back() -> void:
	var layer := _begin()
	var b := _make_button(layer, Rect2(100, 100, 120, 40))
	var presses := [0]
	b.pressed.connect(func() -> void: presses[0] += 1)
	_vc().pointer_pos = Vector2(160, 120)
	_vc().shown = false
	_stick_click()
	assert_true(_vc().shown, "the first press shows the cursor where it was")
	assert_eq(_vc().pointer_pos, Vector2(160, 120), "at its last spot")
	assert_eq(presses[0], 0, "and doesn't click somewhere the player couldn't see")
	_stick_click()
	assert_eq(presses[0], 1, "the next one clicks")
	_end()

func test_a_stick_press_that_brings_the_cursor_back_switches_the_menus_to_the_mouse() -> void:
	# The cursor and the focus highlight are never both up. The first press shows a hidden
	# cursor without clicking; the menus must leave the highlight for the mouse with it.
	var layer := _begin()
	var reader := InputReader.new()
	layer.add_child(reader)
	_vc().pointer_pos = Vector2(160, 120)
	for mode in [[true, false], [false, true]]:   # a pad's highlight, then the keyboard's
		GameManager._apply_input_mode(mode[0], mode[1])
		_vc().shown = false
		assert_true(GameManager.focus_nav_active(), "starting on the highlight")
		_stick_click()
		assert_true(_vc().shown, "the press shows the cursor")
		assert_false(GameManager.focus_nav_active(), "and the menus switch to the mouse, so the highlight goes")
		assert_eq(_vc().pointer_pos, Vector2(160, 120), "the cursor stays where it was")
	assert_eq(reader.presses + reader.releases, 0, "neither press clicked anything")
	_end()

func test_a_stick_press_that_cannot_show_the_cursor_leaves_the_highlight() -> void:
	# With another app in front the press does nothing at all, the menus included.
	_begin()
	_vc().notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	GameManager._apply_input_mode(true, false)
	_vc().shown = false
	_stick_click()
	assert_false(_vc().shown, "the cursor stays hidden")
	assert_true(GameManager.focus_nav_active(), "and the highlight stays")
	_end()

func test_holding_the_stick_press_drags_a_slider() -> void:
	var layer := _begin()
	var slider := HSlider.new()
	slider.position = Vector2(100, 300)
	slider.size = Vector2(300, 24)
	slider.max_value = 100.0
	slider.value = 0.0
	layer.add_child(slider)
	var reader := InputReader.new()
	layer.add_child(reader)
	_vc().pointer_pos = Vector2(104, 312)
	_vc().shown = true
	_pad_button(JOY_BUTTON_RIGHT_STICK, true)
	_tilt(Vector2(1, 0), 0.4)
	assert_eq(reader.last_motion_mask, int(MOUSE_BUTTON_MASK_LEFT), "moves while the stick is held say the button is held")
	_pad_button(JOY_BUTTON_RIGHT_STICK, false)
	assert_true(slider.value > 0.0, "holding the press and pushing the stick right dragged the slider (to %s)" % slider.value)
	_tilt(Vector2(1, 0), 0.1)
	assert_eq(reader.last_motion_mask, 0, "after the release, moves carry no held button")
	_end()

func test_the_right_stick_and_its_press_are_the_cursors_not_the_menus() -> void:
	var layer := _begin()
	var reader := InputReader.new()
	layer.add_child(reader)
	_pad_motion(JOY_AXIS_RIGHT_X, 0.9)
	assert_true(reader.last == null, "the right stick is not passed on")
	_pad_motion(JOY_AXIS_RIGHT_Y, -0.9)
	assert_true(reader.last == null, "either axis of it")
	_pad_button(JOY_BUTTON_RIGHT_STICK, true)
	assert_false(reader.last is InputEventJoypadButton, "nor is its press")
	_pad_button(JOY_BUTTON_RIGHT_STICK, false)
	var left := _pad_motion(JOY_AXIS_LEFT_X, 0.9)
	assert_true(reader.last == left, "the left stick still is")
	_end()

func test_rebinding_sees_the_stick_press_and_the_right_stick() -> void:
	# Review focus 2: while the Controller page waits for a button, it must see
	# everything raw, the right stick and R3 included, and the stick moves nothing.
	var layer := _begin()
	var reader := InputReader.new()
	layer.add_child(reader)
	_vc().pointer_pos = Vector2(500, 300)
	_vc().shown = true
	GameManager.raw_input_passthrough = true
	var press := _pad_button(JOY_BUTTON_RIGHT_STICK, true)
	assert_true(reader.last == press, "the press of the right stick reaches _input as the very event the OS sent")
	_pad_button(JOY_BUTTON_RIGHT_STICK, false)
	var tilt := _pad_motion(JOY_AXIS_RIGHT_X, 0.9)
	assert_true(reader.last == tilt, "and so does the right stick, untouched")
	assert_eq(reader.presses + reader.releases, 0, "neither became a mouse click")
	_tilt(Vector2(1, 0), 0.5)
	assert_eq(_vc().pointer_pos, Vector2(500, 300), "and the stick doesn't move the cursor meanwhile")
	GameManager.raw_input_passthrough = false
	_tilt(Vector2(1, 0), 0.5)
	assert_near(_vc().pointer_pos.x, 884.0, 0.01, "it moves it again once rebinding is over")
	_end()

func test_the_dpad_hides_the_cursor_and_still_navigates() -> void:
	var layer := _begin()
	var reader := InputReader.new()
	layer.add_child(reader)
	_vc().shown = true
	var pad := _pad_button(JOY_BUTTON_DPAD_DOWN, true)
	assert_false(_vc().shown, "a d-pad press hides the cursor")
	assert_true(reader.last == pad, "and reaches _input as the very event the OS sent")
	_pad_button(JOY_BUTTON_DPAD_DOWN, false)
	_vc().shown = true
	var tilt := _pad_motion(JOY_AXIS_LEFT_Y, 0.9)
	assert_false(_vc().shown, "so does the left stick")
	assert_true(reader.last == tilt, "which also still reaches _input")
	_end()

func test_a_dropdown_works_from_the_stick() -> void:
	# Stick clicks don't touch the Input singleton's own button state; the dropdown
	# must open, light the row under the cursor, and choose it all the same.
	var layer := _begin()
	var opt := OptionButton.new()
	for item in ["One", "Two", "Three", "Four"]:
		opt.add_item(item)
	opt.position = Vector2(700, 100)
	opt.size = Vector2(160, 31)
	layer.add_child(opt)
	var popup := opt.get_popup()
	_vc().pointer_pos = Vector2(780, 115)
	_vc().shown = true
	_stick_click()
	assert_true(popup.visible, "pressing the stick on the dropdown opens its list")
	# Just above the third row's middle, then a nudge of the stick onto it.
	_vc().pointer_pos = Vector2(popup.position) + Vector2(popup.size.x * 0.5, popup.size.y * 2.5 / 4.0 - 3.0)
	_vc().step_stick(Vector2(0, 1), 0.004)
	assert_eq(popup.get_focused_item(), 2, "a nudge of the stick lights the row under the cursor")
	_stick_click()
	assert_eq(opt.selected, 2, "pressing the stick on a row chooses it")
	assert_false(popup.visible, "and the list closes")
	_end()

# --- Cursor Click on a shared button, and letting go --------------------------------

func test_a_shared_cursor_click_is_forwarded_while_the_cursor_is_hidden() -> void:
	var layer := _begin()
	var b := _make_button(layer, Rect2(100, 100, 120, 40))
	var presses := [0]
	b.pressed.connect(func() -> void: presses[0] += 1)
	var reader := InputReader.new()
	layer.add_child(reader)
	_bind_cursor_click(JOY_BUTTON_A)   # Confirm is on A too
	var a := InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_A
	assert_true(a.is_action("ui_accept"), "A is also bound to another action")
	_vc().pointer_pos = Vector2(160, 120)
	_vc().shown = false
	var press := _pad_button(JOY_BUTTON_A, true)
	assert_true(reader.last == press, "the press reaches _input unchanged, so Confirm still works")
	assert_false(_vc().shown, "and doesn't bring the cursor back")
	_pad_button(JOY_BUTTON_A, false)
	assert_eq(presses[0], 0, "and doesn't click")
	_end()

func test_a_shared_cursor_click_clicks_while_the_cursor_is_shown() -> void:
	var layer := _begin()
	var b := _make_button(layer, Rect2(100, 100, 120, 40))
	var presses := [0]
	b.pressed.connect(func() -> void: presses[0] += 1)
	var reader := InputReader.new()
	layer.add_child(reader)
	_bind_cursor_click(JOY_BUTTON_A)
	_vc().pointer_pos = Vector2(160, 120)
	_vc().shown = true
	var press := _pad_button(JOY_BUTTON_A, true)
	_pad_button(JOY_BUTTON_A, false)
	assert_eq(presses[0], 1, "with the cursor showing, the shared button clicks")
	assert_false(reader.last == press, "and the cursor keeps the press to itself")
	assert_true(_vc().shown, "still showing")
	_end()

func test_a_press_the_cursor_clicked_is_always_let_go() -> void:
	# However the pad's role changes mid-hold, a drag can never stick.
	var layer := _begin()
	var reader := InputReader.new()
	layer.add_child(reader)
	_vc().pointer_pos = Vector2(300, 300)
	_vc().shown = true
	_pad_button(JOY_BUTTON_RIGHT_STICK, true)
	assert_eq(reader.presses, 1, "the stick press pressed the left button")
	GameManager.raw_input_passthrough = true   # a rebind began while it was held
	var release := _pad_button(JOY_BUTTON_RIGHT_STICK, false)
	assert_eq(reader.releases, 1, "its release still let the left button go")
	assert_true(reader.last == release, "and the raw release is forwarded, as everything is while rebinding")
	assert_true(_vc()._buttons == 0, "so no button is left held")
	GameManager.raw_input_passthrough = false
	_tilt(Vector2(1, 0), 0.1)
	assert_eq(reader.last_motion_mask, 0, "later moves carry no held button")
	_end()

func test_a_press_that_hid_the_cursor_is_still_let_go() -> void:
	var layer := _begin()
	var reader := InputReader.new()
	layer.add_child(reader)
	_vc().pointer_pos = Vector2(300, 300)
	_vc().shown = true
	_pad_button(JOY_BUTTON_RIGHT_STICK, true)
	_pad_button(JOY_BUTTON_DPAD_DOWN, true)   # the d-pad takes over mid-hold
	assert_false(_vc().shown, "the cursor is hidden")
	_pad_button(JOY_BUTTON_RIGHT_STICK, false)
	assert_eq(reader.releases, 1, "the release is still sent")
	_pad_button(JOY_BUTTON_DPAD_DOWN, false)
	_end()

func test_a_release_with_no_press_of_ours_sends_no_release() -> void:
	var layer := _begin()
	var reader := InputReader.new()
	layer.add_child(reader)
	_vc().pointer_pos = Vector2(300, 300)
	_vc().shown = false
	_stick_click()   # the press only shows the cursor
	assert_eq(reader.presses + reader.releases, 0, "a hidden cursor's press and release click nothing")
	_vc().shown = true
	GameManager.raw_input_passthrough = true
	_pad_button(JOY_BUTTON_RIGHT_STICK, true)   # forwarded raw, not turned into a click
	GameManager.raw_input_passthrough = false
	_pad_button(JOY_BUTTON_RIGHT_STICK, false)
	assert_eq(reader.presses + reader.releases, 0, "nor does a release whose press was never ours")
	_end()

func test_a_trigger_bound_to_cursor_click_presses_once_and_lets_go() -> void:
	# Cursor Click can be rebound to an axis: its stream of motion events is one press.
	var layer := _begin()
	var reader := InputReader.new()
	layer.add_child(reader)
	_bind_cursor_click_axis(JOY_AXIS_TRIGGER_RIGHT)
	_vc().pointer_pos = Vector2(300, 300)
	_vc().shown = true
	_pad_motion(JOY_AXIS_TRIGGER_RIGHT, 0.7)
	_pad_motion(JOY_AXIS_TRIGGER_RIGHT, 0.9)
	_pad_motion(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	assert_eq(reader.presses, 1, "three pushes of the trigger are one press")
	_pad_motion(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	assert_eq(reader.releases, 1, "and letting it go is one release")
	_end()

func test_a_trigger_pull_while_the_cursor_is_hidden_only_brings_it_back() -> void:
	# The rest of the same pull must not turn into the click the first sample held back.
	var layer := _begin()
	var reader := InputReader.new()
	layer.add_child(reader)
	_bind_cursor_click_axis(JOY_AXIS_TRIGGER_RIGHT)
	_vc().pointer_pos = Vector2(300, 300)
	_vc().shown = false
	_pad_motion(JOY_AXIS_TRIGGER_RIGHT, 0.7)
	assert_true(_vc().shown, "the first sample over the dead zone shows the cursor")
	_pad_motion(JOY_AXIS_TRIGGER_RIGHT, 0.9)
	_pad_motion(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	assert_eq(reader.presses, 0, "and the rest of that pull clicks nothing")
	_pad_motion(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	assert_eq(reader.presses + reader.releases, 0, "nor does letting go")
	_pad_motion(JOY_AXIS_TRIGGER_RIGHT, 0.8)
	_pad_motion(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_pad_motion(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	assert_eq(reader.presses, 1, "the next pull, with the cursor showing, is one click")
	assert_eq(reader.releases, 1, "let go once")
	_end()

func test_a_trigger_pull_that_began_while_rebinding_is_not_a_click_afterwards() -> void:
	var layer := _begin()
	var reader := InputReader.new()
	layer.add_child(reader)
	_bind_cursor_click_axis(JOY_AXIS_TRIGGER_RIGHT)
	_vc().pointer_pos = Vector2(300, 300)
	_vc().shown = true
	GameManager.raw_input_passthrough = true
	_pad_motion(JOY_AXIS_TRIGGER_RIGHT, 0.7)   # forwarded raw: not ours (and it hid the cursor)
	GameManager.raw_input_passthrough = false
	_vc().shown = true
	_pad_motion(JOY_AXIS_TRIGGER_RIGHT, 0.9)
	assert_eq(reader.presses, 0, "the rest of a pull the cursor never saw begin isn't a click")
	_pad_motion(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	assert_eq(reader.releases, 0, "and has nothing to let go of")
	_end()

# --- What Godot's own window did with every event --------------------------------------

func test_every_routed_event_is_announced_on_the_windows_input_signal() -> void:
	# Window::_window_input emits window_input before delivering; the hook replaces it.
	_begin()
	var root := GameManager.get_tree().root
	var seen: Array[InputEvent] = []
	var listener := func(ev: InputEvent) -> void: seen.append(ev)
	root.window_input.connect(listener)
	var key := _key(KEY_F11, true)
	assert_eq(seen.size(), 1, "a key is announced once")
	assert_true(seen.size() == 1 and seen[0] == key, "as the event the OS sent")
	_key(KEY_F11, false)
	seen.clear()
	_button(MOUSE_BUTTON_LEFT, true)
	assert_eq(seen.size(), 1, "a mouse button is announced once")
	assert_true(seen.size() == 1 and seen[0] is InputEventMouseButton and seen[0].position == _vc().pointer_pos, "at the cursor's tip")
	_button(MOUSE_BUTTON_LEFT, false)
	seen.clear()
	_motion_to(Vector2(300, 300))
	assert_eq(seen.size(), 1, "a mouse move is announced once")
	seen.clear()
	_pad_button(JOY_BUTTON_DPAD_DOWN, true)
	assert_eq(seen.size(), 1, "a controller button is announced once")
	root.window_input.disconnect(listener)
	_end()

# --- Holding and letting go of the mouse ---------------------------------------------

func _bounds() -> Vector2:
	return GameManager.get_tree().root.get_visible_rect().size

func _held() -> bool:
	return _vc().hold.state == CursorHold.State.HELD

## Windowed, the cursor at the right edge, pushed out until the mouse is let go.
func _slip_out() -> void:
	GameManager.settings.window_mode = SettingsModel.WindowMode.WINDOWED
	_vc().pointer_pos = Vector2(_bounds().x - 1.0, 300)
	_vc().shown = true
	_push(Vector2(30, 0))

func test_pushing_out_of_a_windowed_game_lets_the_mouse_go() -> void:
	_begin()
	GameManager.settings.window_mode = SettingsModel.WindowMode.WINDOWED
	_vc().pointer_pos = Vector2(_bounds().x - 1.0, 300)
	_vc().shown = true
	for i in 3:
		_push(Vector2(10, 0))
	assert_eq(_vc().hold.state, CursorHold.State.RELEASED, "pushing 30 px past the right edge lets the mouse go")
	assert_false(_vc().shown, "and the drawn cursor hides: the system pointer carries on from there")
	_end()

func test_the_click_that_picks_the_mouse_up_presses_nothing() -> void:
	var layer := _begin()
	var b := _make_button(layer, Rect2(100, 100, 120, 40))
	var presses := [0]
	b.pressed.connect(func() -> void: presses[0] += 1)
	_slip_out()
	var spot := Vector2(160, 120)
	_left_at(spot, true)
	_left_at(spot, false)
	assert_eq(_vc().hold.state, CursorHold.State.HELD, "a click inside the window picks the mouse up")
	assert_true(_vc().pointer_pos.is_equal_approx(spot), "with the cursor where the click happened (at %s)" % _vc().pointer_pos)
	assert_eq(presses[0], 0, "and the button it landed on is not pressed")
	_end()

func test_switching_away_and_back() -> void:
	_begin()
	var s := GameManager.settings
	_vc().notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_eq(_vc().hold.state, CursorHold.State.RELEASED, "switching away lets the mouse go")
	_vc().notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_eq(_vc().hold.state, CursorHold.State.HELD, "coming back to a fullscreen game picks it up at once")
	s.window_mode = SettingsModel.WindowMode.WINDOWED
	_vc().notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_vc().notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_eq(_vc().hold.state, CursorHold.State.RELEASED, "coming back to a windowed game waits for a click")
	_end()

func test_a_fullscreen_game_never_lets_go_at_the_edge() -> void:
	_begin()
	GameManager.settings.window_mode = SettingsModel.WindowMode.FULLSCREEN
	var edge := Vector2(_bounds().x - 1.0, 300)
	_vc().pointer_pos = edge
	for i in 20:
		_push(Vector2(50, 0))
	assert_eq(_vc().hold.state, CursorHold.State.HELD, "1000 px past the edge, a fullscreen game still holds the mouse")
	assert_eq(_vc().pointer_pos, edge, "and the cursor stays at the edge")
	_end()

func test_borderless_holds_like_fullscreen() -> void:
	_begin()
	GameManager.settings.window_mode = SettingsModel.WindowMode.BORDERLESS
	_vc().pointer_pos = Vector2(0, 300)
	for i in 20:
		_push(Vector2(-50, 0))
	assert_true(_held(), "pushing out of a borderless game's left edge doesn't let go")
	assert_eq(_vc().pointer_pos, Vector2(0, 300), "the cursor stays at the edge")
	_vc().notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_vc().notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_true(_held(), "and coming back to it picks the mouse up at once")
	_end()

func test_a_nudge_at_the_window_edge_keeps_the_mouse() -> void:
	_begin()
	GameManager.settings.window_mode = SettingsModel.WindowMode.WINDOWED
	_vc().pointer_pos = Vector2(_bounds().x - 1.0, 300)
	_push(Vector2(20, 0))
	_push(Vector2(-5, 0))   # back in a little
	_push(Vector2(5, 0))   # back to the edge: no push yet
	_push(Vector2(20, 0))
	assert_true(_held(), "two short pushes with a move back in between don't add up")
	assert_true(_vc().shown, "the drawn cursor is still the one showing")
	_push(Vector2(10, 0))
	assert_false(_held(), "a push that keeps going past %s px does let go" % CursorMotion.SLIP_OUT_DISTANCE)
	_end()

func test_a_move_that_goes_nowhere_does_not_restart_the_push() -> void:
	_begin()
	GameManager.settings.window_mode = SettingsModel.WindowMode.WINDOWED
	_vc().pointer_pos = Vector2(_bounds().x - 1.0, 300)
	_push(Vector2(20, 0))
	_push(Vector2.ZERO)   # a report with no movement in it
	_push(Vector2(5, 0))
	assert_false(_held(), "20 px, a still report, then 5 px is still one push of 25 px")
	_end()

func test_the_push_is_counted_in_the_cursors_own_pixels() -> void:
	_begin()
	GameManager.settings.window_mode = SettingsModel.WindowMode.WINDOWED
	GameManager.settings.mouse_sensitivity = 2.0
	_vc().pointer_pos = Vector2(_bounds().x - 1.0, 300)
	_push(Vector2(12, 0))   # 24 px of cursor movement at 2.00x
	assert_false(_held(), "at 2.00x a 12 px mouse move is the cursor pushing 24 px: it lets go")
	_end()

func test_a_let_go_mouse_reaches_nothing() -> void:
	var layer := _begin()
	var reader := InputReader.new()
	layer.add_child(reader)
	_slip_out()
	var spot := _vc().pointer_pos
	reader.last = null
	reader.last_motion = null
	_motion_to(Vector2(300, 300))
	_button(MOUSE_BUTTON_WHEEL_DOWN, true)
	_button(MOUSE_BUTTON_WHEEL_DOWN, false)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	right.position = GameManager.get_tree().root.get_final_transform() * Vector2(300, 300)
	_vc().route_os_event(right)
	assert_true(reader.last == null, "while let go, no mouse event reaches the game")
	assert_eq(_vc().pointer_pos, spot, "and the cursor stays where it let go")
	assert_false(_held(), "only a left click picks the mouse up")
	_end()

func test_after_picking_up_the_next_click_clicks() -> void:
	var layer := _begin()
	var b := _make_button(layer, Rect2(100, 100, 120, 40))
	var presses := [0]
	b.pressed.connect(func() -> void: presses[0] += 1)
	var reader := InputReader.new()
	layer.add_child(reader)
	_slip_out()
	_left_at(Vector2(160, 120), true)
	_left_at(Vector2(160, 120), false)
	assert_eq(reader.presses + reader.releases, 0, "the pick-up click's press and release reach no _input reader")
	assert_true(_vc().shown, "the drawn cursor is back")
	_click()
	assert_eq(presses[0], 1, "the next click presses the button under the cursor")
	assert_eq(reader.releases, 1, "its release is not swallowed")
	_end()

func test_the_pointer_coming_back_into_the_window_picks_the_mouse_up() -> void:
	# Let go, the pointer is the system's and moves at desktop speed: it must not stay so
	# once it is back over the game, or the player's sensitivity seems lost until a click.
	var layer := _begin()
	var reader := InputReader.new()
	layer.add_child(reader)
	_slip_out()
	_vc().notification(Node.NOTIFICATION_WM_MOUSE_ENTER)
	assert_false(_held(), "letting go can report the pointer entering (it is put just inside the edge): no pick-up")
	_vc().notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
	reader.last = null
	_vc().notification(Node.NOTIFICATION_WM_MOUSE_ENTER)
	assert_true(_held(), "out of the window and back in picks the mouse up, no click needed")
	assert_true(_vc().shown, "the drawn cursor is back")
	assert_true(reader.last is InputEventMouseMotion and reader.last.relative == Vector2.ZERO,
			"with a still move, which tells the menus the mouse is in use")
	assert_eq(reader.presses + reader.releases, 0, "it presses nothing")
	GameManager.settings.mouse_sensitivity = 2.0
	var before := _vc().pointer_pos
	_push(Vector2(-10, 0))
	assert_near(before.x - _vc().pointer_pos.x, 20.0, 0.01, "and the mouse moves it at the game's sensitivity again")
	_end()

func test_the_pointer_coming_back_while_another_app_is_in_front_leaves_the_mouse() -> void:
	_begin()
	_slip_out()
	_vc().notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_vc().notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
	_vc().notification(Node.NOTIFICATION_WM_MOUSE_ENTER)
	assert_false(_held(), "passing over the game while another app is in front never takes the mouse")
	assert_false(_vc().shown, "or shows the drawn cursor")
	_end()

func test_the_right_stick_picks_a_let_go_mouse_up() -> void:
	_begin()
	_slip_out()
	var spot := _vc().pointer_pos
	_tilt(Vector2(-1, 0), 0.5)
	assert_true(_held(), "moving the right stick picks the mouse up")
	assert_near(spot.x - _vc().pointer_pos.x, 384.0, 0.01, "and moves the cursor from where it let go")
	assert_true(_vc().shown, "which shows again")
	_end()

func test_a_drifting_stick_never_picks_a_let_go_mouse_up() -> void:
	_begin()
	_slip_out()
	var spot := _vc().pointer_pos
	_tilt(Vector2(0, 0.45), 1.0)
	assert_false(_held(), "a stick drifting under half tilt leaves the mouse on the desktop")
	assert_eq(_vc().pointer_pos, spot, "and the cursor where it let go")
	_end()

func test_a_stick_press_picks_a_let_go_mouse_up_without_clicking() -> void:
	var layer := _begin()
	var reader := InputReader.new()
	layer.add_child(reader)
	_slip_out()
	_stick_click()
	assert_true(_held(), "a Cursor Click while let go picks the mouse up")
	assert_true(_vc().shown, "and shows the cursor")
	assert_eq(reader.presses + reader.releases, 0, "without clicking")
	_end()

func test_the_stick_never_takes_the_mouse_from_another_app() -> void:
	_begin()
	_vc().pointer_pos = Vector2(500, 300)
	_vc().notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_tilt(Vector2(1, 0), 0.5)
	assert_false(_held(), "with another app in front the stick leaves the mouse alone")
	assert_eq(_vc().pointer_pos, Vector2(500, 300), "and doesn't move the cursor")
	assert_false(_vc().shown, "or show it")
	_stick_click()
	assert_false(_held(), "nor does its press")
	_end()

func test_the_stick_never_lets_go_at_the_edge() -> void:
	_begin()
	GameManager.settings.window_mode = SettingsModel.WindowMode.WINDOWED
	_vc().pointer_pos = Vector2(_bounds().x - 1.0, 300)
	_tilt(Vector2(1, 0), 2.5)
	assert_true(_held(), "the stick pushing past a window's edge keeps the mouse: only the mouse slips out")
	_end()

func test_switching_away_lets_go_of_everything_held() -> void:
	var layer := _begin()
	var reader := InputReader.new()
	layer.add_child(reader)
	_vc().pointer_pos = Vector2(300, 300)
	_vc().shown = true
	_pad_button(JOY_BUTTON_RIGHT_STICK, true)   # Cursor Click held: a left drag
	_button(MOUSE_BUTTON_RIGHT, true)   # and the mouse's right button
	assert_eq(reader.presses, 2, "two buttons held")
	_vc().notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_eq(reader.releases, 2, "switching away lets go of both, so no drag sticks")
	assert_eq(_vc()._buttons, 0, "the cursor holds nothing")
	assert_false(_vc()._click_down, "Cursor Click is no longer pressing")
	assert_false(_vc()._click_held, "and its next press starts afresh")
	_vc().notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_pad_button(JOY_BUTTON_RIGHT_STICK, false)
	assert_eq(reader.releases, 2, "the stick's late release lets go of nothing more")
	_tilt(Vector2(1, 0), 0.1)
	assert_eq(reader.last_motion_mask, 0, "and later moves carry no held button")
	_end()

func test_becoming_fullscreen_picks_a_let_go_mouse_up() -> void:
	_begin()
	_slip_out()
	GameManager.settings.window_mode = SettingsModel.WindowMode.FULLSCREEN
	_vc().notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_vc().on_display_changed()
	assert_false(_held(), "not while another app is in front")
	_vc().notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_true(_held(), "and coming back to it, as fullscreen, picks the mouse up")
	_slip_out()
	GameManager.settings.window_mode = SettingsModel.WindowMode.BORDERLESS
	_vc().on_display_changed()
	assert_true(_held(), "switching a let-go window to borderless picks the mouse up")
	_end()

func test_the_system_cursor_is_the_size_the_cursor_is_drawn() -> void:
	# A window 2.625x the base size on a Retina screen: 2.625 window pixels a base pixel,
	# 2 window pixels a point, and a Mac cursor image is measured in points.
	assert_near(VirtualCursor.os_cursor_scale(2.625, 2.0, "A"), 1.3125, 0.0001, "a Retina Mac draws it in points")
	assert_near(VirtualCursor.os_cursor_scale(1.5, 1.0, "A"), 1.5, 0.0001, "elsewhere in window pixels")
	for shape: String in CursorArt.SHAPES:
		var s := VirtualCursor.os_cursor_scale(12.0, 1.0, shape)
		var img := CursorArt.image(shape, "amethyst", s)
		var big := maxi(img.get_width(), img.get_height())
		assert_true(big <= 256, "%s fits a system cursor's 256 px at any window size (%d px)" % [shape, big])
		assert_true(big >= 250, "%s is capped only as far as it must be (%d px)" % [shape, big])

func test_dressing_the_system_pointer_keeps_the_cursors_own_texture() -> void:
	# The system pointer is drawn straight to an image: it used to go through the texture
	# cache at every window scale, and the cache now holds only the cursor's own style.
	_begin()
	_vc().refresh_style()
	var drawn := _vc().sprite.texture
	_vc()._dress_system_pointer()
	var style := _vc()._style()
	assert_true(CursorArt.texture(style[0], style[1]) == drawn, "the drawn cursor's texture is still the cached one")
	_end()

func test_a_dropdown_taking_focus_inside_the_window_keeps_the_mouse() -> void:
	# An embedded popup grabbing focus sends the root a window focus-out too; only the
	# system's word on the window itself (here: still focused) may let the mouse go.
	_begin()
	assert_true(DisplayServer.window_is_focused(), "the test runner's window counts as focused")
	_vc().notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	assert_true(_held(), "a window focus-out while the system says the window is focused keeps the mouse")
	_vc().notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	assert_true(_held(), "and the focus-in after it changes nothing")
	_end()

func test_the_mouse_is_held_only_while_both_the_app_and_its_window_are_in_front() -> void:
	_begin()
	_vc().notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_vc()._window_focused = false   # and its window minimised (headless can't say so itself)
	_vc().notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_false(_held(), "the app coming back doesn't pick the mouse up while its window is unfocused")
	_tilt(Vector2(1, 0), 0.5)
	assert_false(_held(), "nor does the stick")
	_vc().notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)   # the system now says it is focused
	assert_true(_held(), "once the window has focus again too, a fullscreen game holds it")
	_end()

func test_the_mouse_is_only_ever_captured_while_the_game_is_in_front() -> void:
	_begin()
	assert_eq(_vc()._wanted_mouse_mode(), Input.MOUSE_MODE_CAPTURED, "held and in front: captured")
	_vc()._window_focused = false   # the window still opening, or minimised
	assert_true(_held(), "the mouse still counts as held")
	assert_eq(_vc()._wanted_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "but it is not captured until the game is in front")
	_vc()._window_focused = true
	_slip_out()
	assert_eq(_vc()._wanted_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "let go: visible")
	_end()

func test_a_game_that_opens_behind_another_app_holds_the_mouse_once_in_front() -> void:
	# macOS can take the focus away and give it back while the game is still opening.
	_begin()
	GameManager.settings.window_mode = SettingsModel.WindowMode.WINDOWED
	_vc()._window_focused = false   # as the cursor found the window when it was made
	_vc().notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_true(_held(), "a focus-out before the game was ever in front lets nothing go")
	_vc().notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_vc().notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	assert_true(_held(), "once in front, even a windowed game holds the mouse without a click")
	assert_eq(_vc()._wanted_mouse_mode(), Input.MOUSE_MODE_CAPTURED, "and takes it")
	_end()

# --- Telling the stick's click from the mouse's ------------------------------------

func test_a_stick_click_says_it_came_from_the_pad() -> void:
	# Cursor Click and a real mouse button both reach a control as a left InputEventMouseButton;
	# pad_click is how a control (the Controller page's Rename field) tells them apart.
	var layer := _begin()
	var reader := InputReader.new()
	layer.add_child(reader)
	_motion_to(Vector2(300, 200))   # the cursor is up, so the stick's press clicks
	assert_false(_vc().pad_click, "no click is being pushed")
	_stick_click()
	assert_eq(reader.pad_on_press, [true], "the press the stick made says it came from the pad")
	assert_eq(reader.pad_on_release, [true], "and so does its release")
	assert_false(_vc().pad_click, "and the flag is down again afterwards")
	_click()
	assert_eq(reader.pad_on_press, [true, false], "a real mouse press does not")
	assert_eq(reader.pad_on_release, [true, false], "nor its release")
	assert_false(_vc().pad_click, "and the flag stays down")
	_end()

## A Settings screen on `layer`, on `view`, laid out now, with `field` in the visible part of its
## scroll area. The field commits its text when it loses focus (writing config.cfg), so a test
## that uses it keeps the config file and the controller profile's name (see _keep_config).
func _settings_page(layer: CanvasLayer, view: String, field_name: String) -> SettingsScreen:
	var screen := SettingsScreen.new()
	layer.add_child(screen)
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen._view = view
	screen._build()
	_lay_out(screen)
	var scroll := screen.find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer
	scroll.ensure_control_visible(screen.get(field_name))
	_lay_out(screen)
	return screen

var _kept_config := {}

func _keep_config() -> void:
	var path := "user://config.cfg"
	var profiles := GameManager.input_profiles
	_kept_config = {
		"had": FileAccess.file_exists(path),
		"bytes": FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray(),
		"names": [profiles.name_for(true, profiles.active_index(true)), profiles.name_for(false, profiles.active_index(false))],
	}

func _put_config_back() -> void:
	var path := "user://config.cfg"
	var profiles := GameManager.input_profiles
	profiles.set_name(true, profiles.active_index(true), _kept_config["names"][0])
	profiles.set_name(false, profiles.active_index(false), _kept_config["names"][1])
	if _kept_config["had"]:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(_kept_config["bytes"])
		f.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func test_the_stick_cursor_opens_the_rename_keyboard_and_the_mouse_does_not() -> void:
	var layer := _begin()
	_keep_config()
	var profiles := GameManager.input_profiles
	profiles.set_name(false, profiles.active_index(false), "Couch")
	var screen := _settings_page(layer, "controller", "_pad_profile_name")
	var field := screen._pad_profile_name
	var scroll := screen.find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer
	assert_true(scroll.get_global_rect().encloses(field.get_global_rect()), "the Rename field is inside the scroll area's visible part")

	_motion_to(field.get_global_rect().get_center())
	_click()
	assert_true(screen._keyboard_panel == null, "a real mouse click on the field opens no keyboard")
	assert_true(field.has_focus(), "it puts the caret in, as it always did")
	_stick_click()
	assert_true(is_instance_valid(screen._keyboard_panel), "the stick cursor's click opens the keyboard")
	if is_instance_valid(screen._keyboard_panel):
		assert_eq(screen._keyboard_panel.get_text(), "Couch", "on the profile's current name")

	layer.remove_child(screen)
	screen.free()
	_put_config_back()
	_end()

func test_the_stick_cursor_opens_nothing_from_the_keyboard_pages_field() -> void:
	var layer := _begin()
	_keep_config()
	var screen := _settings_page(layer, "keyboard", "_kb_profile_name")
	var field := screen._kb_profile_name
	_motion_to(field.get_global_rect().get_center())
	_stick_click()
	assert_true(screen._keyboard_panel == null, "the Keyboard page's field gets no on-screen keyboard from the stick either")
	assert_eq(screen.find_children("*", "OnScreenKeyboard", true, false).size(), 0, "none is anywhere under the screen")

	layer.remove_child(screen)
	screen.free()
	_put_config_back()
	_end()
