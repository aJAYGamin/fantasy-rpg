extends Node2D

## OverworldScene — Phase 3
## Reads its area config from a MapArea resource (assigned per-scene) and
## triggers weighted random encounters filtered by party level.

const STEP_DISTANCE: float = 32.0
const ENCOUNTER_CHANCE_PER_STEP: float = 0.01  # +1% per step, resets after each encounter
const BATTLE_SCENE_PATH := "res://scenes/BattleScene.tscn"
const MAIN_MENU_SCENE_PATH := "res://scenes/MainMenu.tscn"
const PAUSE_MENU_SCENE_PATH := "res://scenes/PauseMenu.tscn"

@export var area: MapArea

@onready var player: CharacterBody2D = $Player

var _last_position: Vector2
var _distance_accumulator: float = 0.0
var _steps_since_encounter: int = 0
var _encounter_in_flight: bool = false
var _pause_menu: Control = null

func _ready() -> void:
	GameManager.ensure_default_party()

	if GameManager.in_overworld_battle:
		# Returning from a battle — drop player at the saved spot.
		player.position = GameManager.pending_overworld_return_position
		GameManager.in_overworld_battle = false
		print("[Overworld] Returned from battle at ", player.position)
	elif GameManager.resuming_from_save:
		# Continue from a save — spawn at the saved position.
		player.position = GameManager.save_overworld_position
		GameManager.resuming_from_save = false
		print("[Overworld] Resumed from save at ", player.position)
	elif area != null:
		# Fresh entry to this area — use the area's default spawn.
		player.position = area.default_spawn

	_last_position = player.position

	if area == null:
		push_warning("OverworldScene has no MapArea assigned — encounters will not trigger")

func _input(event: InputEvent) -> void:
	# Use _input (not _unhandled_input) so the pause key is caught before Godot's
	# GUI pipeline can consume it. The remappable "pause" action (default Esc /
	# controller Start) is honored here automatically.
	if event.is_action_pressed("pause"):
		_open_pause_menu()
		get_viewport().set_input_as_handled()

func _open_pause_menu() -> void:
	if _pause_menu == null:
		# Wrap in a CanvasLayer so the menu renders in screen-space and isn't
		# panned around by the player's Camera2D. Matches how BattleScene's UI
		# is parented to a CanvasLayer.
		var layer = CanvasLayer.new()
		layer.layer = 10
		add_child(layer)
		_pause_menu = load(PAUSE_MENU_SCENE_PATH).instantiate()
		layer.add_child(_pause_menu)
		_pause_menu.save_requested.connect(_on_pause_save)
		_pause_menu.quit_requested.connect(_on_pause_quit)
	_pause_menu.open()

func _on_pause_save() -> void:
	if GameManager.active_slot < 0:
		_pause_menu.show_toast("No active slot — start a New Game first.", true)
		return
	GameManager.save_overworld_scene_path = scene_file_path
	GameManager.save_overworld_position = player.position
	if GameManager.save_to_slot(GameManager.active_slot):
		_pause_menu.show_toast("Saved to Slot %d" % (GameManager.active_slot + 1))
	else:
		_pause_menu.show_toast("Save failed.", true)

func _on_pause_quit() -> void:
	# Must unpause before scene change; the tree carries pause state across scenes.
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)

func _physics_process(_delta: float) -> void:
	if _encounter_in_flight:
		return

	var current_pos := player.position
	var moved := current_pos.distance_to(_last_position)
	_last_position = current_pos
	if moved <= 0.0:
		return

	_distance_accumulator += moved
	while _distance_accumulator >= STEP_DISTANCE:
		_distance_accumulator -= STEP_DISTANCE
		_steps_since_encounter += 1
		var chance: float = _steps_since_encounter * ENCOUNTER_CHANCE_PER_STEP
		if randf() < chance:
			_trigger_encounter()
			return

func _trigger_encounter() -> void:
	if area == null:
		return
	var party_level: int = _get_party_max_level()
	var available: Array[EncounterGroup] = []
	for g in area.encounter_groups:
		if g != null and g.min_party_level <= party_level and not g.enemy_pool.is_empty():
			available.append(g)
	if available.is_empty():
		# No groups match the current party level; skip this encounter check.
		return

	var chosen := _weighted_pick(available)
	if chosen == null:
		return
	var enemies := chosen.instantiate_encounter()
	if enemies.is_empty():
		return

	_encounter_in_flight = true
	GameManager.in_overworld_battle = true
	GameManager.pending_battle_enemies = enemies
	GameManager.pending_battle_background = area.battle_background_id
	GameManager.pending_overworld_scene_path = scene_file_path
	GameManager.pending_overworld_return_position = player.position

	print("[Overworld] '%s' encounter (%d enemies) after %d steps" % [
		chosen.group_name, enemies.size(), _steps_since_encounter
	])
	_steps_since_encounter = 0
	get_tree().change_scene_to_file(BATTLE_SCENE_PATH)

func _get_party_max_level() -> int:
	var max_lv: int = 1
	for c in GameManager.party:
		if c.level > max_lv:
			max_lv = c.level
	return max_lv

# Weighted random pick. Groups with weight <= 0 are skipped.
func _weighted_pick(groups: Array[EncounterGroup]) -> EncounterGroup:
	var total: float = 0.0
	for g in groups:
		total += maxf(0.0, g.weight)
	if total <= 0.0:
		return null
	var roll: float = randf() * total
	var acc: float = 0.0
	for g in groups:
		acc += maxf(0.0, g.weight)
		if roll < acc:
			return g
	return groups[groups.size() - 1]
