extends TestSuite

## Tests for the equipment system (Phase P3): Equipment restrictions + bonuses,
## Inventory equip/unequip orchestration + vital clamping, EquipmentFactory,
## SaveSerializer round-trip, the EquipmentScreen.pool_for_slot helper, and the
## equipment entries wired into enemy drop tables. No scene tree required.

func suite_name() -> String:
	return "Equipment"

# --- helpers ------------------------------------------------------------------

func _hero(cls: String, elem: int, sec: int = ElementalSystem.Element.NORMAL) -> Character:
	var c := Character.new()
	c.character_name = "Tester"
	c.character_class = cls
	c.element = elem
	c.secondary_element = sec
	return c

func _mk(name: String, slot: int, bonuses: Dictionary, cls: Array = [], els: Array = []) -> Equipment:
	var e := Equipment.new()
	e.equipment_name = name
	e.slot = slot
	e.stat_bonuses = bonuses
	var c: Array[String] = []
	for x in cls:
		c.append(String(x))
	e.class_restriction = c
	var el: Array[int] = []
	for x in els:
		el.append(int(x))
	e.element_restriction = el
	return e

# --- can_equip ----------------------------------------------------------------

func test_unrestricted_equips_for_anyone() -> void:
	var ring := _mk("Plain Ring", Equipment.Slot.ACCESSORY, {"attack": 2})
	assert_true(ring.can_equip(_hero("Warrior", ElementalSystem.Element.FIRE)), "unrestricted equips on warrior")
	assert_true(ring.can_equip(_hero("Mage", ElementalSystem.Element.WATER)), "unrestricted equips on mage")

func test_class_restriction() -> void:
	var sword := _mk("War Blade", Equipment.Slot.WEAPON, {"attack": 8}, ["Warrior"])
	assert_true(sword.can_equip(_hero("Warrior", ElementalSystem.Element.FIRE)), "warrior gear on warrior")
	assert_false(sword.can_equip(_hero("Mage", ElementalSystem.Element.FIRE)), "warrior gear blocked for mage")

func test_class_restriction_case_insensitive() -> void:
	var sword := _mk("War Blade", Equipment.Slot.WEAPON, {"attack": 8}, ["warrior"])
	assert_true(sword.can_equip(_hero("Warrior", ElementalSystem.Element.FIRE)), "class match ignores case")

func test_element_restriction_primary_and_secondary() -> void:
	var rod := _mk("Tide Rod", Equipment.Slot.WEAPON, {"magic": 10}, [], [ElementalSystem.Element.WATER])
	assert_true(rod.can_equip(_hero("Mage", ElementalSystem.Element.WATER)), "water gear on water primary")
	assert_true(rod.can_equip(_hero("Mage", ElementalSystem.Element.FIRE, ElementalSystem.Element.WATER)), "water gear matches secondary element")
	assert_false(rod.can_equip(_hero("Mage", ElementalSystem.Element.FIRE)), "water gear blocked for fire")

# --- bonus + equipment_bonus summing ------------------------------------------

func test_bonus_lookup() -> void:
	var e := _mk("Mixed", Equipment.Slot.ACCESSORY, {"attack": 4, "speed": -1})
	assert_eq(e.bonus("attack"), 4, "attack bonus")
	assert_eq(e.bonus("speed"), -1, "negative bonus")
	assert_eq(e.bonus("defense"), 0, "absent stat is zero")

func test_equipment_bonus_sums_all_slots() -> void:
	var hero := _hero("Warrior", ElementalSystem.Element.FIRE)
	var pool := Inventory.new()
	var w := _mk("Blade", Equipment.Slot.WEAPON, {"attack": 5})
	var a := _mk("Plate", Equipment.Slot.ARMOR, {"defense": 6, "max_hp": 10})
	var r1 := _mk("Ring A", Equipment.Slot.ACCESSORY, {"attack": 3})
	var r2 := _mk("Ring B", Equipment.Slot.ACCESSORY, {"attack": 2, "speed": 4})
	for e in [w, a, r1, r2]:
		pool.add_equipment(e)
		Inventory.equip_from_pool(hero, pool, e)
	var inv := hero.inventory
	assert_eq(inv.equipment_bonus("attack"), 10, "attack summed across weapon + 2 accessories")
	assert_eq(inv.equipment_bonus("defense"), 6, "defense from armor")
	assert_eq(inv.equipment_bonus("max_hp"), 10, "max_hp from armor")
	assert_eq(inv.equipment_bonus("speed"), 4, "speed from accessory")
	assert_eq(inv.equipped_list().size(), 4, "four pieces equipped")

# --- equip / unequip flow + stat deltas + clamp -------------------------------

