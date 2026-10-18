extends TestSuite

## The on-screen keyboard panel (OnScreenKeyboard): its keys, the draft they edit, and how
## it opens and closes as a focus scope of its own.
##
## Each test puts its panel on a high CanvasLayer under GameManager (the root is busy while
## the runner sets up), and frees that layer at the end together with whatever input mode
## the test forced.

func suite_name() -> String:
	return "OnScreenKeyboard"

# --- Setup ---------------------------------------------------------------------

var _layer: CanvasLayer
var _saved_controller := false
var _saved_keyboard := false

func _begin() -> void:
	_saved_controller = GameManager._controller_mode
	_saved_keyboard = GameManager._keyboard_nav
	_layer = CanvasLayer.new()
	_layer.layer = 150
	GameManager.add_child(_layer)

func _end() -> void:
	_layer.free()
	GameManager._apply_input_mode(_saved_controller, _saved_keyboard)

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
