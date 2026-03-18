class_name DialogueManager
extends Node

## A simple branching dialogue system.
## Dialogue is stored as a Dictionary so you can write it in JSON files.
##
## Format:
##   { "id": "intro",
##     "speaker": "Elder",
##     "text": "Welcome, young hero...",
##     "choices": [
##       { "label": "Tell me more.", "next": "more_info" },
##       { "label": "I must go.",    "next": null }   <- null ends dialogue
##     ]
##   }
## If no "choices" key, the dialogue auto-advances to "next".

signal dialogue_started(dialogue_id: String)
signal line_displayed(speaker: String, text: String)
signal choices_presented(choices: Array)
signal dialogue_ended

var _dialogue_tree: Dictionary = {}   # All nodes keyed by id
var _current_node_id: String = ""
var _is_active: bool = false

## Load a dialogue JSON file at runtime
func load_dialogue_file(path: String):
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Could not open dialogue file: " + path)
		return
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	if err != OK:
		push_error("JSON parse error in: " + path)
		return
	var data = json.data
	for node in data:
		_dialogue_tree[node["id"]] = node

## Load dialogue directly from a GDScript Array (for small in-code dialogues)
func load_dialogue_array(nodes: Array):
	for node in nodes:
		_dialogue_tree[node["id"]] = node

## Start a dialogue by entry id
func start(entry_id: String):
	if not _dialogue_tree.has(entry_id):
		push_error("Dialogue id not found: " + entry_id)
		return
	_is_active = true
	_current_node_id = entry_id
	emit_signal("dialogue_started", entry_id)
	_show_current()

func _show_current():
	if _current_node_id == "" or not _dialogue_tree.has(_current_node_id):
		end_dialogue()
		return

	var node = _dialogue_tree[_current_node_id]
	var speaker = node.get("speaker", "")
	var text    = node.get("text", "")

	emit_signal("line_displayed", speaker, text)

	# If choices exist, wait for player input
	if node.has("choices"):
		emit_signal("choices_presented", node["choices"])
	# Otherwise auto-advance is triggered by advance()

## Call this when the player presses "Next" (no choices)
func advance():
	if not _is_active: return
	var node = _dialogue_tree.get(_current_node_id, {})
	if node.has("choices"): return  # Choices are handled separately
	var next = node.get("next", null)
	if next == null:
		end_dialogue()
	else:
		_current_node_id = next
		_show_current()

## Call this when the player picks a numbered choice
func choose(choice_index: int):
	if not _is_active: return
	var node = _dialogue_tree.get(_current_node_id, {})
	if not node.has("choices"): return
	var choices = node["choices"]
	if choice_index < 0 or choice_index >= choices.size(): return

	var chosen = choices[choice_index]
	var next = chosen.get("next", null)
	if next == null:
		end_dialogue()
	else:
		_current_node_id = next
		_show_current()

func end_dialogue():
	_is_active = false
	_current_node_id = ""
	emit_signal("dialogue_ended")

func is_active() -> bool:
	return _is_active

# ─────────────────────────────────────────────────────────────
# Example dialogue data (put this in a .json or use load_dialogue_array)
# ─────────────────────────────────────────────────────────────
static func get_example_dialogue() -> Array:
	return [
		{
			"id": "village_elder",
			"speaker": "Village Elder",
			"text": "Ah, travelers! The Dark Sorcerer Malachar threatens our kingdom. Will you help us?",
			"choices": [
				{"label": "We will help!", "next": "accept_quest"},
				{"label": "What's in it for us?", "next": "reward_info"},
				{"label": "We're too busy.", "next": "refuse_quest"}
			]
		},
		{
			"id": "accept_quest",
			"speaker": "Village Elder",
			"text": "Bless you! Travel north through the Darkwood Forest. His tower lies beyond.",
			"next": "accept_quest_2"
		},
		{
			"id": "accept_quest_2",
			"speaker": "Village Elder",
			"text": "Take these supplies for your journey. May the light guide you!",
			"next": null  # End dialogue
		},
		{
			"id": "reward_info",
			"speaker": "Village Elder",
			"text": "The kingdom offers 500 gold and the legendary sword Dawnbringer to whoever defeats him.",
			"choices": [
				{"label": "That's enough. We'll do it!", "next": "accept_quest"},
				{"label": "Still not interested.", "next": "refuse_quest"}
			]
		},
		{
			"id": "refuse_quest",
			"speaker": "Village Elder",
			"text": "I understand... but please reconsider. The kingdom needs heroes like you.",
			"next": null
		}
	]
