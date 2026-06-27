extends TestSuite

## DialogueManager (autoload) branching-tree engine: linear play_lines, branching
## play() with choices, the advance/choose flow, and the state getters. The global
## DialogueBox is a passive signal listener and isn't exercised here. Every test
## fully ends its conversation so no state leaks into the next.

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
