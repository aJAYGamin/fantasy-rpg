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
	"Health Potion": {"desc": "A bitter red draught. Restores 50 HP to one ally.", "type": Item.ItemType.HP_RESTORE, "value": 50, "target": Item.TargetType.SINGLE_ALLY, "price": 30},
	"Mana Potion": {"desc": "Cool blue liquid that sharpens a tired mind. Restores 30 MP to one ally.", "type": Item.ItemType.MP_RESTORE, "value": 30, "target": Item.TargetType.SINGLE_ALLY, "price": 25},
	"Elixir": {"desc": "A whole flask of concentrated remedy. Restores 100 HP to every ally.", "type": Item.ItemType.HP_RESTORE, "value": 100, "target": Item.TargetType.ALL_ALLIES, "price": 120},
	"Phoenix Down": {"desc": "A single ember-bright feather. Revives one fallen ally at half health.", "type": Item.ItemType.REVIVAL, "value": 50, "target": Item.TargetType.SINGLE_ALLY, "price": 200},
	# Status cleansing (BATTLE items — statuses only exist during a fight).
	"Antidote": {"desc": "A chalky cure-all for venom. Cures POISON from one ally.", "type": Item.ItemType.ANTIDOTE, "cures": [StatusSystem.POISON], "value": 0, "target": Item.TargetType.SINGLE_ALLY, "price": 20},
	"Burn Salve": {"desc": "Cool green paste that draws out heat. Cures SCORCHED from one ally, restoring their attack.", "type": Item.ItemType.ANTIDOTE, "cures": [StatusSystem.SCORCHED], "value": 0, "target": Item.TargetType.SINGLE_ALLY, "price": 25},
	"Warming Tonic": {"desc": "Spiced and still steaming. Cures FROSTBITE from one ally, restoring their magic.", "type": Item.ItemType.ANTIDOTE, "cures": [StatusSystem.FROSTBITE], "value": 0, "target": Item.TargetType.SINGLE_ALLY, "price": 25},
	"Nerve Tonic": {"desc": "Sharp enough to make the eyes water. Cures PARALYSIS from one ally — otherwise it lingers all battle.", "type": Item.ItemType.ANTIDOTE, "cures": [StatusSystem.PARALYSIS], "value": 0, "target": Item.TargetType.SINGLE_ALLY, "price": 40},
	"Smelling Salts": {"desc": "A pungent snap of clarity. Wakes one ally from SLEEP and shakes off STUN.", "type": Item.ItemType.ANTIDOTE, "cures": [StatusSystem.SLEEP, StatusSystem.STUN], "value": 0, "target": Item.TargetType.SINGLE_ALLY, "price": 30},
	"Panacea": {"desc": "The alchemist's masterwork. Cures ANY status from one ally — poison, scorched, frostbite, paralysis, sleep or stun.", "type": Item.ItemType.ANTIDOTE, "cures": [StatusSystem.POISON, StatusSystem.SCORCHED, StatusSystem.FROSTBITE, StatusSystem.PARALYSIS, StatusSystem.SLEEP, StatusSystem.STUN], "value": 0, "target": Item.TargetType.SINGLE_ALLY, "price": 120},
	# Battle items (combat-only).
	"Fire Bomb": {"desc": "A clay flask that bursts into flame. Deals 40 fire damage to every enemy.", "type": Item.ItemType.DAMAGE, "value": 40, "target": Item.TargetType.ALL_ENEMIES, "price": 60},
	"Smoke Veil": {"desc": "Thick grey smoke that blurs an ally's outline. Grants a 20% chance to dodge attacks for one turn.", "type": Item.ItemType.DODGE_BUFF, "value": 20, "target": Item.TargetType.SINGLE_ALLY, "price": 80},
	# General / crafting materials (sellable; the kind of thing enemies drop).
	"Monster Fang": {"desc": "A sharp fang prised from a beast. Worth something to the right buyer.", "type": Item.ItemType.GENERAL, "value": 0, "target": Item.TargetType.SINGLE_ALLY, "price": 10},
	"Beast Hide": {"desc": "Thick, weather-beaten hide. Tanners pay well for an unmarked pelt.", "type": Item.ItemType.GENERAL, "value": 0, "target": Item.TargetType.SINGLE_ALLY, "price": 16},
	"Glimmer Dust": {"desc": "Motes shed by magical foes, still faintly warm. Sells well.", "type": Item.ItemType.GENERAL, "value": 0, "target": Item.TargetType.SINGLE_ALLY, "price": 30},
	"Worn Pendant": {"desc": "Tarnished almost black, the engraving worn smooth. Someone cared for it once.", "type": Item.ItemType.GENERAL, "value": 0, "target": Item.TargetType.SINGLE_ALLY, "price": 24},
	# Key items (story/event — never consumed or sold).
	"Amethyst Shard": {"desc": "A humming shard of amethyst. It resonates faintly with the coming Requiem.", "type": Item.ItemType.KEY, "value": 0, "target": Item.TargetType.SINGLE_ALLY, "price": 0},
	"Silent Shrine Key": {"desc": "An old key said to open one of the fallen water-shrines.", "type": Item.ItemType.KEY, "value": 0, "target": Item.TargetType.SINGLE_ALLY, "price": 0},
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
	# Only cleansing items define `cures`; everything else leaves it empty.
	var def_cures: Array = d.get("cures", [])
	var typed: Array[String] = []
	for c in def_cures:
		typed.append(String(c))
	it.cures = typed
	it.target_type = d["target"]
	it.price = int(d.get("price", 0))
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
