class_name ShopFactory
extends RefCounted

## Named shop inventories. A shop sells a fixed list of item names (ItemFactory) and
## equipment names (EquipmentFactory). Shopkeeper NPCs open a ShopScreen for a shop_id.

const DEFS := {
	# Item / apothecary shop — consumables + battle items.
	"apothecary": {
		"name": "Apothecary",
		"items": ["Health Potion", "Mana Potion", "Antidote", "Elixir", "Phoenix Down", "Fire Bomb", "Smoke Veil"],
		"equipment": [],
	},
	# Weapon & armor shop.
	"armory": {
		"name": "Armory",
		"items": [],
		"equipment": ["Worn Shortsword", "Iron Greatsword", "Apprentice Staff", "Cedar Wand",
			"Leather Vest", "Mage Robe", "Galewind Cloak", "Power Ring", "Guardian Charm", "Swift Boots"],
	},
	# Village / small-town general store — a little of both.
	"general_store": {
		"name": "General Store",
		"items": ["Health Potion", "Mana Potion", "Antidote"],
		"equipment": ["Worn Shortsword", "Leather Vest", "Power Ring"],
	},
}

static func has_shop(id: String) -> bool:
	return DEFS.has(id)

static func shop_name(id: String) -> String:
	return String((DEFS.get(id, {}) as Dictionary).get("name", "Shop"))

static func item_names(id: String) -> Array:
	return (DEFS.get(id, {}) as Dictionary).get("items", [])

static func equipment_names(id: String) -> Array:
	return (DEFS.get(id, {}) as Dictionary).get("equipment", [])
