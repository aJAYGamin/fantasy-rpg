extends TestSuite

## Tests for ItemFactory (named item definitions + drop rolling) and the enemy
## drop tables wired into the .tres data. No scene tree required.

func suite_name() -> String:
	return "ItemFactory"

# --- create / has_item --------------------------------------------------------

func test_create_known_item() -> void:
	var potion := ItemFactory.create("Health Potion")
	assert_true(potion != null, "known item created")
	assert_eq(potion.item_name, "Health Potion", "name set")
	assert_eq(potion.item_type, Item.ItemType.HP_RESTORE, "type set")
	assert_eq(potion.effect_value, 50, "effect value set")
	assert_eq(potion.quantity, 1, "default quantity is 1")

func test_create_with_quantity() -> void:
	var fangs := ItemFactory.create("Monster Fang", 3)
	assert_eq(fangs.quantity, 3, "quantity honored")

func test_create_unknown_returns_null() -> void:
	assert_eq(ItemFactory.create("Nonexistent Widget"), null, "unknown item returns null")

func test_has_item() -> void:
	assert_true(ItemFactory.has_item("Elixir"), "known item reported present")
	assert_false(ItemFactory.has_item("Nonexistent Widget"), "unknown item reported absent")

func test_key_item_category() -> void:
	var key := ItemFactory.create("Amethyst Shard")
	assert_eq(key.get_category(), Item.ItemCategory.KEY, "shard is a key item")

# --- roll_drops ---------------------------------------------------------------

func test_roll_drops_guaranteed() -> void:
	var table := [
		{ "item_name": "Monster Fang", "chance": 1.0, "quantity": 2 },
		{ "item_name": "Beast Hide", "chance": 1.0, "quantity": 1 },
	]
	var dropped := ItemFactory.roll_drops(table)
	assert_eq(dropped.size(), 2, "both guaranteed drops rolled")
	assert_eq(dropped[0].quantity, 2, "drop quantity honored")

func test_roll_drops_impossible() -> void:
	var table := [{ "item_name": "Monster Fang", "chance": 0.0, "quantity": 1 }]
	assert_eq(ItemFactory.roll_drops(table).size(), 0, "zero-chance drop never rolls")

func test_roll_drops_skips_unknown() -> void:
	var table := [{ "item_name": "Nonexistent Widget", "chance": 1.0, "quantity": 1 }]
	assert_eq(ItemFactory.roll_drops(table).size(), 0, "unknown drop name skipped")

func test_roll_drops_empty_table() -> void:
	assert_eq(ItemFactory.roll_drops([]).size(), 0, "empty drop table yields nothing")

# --- enemy .tres drop tables --------------------------------------------------

func test_enemy_drop_tables_loaded() -> void:
	var paths := {
		"res://data/enemies/dark_wraith.tres": 3,
		"res://data/enemies/sea_serpent.tres": 4,
		"res://data/enemies/earth_golem.tres": 4,
	}
	for path in paths:
		var enemy: Enemy = load(path)
		assert_true(enemy != null, "%s loads" % path)
		assert_eq(enemy.drop_table.size(), paths[path], "%s has expected drop count" % path)

func test_enemy_drop_names_are_known() -> void:
	# Drops route to either ItemFactory (consumables) or EquipmentFactory (gear).
	var enemy: Enemy = load("res://data/enemies/dark_wraith.tres")
	for entry in enemy.drop_table:
		var n: String = entry["item_name"]
		assert_true(ItemFactory.has_item(n) or EquipmentFactory.has_equipment(n),
			"drop '%s' is a known item or equipment" % n)

# --- Status cleansing -----------------------------------------------------------
# Cleansing is driven by each item's `cures` list, never by its name, so adding a
# cure is a data change. Statuses are battle-temp, so every cleanser is a BATTLE
# item — a cleanse used in the overworld could never have anything to remove.

func _afflicted(status: String) -> Character:
	var c := Character.new()
	c.character_name = "Patient"
	c.base_hp = 100
	c.level = 1
	c.current_hp = c.max_hp()
	c.add_status(status)
	return c

func test_every_mutex_status_has_a_cure() -> void:
	# The gap this work closes: only poison could be cured, and paralysis
	# cleared solely at battle end.
	for status in StatusSystem.MUTEX_STATUSES:
		var covered := false
		for name in ItemFactory.DEFS:
			var d: Dictionary = ItemFactory.DEFS[name]
			if status in d.get("cures", []):
				covered = true
				break
		assert_true(covered, "some item cures '%s'" % status)

