extends TestSuite

## The on-screen keyboard panel (OnScreenKeyboard): its keys, the draft they edit, how it
## opens and closes as a focus scope of its own, and how it takes the pad's buttons and a
## real keyboard's keys.
##
## Each test puts its panel on a high CanvasLayer under GameManager (the root is busy while
## the runner sets up), and frees that layer at the end together with whatever input mode
## the test forced. Input goes in through the real pipeline (`push_input` on the root), and
## an InputReader added to GameManager BEFORE the layer hears only what the panel lets
## through: the engine calls `_input` in reverse tree order and stops at the first handler
## that marks the event handled.

func suite_name() -> String:
	return "OnScreenKeyboard"

## Records the pad buttons, keys and mouse buttons that reach it, which is everything a
## node behind the panel (a page, a menu) would have heard: presses in `heard`, releases
## of pad buttons and keys in `released`, every stick or trigger sample in `motion`.
class InputReader extends Node:
	var heard: Array = []
	var released: Array = []
	var motion: Array = []

	func _input(ev: InputEvent) -> void:
		if ev is InputEventJoypadMotion:
			motion.append(ev)
		if ev is InputEventJoypadButton or ev is InputEventKey or ev is InputEventMouseButton:
			if ev.pressed:
				heard.append(ev)
			elif not ev is InputEventMouseButton:
				released.append(ev)

# --- Setup ---------------------------------------------------------------------

## The bindings these tests read, so they hold whatever the player has remapped.
const _BOUND_ACTIONS := ["confirm", "cancel", "pause", "cursor_click", "move_up", "move_down",
	"move_left", "move_right", "ui_accept", "ui_cancel"]

var _layer: CanvasLayer
var _reader: InputReader
var _saved_controller := false
var _saved_keyboard := false
var _saved_bindings := {}

func _begin() -> void:
	_saved_controller = GameManager._controller_mode
	_saved_keyboard = GameManager._keyboard_nav
	_saved_bindings = {}
	for action: String in _BOUND_ACTIONS:
		_saved_bindings[action] = InputMap.action_get_events(action)
	InputMapConfig.reset_all_controller()   # the pad's stock buttons: A confirm, B cancel, Start pause
	_reader = InputReader.new()
	GameManager.add_child(_reader)
	_layer = CanvasLayer.new()
	_layer.layer = 150
	GameManager.add_child(_layer)

func _end() -> void:
	_layer.free()
	_reader.free()
	_put_bindings_back(_saved_bindings)
	GameManager._apply_input_mode(_saved_controller, _saved_keyboard)

func _put_bindings_back(bindings: Dictionary) -> void:
	for action: String in bindings:
		InputMap.action_erase_events(action)
		for ev: InputEvent in bindings[action]:
			InputMap.action_add_event(action, ev)

func _open(initial: String, max_length: int = 18) -> OnScreenKeyboard:
	var panel := OnScreenKeyboard.new()
	_layer.add_child(panel)
	panel.open(initial, max_length)
	return panel

## Presses a key the way a click or the highlight's Confirm does.
func _press(panel: OnScreenKeyboard, id: String) -> void:
	panel.key_button(id).pressed.emit()

func _text_named(panel: OnScreenKeyboard, node_name: String) -> String:
	return (panel.find_child(node_name, true, false) as Label).text

## Every Button under `node`.
func _buttons_under(node: Node) -> Array:
	var found: Array = []
	for child in node.get_children():
		if child is Button:
			found.append(child)
		found.append_array(_buttons_under(child))
	return found

## The texts of the keys sharing `id`'s row, left to right, joined with "|".
func _row_of(panel: OnScreenKeyboard, id: String) -> String:
	var texts: Array = []
	for key in panel.key_button(id).get_parent().get_children():
		texts.append((key as Button).text)
	return "|".join(texts)

## A frame lays containers out on a deferred call and none runs inside a test, so sort
## them here, top-down, the way the engine would.
func _lay_out(node: Node) -> void:
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child in node.get_children():
		_lay_out(child)

# --- Tests ---------------------------------------------------------------------

func test_opening_shows_the_current_name_and_its_count() -> void:
	_begin()
	var panel := _open("Couch", 18)
	assert_eq(panel.get_text(), "Couch", "the draft starts as the current name")
	assert_true(_text_named(panel, "NameText").begins_with("Couch"), "the name box shows it")
	assert_eq(_text_named(panel, "CountText"), "5 / 18", "the count reads length / cap")
	assert_eq(panel.process_mode, Node.PROCESS_MODE_ALWAYS, "it works while the tree is paused")
	assert_true(GameManager.has_focus_scope(panel), "opening makes it a focus scope of its own")
	_end()

