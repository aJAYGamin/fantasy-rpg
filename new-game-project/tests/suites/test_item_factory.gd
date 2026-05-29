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
