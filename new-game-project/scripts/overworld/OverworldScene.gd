extends Node2D

## OverworldScene — Phase 3
## Reads its area config from a MapArea resource (assigned per-scene) and
## triggers weighted random encounters filtered by party level.

const STEP_DISTANCE: float = 32.0
const ENCOUNTER_CHANCE_PER_STEP: float = 0.01  # +1% per step, resets after each encounter
const BATTLE_SCENE_PATH := "res://scenes/BattleScene.tscn"

@export var area: MapArea

@onready var player: CharacterBody2D = $Player

var _last_position: Vector2
var _distance_accumulator: float = 0.0
var _steps_since_encounter: int = 0
var _encounter_in_flight: bool = false

func _ready() -> void:
	GameManager.ensure_default_party()

	if GameManager.in_overworld_battle:
		# Returning from a battle — drop player at the saved spot.
		player.position = GameManager.pending_overworld_return_position
		GameManager.in_overworld_battle = false
		print("[Overworld] Returned from battle at ", player.position)
	elif area != null:
		# Fresh entry to this area — use the area's default spawn.
		player.position = area.default_spawn

	_last_position = player.position

	if area == null:
		push_warning("OverworldScene has no MapArea assigned — encounters will not trigger")

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