func test_letters_type_lowercase_until_capitals_are_on() -> void:
	_begin()
	var panel := _open("")
	_press(panel, "Q")
	assert_eq(panel.get_text(), "q", "capitals start off")
	assert_eq(panel.key_button("W").text, "w", "a letter key shows the case it will type")
	panel.toggle_caps()
	assert_true(panel.caps, "capitals are on")
	assert_eq(panel.key_button("W").text, "W", "the keys relabel to capitals")
	_press(panel, "W")
	_press(panel, "E")
	assert_eq(panel.get_text(), "qWE", "capitals stay on for every letter until toggled (a lock)")
	panel.toggle_caps()
	_press(panel, "R")
	assert_eq(panel.get_text(), "qWEr", "toggled off, letters are lower case again")
	_press(panel, "shift")
	assert_true(panel.caps, "the shift key toggles capitals too")
	_end()

func test_space_delete_and_the_length_cap() -> void:
	_begin()
	var panel := _open("ab", 4)
	_press(panel, "space")
	assert_eq(panel.get_text(), "ab ", "the space key adds a space")
	_press(panel, "backspace")
	assert_eq(panel.get_text(), "ab", "the backspace key removes the last character")
	panel.delete_last()
	panel.delete_last()
	assert_eq(panel.get_text(), "", "delete_last empties the draft")
	panel.delete_last()
	assert_eq(panel.get_text(), "", "and does nothing on an empty draft")
	assert_eq(_text_named(panel, "CountText"), "0 / 4", "the count follows the deletes")
	for c in "abcd":
		panel.type_char(c)
	_press(panel, "Z")
	assert_eq(panel.get_text(), "abcd", "a letter at the cap adds nothing")
	_press(panel, "space")
	assert_eq(panel.get_text(), "abcd", "nor does a space")
	assert_eq(_text_named(panel, "CountText"), "4 / 4", "the count reads full")
	_end()

func test_the_symbols_page_swaps_only_the_letter_rows() -> void:
	_begin()
	var panel := _open("")
	panel.toggle_symbols()
	assert_true(panel.symbols, "the symbols page is on")
	assert_eq(panel.key_button("Q").text, "!", "the first letter key shows the first symbol")
	_press(panel, "Q")
	assert_eq(panel.get_text(), "!", "and types it")
	assert_eq(panel.key_button("'").text, "'", "the apostrophe key stays an apostrophe")
	_press(panel, "'")
	assert_eq(panel.get_text(), "!'", "and types the last of the second symbol row")
	assert_eq(panel.key_button("V").text, "]", "the third row follows the symbol rows key for key")
	assert_eq(panel.key_button("M").text, "$", "down to its last symbol")
	assert_eq(panel.key_button("-").text, "-", "the hyphen is on both pages")
	assert_eq(panel.key_button("1").text, "1", "the number row is not swapped")
	assert_eq(panel.key_button("symbols").text, "ABC", "the page key offers the way back")
	panel.toggle_symbols()
	assert_eq(panel.key_button("Q").text, "q", "toggling again brings the letters back")
	assert_eq(panel.key_button("symbols").text, "! ?", "and the page key its first label")
	_press(panel, "symbols")
	assert_true(panel.symbols, "the page key toggles the page")
	_end()

func test_done_and_cancel_report_once_and_let_go_of_the_highlight() -> void:
	_begin()
	GameManager.set_controller_mode_for_test(true)
	var panel := _open("Couch", 18)
	GameManager.update_focus_guard_for_test()
	var done_texts: Array = []
	var cancels := [0]
	panel.finished.connect(func(text: String) -> void: done_texts.append(text))
	panel.cancelled.connect(func() -> void: cancels[0] += 1)
	assert_true(GameManager.has_focus_scope(panel), "open: it is a focus scope")
	assert_eq(panel.get_viewport().gui_get_focus_owner(), panel.key_button("Q"), "the highlight is on its keys")
	panel.finish()
	panel.finish()
	assert_eq(done_texts, ["Couch"], "finish reports the draft once")
	assert_eq(cancels[0], 0, "and does not cancel")
	panel.cancel()
	assert_eq(cancels[0], 0, "a closed panel reports nothing more")
	assert_false(GameManager.has_focus_scope(panel), "closed: no longer a focus scope")
	# Gone from the guard's eyes at once, not a frame later when queue_free lands, so its next
	# tick hands the highlight to the page behind.
	assert_false(panel.is_visible_in_tree(), "closed: not visible")
	var holder := panel.get_viewport().gui_get_focus_owner()
	assert_true(holder == null or not panel.is_ancestor_of(holder), "closed: no key holds the focus")

	var second := _open("Couch", 18)
	var second_done: Array = []
	var second_cancels := [0]
	second.finished.connect(func(text: String) -> void: second_done.append(text))
	second.cancelled.connect(func() -> void: second_cancels[0] += 1)
	second.cancel()
	second.cancel()
	second.finish()
	assert_eq(second_cancels[0], 1, "cancel reports once")
	assert_eq(second_done.size(), 0, "and never finishes")
	assert_false(GameManager.has_focus_scope(second), "a cancelled panel is no focus scope either")

	var third := _open(" Hi ")
	var third_done: Array = []
	third.finished.connect(func(text: String) -> void: third_done.append(text))
	_press(third, "done")
	assert_eq(third_done, [" Hi "], "the Done key finishes, sending the draft as typed (the caller cleans it)")
	assert_false(GameManager.has_focus_scope(third), "and lets go of the focus scope")

	var fourth := _open("Couch")
	var fourth_done: Array = []
	var fourth_cancels := [0]
	fourth.finished.connect(func(text: String) -> void: fourth_done.append(text))
	fourth.cancelled.connect(func() -> void: fourth_cancels[0] += 1)
	_press(fourth, "cancel")
	assert_eq(fourth_cancels[0], 1, "the Cancel key cancels")
	assert_eq(fourth_done.size(), 0, "without finishing")
	assert_false(GameManager.has_focus_scope(fourth), "and lets go of the focus scope")
	_end()

