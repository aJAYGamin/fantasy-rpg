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
