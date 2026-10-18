extends TestSuite

## DialogueManager (autoload) branching-tree engine: linear play_lines, branching
## play() with choices, the advance/choose flow, and the state getters. The global
## DialogueBox is a passive signal listener and isn't exercised here. Every test
## fully ends its conversation so no state leaks into the next.

const OverworldScene := preload("res://scripts/overworld/OverworldScene.gd")

func suite_name() -> String:
	return "Dialogue"

func test_play_lines_linear() -> void:
	DialogueManager.play_lines("Bob", ["one", "two", "three"])
	assert_true(DialogueManager.is_active(), "dialogue active after play_lines")
	assert_eq(DialogueManager.current_speaker(), "Bob", "speaker set")
	assert_eq(DialogueManager.current_text(), "one", "first line shown")
	assert_false(DialogueManager.current_has_choices(), "a linear line has no choices")
	DialogueManager.advance()
	assert_eq(DialogueManager.current_text(), "two", "advanced to the second line")
	DialogueManager.advance()
	assert_eq(DialogueManager.current_text(), "three", "advanced to the third line")
	DialogueManager.advance()
	assert_false(DialogueManager.is_active(), "dialogue ends after the last line")

func test_play_branching_choose() -> void:
	var nodes := [
		{"id": "start", "speaker": "Elder", "text": "Help us?",
			"choices": [{"label": "Yes", "next": "yes"}, {"label": "No", "next": null}]},
		{"id": "yes", "speaker": "Elder", "text": "Thank you!", "next": null},
	]
	DialogueManager.play(nodes)
	assert_eq(DialogueManager.current_text(), "Help us?", "branch entry shown")
	assert_true(DialogueManager.current_has_choices(), "entry presents choices")
	assert_eq(DialogueManager.current_choices().size(), 2, "two choices offered")
	DialogueManager.choose(0)
	assert_eq(DialogueManager.current_text(), "Thank you!", "chose Yes -> follow-up line")
	DialogueManager.advance()
	assert_false(DialogueManager.is_active(), "follow-up ends the conversation")

func test_choice_with_null_next_ends() -> void:
	DialogueManager.play([
		{"id": "start", "speaker": "Guard", "text": "Move along.",
			"choices": [{"label": "Okay", "next": null}]},
	])
	DialogueManager.choose(0)
	assert_false(DialogueManager.is_active(), "a null-next choice ends dialogue")

func test_advance_ignored_on_choice_node() -> void:
	DialogueManager.play([
		{"id": "start", "speaker": "Q", "text": "Pick:",
			"choices": [{"label": "A", "next": null}, {"label": "B", "next": null}]},
	])
	DialogueManager.advance()   # advance must do nothing on a choice node
	assert_true(DialogueManager.is_active(), "advance() does not skip a choice node")
	assert_true(DialogueManager.current_has_choices(), "still awaiting a choice")
	DialogueManager.choose(1)
	assert_false(DialogueManager.is_active(), "choosing resolves it")

func test_play_replaces_previous_tree() -> void:
	DialogueManager.play_lines("A", ["first convo"])
	DialogueManager.end_dialogue()
	DialogueManager.play_lines("B", ["second convo"])
	assert_eq(DialogueManager.current_speaker(), "B", "new conversation replaces the old tree")
	assert_eq(DialogueManager.current_text(), "second convo", "shows the new line, no stale ids")
	DialogueManager.advance()
	assert_false(DialogueManager.is_active(), "ends cleanly")

func test_out_of_range_choice_is_noop() -> void:
	DialogueManager.play([
		{"id": "start", "speaker": "Q", "text": "Pick:",
			"choices": [{"label": "A", "next": null}]},
	])
	DialogueManager.choose(5)   # out of range
	assert_true(DialogueManager.is_active(), "out-of-range choice is ignored")
	DialogueManager.choose(0)
	assert_false(DialogueManager.is_active(), "a valid choice then resolves it")

# --- the pause key during a conversation --------------------------------------

func test_the_pause_key_waits_for_a_conversation_to_end() -> void:
	# The dialogue box (layer 50) draws above the pause menu (layer 10): opened
	# mid-conversation, the box covered the menu's lower buttons, and a click on it
	# advanced the talk underneath. A conversation is modal (the player can't walk,
	# the clock stops), so the pause key now waits for it to end.
	DialogueManager.play_lines("Bob", ["one"])
	assert_false(OverworldScene.pause_menu_allowed(false, false, DialogueManager.is_active()),
		"no pause menu while someone is talking")
	DialogueManager.advance()
	assert_false(DialogueManager.is_active(), "the conversation is over")
	assert_true(OverworldScene.pause_menu_allowed(false, false, DialogueManager.is_active()),
		"and then the pause key opens the menu")

# --- clicking the box ---------------------------------------------------------

## A left press and release pushed into the root at `spot` (root-viewport pixels), as
## the themed cursor pushes the mouse and the stick's Cursor Click.
func _click_at(spot: Vector2) -> void:
	var root := GameManager.get_tree().root
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = spot
		ev.global_position = spot
		root.push_input(ev, true)

func test_a_click_on_the_dialogue_box_advances_it() -> void:
	# The box is where a player clicks (with the mouse, or the stick cursor's Cursor
	# Click). Its panel used to stop the click, so it never reached the advance; only a
	# click elsewhere on the screen moved the conversation on.
	var kept_controller: bool = GameManager._controller_mode
	var kept_keyboard: bool = GameManager._keyboard_nav
	# DialogueManager makes the global box on a deferred call, after the tests have run,
	# so build one the same way (a child of the manager) if it isn't there yet.
	var box = DialogueManager._box
	var made := box == null
	if made:
		box = load("res://scripts/dialogue/DialogueBox.gd").new()
		DialogueManager.add_child(box)
	DialogueManager.play_lines("Bob", ["one", "two", "three"])
	box._finish_typing()   # the line has finished typing out
	var panel: Control = box._root.get_child(0)
	_click_at(panel.get_global_rect().get_center())
	assert_eq(DialogueManager.current_text(), "two", "a click on the box shows the next line")
	box._finish_typing()
	_click_at(panel.get_global_rect().position + Vector2(6, 6))   # the box's padding, outside the text
	assert_eq(DialogueManager.current_text(), "three", "so does a click on the box's edge")

	# A revealed choice is still picked with its button, which keeps taking clicks.
	DialogueManager.play([
		{"id": "q", "speaker": "Bob", "text": "Well?", "choices": [
			{"label": "Yes", "next": null},
			{"label": "No", "next": null},
		]},
	])
	box._finish_typing()
	assert_true(box._choices_box.visible, "the choices are showing")
	for b in box._choice_buttons:
		assert_eq((b as Control).mouse_filter, Control.MOUSE_FILTER_STOP, "each choice button still takes its click")
	_click_at(panel.get_global_rect().get_center())
	assert_eq(DialogueManager.current_text(), "Well?", "a click beside the choices doesn't skip the question")

	DialogueManager.end_dialogue()
	if made:
		DialogueManager.remove_child(box)
		box.free()
	GameManager._apply_input_mode(kept_controller, kept_keyboard)
