class_name ItemFactory
extends RefCounted

## ItemFactory — single source of truth for the game's (currently temporary)
## item definitions. Both the starter-inventory seed (PartyFactory) and enemy
## drop rolls (BattleManager) build Item instances from here so item stats live
## in one place. Replace with data-driven .tres items when real content lands.

# item_name -> definition. Only the fields that differ from Item's defaults are
# listed; effect_stat stays "" since none of these are stat buff/debuff items.
const DEFS := {
	# Healing consumables (field-usable).
	"Health Potion": {"desc": "Restores 50 HP to one ally.", "type": Item.ItemType.HP_RESTORE, "value": 50, "target": Item.TargetType.SINGLE_ALLY},
	"Mana Potion": {"desc": "Restores 30 MP to one ally.", "type": Item.ItemType.MP_RESTORE, "value": 30, "target": Item.TargetType.SINGLE_ALLY},
	"Elixir": {"desc": "Restores 100 HP to all allies.", "type": Item.ItemType.HP_RESTORE, "value": 100, "target": Item.TargetType.ALL_ALLIES},
	"Phoenix Down": {"desc": "Revives a defeated ally with 50% HP.", "type": Item.ItemType.REVIVAL, "value": 50, "target": Item.TargetType.SINGLE_ALLY},
	"Antidote": {"desc": "Cures poison and burn from one ally.", "type": Item.ItemType.ANTIDOTE, "value": 0, "target": Item.TargetType.SINGLE_ALLY},
	# Battle items (combat-only).
	"Fire Bomb": {"desc": "Deals 40 fire damage to all enemies.", "type": Item.ItemType.DAMAGE, "value": 40, "target": Item.TargetType.ALL_ENEMIES},
	"Smoke Veil": {"desc": "Grants a 20% chance to dodge attacks to one ally.", "type": Item.ItemType.DODGE_BUFF, "value": 20, "target": Item.TargetType.SINGLE_ALLY},
	# General / crafting materials (the kind of thing enemies drop).
	"Monster Fang": {"desc": "A sharp fang dropped by beasts. Crafting material.", "type": Item.ItemType.GENERAL, "value": 0, "target": Item.TargetType.SINGLE_ALLY},
	"Beast Hide": {"desc": "Tough hide from a wild creature. Crafting material.", "type": Item.ItemType.GENERAL, "value": 0, "target": Item.TargetType.SINGLE_ALLY},
	"Glimmer Dust": {"desc": "Faintly glowing dust shed by magical foes. Crafting material.", "type": Item.ItemType.GENERAL, "value": 0, "target": Item.TargetType.SINGLE_ALLY},
	"Worn Pendant": {"desc": "A tarnished pendant of little obvious value.", "type": Item.ItemType.GENERAL, "value": 0, "target": Item.TargetType.SINGLE_ALLY},
	# Key items (story/event — never consumed).
	"Amethyst Shard": {"desc": "A humming shard of amethyst. It resonates faintly with the coming Requiem.", "type": Item.ItemType.KEY, "value": 0, "target": Item.TargetType.SINGLE_ALLY},
	"Silent Shrine Key": {"desc": "An old key said to open one of the fallen water-shrines.", "type": Item.ItemType.KEY, "value": 0, "target": Item.TargetType.SINGLE_ALLY},
}

static func has_item(name: String) -> bool:
	return DEFS.has(name)

# Builds a fresh Item instance for the named definition. Returns null (with a
# warning) if the name is unknown so callers fail loudly during development.
static func create(name: String, quantity: int = 1) -> Item:
	if not DEFS.has(name):
		push_warning("ItemFactory: unknown item '%s'" % name)
		return null
	var d: Dictionary = DEFS[name]
	var it := Item.new()
	it.item_name = name
	it.description = d["desc"]
	it.item_type = d["type"]
	it.effect_value = d["value"]
	it.target_type = d["target"]
	it.quantity = quantity
	return it

# Rolls an enemy's drop table independently per entry. Each entry is a Dictionary
# {"item_name": String, "chance": float (0-1), "quantity": int}. Returns the Items
# that dropped (unstacked). Unknown item names are skipped.
static func roll_drops(drop_table: Array) -> Array:
	var dropped: Array = []
	for entry in drop_table:
		var chance: float = float(entry.get("chance", 0.0))
		if randf() < chance:
			var qty: int = int(entry.get("quantity", 1))
			var it := create(String(entry.get("item_name", "")), qty)
			if it != null:
				dropped.append(it)
	return dropped
