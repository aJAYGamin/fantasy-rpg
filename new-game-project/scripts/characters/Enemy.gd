class_name Enemy
extends Character

## Enemy.gd — Extends Character with enemy-specific features

@export var species: String = "Unknown"
@export var rarity: Rarity.Tier = Rarity.Tier.COMMON
@export var base_exp_reward: int = 20
@export var base_gold_reward: int = 10

# --- Memory Echo ---
# Tracks how many times this species has been fought
# Stored globally in GameManager so it persists across battles
var memory_level: int = 0  # 0 = no memory, grows over time

# Adaptation thresholds
const MEMORY_THRESHOLD_1 = 3   # Starts noticing patterns
const MEMORY_THRESHOLD_2 = 7   # Actively adapts
const MEMORY_THRESHOLD_3 = 15  # Fully adapted

# --- Drop table ---
@export var drop_table: Array[Dictionary] = []
# Format: [{"item_name": "Health Potion", "chance": 0.3, "quantity": 1}]

## Multi-phase boss behaviour. An enemy with phases IS a boss — there is no
## separate flag to fall out of sync with the data.
@export var phases: Array[BossPhase] = []

## Battle-temp: which phase is active. -1 = none entered yet. Never serialized.
var active_phase: int = -1

func is_boss() -> bool:
	return not phases.is_empty()

func hp_fraction() -> float:
	var m := max_hp()
	if m <= 0:
		return 0.0
	return float(current_hp) / float(m)

## Phases advance FORWARD ONLY, one step at a time. Recomputing the active phase
## from HP cannot express a transformation: refilling HP returns the fraction to
## 1.0, so a recomputing formula would drop the boss back to its opening form.
func should_advance_phase() -> bool:
	var nxt := active_phase + 1
	if nxt >= phases.size():
		return false
	return hp_fraction() <= phases[nxt].enter_at_hp

func advance_phase() -> BossPhase:
	if active_phase + 1 >= phases.size():
		return null
	active_phase += 1
	return phases[active_phase]

func current_phase() -> BossPhase:
	if active_phase < 0 or active_phase >= phases.size():
		return null
	return phases[active_phase]

func _init():
	super._init()

func get_exp_reward() -> int:
	var multiplier = Rarity.get_exp_multiplier(rarity)
	return int(base_exp_reward * multiplier * (1.0 + (level - 1) * 0.1))

func get_gold_reward() -> int:
	var multiplier = Rarity.get_loot_multiplier(rarity)
	return int(base_gold_reward * multiplier * (1.0 + (level - 1) * 0.05))

func get_rarity_color() -> Color:
	return Rarity.get_color(rarity)

func get_rarity_name() -> String:
	return Rarity.tier_name(rarity)

# --- Memory Echo ---
func load_memory():
	memory_level = GameManager.get_species_memory(species)

func get_memory_description() -> String:
	if memory_level < MEMORY_THRESHOLD_1:
		return ""
	elif memory_level < MEMORY_THRESHOLD_2:
		return "%s senses something familiar..." % species
	elif memory_level < MEMORY_THRESHOLD_3:
		return "%s has learned from past encounters!" % species
	else:
		return "%s has fully adapted to your tactics!" % species

func get_damage_reduction_bonus() -> float:
	# Higher memory = slightly more resistant to repeated tactics
	if memory_level >= MEMORY_THRESHOLD_3:
		return 0.20
	elif memory_level >= MEMORY_THRESHOLD_2:
		return 0.12
	elif memory_level >= MEMORY_THRESHOLD_1:
		return 0.05
	return 0.0
