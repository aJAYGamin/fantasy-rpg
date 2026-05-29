class_name EquipmentFactory
extends RefCounted

## Single source of truth for named equipment definitions. Mirrors ItemFactory:
## create() builds a fresh Equipment instance; roll_drops() rolls a drop table.
## Each created piece is a distinct physical instance (equipment never stacks).

const DEFS := {
	# --- Weapons --------------------------------------------------------------
	"Worn Shortsword": {
		"desc": "A chipped blade that has seen better days.",
		"slot": Equipment.Slot.WEAPON,
		"rarity": Rarity.Tier.COMMON,
		"bonuses": {"attack": 3},
	},
	"Iron Greatsword": {
		"desc": "Heavy two-handed steel. Slows the wielder but hits hard.",
		"slot": Equipment.Slot.WEAPON,
		"rarity": Rarity.Tier.UNCOMMON,
		"bonuses": {"attack": 8, "speed": -1},
		"class_restriction": ["Warrior"],
	},
	"Apprentice Staff": {
		"desc": "A practice staff humming with faint arcane energy.",
		"slot": Equipment.Slot.WEAPON,
		"rarity": Rarity.Tier.COMMON,
		"bonuses": {"magic": 6, "max_mp": 5},
		"class_restriction": ["Mage"],
	},
	"Cedar Wand": {
		"desc": "A gentle wand favored by field medics.",
		"slot": Equipment.Slot.WEAPON,
		"rarity": Rarity.Tier.COMMON,
		"bonuses": {"magic": 4, "arcane": 2},
		"class_restriction": ["Healer"],
	},
	"Emberbrand Blade": {
		"desc": "A sword wreathed in everlasting embers.",
		"slot": Equipment.Slot.WEAPON,
		"rarity": Rarity.Tier.RARE,
		"bonuses": {"attack": 10, "magic": 4},
		"element_restriction": [ElementalSystem.Element.FIRE],
	},
	"Tidecaller Rod": {
		"desc": "A coral rod that channels the tides.",
		"slot": Equipment.Slot.WEAPON,
		"rarity": Rarity.Tier.RARE,
		"bonuses": {"magic": 10, "max_mp": 8},
		"element_restriction": [ElementalSystem.Element.WATER],
	},

	# --- Armor ----------------------------------------------------------------
	"Leather Vest": {
		"desc": "Simple boiled-leather protection.",
		"slot": Equipment.Slot.ARMOR,
		"rarity": Rarity.Tier.COMMON,
		"bonuses": {"defense": 3},
	},
	"Knight's Plate": {
		"desc": "Full steel plate. Sturdy, but cumbersome.",
		"slot": Equipment.Slot.ARMOR,
		"rarity": Rarity.Tier.UNCOMMON,
		"bonuses": {"defense": 9, "max_hp": 10, "speed": -2},
		"class_restriction": ["Warrior"],
	},
	"Mage Robe": {
		"desc": "Enchanted cloth that wards off hostile magic.",
		"slot": Equipment.Slot.ARMOR,
		"rarity": Rarity.Tier.COMMON,
		"bonuses": {"arcane": 6, "max_mp": 6},
		"class_restriction": ["Mage"],
	},
	"Healer's Garb": {
		"desc": "Blessed vestments that bolster vitality.",
		"slot": Equipment.Slot.ARMOR,
		"rarity": Rarity.Tier.COMMON,
		"bonuses": {"arcane": 4, "max_hp": 8},
		"class_restriction": ["Healer"],
	},
	"Galewind Cloak": {
		"desc": "A cloak that always billows, even in still air.",
		"slot": Equipment.Slot.ARMOR,
		"rarity": Rarity.Tier.RARE,
		"bonuses": {"defense": 5, "speed": 6},
		"element_restriction": [ElementalSystem.Element.WIND],
	},

	# --- Accessories ----------------------------------------------------------
	"Power Ring": {
		"desc": "A band that lends raw strength.",
		"slot": Equipment.Slot.ACCESSORY,
		"rarity": Rarity.Tier.UNCOMMON,
		"bonuses": {"attack": 4},
	},
	"Guardian Charm": {
		"desc": "A warding charm against blade and spell alike.",
		"slot": Equipment.Slot.ACCESSORY,
		"rarity": Rarity.Tier.UNCOMMON,
		"bonuses": {"defense": 3, "arcane": 3},
	},
	"Swift Boots": {
		"desc": "Featherlight boots that quicken the step.",
		"slot": Equipment.Slot.ACCESSORY,
		"rarity": Rarity.Tier.UNCOMMON,
		"bonuses": {"speed": 5},
	},
	"Sage Pendant": {
		"desc": "A pendant that deepens one's magical wellspring.",
		"slot": Equipment.Slot.ACCESSORY,
		"rarity": Rarity.Tier.RARE,
		"bonuses": {"magic": 5, "max_mp": 10},
	},
	"Vitality Brooch": {
		"desc": "A brooch that fortifies the body.",
		"slot": Equipment.Slot.ACCESSORY,
		"rarity": Rarity.Tier.RARE,
		"bonuses": {"max_hp": 25},
	},
	"Phoenix Feather": {
		"desc": "A smoldering plume that burns for its bearer.",
		"slot": Equipment.Slot.ACCESSORY,
		"rarity": Rarity.Tier.EPIC,
		"bonuses": {"attack": 5, "max_hp": 15},
		"element_restriction": [ElementalSystem.Element.FIRE],
	},
	"Amethyst Sigil": {
		"desc": "A signet that strengthens every facet of its wielder.",
		"slot": Equipment.Slot.ACCESSORY,
		"rarity": Rarity.Tier.LEGENDARY,
		"bonuses": {"attack": 4, "defense": 4, "magic": 4, "arcane": 4, "speed": 4},
	},
}

static func has_equipment(name: String) -> bool:
	return DEFS.has(name)

static func create(name: String) -> Equipment:
	if not DEFS.has(name):
		push_warning("EquipmentFactory: unknown equipment '%s'" % name)
		return null
	var d: Dictionary = DEFS[name]
	var e := Equipment.new()
	e.equipment_name = name
	e.description = d.get("desc", "")
	e.slot = d.get("slot", Equipment.Slot.WEAPON)
	e.rarity = d.get("rarity", Rarity.Tier.COMMON)
	e.stat_bonuses = (d.get("bonuses", {}) as Dictionary).duplicate(true)
	var cls: Array[String] = []
	for c in d.get("class_restriction", []):
		cls.append(String(c))
	e.class_restriction = cls
	var els: Array[int] = []
	for el in d.get("element_restriction", []):
		els.append(int(el))
	e.element_restriction = els
	return e

# Rolls a drop table ([{item_name, chance, quantity}]). Each successful roll
# yields `quantity` distinct pieces. Unknown names are skipped.
static func roll_drops(drop_table: Array) -> Array[Equipment]:
	var dropped: Array[Equipment] = []
	for entry in drop_table:
		if randf() < float(entry.get("chance", 0.0)):
			for i in range(max(1, int(entry.get("quantity", 1)))):
				var e := create(String(entry.get("item_name", "")))
				if e != null:
					dropped.append(e)
	return dropped
