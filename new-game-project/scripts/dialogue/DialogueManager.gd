extends Node

## DialogueManager.gd — Autoload singleton (registered as "DialogueManager").
##
## A small branching dialogue engine + a global themed dialogue box. NPCs (and
## later shopkeepers / quest-givers) call play_lines() for simple linear talk or
## play() for a branching tree; the box renders it everywhere, no per-scene setup.
##
## Node format (one entry in the tree, keyed by "id"):
##   { "id": "intro", "speaker": "Elder", "text": "Welcome...",
##     "next": "more"  }                      # auto-advances to "more"
## or with choices:
##   { "id": "intro", "speaker": "Elder", "text": "Will you help?",
##     "choices": [ {"label": "Yes", "next": "accept"},
##                  {"label": "No",  "next": null} ] }   # null = end
##
## NOTE: this is an autoload, so it has NO class_name (mirrors GameManager) — refer
## to it by the singleton name `DialogueManager`.

signal dialogue_started(dialogue_id: String)
signal line_displayed(speaker: String, text: String)
signal choices_presented(choices: Array)
# Emitted when the shown node carries an "event" key — a hook for side effects
# (accept a quest, give an item, set a story flag) tied to reaching that node.
signal dialogue_event(event_name: String)
signal dialogue_ended

# Path (not preload) so there's no COMPILE-TIME dependency on DialogueBox — the box
# references this autoload, so preloading it here would form a parse cycle (the
# box can't see this script's signals while this script is still compiling). We
# load() it at runtime in _ready() instead.
const DIALOGUE_BOX_PATH := "res://scripts/dialogue/DialogueBox.gd"

var _dialogue_tree: Dictionary = {}   # all nodes keyed by id
var _current_node_id: String = ""
var _is_active: bool = false
var _box: CanvasLayer = null

func _ready() -> void:
	# Run + render the box even while the tree is paused (future cutscenes).
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Create the global box DEFERRED — so DialogueBox.gd is compiled after this
	# script has fully settled, never re-entrantly while we're still in _ready()
	# (which made the box's parser fail to resolve this autoload's members).
	_create_box.call_deferred()

func _create_box() -> void:
	# One global themed box, available in every scene.
	var box_script: GDScript = load(DIALOGUE_BOX_PATH)
	_box = box_script.new()
	add_child(_box)

# --- Playback API -------------------------------------------------------------

## Play a fresh branching tree (replaces any previously loaded nodes). entry_id
## defaults to the first node's id.
func play(nodes: Array, entry_id: String = "") -> void:
	_dialogue_tree.clear()
	load_dialogue_array(nodes)
	if entry_id == "" and not nodes.is_empty():
		entry_id = String(nodes[0].get("id", ""))
	start(entry_id)

## Convenience for the common case: a single speaker reading N lines in order.
func play_lines(speaker_name: String, lines: Array) -> void:
	var nodes: Array = []
	for i in lines.size():
		nodes.append({
			"id": str(i),
			"speaker": speaker_name,
			"text": String(lines[i]),
			"next": (str(i + 1) if i + 1 < lines.size() else null),
		})
	play(nodes, "0")

## Load a dialogue JSON file at runtime (array of node dicts). Appends to the tree.
func load_dialogue_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open dialogue file: " + path)
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("JSON parse error in: " + path)
		return
	if json.data is Array:
		load_dialogue_array(json.data)

## Load dialogue directly from a GDScript Array (appends to the tree).
func load_dialogue_array(nodes: Array) -> void:
	for node in nodes:
		_dialogue_tree[String(node["id"])] = node

## Start an already-loaded tree at entry_id.
func start(entry_id: String) -> void:
	if not _dialogue_tree.has(entry_id):
		push_error("Dialogue id not found: " + entry_id)
		return
	_is_active = true
	_current_node_id = entry_id
	dialogue_started.emit(entry_id)
	_show_current()

func _show_current() -> void:
	if _current_node_id == "" or not _dialogue_tree.has(_current_node_id):
		end_dialogue()
		return
	var node: Dictionary = _dialogue_tree[_current_node_id]
	line_displayed.emit(String(node.get("speaker", "")), String(node.get("text", "")))
	if node.has("event"):
		dialogue_event.emit(String(node["event"]))
	if node.has("choices"):
		choices_presented.emit(node["choices"])

## Advance a no-choice line (player pressed continue).
func advance() -> void:
	if not _is_active:
		return
	var node: Dictionary = _dialogue_tree.get(_current_node_id, {})
	if node.has("choices"):
		return  # choices are resolved via choose()
	var next = node.get("next", null)
	if next == null:
		end_dialogue()
	else:
		_current_node_id = String(next)
		_show_current()

## Resolve a presented choice by index.
func choose(choice_index: int) -> void:
	if not _is_active:
		return
	var node: Dictionary = _dialogue_tree.get(_current_node_id, {})
	if not node.has("choices"):
		return
	var choices: Array = node["choices"]
	if choice_index < 0 or choice_index >= choices.size():
		return
	var next = choices[choice_index].get("next", null)
	if next == null:
		end_dialogue()
	else:
		_current_node_id = String(next)
		_show_current()

func end_dialogue() -> void:
	if not _is_active:
		return
	_is_active = false
	_current_node_id = ""
	dialogue_ended.emit()

func is_active() -> bool:
	return _is_active

## True if the current node is waiting on a choice (vs a plain continue line).
func current_has_choices() -> bool:
	var node: Dictionary = _dialogue_tree.get(_current_node_id, {})
	return node.has("choices")

func current_speaker() -> String:
	return String(_dialogue_tree.get(_current_node_id, {}).get("speaker", ""))

func current_text() -> String:
	return String(_dialogue_tree.get(_current_node_id, {}).get("text", ""))

func current_choices() -> Array:
	return _dialogue_tree.get(_current_node_id, {}).get("choices", [])
