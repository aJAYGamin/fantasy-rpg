extends TestSuite

## The save safety net. Every field on a hero, a move, an item, a piece of gear,
## an inventory and the game itself must either reach the save file or be
## listed below with the reason it doesn't need to. Adding a field without doing
## either fails these tests: the alternative is a value that silently resets on
## load, as item and gear prices did until this suite existed.
##
## The round-trip tests give every saved plain value (number, flag, text) a
## value unlike its default, pass it through JSON exactly as a save file does,
## and check it comes back — so a field the loader forgets is caught too, not
## just one the writer forgets.

func suite_name() -> String:
	return "SaveCoverage"

# --- What is deliberately NOT saved, and why ----------------------------------

const BATTLE_ONLY := "battle-only, cleared by Character.clear_battle_effects"
const HAND_OFF := "a one-shot hand-off between scenes, used up on arrival"
const CONFIG_FILE := "kept in user://config.cfg, not inside a save slot"

const CHARACTER_NOT_SAVED := {
	"portrait": "art, not progress: nothing sets it yet, and hero art will come from the hero's definition",
	"combat_stat_multiplier": "difficulty scaling on enemy battle copies; heroes stay at 1.0",
	"phase_multipliers": "boss phase scaling, battle-only",
	"max_hp_multiplier": "boss transformation scaling, battle-only",
	"buffs": BATTLE_ONLY,
	"debuffs": BATTLE_ONLY,
	"buff_turns": BATTLE_ONLY,
	"debuff_turns": BATTLE_ONLY,
	"sleep_turn": BATTLE_ONLY,
	"is_defending": BATTLE_ONLY,
	"regen_turns": BATTLE_ONLY,
	"regen_amount": BATTLE_ONLY,
	"recharge_turns_left": BATTLE_ONLY,
	"dodge_chance": BATTLE_ONLY,
	"pending_learned": "hand-off from a battle to its victory screen",
}
const SKILL_NOT_SAVED := {}
const ITEM_NOT_SAVED := {}
const EQUIPMENT_NOT_SAVED := {}
const INVENTORY_NOT_SAVED := {}

## GameManager: each saved field -> where it lives in the save ("a/b" = nested).
const GAME_SAVED := {
	"party": "party",
	"species_memory": "species_memory",
	"gold": "gold",
	"current_map": "current_map",
	"clock": "time_minutes",
	"quest_log": "quests",
	"story_flags": "story_flags",
	"play_time_seconds": "metadata/playtime_seconds",
	"save_overworld_scene_path": "overworld_scene_path",
	"save_overworld_position": "overworld_position",
	"inn_cost_tier": "inn_cost_tier",
	"rest_swaps_remaining": "rest_swaps_remaining",
	"battles_since_rest_refresh": "battles_since_rest_refresh",
	"rest_available": "rest_available",
	# The roamers of the map the save was made on (initialized = a region is named).
	"roamer_region": "roamers/region",
	"roamers_initialized": "roamers/region",
	"roamer_states": "roamers/states",
}
const GAME_NOT_SAVED := {
	"in_overworld_battle": HAND_OFF,
	"pending_battle_enemies": HAND_OFF,
	"pending_battle_background": HAND_OFF,
	"pending_overworld_scene_path": HAND_OFF,
	"pending_overworld_return_position": HAND_OFF,
	"pending_roamer_id": HAND_OFF,
	"last_battle_won": HAND_OFF,
	"pending_flee_iframes": HAND_OFF,
	"pending_transition_active": HAND_OFF,
	"pending_transition_spawn": HAND_OFF,
	"pending_fade_in": HAND_OFF,
	"transition_origin_scene": HAND_OFF,
	"transition_origin_pos": HAND_OFF,
	"resuming_from_save": HAND_OFF,
	"roamer_snapshot": "a live hook into the current map's roamers, not data",
	"active_slot": CONFIG_FILE,
	"settings": CONFIG_FILE,
	"input_profiles": CONFIG_FILE,
}

# --- Helpers ------------------------------------------------------------------

## An object's own fields: its script variables, exported or not. Engine
## properties, inspector groups and underscore-private runtime state are left out.
func _fields(obj: Object) -> Array[String]:
	var out: Array[String] = []
	for p in obj.get_property_list():
		var name := String(p["name"])
		if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) and not name.begins_with("_"):
			out.append(name)
	return out

func _check_coverage(what: String, obj: Object, saved: Array, not_saved: Dictionary) -> void:
	var fields := _fields(obj)
	for f in fields:
		assert_true(saved.has(f) or not_saved.has(f),
				"%s.%s is saved, or listed as not saved with a reason" % [what, f])
	for f in not_saved:
		assert_true(fields.has(f), "%s.%s is still a field (no stale entries)" % [what, f])
		assert_false(saved.has(f), "%s.%s is not both saved and excused" % [what, f])

