class_name Equipment
extends Resource

## A piece of equippable gear. Five slots exist per hero (1 Weapon, 1 Armor,
## 3 Accessory). Bonuses are flexible per-stat. Equipping can be gated by class
## and/or element; an empty restriction list means "anyone". Rarity is a cosmetic
## tier (color/label), NOT a gate.

enum Slot { WEAPON, ARMOR, ACCESSORY }

# Stat-bonus keys — match the strings Character stat getters pass to
# Inventory.equipment_bonus(). Stored as plain strings so saves round-trip cleanly.
const STAT_KEYS := ["attack", "defense", "magic", "arcane", "speed", "max_hp", "max_mp"]
const STAT_LABELS := {
	"attack": "ATK", "defense": "DEF", "magic": "MAG", "arcane": "ARC",
	"speed": "SPD", "max_hp": "HP", "max_mp": "MP",
}

@export var equipment_name: String = ""
@export var description: String = ""
@export var slot: Slot = Slot.WEAPON
@export var rarity: int = Rarity.Tier.COMMON          # Rarity.Tier
@export var stat_bonuses: Dictionary = {}             # stat key -> bonus int
@export var class_restriction: Array[String] = []     # empty = any class
@export var element_restriction: Array[int] = []      # ElementalSystem.Element ints; empty = any

func bonus(stat: String) -> int:
	return int(stat_bonuses.get(stat, 0))

# True if `character` satisfies every restriction (class AND element). An empty
# restriction list for a dimension means that dimension is unrestricted.
func can_equip(character: Character) -> bool:
	if not class_restriction.is_empty():
		var matched := false
		for c in class_restriction:
			if String(c).to_lower() == String(character.character_class).to_lower():
				matched = true
				break
		if not matched:
			return false
	if not element_restriction.is_empty():
		if not (int(character.element) in element_restriction \
				or int(character.secondary_element) in element_restriction):
			return false
	return true

func rarity_color() -> Color:
	return Rarity.get_color(rarity)

func rarity_name() -> String:
	return Rarity.tier_name(rarity)

func slot_name() -> String:
	match slot:
		Slot.WEAPON:    return "Weapon"
		Slot.ARMOR:     return "Armor"
		Slot.ACCESSORY: return "Accessory"
	return "Equipment"

# Human-readable restriction summary for the UI: "Warrior", "Fire", "Warrior / Fire",
# or "" when the piece has no restrictions.
func restriction_text() -> String:
	var parts: Array[String] = []
	for c in class_restriction:
		parts.append(String(c))
	for e in element_restriction:
		parts.append(ElementalSystem.get_element_name(e))
	return " / ".join(parts)

# Sorted "+ATK 5  +SPD 2" summary of the stat bonuses, for the UI.
func bonus_text() -> String:
	var parts: Array[String] = []
	for key in STAT_KEYS:
		var v := int(stat_bonuses.get(key, 0))
		if v != 0:
			parts.append("%s %+d" % [STAT_LABELS[key], v])
	return "  ".join(parts)
