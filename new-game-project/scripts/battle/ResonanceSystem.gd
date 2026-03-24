class_name ResonanceSystem
extends Node

## ResonanceSystem.gd
## Manages the Amethyst Resonance meter for all party members
## Add as a child of BattleManager

signal resonance_changed(character: Character, new_value: float)
signal resonance_full(character: Character)
signal resonance_spent(character: Character)
signal combined_resonance_ready(characters: Array)

const MAX_RESONANCE = 100.0

# How much resonance each action gives
const RESONANCE_PER_ATTACK = 12.0
const RESONANCE_PER_SKILL  = 20.0
const RESONANCE_PER_DAMAGE_TAKEN = 8.0
const RESONANCE_PER_HEAL = 10.0

var resonance_values: Dictionary = {}  # character -> float
var party: Array[Character] = []

func setup(party_members: Array[Character]):
	party = party_members
	for c in party:
		resonance_values[c] = 0.0

func add_resonance(character: Character, amount: float):
	if not resonance_values.has(character):
		return
	var was_full = is_full(character)
	resonance_values[character] = minf(resonance_values[character] + amount, MAX_RESONANCE)
	emit_signal("resonance_changed", character, resonance_values[character])
	if not was_full and is_full(character):
		emit_signal("resonance_full", character)
		print("%s Resonance is FULL!" % character.character_name)

func get_resonance(character: Character) -> float:
	return resonance_values.get(character, 0.0)

func get_resonance_percent(character: Character) -> float:
	return get_resonance(character) / MAX_RESONANCE

func is_full(character: Character) -> bool:
	return get_resonance(character) >= MAX_RESONANCE

func can_combine(characters: Array[Character]) -> bool:
	for c in characters:
		if not is_full(c):
			return false
	return characters.size() >= 2

# Called when a character attacks
func on_attack(attacker: Character):
	add_resonance(attacker, RESONANCE_PER_ATTACK)

# Called when a character uses a skill
func on_skill_used(user: Character):
	add_resonance(user, RESONANCE_PER_SKILL)

# Called when a character takes damage
func on_damage_taken(character: Character):
	add_resonance(character, RESONANCE_PER_DAMAGE_TAKEN)

# Called when a character heals
func on_heal(healer: Character):
	add_resonance(healer, RESONANCE_PER_HEAL)

# Spend one character's resonance for their ultimate
func spend_solo_ultimate(character: Character) -> bool:
	if not is_full(character):
		return false
	resonance_values[character] = 0.0
	emit_signal("resonance_spent", character)
	emit_signal("resonance_changed", character, 0.0)
	return true

# Spend multiple characters' resonance for combined attack
func spend_combined_resonance(characters: Array[Character]) -> bool:
	if not can_combine(characters):
		return false
	for c in characters:
		resonance_values[c] = 0.0
		emit_signal("resonance_spent", c)
		emit_signal("resonance_changed", c, 0.0)
	emit_signal("combined_resonance_ready", characters)
	return true

# Get which characters have full resonance
func get_full_resonance_characters() -> Array[Character]:
	var full: Array[Character] = []
	for c in party:
		if is_full(c):
			full.append(c)
	return full

# Get the name of a combined attack for a pair
func get_combined_attack_name(characters: Array[Character]) -> String:
	# This can be expanded with a lookup table per character pair
	var names = characters.map(func(c): return c.character_name)
	names.sort()
	return " & ".join(names) + " — Amethyst Requiem"