func test_freeing_the_panel_unregisters_its_scope() -> void:
	# A page rebuild frees the panel without Done or Cancel.
	_begin()
	var panel := _open("Couch")
	assert_true(GameManager.has_focus_scope(panel), "registered while open")
	_layer.remove_child(panel)
	assert_false(GameManager.has_focus_scope(panel), "leaving the tree drops the scope")
	panel.free()
	_end()

func test_the_highlight_starts_on_q() -> void:
	_begin()
	GameManager.set_controller_mode_for_test(true)
	var panel := _open("")
	GameManager.update_focus_guard_for_test()
	assert_eq(panel.get_viewport().gui_get_focus_owner(), panel.key_button("Q"), "the highlight starts on Q")
	_end()

func test_every_key_is_a_themed_button_in_the_mockup_rows() -> void:
	_begin()
	var panel := _open("")
	var keys := _buttons_under(panel)
	assert_eq(keys.size(), 44, "four rows of ten plus the four bottom keys")
	var themed := true
	var tall_enough := true
	for key: Button in keys:
		themed = themed and key.has_theme_stylebox_override("normal") and key.has_theme_stylebox_override("focus")
		tall_enough = tall_enough and key.custom_minimum_size.y >= 32
	assert_true(themed, "every key has the BattleUITheme button styles")
	assert_true(tall_enough, "every key is at least 32 px tall")

	assert_eq(_row_of(panel, "1"), "|".join("1234567890".split("")), "the number row")
	assert_eq(_row_of(panel, "Q"), "|".join("qwertyuiop".split("")), "the first letter row")
	assert_eq(_row_of(panel, "A"), "|".join("asdfghjkl'".split("")), "the second letter row")
	assert_eq(_row_of(panel, "Z"), "⇧|" + "|".join("zxcvbnm-".split("")) + "|⌫", "the third has shift and backspace at its ends")
	assert_eq(_row_of(panel, "space"), "! ?|Space|✕ Cancel|✓ Done", "the bottom row")
	assert_eq(panel.key_button("shift").get_parent(), panel.key_button("Z").get_parent(), "shift shares Z's row")
	assert_eq(panel.key_button("backspace").get_parent(), panel.key_button("-").get_parent(), "backspace shares the hyphen's row")

	assert_eq(panel.key_button("space").size_flags_stretch_ratio, 2.0 * panel.key_button("cancel").size_flags_stretch_ratio,
		"Space is given twice Cancel's share of the row")
	assert_eq(panel.key_button("symbols").size_flags_stretch_ratio, panel.key_button("cancel").size_flags_stretch_ratio,
		"the page key is as wide as Cancel")
	assert_eq(panel.key_button("done").size_flags_stretch_ratio, panel.key_button("cancel").size_flags_stretch_ratio,
		"and so is Done")

	_lay_out(panel)
	var space := panel.key_button("space")
	var cancel := panel.key_button("cancel")
	assert_true(cancel.size.x > 0.0, "the bottom row has been laid out")
	assert_near(space.size.x, 2.0 * cancel.size.x, OnScreenKeyboard.KEY_GAP, "Space is twice as wide as Cancel (give or take a gap)")
	assert_near(panel.key_button("symbols").get_global_rect().position.x, panel.key_button("1").get_global_rect().position.x, 1.0,
		"the bottom row starts where the grid does")
	assert_near(panel.key_button("done").get_global_rect().end.x, panel.key_button("0").get_global_rect().end.x, 1.0,
		"and ends where it does")
	_end()

# --- Input helpers -------------------------------------------------------------

## A pad button into the root, as the engine delivers it.
func _pad(button: JoyButton, pressed := true) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = pressed
	GameManager.get_viewport().push_input(ev)

