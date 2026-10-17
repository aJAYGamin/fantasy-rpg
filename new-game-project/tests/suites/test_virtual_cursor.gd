extends TestSuite

## The virtual cursor (VirtualCursor): the hook that re-delivers every mouse event at
## the drawn cursor's position, passes keyboard and controller input through
## untouched, and draws the themed cursor (over an open dropdown list too).
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
	var cancels := 0
	var last: InputEvent = null
	var last_motion_mask := -1

	func _input(ev: InputEvent) -> void:
		last = ev
		if ev is InputEventMouseButton and ev.pressed:
			presses += 1
		elif ev is InputEventMouseMotion:
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
	}
	s.mouse_sensitivity = 1.0   # the moves below assume 1.00x
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
	s.cursor_shape = _saved["shape"]
	s.cursor_colour = _saved["colour"]
	_vc().refresh_style()
	_vc().pointer_pos = _saved["pointer"]
	_vc().shown = _saved["shown"]
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
