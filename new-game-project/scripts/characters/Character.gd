class_name Character
extends Resource

## Base class for all playable characters and enemies

@export var character_name: String = "Unknown"
@export var character_class: String = "Warrior"
@export var portrait: Texture2D

# --- Core Stats ---
@export var base_hp: int = 100
@export var base_mp: int = 50
@export var base_attack: int = 10
@export var base_defense: int = 5
@export var base_magic: int = 5
@export var base_speed: int = 10

# --- Elemental Affinity ---
@export var element: ElementalSystem.Element = ElementalSystem.Element.NONE
@export var extra_weakness: ElementalSystem.Element = ElementalSystem.Element.NONE
@export var extra_resistance: ElementalSystem.Element = ElementalSystem.Element.NONE

# --- Runtime State ---
var current_hp: int
var current_mp: int
var level: int = 1
var experience: int = 0
var experience_to_next: int = 100

# --- Inventory ---
var inventory: Inventory

# --- Skills ---
var skills: Array[Skill] = []

# --- Status Effects ---
var status_effects: Array[String] = []

func _init():
	current_hp = max_hp()
	current_mp = max_mp()
	inventory = Inventory.new()

# --- Stat Calculations ---
func max_hp() -> int:
	return base_hp + (level - 1) * 15

func max_mp() -> int:
	return base_mp + (level - 1) * 8

func attack_power() -> int:
	var weapon_bonus = inventory.get_weapon_attack()
	return base_attack + (level - 1) * 2 + weapon_bonus

func defense_power() -> int:
	var armor_bonus = inventory.get_armor_defense()
	return base_defense + (level - 1) * 1 + armor_bonus

func magic_power() -> int:
	return base_magic + (level - 1) * 2

func speed() -> int:
	return base_speed + (level - 1) * 1

func is_alive() -> bool:
	return current_hp > 0

func is_status(effect: String) -> bool:
	return effect in status_effects

# --- Combat ---
func take_damage(amount: int, attack_element: ElementalSystem.Element = ElementalSystem.Element.NONE) -> Dictionary:
	var multiplier = ElementalSystem.get_multiplier(attack_element, element)

	if extra_weakness != ElementalSystem.Element.NONE and attack_element == extra_weakness:
		multiplier *= 1.5
	if extra_resistance != ElementalSystem.Element.NONE and attack_element == extra_resistance:
		multiplier *= 0.6

	var base_damage = max(1, amount - defense_power())
	var final_damage = max(1, int(base_damage * multiplier))
	current_hp = max(0, current_hp - final_damage)

	return {
		"damage": final_damage,
		"multiplier": multiplier,
		"effectiveness": ElementalSystem.get_effectiveness_text(multiplier),
		"effectiveness_color": ElementalSystem.get_effectiveness_color(multiplier)
	}

func take_magic_damage(amount: int, attack_element: ElementalSystem.Element = ElementalSystem.Element.NONE) -> Dictionary:
	var multiplier = ElementalSystem.get_multiplier(attack_element, element)

	if extra_weakness != ElementalSystem.Element.NONE and attack_element == extra_weakness:
		multiplier *= 1.5
	if extra_resistance != ElementalSystem.Element.NONE and attack_element == extra_resistance:
		multiplier *= 0.6

	var final_damage = max(1, int(amount * multiplier))
	current_hp = max(0, current_hp - final_damage)

	return {
		"damage": final_damage,
		"multiplier": multiplier,
		"effectiveness": ElementalSystem.get_effectiveness_text(multiplier),
		"effectiveness_color": ElementalSystem.get_effectiveness_color(multiplier)
	}

func heal(amount: int) -> int:
	var actual_heal = min(amount, max_hp() - current_hp)
	current_hp += actual_heal
	return actual_heal

func restore_mp(amount: int) -> int:
	var actual_restore = min(amount, max_mp() - current_mp)
	current_mp += actual_restore
	return actual_restore

func use_mp(amount: int) -> bool:
	if current_mp >= amount:
		current_mp -= amount
		return true
	return false

func add_status(effect: String):
	if not is_status(effect):
		status_effects.append(effect)

func remove_status(effect: String):
	status_effects.erase(effect)

func process_status_effects() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if is_status("poison"):
		var dmg = max(1, max_hp() / 10)
		current_hp = max(0, current_hp - dmg)
		results.append({"type": "poison", "value": dmg})
	if is_status("regenerate"):
		var heal_amt = max(1, max_hp() / 8)
		heal(heal_amt)
		results.append({"type": "regenerate", "value": heal_amt})
	return results

# --- Leveling ---
func gain_experience(amount: int) -> bool:
	experience += amount
	if experience >= experience_to_next:
		level_up()
		return true
	return false

func level_up():
	level += 1
	experience -= experience_to_next
	experience_to_next = int(experience_to_next * 1.5)
	current_hp = max_hp()
	current_mp = max_mp()
	_learn_skills_at_level()

func _learn_skills_at_level():
	pass

func get_stats_summary() -> Dictionary:
	return {
		"name": character_name,
		"class": character_class,
		"level": level,
		"hp": "%d/%d" % [current_hp, max_hp()],
		"mp": "%d/%d" % [current_mp, max_mp()],
		"attack": attack_power(),
		"defense": defense_power(),
		"magic": magic_power(),
		"speed": speed(),
		"element": ElementalSystem.get_element_name(element),
		"exp": "%d/%d" % [experience, experience_to_next]
	}
	