## A key into the root. A printable key carries its `unicode`, as a real one does.
func _key(keycode: Key, unicode := 0, pressed := true, echo := false, ctrl := false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.unicode = unicode
	ev.pressed = pressed
	ev.echo = echo
	ev.ctrl_pressed = ctrl
	GameManager.get_viewport().push_input(ev)

## A stick or trigger sample into the root.
func _motion(axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	GameManager.get_viewport().push_input(ev)

func _focus_owner() -> Control:
	return GameManager.get_viewport().gui_get_focus_owner()

## Records what the panel reports.
class Outcome extends RefCounted:
	var finished: Array = []
	var cancels := 0

func _watch(panel: OnScreenKeyboard) -> Outcome:
	var outcome := Outcome.new()
	panel.finished.connect(func(text: String) -> void: outcome.finished.append(text))
	panel.cancelled.connect(func() -> void: outcome.cancels += 1)
	return outcome

# --- The pad's buttons ---------------------------------------------------------

func test_pad_buttons_edit_and_close() -> void:
	_begin()
	var panel := _open("Couch", 18)
	var outcome := _watch(panel)
	_pad(JOY_BUTTON_B)
	assert_eq(panel.get_text(), "Couc", "the player's Cancel (B) deletes the last letter")
	_pad(JOY_BUTTON_Y)
	assert_eq(panel.get_text(), "Couc ", "Y adds a space")
	assert_false(panel.caps, "capitals start off")
	_pad(JOY_BUTTON_LEFT_SHOULDER)
	assert_true(panel.caps, "LB toggles capitals on")
	_pad(JOY_BUTTON_LEFT_SHOULDER)
	assert_false(panel.caps, "and off again")
	assert_eq(outcome.finished.size() + outcome.cancels, 0, "none of that closed the panel")
	_pad(JOY_BUTTON_START)
	assert_eq(outcome.finished, ["Couc "], "the player's Pause (Start) finishes, sending the draft as typed")
	assert_eq(outcome.cancels, 0, "and does not cancel")
	assert_false(GameManager.has_focus_scope(panel), "and closes it")

	var second := _open("Couch", 18)
	var second_outcome := _watch(second)
	_pad(JOY_BUTTON_X)
	assert_eq(second_outcome.cancels, 1, "X closes without saving")
	assert_eq(second_outcome.finished.size(), 0, "and finishes nothing")
	assert_eq(second.get_text(), "Couch", "the draft is untouched")
	assert_eq(_reader.heard.size(), 0, "no node behind the panel heard any of those presses")
	_end()

func test_confirm_presses_the_highlighted_key_and_directions_move_it() -> void:
	_begin()
	GameManager.set_controller_mode_for_test(true)
	var panel := _open("")
	GameManager.update_focus_guard_for_test()
	_lay_out(panel)
	assert_eq(_focus_owner(), panel.key_button("Q"), "the highlight starts on Q")
	_pad(JOY_BUTTON_A)
	_pad(JOY_BUTTON_A, false)
	assert_eq(panel.get_text(), "q", "the player's Confirm (A) presses the highlighted key, which types its letter")
	assert_eq(_reader.heard.size(), 1, "the press was left for the key to hear")
	_pad(JOY_BUTTON_DPAD_RIGHT)
	assert_eq(_focus_owner(), panel.key_button("W"), "the d-pad moves the highlight")
	assert_eq(panel.get_text(), "q", "and types nothing")
	_pad(JOY_BUTTON_DPAD_RIGHT, false)
	assert_eq(_reader.heard.size(), 2, "a direction passes through")
	_end()

func test_releases_pass_through_and_change_nothing() -> void:
	_begin()
	var panel := _open("Couch")
	var outcome := _watch(panel)
	var released: Array = [JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_START, JOY_BUTTON_LEFT_SHOULDER,
		JOY_BUTTON_RIGHT_SHOULDER]
	for button: JoyButton in released:
		_pad(button, false)
	assert_eq(_reader.released.size(), released.size(), "every one of the pad releases passed through")
	assert_eq(panel.get_text(), "Couch", "a release does nothing")
	assert_false(panel.caps, "not even LB's")
	assert_eq(outcome.finished.size() + outcome.cancels, 0, "and closes nothing")
	_key(KEY_ESCAPE, 0, false)
	_key(KEY_BACKSPACE, 0, false)
	assert_eq(_reader.released.size(), released.size() + 2, "and the keys' did too")
	assert_eq(outcome.finished.size() + outcome.cancels, 0, "nor does a key's")
	assert_true(GameManager.has_focus_scope(panel), "the panel is still open")
	_end()

func test_holding_the_pad_delete_keeps_deleting() -> void:
	_begin()
	var panel := _open("abcdef", 18)
	panel.step_hold(true, 0.016)
	assert_eq(panel.get_text(), "abcdef", "the first frame held only starts the clock")
	panel.step_hold(true, 0.40)
	assert_eq(panel.get_text(), "abcdef", "before the initial delay nothing repeats")
	panel.step_hold(true, 0.05)
	assert_eq(panel.get_text(), "abcde", "past the initial delay one letter goes")
	panel.step_hold(true, 0.16)
	assert_eq(panel.get_text(), "abcd", "and another at the repeat interval")
	panel.step_hold(false, 0.016)
	panel.step_hold(true, 0.016)
	panel.step_hold(true, 0.40)
	assert_eq(panel.get_text(), "abcd", "letting go starts the delay over")
	for frame in 40:
		panel._process(0.1)
	assert_eq(panel.get_text(), "abcd", "frames with no pad holding Cancel / Back delete nothing")
	_end()

func test_other_pad_buttons_stop_at_the_panel() -> void:
	_begin()
	var panel := _open("Couch")
	var outcome := _watch(panel)
	_pad(JOY_BUTTON_RIGHT_SHOULDER)
	_pad(JOY_BUTTON_BACK)
	_pad(JOY_BUTTON_LEFT_STICK)
	assert_eq(panel.get_text(), "Couch", "RB, Back and L3 change nothing")
	assert_eq(_reader.heard.size(), 0, "and nothing behind the panel heard them")
	assert_eq(outcome.finished.size() + outcome.cancels, 0, "nor did they close it")
	assert_true(GameManager.has_focus_scope(panel), "the panel is still open")
	_end()

func test_a_closed_panel_lets_input_through() -> void:
	# The panel frees itself at the end of the frame, so it lingers (hidden) after Done.
	_begin()
	var panel := _open("Couch")
	var outcome := _watch(panel)
	_pad(JOY_BUTTON_START)
	assert_eq(outcome.finished, ["Couch"], "Start finished it")
	assert_eq(_reader.heard.size(), 0, "and nothing behind it heard that press")
	_pad(JOY_BUTTON_START)
	_pad(JOY_BUTTON_B)
	_key(KEY_C, 99)
	assert_eq(_reader.heard.size(), 3, "afterwards the dying panel takes nothing: all three reached the reader")
	assert_eq(outcome.finished, ["Couch"], "it reported once")
	assert_eq(panel.get_text(), "Couch", "and its draft is untouched")
	_end()

# --- A real keyboard -----------------------------------------------------------

func test_a_real_keyboard_types_into_the_panel() -> void:
	_begin()
	GameManager.set_controller_mode_for_test(true)
	var panel := _open("ab")
	GameManager.update_focus_guard_for_test()
	_lay_out(panel)
	var outcome := _watch(panel)
	assert_eq(_focus_owner(), panel.key_button("Q"), "the highlight is on Q")
	_key(KEY_C, 99)
	assert_eq(panel.get_text(), "abc", "a printable key types its character")
	_key(KEY_SPACE, 32)
	assert_eq(panel.get_text(), "abc ", "Space types a space and does not press the highlighted Q")
	_key(KEY_BACKSPACE)
	assert_eq(panel.get_text(), "abc", "Backspace deletes")
	_key(KEY_BACKSPACE, 0, true, true)
	assert_eq(panel.get_text(), "ab", "and so does its echo, so holding it keeps deleting")
	assert_eq(_reader.heard.size(), 0, "nothing behind the panel heard c, Space or Backspace")
	_key(KEY_RIGHT)
	assert_eq(_focus_owner(), panel.key_button("W"), "an arrow key moves the highlight")
	assert_eq(_reader.heard.size(), 1, "the arrow passed through")
	assert_eq(panel.get_text(), "ab", "and typed nothing")
	_key(KEY_ENTER, 13)
	assert_eq(outcome.finished, ["ab"], "Enter finishes (it does not press the highlighted key)")
	assert_eq(outcome.cancels, 0, "and does not cancel")

	var second := _open("ab")
	var second_outcome := _watch(second)
	_key(KEY_ESCAPE)
	assert_eq(second_outcome.cancels, 1, "Esc cancels")
	assert_eq(second_outcome.finished.size(), 0, "and finishes nothing")

	var third := _open("ab")
	var third_outcome := _watch(third)
	_key(KEY_KP_ENTER, 13)
	assert_eq(third_outcome.finished, ["ab"], "the keypad's Enter finishes too")
	assert_eq(_reader.heard.size(), 1, "still only the arrow reached the reader: not Enter, Esc or the keypad's Enter")
	_end()

func test_capitals_and_symbols_type_as_the_keyboard_sends_them() -> void:
	_begin()
	var panel := _open("")
	_key(KEY_A, 65)
	_key(KEY_1, 33)
	_key(KEY_APOSTROPHE, 39)
	assert_eq(panel.get_text(), "A!'", "the keyboard's own case and symbols are typed, whatever the on-screen capitals say")
	assert_false(panel.caps, "and the capitals lock is untouched")
	_end()

func test_keys_that_are_not_text_are_swallowed() -> void:
	_begin()
	var panel := _open("ab")
	var outcome := _watch(panel)
	_key(KEY_C, 99, true, false, true)   # Ctrl+C
	var meta := InputEventKey.new()
	meta.keycode = KEY_V
	meta.physical_keycode = KEY_V
	meta.unicode = 118
	meta.pressed = true
	meta.meta_pressed = true
	GameManager.get_viewport().push_input(meta)
	var alt := meta.duplicate() as InputEventKey
	alt.meta_pressed = false
	alt.alt_pressed = true
	GameManager.get_viewport().push_input(alt)
	_key(KEY_F1)
	_key(KEY_TAB, 9)
	_key(KEY_SHIFT)
	_key(KEY_DELETE, 127)
	assert_eq(panel.get_text(), "ab", "Ctrl, Cmd and Alt chords, function keys, Tab, Shift on its own and Delete type nothing")
	assert_eq(_reader.heard.size(), 0, "and none of them reached what is behind the panel")
	assert_eq(outcome.finished.size() + outcome.cancels, 0, "or closed the panel")
	_end()

func test_the_mouse_is_left_alone() -> void:
	_begin()
	var panel := _open("ab")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.position = Vector2(5, 5)
	GameManager.get_viewport().push_input(click)
	assert_eq(_reader.heard.size(), 1, "a mouse press passes through the panel")
	assert_eq(panel.get_text(), "ab", "and types nothing")
	assert_true(GameManager.has_focus_scope(panel), "or closes the panel")
	assert_false(GameManager.is_controller_mode(), "it is the mouse's mode, left to GameManager")
	_end()

# --- The player's own buttons --------------------------------------------------

## Makes `button` the pad half of Confirm (A stops being Confirm), the way the Controller
## page does, mirrored onto ui_accept.
func _bind_confirm_to(button: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMapConfig.rebind_controller("confirm", ev)

func test_a_remapped_confirm_on_x_types_instead_of_cancelling() -> void:
	_begin()
	GameManager.set_controller_mode_for_test(true)
	_bind_confirm_to(JOY_BUTTON_X)
	var panel := _open("")
	GameManager.update_focus_guard_for_test()
	var outcome := _watch(panel)
	assert_eq(_focus_owner(), panel.key_button("Q"), "the highlight is on Q")
	_pad(JOY_BUTTON_X)
	_pad(JOY_BUTTON_X, false)
	assert_eq(panel.get_text(), "q", "X is the player's Confirm now, so it types the highlighted key")
	assert_eq(outcome.cancels, 0, "and does not throw the name away")
	assert_true(GameManager.has_focus_scope(panel), "the panel is still open")
	var entries := OnScreenKeyboard.legend_entries()
	assert_eq(entries[0], ["X / Square", "Type"], "the legend says X types")
	var verbs: Array = []
	for entry: Array in entries:
		verbs.append(entry[1])
	assert_false(verbs.has("Cancel"), "and does not promise \"X Cancel\"")
	_pad(JOY_BUTTON_A)
	assert_eq(panel.get_text(), "q", "A is no longer Confirm; as nothing else in the panel, it is swallowed")
	_end()
	GameManager.input_profiles.sync_from_input_map()   # as the stock bindings are back

func test_a_remapped_cancel_or_pause_wins_over_the_fixed_buttons() -> void:
	_begin()
	var panel := _open("abc")
	var outcome := _watch(panel)
	var cancel_on_y := InputEventJoypadButton.new()
	cancel_on_y.button_index = JOY_BUTTON_Y
	InputMapConfig.rebind_controller("cancel", cancel_on_y)
	_pad(JOY_BUTTON_Y)
	assert_eq(panel.get_text(), "ab", "Y is the player's Cancel now, so it deletes rather than adding a space")
	var pause_on_lb := InputEventJoypadButton.new()
	pause_on_lb.button_index = JOY_BUTTON_LEFT_SHOULDER
	InputMapConfig.rebind_controller("pause", pause_on_lb)
	_pad(JOY_BUTTON_LEFT_SHOULDER)
	assert_false(panel.caps, "LB is the player's Pause now, so it does not toggle capitals")
	assert_eq(outcome.finished, ["ab"], "it finishes")
	var entries := OnScreenKeyboard.legend_entries()
	var verbs: Array = []
	for entry: Array in entries:
		verbs.append(entry[1])
	assert_eq(verbs, ["Type", "Delete", "Cancel", "Done"], "the legend drops Space and Caps, whose buttons were taken")
	_end()
	GameManager.input_profiles.sync_from_input_map()

func test_the_legend_names_the_players_buttons() -> void:
	_begin()
	assert_eq(OnScreenKeyboard.legend_entries(), [
		["A / Cross", "Type"], ["B / Circle", "Delete"], ["X / Square", "Cancel"],
		["Y / Triangle", "Space"], ["LB / L1", "Caps"], ["Start / Options", "Done"]],
		"the stock buttons, in the order the legend reads")
	var cancel_on_rb := InputEventJoypadButton.new()
	cancel_on_rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	InputMapConfig.rebind_controller("cancel", cancel_on_rb)
	var entries := OnScreenKeyboard.legend_entries()
	assert_eq(entries[1], ["RB / R1", "Delete"], "Delete follows the player's Cancel binding")
	_end()
	GameManager.input_profiles.sync_from_input_map()

func test_the_legend_label_shows_the_entries_with_the_names_picked_out() -> void:
	_begin()
	var panel := _open("")
	var legend := panel.find_child("LegendText", true, false) as RichTextLabel
	assert_true(legend != null, "the panel has a legend")
	if legend == null:
		_end()
		return
	var text := legend.get_parsed_text()
	for entry: Array in OnScreenKeyboard.legend_entries():
		assert_true(text.contains(entry[0]) and text.contains(entry[1]), "the legend reads %s %s" % entry)
	assert_true(text.contains("\n"), "the legend runs to two lines")
	assert_false(text.strip_edges().contains("\n\n"), "and no more")
	assert_true(legend.text.contains(BattleUITheme.TEXT_SUBTITLE.to_html(false)), "the button names are in the subtitle colour")
	assert_eq(legend.get_theme_color("default_color"), SettingsScreen.NOTE_COLOR, "the rest is in the note colour")
	assert_eq(legend.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the legend takes no clicks")
	_lay_out(panel)
	assert_true(legend.size.y <= 2.0 * (OnScreenKeyboard.LEGEND_FONT_SIZE + 6), "laid out, it is two lines tall, not a screen tall (%s)" % legend.size.y)
	assert_true(legend.get_combined_minimum_size().x <= OnScreenKeyboard.PANEL_WIDTH - 36, "and never wider than the panel's inside, so it cannot widen it")
	assert_true(legend.get_parent().get_parent().size.y < GameManager.get_viewport().get_visible_rect().size.y, "the panel with its legend fits the screen")
	_end()

# --- Which mode a pad press brings back ----------------------------------------

func test_buttons_the_panel_takes_still_switch_to_the_highlight() -> void:
	_begin()
	GameManager.set_controller_mode_for_test(false)
	var panel := _open("Couch")
	assert_false(GameManager.focus_nav_active(), "pure mouse mode: no highlight")
	_pad(JOY_BUTTON_B)
	assert_eq(panel.get_text(), "Couc", "the panel took B")
	assert_true(GameManager.is_controller_mode(), "and B still brought the highlight back, as the pad's mode")
	GameManager.set_controller_mode_for_test(false)
	_key(KEY_C, 99)
	assert_eq(panel.get_text(), "Coucc", "the panel took the key")
	assert_true(GameManager.focus_nav_active(), "and the key still brought the highlight back")
	assert_false(GameManager.is_controller_mode(), "as the keyboard's mode, not the pad's")
	GameManager.set_controller_mode_for_test(false)
	_pad(JOY_BUTTON_RIGHT_SHOULDER)
	assert_true(GameManager.is_controller_mode(), "even a button that does nothing here does")
	_end()

func test_note_input_device_is_the_mode_switch_and_the_activity_stamps() -> void:
	_begin()
	var kept_kb := GameManager._last_kb_ms
	var kept_mouse := GameManager._last_mouse_ms
	GameManager._last_kb_ms = -100000
	GameManager._last_mouse_ms = -100000

	assert_eq(GameManager.keyboard_status_text(), "No external keyboard found", "no key yet")
	assert_eq(GameManager.mouse_status_text(), "No external mouse found", "no mouse yet")
	GameManager.set_controller_mode_for_test(true)
	GameManager.note_input_device(InputEventKey.new())
	assert_true(GameManager.focus_nav_active(), "a key leaves the highlight on")
	assert_false(GameManager.is_controller_mode(), "as the keyboard's")
	assert_eq(GameManager.keyboard_status_text(), "Keyboard detected", "and stamps the keyboard")

	var click := InputEventMouseButton.new()
	GameManager.note_input_device(click)
	assert_false(GameManager.focus_nav_active(), "a mouse button is pure mouse mode")
	assert_eq(GameManager.mouse_status_text(), "Mouse detected", "and stamps the mouse")

	GameManager._last_mouse_ms = -100000
	GameManager.note_input_device(InputEventMouseMotion.new())
	assert_eq(GameManager.mouse_status_text(), "Mouse detected", "so does a mouse move")
	GameManager.note_input_device(InputEventMagnifyGesture.new())
	assert_false(GameManager.focus_nav_active(), "and a trackpad gesture")

	var release := InputEventJoypadButton.new()
	release.pressed = false
	GameManager.note_input_device(release)
	assert_false(GameManager.is_controller_mode(), "a pad release is not use")
	var press := InputEventJoypadButton.new()
	press.pressed = true
	GameManager.note_input_device(press)
	assert_true(GameManager.is_controller_mode(), "a pad press is")

	GameManager.set_controller_mode_for_test(false)
	var light := InputEventJoypadMotion.new()
	light.axis_value = 0.4
	GameManager.note_input_device(light)
	assert_false(GameManager.is_controller_mode(), "a stick nudged to under half is not")
	var hard := InputEventJoypadMotion.new()
	hard.axis_value = -0.8
	GameManager.note_input_device(hard)
	assert_true(GameManager.is_controller_mode(), "a stick pushed past half is, either way")

	GameManager._last_kb_ms = kept_kb
	GameManager._last_mouse_ms = kept_mouse
	_end()

func test_game_manager_input_runs_the_same_switch() -> void:
	# GameManager._input is now a call to note_input_device; an event nothing handles still switches.
	_begin()
	GameManager.set_controller_mode_for_test(false)
	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_START
	press.pressed = true
	GameManager.get_viewport().push_input(press)
	assert_true(GameManager.is_controller_mode(), "a pad press nothing took reaches GameManager and switches the mode")
	_key(KEY_F1)
	assert_true(GameManager.focus_nav_active() and not GameManager.is_controller_mode(), "and so does a key")
	_end()

# --- A trigger bound to Cancel / Back or Pause / Menu ---------------------------------

## Makes `axis` (pulled fully, +1) the whole of `action`'s pad binding, mirrored onto
## ui_accept / ui_cancel by InputMapConfig.
func _bind_axis(action: String, axis: JoyAxis) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = 1.0
	InputMapConfig.rebind_controller(action, ev)

func test_a_trigger_bound_to_cancel_deletes_once_per_pull_and_is_swallowed() -> void:
	_begin()
	_bind_axis("cancel", JOY_AXIS_TRIGGER_LEFT)
	var panel := _open("abcdef")
	var outcome := _watch(panel)
	_motion(JOY_AXIS_TRIGGER_LEFT, 0.6)
	_motion(JOY_AXIS_TRIGGER_LEFT, 0.9)
	_motion(JOY_AXIS_TRIGGER_LEFT, 1.0)
	assert_eq(panel.get_text(), "abcde", "a pull of three samples deletes one letter, on the first")
	assert_eq(_reader.motion.size(), 0, "and nothing behind the panel heard any of the samples")
	assert_true(panel._cancel_held(), "the hold counts the trigger as Cancel held")
	_motion(JOY_AXIS_TRIGGER_LEFT, 0.0)
	assert_eq(_reader.motion.size(), 0, "nor the sample that lets it go")
	assert_eq(panel.get_text(), "abcde", "which deletes nothing")
	assert_false(panel._cancel_held(), "and ends the hold")
	_motion(JOY_AXIS_TRIGGER_LEFT, 0.8)
	assert_eq(panel.get_text(), "abcd", "the next pull deletes again")
	_motion(JOY_AXIS_TRIGGER_LEFT, 0.0)
	assert_eq(_reader.motion.size(), 0, "still nothing behind the panel heard it")
	# A light touch is not a press, and takes nothing (nor is it any press for what is behind).
	_motion(JOY_AXIS_TRIGGER_LEFT, 0.3)
	assert_eq(panel.get_text(), "abcd", "a pull under the threshold deletes nothing")
	assert_eq(outcome.finished.size() + outcome.cancels, 0, "none of it closed the panel")
	# The left stick's directions still walk the highlight.
	var heard_before := _reader.motion.size()
	_motion(JOY_AXIS_LEFT_X, 0.8)
	assert_eq(_reader.motion.size(), heard_before + 1, "a left-stick sample passes through")
	assert_eq(panel.get_text(), "abcd", "and changes nothing")
	_end()
	GameManager.input_profiles.sync_from_input_map()

func test_a_trigger_bound_to_pause_finishes_once_and_the_hold_goes_no_further() -> void:
	_begin()
	_bind_axis("pause", JOY_AXIS_TRIGGER_RIGHT)
	var panel := _open("abc")
	var outcome := _watch(panel)
	_motion(JOY_AXIS_TRIGGER_RIGHT, 0.6)
	assert_eq(outcome.finished, ["abc"], "the first sample past the threshold finishes")
	assert_false(panel.is_queued_for_deletion(), "the panel stays until the trigger is let go, to take the rest of the hold")
	_motion(JOY_AXIS_TRIGGER_RIGHT, 0.9)
	_motion(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	assert_eq(outcome.finished, ["abc"], "it finished once")
	assert_eq(outcome.cancels, 0, "and did not cancel")
	assert_eq(_reader.motion.size(), 0, "no node behind the panel (the pause handler, say) heard the rest of the hold")
	_motion(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	assert_eq(_reader.motion.size(), 0, "nor the sample that lets it go")
	assert_true(panel.is_queued_for_deletion(), "which frees the panel")
	_motion(JOY_AXIS_TRIGGER_RIGHT, 0.9)
	assert_eq(_reader.motion.size(), 1, "and a pull after that is for whoever is behind")
	assert_eq(outcome.finished, ["abc"], "the finished panel reports nothing more")
	_end()
	GameManager.input_profiles.sync_from_input_map()

func test_a_trigger_bound_to_confirm_passes_through() -> void:
	_begin()
	_bind_axis("confirm", JOY_AXIS_TRIGGER_RIGHT)
	var panel := _open("ab")
	var outcome := _watch(panel)
	_motion(JOY_AXIS_TRIGGER_RIGHT, 0.9)
	_motion(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	assert_eq(_reader.motion.size(), 2, "Confirm on a trigger is left to the highlighted key, as the button is")
	assert_eq(outcome.finished.size() + outcome.cancels, 0, "it closes nothing")
	assert_true(GameManager.has_focus_scope(panel), "the panel is still open")
	_end()
	GameManager.input_profiles.sync_from_input_map()
