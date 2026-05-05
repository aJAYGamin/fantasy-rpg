extends Node2D

## OverworldScene — Phase 2b
## Tracks player movement, rolls for random encounters, and hands off to BattleScene
## when one triggers.

const STEP_DISTANCE: float = 32.0
const ENCOUNTER_CHANCE_PER_STEP: float = 0.01  # +1% per step, resets after each encounter
const MIN_ENEMIES_PER_ENCOUNTER: int = 1
const MAX_ENEMIES_PER_ENCOUNTER: int = 3

# Phase 2b: hardcoded encounter pool. Phase 3 moves this onto MapArea resources.
const ENCOUNTER_POOL: Array[String] = [
	"ice_golem", "fire_drake", "dark_wraith", "storm_eagle", "earth_golem",
	"sea_serpent", "wind_sprite", "light_golem", "void_shade", "frost_wyrm",
]

const BATTLE_SCENE_PATH := "res://scenes/BattleScene.tscn"

@onready var player: CharacterBody2D = $Player

var _last_position: Vector2
var _distance_accumulator: float = 0.0
var _steps_since_encounter: int = 0
var _encounter_in_flight: bool = false

func _ready() -> void:
	GameManager.ensure_default_party()

	# If we're returning from a battle, drop the player back where they were.
	if GameManager.in_overworld_battle:
		player.position = GameManager.pending_overworld_return_position
		GameManager.in_overworld_battle = false
		print("[Overworld] Returned from battle at ", player.position)

	_last_position = player.position

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
	_encounter_in_flight = true

	var pool := ENCOUNTER_POOL.duplicate()
	pool.shuffle()
	var num_enemies: int = randi_range(MIN_ENEMIES_PER_ENCOUNTER, MAX_ENEMIES_PER_ENCOUNTER)
	var picked: Array[String] = []
	for i in range(num_enemies):
		picked.append(pool[i])

	GameManager.in_overworld_battle = true
	GameManager.pending_battle_enemies = picked
	GameManager.pending_overworld_scene_path = scene_file_path
	GameManager.pending_overworld_return_position = player.position

	print("[Overworld] Encounter after %d steps: %s" % [_steps_since_encounter, ", ".join(picked)])
	_steps_since_encounter = 0

	get_tree().change_scene_to_file(BATTLE_SCENE_PATH)