## Gives every saved plain field (int, float, bool, String) a value unlike its
## default.
func _scramble(obj: Object, saved: Array) -> void:
	for p in obj.get_property_list():
		var name := String(p["name"])
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) or not saved.has(name):
			continue
		match int(p["type"]):
			TYPE_INT:
				obj.set(name, int(obj.get(name)) + 3)
			TYPE_FLOAT:
				obj.set(name, float(obj.get(name)) + 1.25)
			TYPE_BOOL:
				obj.set(name, not bool(obj.get(name)))
			TYPE_STRING:
				obj.set(name, String(obj.get(name)) + "x")

## Every saved plain field of `before` came back unchanged on `after`.
func _check_round_trip(what: String, before: Object, after: Object, saved: Array) -> void:
	for p in before.get_property_list():
		var name := String(p["name"])
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) or not saved.has(name):
			continue
		match int(p["type"]):
			TYPE_FLOAT:
				assert_near(float(after.get(name)), float(before.get(name)), 0.0001,
						"%s.%s survives a save and load" % [what, name])
			TYPE_INT, TYPE_BOOL, TYPE_STRING:
				assert_eq(after.get(name), before.get(name), "%s.%s survives a save and load" % [what, name])

## Through JSON and back, exactly as a save file stores it.
func _through_json(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))

# --- Every field is saved or excused -------------------------------------------

func test_every_character_field_is_saved_or_excused() -> void:
	var c := Character.new()
	c.inventory = Inventory.new()
	_check_coverage("Character", c, SaveSerializer.serialize_character(c).keys(), CHARACTER_NOT_SAVED)

func test_every_skill_field_is_saved_or_excused() -> void:
	_check_coverage("Skill", Skill.new(), SaveSerializer.serialize_skill(Skill.new()).keys(), SKILL_NOT_SAVED)

func test_every_item_field_is_saved_or_excused() -> void:
	_check_coverage("Item", Item.new(), SaveSerializer.serialize_item(Item.new()).keys(), ITEM_NOT_SAVED)

func test_every_equipment_field_is_saved_or_excused() -> void:
	_check_coverage("Equipment", Equipment.new(),
			SaveSerializer.serialize_equipment(Equipment.new()).keys(), EQUIPMENT_NOT_SAVED)

func test_every_inventory_field_is_saved_or_excused() -> void:
	_check_coverage("Inventory", Inventory.new(),
			SaveSerializer.serialize_inventory(Inventory.new()).keys(), INVENTORY_NOT_SAVED)

func test_every_game_field_is_saved_or_excused() -> void:
	_check_coverage("GameManager", GameManager, GAME_SAVED.keys(), GAME_NOT_SAVED)
	var d: Dictionary = GameManager._build_save_dict()
	for field in GAME_SAVED:
		var at = d
		for part in String(GAME_SAVED[field]).split("/"):
			at = at.get(part) if at is Dictionary else null
		assert_true(at != null, "GameManager.%s is written to the save as \"%s\"" % [field, GAME_SAVED[field]])

# --- Every saved value comes back -----------------------------------------------

func test_every_saved_skill_value_survives_a_round_trip() -> void:
	var s := Skill.new()
	var saved := SaveSerializer.serialize_skill(s).keys()
	_scramble(s, saved)
	_check_round_trip("Skill", s, SaveSerializer.deserialize_skill(_through_json(SaveSerializer.serialize_skill(s))), saved)

func test_every_saved_item_value_survives_a_round_trip() -> void:
	var it := Item.new()
	var saved := SaveSerializer.serialize_item(it).keys()
	_scramble(it, saved)
	_check_round_trip("Item", it, SaveSerializer.deserialize_item(_through_json(SaveSerializer.serialize_item(it))), saved)

func test_every_saved_equipment_value_survives_a_round_trip() -> void:
	var eq := Equipment.new()
	var saved := SaveSerializer.serialize_equipment(eq).keys()
	_scramble(eq, saved)
	_check_round_trip("Equipment", eq,
			SaveSerializer.deserialize_equipment(_through_json(SaveSerializer.serialize_equipment(eq))), saved)

func test_every_saved_character_value_survives_a_round_trip() -> void:
	var c := Character.new()
	c.inventory = Inventory.new()
	var saved := SaveSerializer.serialize_character(c).keys()
	_scramble(c, saved)
	_check_round_trip("Character", c,
			SaveSerializer.deserialize_character(_through_json(SaveSerializer.serialize_character(c))), saved)

