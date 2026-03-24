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
var drop_table: Array[Dictionary] = []
# Format: [{"item_name": "Health Potion", "chance": 0.3, "quantity": 1}]

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
	return Rarity.get_name(rarity)

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