func test_equip_changes_stats_and_unequip_restores() -> void:
	var hero := _hero("Warrior", ElementalSystem.Element.FIRE)
	var base_atk := hero.attack_power()
	var pool := Inventory.new()
	var ring := _mk("Power Ring", Equipment.Slot.ACCESSORY, {"attack": 7})
	pool.add_equipment(ring)
	assert_true(Inventory.equip_from_pool(hero, pool, ring), "equip succeeds")
	assert_eq(hero.attack_power(), base_atk + 7, "attack reflects equipped bonus")
	assert_eq(pool.equipment.size(), 0, "pool emptied on equip")
	var removed := Inventory.unequip_to_pool(hero, pool, Equipment.Slot.ACCESSORY, 0)
	assert_eq(removed, ring, "unequip returns the piece")
	assert_eq(hero.attack_power(), base_atk, "attack restored after unequip")
	assert_eq(pool.equipment.size(), 1, "piece returned to pool")

func test_equip_blocked_returns_false_and_keeps_pool() -> void:
	var mage := _hero("Mage", ElementalSystem.Element.WATER)
	var pool := Inventory.new()
	var sword := _mk("War Blade", Equipment.Slot.WEAPON, {"attack": 8}, ["Warrior"])
	pool.add_equipment(sword)
	assert_false(Inventory.equip_from_pool(mage, pool, sword), "restricted equip fails")
	assert_eq(pool.equipment.size(), 1, "piece stays in pool on failed equip")
	assert_eq(mage.inventory.equipped_weapon, null, "weapon slot stays empty")

func test_displaced_weapon_returns_to_pool() -> void:
	var hero := _hero("Warrior", ElementalSystem.Element.FIRE)
	var pool := Inventory.new()
	var w1 := _mk("Old Blade", Equipment.Slot.WEAPON, {"attack": 3})
	var w2 := _mk("New Blade", Equipment.Slot.WEAPON, {"attack": 9})
	pool.add_equipment(w1)
	pool.add_equipment(w2)
	Inventory.equip_from_pool(hero, pool, w1)
	Inventory.equip_from_pool(hero, pool, w2)
	assert_eq(hero.inventory.equipped_weapon, w2, "new weapon equipped")
	assert_true(w1 in pool.equipment, "displaced weapon back in pool")

func test_accessory_auto_picks_first_empty() -> void:
	var hero := _hero("Mage", ElementalSystem.Element.WATER)
	var pool := Inventory.new()
	var a1 := _mk("Acc 1", Equipment.Slot.ACCESSORY, {"speed": 1})
	var a2 := _mk("Acc 2", Equipment.Slot.ACCESSORY, {"speed": 2})
	pool.add_equipment(a1)
	pool.add_equipment(a2)
	Inventory.equip_from_pool(hero, pool, a1)
	Inventory.equip_from_pool(hero, pool, a2)
	assert_eq(hero.inventory.get_equipped(Equipment.Slot.ACCESSORY, 0), a1, "first accessory in slot 0")
	assert_eq(hero.inventory.get_equipped(Equipment.Slot.ACCESSORY, 1), a2, "second accessory in slot 1")

func test_unequip_clamps_overflow_hp() -> void:
	var hero := _hero("Warrior", ElementalSystem.Element.FIRE)
	var pool := Inventory.new()
	var brooch := _mk("Vitality Brooch", Equipment.Slot.ACCESSORY, {"max_hp": 25})
	pool.add_equipment(brooch)
	Inventory.equip_from_pool(hero, pool, brooch)
	hero.current_hp = hero.max_hp()          # top off at the boosted max
	var boosted_max := hero.max_hp()
	Inventory.unequip_to_pool(hero, pool, Equipment.Slot.ACCESSORY, 0)
	assert_eq(hero.max_hp(), boosted_max - 25, "max HP drops without the brooch")
	assert_eq(hero.current_hp, hero.max_hp(), "current HP clamped to new max")

# --- EquipmentFactory ---------------------------------------------------------

func test_factory_create_known() -> void:
	var sword := EquipmentFactory.create("Iron Greatsword")
	assert_true(sword != null, "known piece created")
	assert_eq(sword.equipment_name, "Iron Greatsword", "name set")
	assert_eq(sword.slot, Equipment.Slot.WEAPON, "slot set")
	assert_eq(sword.bonus("attack"), 8, "attack bonus set")
	assert_true("Warrior" in sword.class_restriction, "class restriction set")

func test_factory_create_unknown_returns_null() -> void:
	assert_eq(EquipmentFactory.create("Nonexistent Gizmo"), null, "unknown piece returns null")

func test_factory_has_equipment() -> void:
	assert_true(EquipmentFactory.has_equipment("Amethyst Sigil"), "known piece present")
	assert_false(EquipmentFactory.has_equipment("Nonexistent Gizmo"), "unknown piece absent")

func test_factory_instances_are_distinct() -> void:
	var a := EquipmentFactory.create("Power Ring")
	var b := EquipmentFactory.create("Power Ring")
	assert_ne(a, b, "two creates yield separate instances")
	a.stat_bonuses["attack"] = 999
	assert_ne(b.bonus("attack"), 999, "mutating one does not affect the other")

