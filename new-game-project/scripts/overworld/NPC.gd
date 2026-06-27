class_name NPC
extends StaticBody2D

## A solid, talk-to-able overworld character. Drop one into a scene, set its name +
## lines (or a full branching tree), and walking up + pressing Confirm starts a
## DialogueManager conversation. Builds its own collision / interaction area /
## placeholder visual in code so it's a one-node drop-in until real art arrives.

@export var npc_name: String = "Villager"
## Simple linear dialogue (one speaker, these lines in order). For branching trees
## or quest hooks, override interact() / set `dialogue_nodes`.
@export_multiline var lines: PackedStringArray = ["Hello, traveler!"]
## Optional full branching tree (array of DialogueManager node dicts). If set, it
## takes precedence over `lines`.
@export var dialogue_nodes: Array = []
@export var body_size: Vector2 = Vector2(48, 56)
@export var interact_radius: float = 76.0
@export var body_color: Color = Color(0.62, 0.52, 0.82)

# Waypoint marker colours (match the Quests menu): pastel yellow = story quest,
# pastel blue = active side quest.
const WP_STORY_COLOR := Color(0.98, 0.90, 0.52)
const WP_SIDE_COLOR := Color(0.56, 0.78, 0.98)

var _player_in_range: bool = false
var _name_lbl: Label = null
var _prompt: Label = null
var _waypoint: Label = null

func _ready() -> void:
	# Solid body so the player can't walk through the NPC.
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = body_size
	cs.shape = rect
	add_child(cs)

	# Placeholder visual (swapped for a sprite when art lands).
	var vis := Polygon2D.new()
	vis.polygon = PackedVector2Array([
		Vector2(-body_size.x * 0.5, -body_size.y * 0.5),
		Vector2(body_size.x * 0.5, -body_size.y * 0.5),
		Vector2(body_size.x * 0.5, body_size.y * 0.5),
		Vector2(-body_size.x * 0.5, body_size.y * 0.5)])
	vis.color = body_color
	add_child(vis)

	# Name tag + "✦ Talk" prompt above the NPC. Both are hidden by default and only
	# appear together while the player is in range AND no conversation is happening
	# (see _update_tags).
	_name_lbl = _world_label(npc_name, 13, BattleUITheme.TEXT_PRIMARY)
	_name_lbl.position = Vector2(-90, -body_size.y * 0.5 - 26)
	_name_lbl.visible = false
	add_child(_name_lbl)

	_prompt = _world_label("✦ Talk", 13, BattleUITheme.TEXT_ACCENT)
	_prompt.position = Vector2(-90, -body_size.y * 0.5 - 46)
	_prompt.visible = false
	add_child(_prompt)

	# Floating quest waypoint marker — visible from any range (it's a "go here" cue)
	# when this NPC is the current target of the story quest (yellow) or active side
	# quest (blue). Points down at the NPC and bobs.
	_waypoint = _world_label("▼", 26, WP_SIDE_COLOR)
	_waypoint.position = Vector2(-90, -body_size.y * 0.5 - 84)
	_waypoint.visible = false
	add_child(_waypoint)

	# Proximity sensor.
	var area := Area2D.new()
	var acs := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = interact_radius
	acs.shape = circ
	area.add_child(acs)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

	# Hide the tags while ANY conversation is active, restore them when it ends (so
	# the NPC you're talking to drops its name/prompt, then shows them again after).
	DialogueManager.dialogue_started.connect(_update_tags)
	DialogueManager.dialogue_ended.connect(_update_tags)

	# Keep the waypoint marker in sync with quest state.
	GameManager.quests_changed.connect(_refresh_waypoint)
	_start_waypoint_bob()
	_refresh_waypoint()

func _on_body_entered(body: Node) -> void:
	if body is OverworldPlayer:
		_player_in_range = true
		_update_tags()

func _on_body_exited(body: Node) -> void:
	if body is OverworldPlayer:
		_player_in_range = false
		_update_tags()

# Name + prompt are visible together only when the player is close and no dialogue
# is running. Accepts an optional arg so it can connect to both dialogue signals
# (dialogue_started passes an id; dialogue_ended passes nothing).
func _update_tags(_unused = null) -> void:
	var show_tags: bool = _player_in_range and not DialogueManager.is_active()
	if _name_lbl:
		_name_lbl.visible = show_tags
	if _prompt:
		_prompt.visible = show_tags

# Shows + colours the floating waypoint marker for whichever active quest (if any)
# currently points at this NPC by name.
func _refresh_waypoint() -> void:
	if _waypoint == null:
		return
	var kind: String = GameManager.quest_log.waypoint_kind_for_npc(npc_name)
	if kind == "story":
		_waypoint.add_theme_color_override("font_color", WP_STORY_COLOR)
		_waypoint.visible = true
	elif kind == "side":
		_waypoint.add_theme_color_override("font_color", WP_SIDE_COLOR)
		_waypoint.visible = true
	else:
		_waypoint.visible = false

func _start_waypoint_bob() -> void:
	var base_y: float = _waypoint.position.y
	var t := create_tween().set_loops()
	t.tween_property(_waypoint, "position:y", base_y - 7.0, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_waypoint, "position:y", base_y, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range or DialogueManager.is_active():
		return
	if event.is_action_pressed("confirm") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		interact()

## Starts this NPC's conversation. Override in a subclass for shopkeepers /
## quest-givers that branch on game state.
func interact() -> void:
	if not dialogue_nodes.is_empty():
		DialogueManager.play(dialogue_nodes)
	elif not lines.is_empty():
		var arr: Array = []
		for l in lines:
			arr.append(l)
		DialogueManager.play_lines(npc_name, arr)

func _world_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(180, 0)
	var f := BattleUITheme.font_bold()
	if f:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	# A dark outline so names read over any background.
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.08, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	return l
