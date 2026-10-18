extends TestSuite

## CyclerRow: a `◀ value ▶` settings row. The arrows are clickable, left / right step
## a focused row (and are consumed, so focus never slides sideways), up / down still
## move between rows, a held direction keeps stepping, and the row is ONE focus stop
## that the focus guard governs like the other settings controls.

func suite_name() -> String:
	return "CyclerRow"

var _saved_controller := false
var _saved_keyboard := false

func _begin() -> void:
	_saved_controller = GameManager._controller_mode
	_saved_keyboard = GameManager._keyboard_nav

func _end(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			GameManager.unregister_focus_scope(n)
			n.free()
	GameManager._apply_input_mode(_saved_controller, _saved_keyboard)

func _row(label_text: String, labels: Array, start := 0) -> CyclerRow:
	var r := CyclerRow.new()
	r.setup(label_text, PackedStringArray(labels), start)
	return r

func _key(keycode: Key, echo := false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	ev.echo = echo
	GameManager.get_viewport().push_input(ev)

func _arrows(r: CyclerRow) -> Array[Button]:
	var out: Array[Button] = []
	for b in r.find_children("*", "Button", true, false):
		out.append(b)
	return out

func test_the_arrows_step_and_wrap() -> void:
	var r := CyclerRow.new()
	r.setup("Colour", PackedStringArray(["A", "B", "C"]), 0)
	var seen := []
	r.changed.connect(func(i): seen.append(i))
	r.step(-1)
	r.step(+1)
	r.step(+1)
	assert_eq(seen, [2, 0, 1], "wraps both ways")
	assert_eq(r.index, 1, "index follows the steps")
	r.free()

func test_the_value_shows_the_current_label() -> void:
	var r := _row("Max FPS", ["Uncapped", "30", "60"], 1)
	assert_eq(r._value_label.text, "30", "starts on the given index")
	r.step(1)
	assert_eq(r._value_label.text, "60", "stepping shows the next label")
	r.step(1)
	assert_eq(r._value_label.text, "Uncapped", "and wraps to the first")
	assert_eq(r._name_label.text, "Max FPS", "the name is the row's own")
	r.free()

func test_a_start_outside_the_list_is_clamped_and_an_empty_list_is_safe() -> void:
	var r := _row("X", ["a", "b"], 9)
	assert_eq(r.index, 1, "past the end lands on the last choice")
	r.free()
	var empty := _row("X", [])
	var fired := [0]
	empty.changed.connect(func(_i): fired[0] += 1)
	empty.step(1)
	assert_eq(fired[0], 0, "nothing to step through: no change reported")
	assert_eq(empty._value_label.text, "", "and no value shown")
	empty.free()

func test_the_arrow_buttons_click_and_are_not_focus_stops() -> void:
	var r := _row("Colour", ["A", "B", "C"])
	var arrows := _arrows(r)
	assert_eq(arrows.size(), 2, "a left arrow and a right arrow")
	assert_eq(arrows[0].text, "◀", "left arrow first")
	assert_eq(arrows[1].text, "▶", "right arrow second")
	arrows[1].pressed.emit()
	assert_eq(r.index, 1, "▶ steps forward")
	arrows[0].pressed.emit()
	arrows[0].pressed.emit()
	assert_eq(r.index, 2, "◀ steps back, wrapping")
	for a in arrows:
		assert_eq(a.focus_mode, Control.FOCUS_NONE, "an arrow is never a focus stop")
		assert_true(a.has_meta(BattleUITheme.NO_FOCUS_META), "and the focus guard knows to leave it so")
	assert_eq(r.focus_mode, Control.FOCUS_ALL, "the row itself is the one focus stop")
	r.free()

func test_left_and_right_change_a_focused_row() -> void:
	_begin()
	var box := VBoxContainer.new()
	var r := _row("Colour", ["A", "B", "C"])
	box.add_child(r)
	GameManager.add_child(box)
	r.grab_focus()
	var seen := []
	r.changed.connect(func(i): seen.append(i))
	_key(KEY_RIGHT)
	assert_eq(r.index, 1, "right steps forward")
	_key(KEY_LEFT)
	assert_eq(r.index, 0, "left steps back")
	_key(KEY_LEFT)
	assert_eq(r.index, 2, "and wraps")
	assert_eq(seen, [1, 0, 2], "each press reports once")
	_end([box])

func test_left_and_right_are_consumed_so_focus_never_slides_sideways() -> void:
	# A neighbour wired to the row's right and left: without the row consuming the key,
	# focus would move to it (this is also how the focus guard's wrap-around works).
	_begin()
	var box := VBoxContainer.new()
	var r := _row("Colour", ["A", "B", "C"])
	var left := Button.new()
	var right := Button.new()
	box.add_child(left)
	box.add_child(r)
	box.add_child(right)
	GameManager.add_child(box)
	r.focus_neighbor_left = r.get_path_to(left)
	r.focus_neighbor_right = r.get_path_to(right)
	r.grab_focus()
	_key(KEY_RIGHT)
	assert_eq(r.get_viewport().gui_get_focus_owner(), r, "right stayed on the row")
	_key(KEY_LEFT)
	assert_eq(r.get_viewport().gui_get_focus_owner(), r, "left stayed on the row")
	_end([box])

func test_a_keys_own_repeat_is_swallowed_not_stepped() -> void:
	# A held direction repeats through GameManager's nav repeat, the same for every
	# device; the key's own repeat must neither step again (double speed) nor leak
	# through to move focus.
	_begin()
	var box := VBoxContainer.new()
	var r := _row("Colour", ["A", "B", "C"])
	var right := Button.new()
	box.add_child(r)
	box.add_child(right)
	GameManager.add_child(box)
	r.focus_neighbor_right = r.get_path_to(right)
	r.grab_focus()
	_key(KEY_RIGHT, true)
	assert_eq(r.index, 0, "an echo doesn't step")
	assert_eq(r.get_viewport().gui_get_focus_owner(), r, "and doesn't move focus either")
	_end([box])

func _stick(axis_value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = JOY_AXIS_LEFT_X
	ev.axis_value = axis_value
	GameManager.get_viewport().push_input(ev)

func _dpad(button: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = true
	GameManager.get_viewport().push_input(ev)

## A row whose idea of "the action just became pressed" the test decides (see
## CyclerRow._newly_pressed).
class PushRow extends CyclerRow:
	var newly_pressed := false
	func _newly_pressed(_action: String) -> bool:
		return newly_pressed

func test_a_stick_steps_once_per_push_not_once_per_motion_event() -> void:
	# A stick push sends a stream of changing axis values, every one past the deadzone.
	# Like Godot's own focus navigation, only the event that makes the action newly
	# pressed steps; the rest of the stream is consumed but does nothing.
	_begin()
	var box := VBoxContainer.new()
	var r := PushRow.new()
	r.setup("Colour", PackedStringArray(["A", "B", "C", "D", "E", "F", "G", "H"]), 0)
	var right := Button.new()
	box.add_child(r)
	box.add_child(right)
	GameManager.add_child(box)
	r.focus_neighbor_right = r.get_path_to(right)
	r.grab_focus()

	# A push: one event crosses the deadzone, then the stream carries on past it.
	r.newly_pressed = true
	_stick(0.6)
	r.newly_pressed = false
	for v in [0.8, 1.0, 0.97, 1.0, 0.95]:
		_stick(v)
	assert_eq(r.index, 1, "six events, one push, one step")
	assert_eq(r.get_viewport().gui_get_focus_owner(), r, "and focus never left the row")

	# The next push steps again.
	r.newly_pressed = true
	_stick(0.7)
	r.newly_pressed = false
	_stick(1.0)
	assert_eq(r.index, 2, "a second push steps once more")
	_end([box])

func test_a_stick_push_steps_a_real_row_through_inputs_own_bookkeeping() -> void:
	# The production check, not the stand-in: with the action newly pressed in Input,
	# the event that crossed the deadzone steps the row once.
	_begin()
	var box := VBoxContainer.new()
	var r := _row("Colour", ["A", "B", "C"])
	box.add_child(r)
	GameManager.add_child(box)
	r.grab_focus()
	Input.action_press("ui_right")
	_stick(0.6)
	Input.action_release("ui_right")
	assert_eq(r.index, 1, "the first event of a push steps once")
	_end([box])

func test_a_held_stick_repeats_at_the_nav_repeat_cadence_not_per_motion_event() -> void:
	# While the stick stays pushed the row keeps stepping through GameManager's nav
	# repeat; motion events arriving every frame on top add nothing.
	_begin()
	var delta := 1.0 / 60.0
	var counts := []
	for with_events in [false, true]:
		var scope := VBoxContainer.new()
		var r := PushRow.new()
		r.setup("Colour", PackedStringArray(["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"]), 0)
		scope.add_child(r)
		GameManager.add_child(scope)
		GameManager.register_focus_scope(scope)
		GameManager.set_controller_mode_for_test(true)
		GameManager.update_focus_guard_for_test()
		r.grab_focus()
		Input.action_press("ui_right")
		var t := 0.0
		while t < 1.0:
			if with_events:
				_stick(1.0)
			GameManager.update_nav_repeat_for_test(delta)
			t += delta
		Input.action_release("ui_right")
		GameManager.update_nav_repeat_for_test(delta)
		counts.append(r.index)
		GameManager.unregister_focus_scope(scope)
		scope.free()
	assert_true(counts[0] >= 2, "the held stick repeats (index %d)" % counts[0])
	assert_eq(counts[1], counts[0], "and motion events every frame change nothing")
	GameManager._apply_input_mode(_saved_controller, _saved_keyboard)

func test_a_dpad_press_still_steps_once() -> void:
	# A button isn't a stream: every press steps, with no action state to consult.
	_begin()
	var box := VBoxContainer.new()
	var r := _row("Colour", ["A", "B", "C"])
	box.add_child(r)
	GameManager.add_child(box)
	r.grab_focus()
	_dpad(JOY_BUTTON_DPAD_RIGHT)
	assert_eq(r.index, 1, "d-pad right steps forward")
	_dpad(JOY_BUTTON_DPAD_LEFT)
	_dpad(JOY_BUTTON_DPAD_LEFT)
	assert_eq(r.index, 2, "d-pad left steps back and wraps")
	_end([box])

func test_up_and_down_still_move_between_rows() -> void:
	_begin()
	var box := VBoxContainer.new()
	var top := _row("One", ["A", "B"])
	var bottom := _row("Two", ["C", "D"])
	box.add_child(top)
	box.add_child(bottom)
	GameManager.add_child(box)
	top.focus_neighbor_bottom = top.get_path_to(bottom)
	bottom.focus_neighbor_top = bottom.get_path_to(top)
	top.grab_focus()
	_key(KEY_DOWN)
	assert_eq(top.get_viewport().gui_get_focus_owner(), bottom, "down reaches the next row")
	_key(KEY_UP)
	assert_eq(top.get_viewport().gui_get_focus_owner(), top, "up comes back")
	assert_eq(top.index + bottom.index, 0, "and neither row's value moved")
	_end([box])

func test_an_unfocused_row_ignores_left_and_right() -> void:
	_begin()
	var box := VBoxContainer.new()
	var r := _row("Colour", ["A", "B"])
	var other := Button.new()
	box.add_child(r)
	box.add_child(other)
	GameManager.add_child(box)
	other.grab_focus()
	_key(KEY_RIGHT)
	assert_eq(r.index, 0, "keys go to the focused control only")
	_end([box])

func test_the_guard_governs_the_row_but_not_its_arrows() -> void:
	_begin()
	var scope := Control.new()
	var r := _row("Colour", ["A", "B"])
	scope.add_child(r)
	GameManager.add_child(scope)
	GameManager.register_focus_scope(scope)

	GameManager.set_controller_mode_for_test(true)
	GameManager.update_focus_guard_for_test()
	assert_eq(r.focus_mode, Control.FOCUS_ALL, "controller mode makes the row focusable")
	for a in _arrows(r):
		assert_eq(a.focus_mode, Control.FOCUS_NONE, "but not its arrows")
	assert_eq(r.get_viewport().gui_get_focus_owner(), r, "the guard lands focus on the row")

	GameManager.set_controller_mode_for_test(false)
	GameManager.update_focus_guard_for_test()
	assert_eq(r.focus_mode, Control.FOCUS_NONE, "pure mouse mode makes it click-only like the other controls")
	_end([scope])

func test_holding_left_or_right_keeps_stepping_without_moving_focus() -> void:
	_begin()
	var scope := VBoxContainer.new()
	var above := Button.new()
	var r := _row("Colour", ["A", "B", "C", "D", "E", "F", "G", "H"])
	var below := Button.new()
	scope.add_child(above)
	scope.add_child(r)
	scope.add_child(below)
	GameManager.add_child(scope)
	GameManager.register_focus_scope(scope)
	GameManager.set_controller_mode_for_test(true)
	GameManager.update_focus_guard_for_test()
	r.grab_focus()

	var delta := 1.0 / 60.0
	Input.action_press("ui_right")
	var t := 0.0
	while t < 1.0:
		GameManager.update_nav_repeat_for_test(delta)
		t += delta
	Input.action_release("ui_right")
	GameManager.update_nav_repeat_for_test(delta)   # the next frame, so the hold clock clears
	assert_true(r.index >= 2, "a held right steps on past the first press (index %d)" % r.index)
	assert_eq(r.get_viewport().gui_get_focus_owner(), r, "and never moves focus off the row")

	var before := r.index
	Input.action_press("ui_left")
	t = 0.0
	while t < 1.0:
		GameManager.update_nav_repeat_for_test(delta)
		t += delta
	Input.action_release("ui_left")
	GameManager.update_nav_repeat_for_test(delta)
	assert_ne(r.index, before, "a held left steps back")
	assert_eq(r.get_viewport().gui_get_focus_owner(), r, "still on the row")
	_end([scope])

func test_an_icon_or_a_dot_shows_before_the_value() -> void:
	var r := _row("Cursor", ["A", "B"])
	assert_false(r._icon.visible, "no mark until one is set")
	assert_false(r._dot.visible, "neither icon nor dot")
	var tex := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	r.set_icon(tex)
	assert_true(r._icon.visible, "an icon shows")
	assert_eq(r._icon.texture, tex, "the one given")
	assert_false(r._dot.visible, "and no dot")

	r.set_swatch(Color("E0559E"))
	var style := r._dot.get_theme_stylebox("panel") as StyleBoxFlat
	assert_true(r._dot.visible, "a swatch shows a dot")
	assert_false(r._icon.visible, "in place of the icon")
	assert_eq(style.bg_color, Color("E0559E"), "in the colour given")
	assert_eq(style.border_width_left, 0, "plain by default")

	r.set_swatch(Color("1A1A1F"), true)
	assert_eq(style.border_width_left, 1, "a dark swatch gets its 1 px ring")
	assert_eq(style.border_color, CyclerRow.RING_COLOR, "in the light ring colour")
	r.set_swatch(Color("E0559E"))
	assert_eq(style.border_width_left, 0, "and the next, lighter one loses it")

	r.set_icon(null)
	assert_false(r._icon.visible, "no icon hides it")
	r.free()

func test_the_name_column_can_be_shared() -> void:
	var r := CyclerRow.new()
	r.setup("Cursor Shape", PackedStringArray(["A"]), 0, 190)
	assert_eq(r._name_label.custom_minimum_size.x, 190.0, "rows that sit together can share a name column")
	var plain := _row("Max FPS", ["A"])
	assert_eq(plain._name_label.custom_minimum_size.x, 0.0, "otherwise the name is as wide as its text")
	r.free()
	plain.free()