func test_a_specific_cleanser_removes_only_its_status() -> void:
	var salve := ItemFactory.create("Burn Salve")
	var scorched := _afflicted(StatusSystem.SCORCHED)
	salve.use(scorched)
	assert_false(scorched.is_status(StatusSystem.SCORCHED), "the salve cured scorched")

	var poisoned := _afflicted(StatusSystem.POISON)
	ItemFactory.create("Burn Salve").use(poisoned)
	assert_true(poisoned.is_status(StatusSystem.POISON), "but it does nothing for poison")

func test_the_panacea_cures_any_single_status() -> void:
	for status in StatusSystem.MUTEX_STATUSES:
		var victim := _afflicted(status)
		# Skip statuses this character is elementally immune to.
		if not victim.is_status(status):
			continue
		ItemFactory.create("Panacea").use(victim)
		assert_false(victim.is_status(status), "panacea cured '%s'" % status)

func test_smelling_salts_cover_both_sleep_and_stun() -> void:
	var asleep := _afflicted(StatusSystem.SLEEP)
	ItemFactory.create("Smelling Salts").use(asleep)
	assert_false(asleep.is_status(StatusSystem.SLEEP), "woke them")
	var stunned := _afflicted(StatusSystem.STUN)
	ItemFactory.create("Smelling Salts").use(stunned)
	assert_false(stunned.is_status(StatusSystem.STUN), "and cleared a stun")

func test_paralysis_is_curable_at_all() -> void:
	# It previously cleared ONLY at battle end — there was no answer to it.
	var c := _afflicted(StatusSystem.PARALYSIS)
	ItemFactory.create("Nerve Tonic").use(c)
	assert_false(c.is_status(StatusSystem.PARALYSIS), "a nerve tonic answers paralysis")

func test_use_reports_what_it_actually_cured() -> void:
	var healthy := Character.new()
	healthy.base_hp = 50
	healthy.level = 1
	healthy.current_hp = healthy.max_hp()
	var result: Dictionary = ItemFactory.create("Panacea").use(healthy)
	assert_eq(int(result.get("value", -1)), 0, "curing nothing reports nothing cured")

func test_can_cleanse_gates_the_use_button() -> void:
	var salve := ItemFactory.create("Burn Salve")
	var healthy := Character.new()
	healthy.base_hp = 50
	healthy.level = 1
	healthy.current_hp = healthy.max_hp()
	assert_false(salve.can_cleanse(healthy), "nothing to cure")
	assert_true(salve.can_cleanse(_afflicted(StatusSystem.SCORCHED)), "something to cure")
	assert_false(salve.can_cleanse(null), "a null target is not a crash")

func test_every_cleanser_is_a_battle_item() -> void:
	for name in ItemFactory.DEFS:
		var d: Dictionary = ItemFactory.DEFS[name]
		if d.get("cures", []).is_empty():
			continue
		var it := ItemFactory.create(name)
		assert_eq(it.get_category(), Item.ItemCategory.BATTLE, "%s is a battle item" % name)
		assert_false(it.is_field_usable(), "%s is not usable in the overworld" % name)

func test_cures_survive_a_save_round_trip() -> void:
	# A new field that never reaches SaveSerializer loads as [] and the item
	# becomes silently inert.
	var panacea := ItemFactory.create("Panacea")
	var back := SaveSerializer.deserialize_item(SaveSerializer.serialize_item(panacea))
	assert_eq(back.cures.size(), panacea.cures.size(), "the cures list round-trips")
	var victim := _afflicted(StatusSystem.FROSTBITE)
	back.use(victim)
	assert_false(victim.is_status(StatusSystem.FROSTBITE), "and the loaded item still works")

func test_a_legacy_antidote_save_still_cures_poison() -> void:
	# Pre-cleansing saves have no "cures" key; without a migration the old
	# Antidote would load inert.
	var legacy := {"item_name": "Antidote", "item_type": Item.ItemType.ANTIDOTE, "quantity": 1}
	var it := SaveSerializer.deserialize_item(legacy)
	var poisoned := _afflicted(StatusSystem.POISON)
	it.use(poisoned)
	assert_false(poisoned.is_status(StatusSystem.POISON), "a legacy antidote is not inert")