func test_factory_roll_drops() -> void:
	var guaranteed := [{ "item_name": "Power Ring", "chance": 1.0, "quantity": 2 }]
	var dropped := EquipmentFactory.roll_drops(guaranteed)
	assert_eq(dropped.size(), 2, "guaranteed roll yields quantity distinct pieces")
	assert_ne(dropped[0], dropped[1], "rolled pieces are distinct instances")
	assert_eq(EquipmentFactory.roll_drops([{ "item_name": "Power Ring", "chance": 0.0, "quantity": 1 }]).size(), 0, "zero-chance never rolls")
	assert_eq(EquipmentFactory.roll_drops([{ "item_name": "Nope", "chance": 1.0, "quantity": 1 }]).size(), 0, "unknown name skipped")

# --- EquipmentScreen.pool_for_slot --------------------------------------------

func test_pool_for_slot_filters_by_type() -> void:
	var pool := Inventory.new()
	pool.add_equipment(_mk("W", Equipment.Slot.WEAPON, {}))
	pool.add_equipment(_mk("A", Equipment.Slot.ARMOR, {}))
	pool.add_equipment(_mk("R1", Equipment.Slot.ACCESSORY, {}))
	pool.add_equipment(_mk("R2", Equipment.Slot.ACCESSORY, {}))
	assert_eq(EquipmentScreen.pool_for_slot(pool, Equipment.Slot.WEAPON).size(), 1, "one weapon")
	assert_eq(EquipmentScreen.pool_for_slot(pool, Equipment.Slot.ACCESSORY).size(), 2, "two accessories")
	assert_eq(EquipmentScreen.pool_for_slot(null, Equipment.Slot.WEAPON).size(), 0, "null pool safe")

# --- SaveSerializer round-trip ------------------------------------------------

func test_serialize_equipment_round_trip() -> void:
	var e := _mk("Emberbrand Blade", Equipment.Slot.WEAPON, {"attack": 10, "magic": 4}, ["Warrior"], [ElementalSystem.Element.FIRE])
	e.description = "fiery"
	e.rarity = Rarity.Tier.RARE
	var back := SaveSerializer.deserialize_equipment(SaveSerializer.serialize_equipment(e))
	assert_eq(back.equipment_name, "Emberbrand Blade", "name round-trips")
	assert_eq(back.slot, Equipment.Slot.WEAPON, "slot round-trips")
	assert_eq(back.rarity, Rarity.Tier.RARE, "rarity round-trips")
	assert_eq(back.bonus("attack"), 10, "attack bonus round-trips")
	assert_eq(back.bonus("magic"), 4, "magic bonus round-trips")
	assert_true("Warrior" in back.class_restriction, "class restriction round-trips")
	assert_true(ElementalSystem.Element.FIRE in back.element_restriction, "element restriction round-trips")

func test_serialize_inventory_equipment_round_trip() -> void:
	var hero := _hero("Warrior", ElementalSystem.Element.FIRE)
	var inv := hero.inventory
	# Equip via the hero's own inventory acting as its own pool.
	for name in ["Iron Greatsword", "Knight's Plate", "Power Ring"]:
		var piece := EquipmentFactory.create(name)
		inv.add_equipment(piece)
		Inventory.equip_from_pool(hero, inv, piece)
	# Leave a spare in the pool too.
	inv.add_equipment(EquipmentFactory.create("Guardian Charm"))

	var back := SaveSerializer.deserialize_inventory(SaveSerializer.serialize_inventory(inv))
	assert_eq(back.equipped_weapon.equipment_name, "Iron Greatsword", "weapon round-trips")
	assert_eq(back.equipped_armor.equipment_name, "Knight's Plate", "armor round-trips")
	assert_eq(back.get_equipped(Equipment.Slot.ACCESSORY, 0).equipment_name, "Power Ring", "accessory round-trips")
	assert_eq(back.equipment.size(), 1, "spare pool piece round-trips")
	assert_eq(back.equipment_bonus("attack"), inv.equipment_bonus("attack"), "summed attack bonus preserved")

func test_character_round_trip_preserves_equipment_stats() -> void:
	var hero := _hero("Warrior", ElementalSystem.Element.FIRE)
	var ring := EquipmentFactory.create("Power Ring")
	hero.inventory.add_equipment(ring)
	Inventory.equip_from_pool(hero, hero.inventory, ring)
	var atk := hero.attack_power()
	var back := SaveSerializer.deserialize_character(SaveSerializer.serialize_character(hero))
	assert_eq(back.attack_power(), atk, "equipped attack bonus survives character round-trip")
	assert_eq(back.inventory.equipped_accessories[0].equipment_name, "Power Ring", "equipped accessory survives")

# --- enemy .tres equipment drops ----------------------------------------------

func test_enemy_equipment_drops_are_known() -> void:
	var paths := [
		"res://data/enemies/dark_wraith.tres",
		"res://data/enemies/sea_serpent.tres",
		"res://data/enemies/earth_golem.tres",
	]
	var equipment_drop_seen := false
	for path in paths:
		var enemy: Enemy = load(path)
		for entry in enemy.drop_table:
			var n: String = entry["item_name"]
			assert_true(ItemFactory.has_item(n) or EquipmentFactory.has_equipment(n),
				"drop '%s' resolves to a known item or equipment" % n)
			if EquipmentFactory.has_equipment(n):
				equipment_drop_seen = true
	assert_true(equipment_drop_seen, "at least one enemy drops equipment")