func test_the_game_state_survives_a_round_trip() -> void:
	var gm := GameManager
	var party_before: Array[Character] = gm.party
	var original: Dictionary = gm._build_save_dict()
	gm.gold = 4321
	gm.current_map = "probe_map"
	gm.clock.set_minutes(777.0)
	gm.story_flags = {"probe_flag": true}
	gm.species_memory = {"ProbeSpecies": 9}
	gm.play_time_seconds = 1234.5
	gm.save_overworld_scene_path = "res://probe.tscn"
	gm.save_overworld_position = Vector2(12, 34)
	gm.inn_cost_tier = 2
	gm.rest_swaps_remaining = maxi(0, GameManager.REST_SWAP_ALLOWANCE - 1)
	gm.battles_since_rest_refresh = 4
	gm.rest_available = not gm.rest_available
	var probe_rest_available := gm.rest_available
	var roamers_before := {"region": gm.roamer_region, "init": gm.roamers_initialized,
			"states": gm.roamer_states, "hook": gm.roamer_snapshot}
	gm.roamer_snapshot = Callable()
	gm.set_roamer_state("res://probe.tscn", [{"id": 5, "group_index": 0, "position": Vector2(40, 50),
			"home": Rect2(0, 0, 900, 900), "home_poly": PackedVector2Array()}])
	var saved := _through_json(gm._build_save_dict())
	# Back to the original values first, so a field the loader skips keeps the
	# original and shows up as wrong.
	gm._apply_save_dict(original)
	gm._apply_save_dict(saved)
	var got := {
		"gold": gm.gold, "map": gm.current_map, "minutes": gm.clock.minutes,
		"flag": gm.story_flags.get("probe_flag", false), "memory": gm.species_memory.get("ProbeSpecies"),
		"play": gm.play_time_seconds, "scene": gm.save_overworld_scene_path,
		"pos": gm.save_overworld_position, "inn": gm.inn_cost_tier,
		"swaps": gm.rest_swaps_remaining, "battles": gm.battles_since_rest_refresh,
		"rest": gm.rest_available,
		"roamer_region": gm.roamer_region, "roamers": gm.roamer_states.duplicate(),
	}
	gm._apply_save_dict(original)
	gm.party = party_before
	gm.roamer_region = roamers_before["region"]
	gm.roamers_initialized = roamers_before["init"]
	gm.roamer_states = roamers_before["states"]
	gm.roamer_snapshot = roamers_before["hook"]
	assert_eq(got["gold"], 4321, "gold")
	assert_eq(got["map"], "probe_map", "current map")
	assert_near(got["minutes"], 777.0, 0.01, "time of day")
	assert_true(got["flag"], "story flags")
	assert_eq(got["memory"], 9, "Memory Echo counts")
	assert_eq(typeof(got["memory"]), TYPE_INT, "which come back as whole numbers, not decimals")
	assert_near(got["play"], 1234.5, 0.01, "play time")
	assert_eq(got["scene"], "res://probe.tscn", "saved scene")
	assert_eq(got["pos"], Vector2(12, 34), "saved position")
	assert_eq(got["inn"], 2, "inn price tier")
	assert_eq(got["swaps"], maxi(0, GameManager.REST_SWAP_ALLOWANCE - 1), "rest-area swaps left")
	assert_eq(got["battles"], 4, "battles since the rest area refreshed")
	assert_eq(got["rest"], probe_rest_available, "rest available")
	assert_eq(got["roamer_region"], "res://probe.tscn", "the saved map's roamers")
	assert_eq(got["roamers"].size(), 1, "every one left")
	assert_eq(got["roamers"][0]["position"] if got["roamers"].size() > 0 else null, Vector2(40, 50),
			"where each stood")

# --- Saves written before prices were stored ------------------------------------

func test_an_old_save_gets_item_prices_from_the_catalog() -> void:
	var d := SaveSerializer.serialize_item(ItemFactory.create("Health Potion"))
	d.erase("price")
	assert_eq(SaveSerializer.deserialize_item(d).price, int(ItemFactory.DEFS["Health Potion"]["price"]),
			"a Health Potion saved without its price can be sold again")

func test_an_old_save_gets_gear_prices_from_the_catalog() -> void:
	# Gear prices are worked out from rarity and stats when a piece is made.
	var made := EquipmentFactory.create("Iron Greatsword")
	assert_true(made.price > 0, "the catalog prices it")
	var d := SaveSerializer.serialize_equipment(made)
	d.erase("price")
	assert_eq(SaveSerializer.deserialize_equipment(d).price, made.price,
			"an Iron Greatsword saved without its price can be sold again")

func test_an_old_save_item_the_catalog_does_not_know_stays_unpriced() -> void:
	var d := {"item_name": "Mystery Trinket", "item_type": Item.ItemType.HP_RESTORE}
	assert_eq(SaveSerializer.deserialize_item(d).price, 0, "unknown items load as before, unsellable")
