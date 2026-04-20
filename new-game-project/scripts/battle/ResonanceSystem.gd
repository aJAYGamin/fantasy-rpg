class_name ResonanceSystem
extends Node

## ResonanceSystem.gd
## Manages the Amethyst Resonance meter for all party members
## Default: every damage skill grants 10% resonance (once per use, not per target)
## Skills can override via Skill.resonance_gain_override
## Taking damage also grants resonance to the target

signal resonance_changed(character: Character, new_value: float)
signal resonance_full(character: Character)
signal resonance_spent(character: Character)
signal combined_resonance_ready(characters: Array)

const MAX_RESONANCE = 100.0

# Default gain per damage skill / attack
const RESONANCE_PER_ATTACK = 10.0
# Resonance gained from taking damage (receiving side)
const RESONANCE_PER_DAMAGE_TAKEN = 10.0

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
	var new_val = clampf(resonance_values[character] + amount, 0.0, MAX_RESONANCE)
	resonance_values[character] = new_val
	emit_signal("resonance_changed", character, new_val)
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

# Called once per basic attack — 10% default
func on_attack(attacker: Character):
	add_resonance(attacker, RESONANCE_PER_ATTACK)

# Called ONCE per skill use (regardless of target count)
# Uses the skill's resonance_gain_override if set, else default 10%
func on_skill_used(user: Character, skill: Skill):
	if skill == null:
		add_resonance(user, RESONANCE_PER_ATTACK)
		return
	var amount = skill.get_resonance_gain()
	if amount != 0.0:
		add_resonance(user, amount)

# Called when a character takes damage
func on_damage_taken(character: Character):
	add_resonance(character, RESONANCE_PER_DAMAGE_TAKEN)

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
	var names = characters.map(func(c): return c.character_name)
	names.sort()
	return " & ".join(names) + " — Amethyst Requiem"
