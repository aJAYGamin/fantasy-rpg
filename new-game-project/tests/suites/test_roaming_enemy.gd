extends TestSuite

## Roaming-enemy encounters (P7): territory clamping, persistent region-scoped
## state (no respawn until you leave & return), flee i-frame handoff, and the
## RoamingEnemy data holder.

const OverworldScene := preload("res://scripts/overworld/OverworldScene.gd")

func suite_name() -> String:
	return "RoamingEnemy"

# --- Pure helpers -------------------------------------------------------------
func test_point_in_zones() -> void:
	var zones := [Rect2(800, 800, 100, 100)]
	assert_true(OverworldScene._point_in_zones(Vector2(850, 850), zones), "point inside zone detected")
	assert_false(OverworldScene._point_in_zones(Vector2(50, 50), zones), "point outside zone")

func test_rect_overlaps_any() -> void:
	var zones := [Rect2(800, 800, 100, 100)]
	assert_true(OverworldScene._rect_overlaps_any(Rect2(850, 850, 200, 200), zones), "overlapping rect detected")
	assert_false(OverworldScene._rect_overlaps_any(Rect2(0, 0, 100, 100), zones), "non-overlapping rect")

# --- RoamingEnemy node --------------------------------------------------------
func test_setup_stores_data_and_territory() -> void:
	var r := RoamingEnemy.new()
	var group := EncounterGroup.new()
	group.group_name = "Test Pack"
	var home := Rect2(100, 100, 500, 500)
	r.setup(7, group, 2, null, home)
	assert_eq(r.spawn_id, 7, "spawn_id stored")
	assert_eq(r.group_index, 2, "group_index stored")
	assert_eq(r.encounter_group, group, "encounter group stored")
	assert_eq(r.home_rect, home, "home territory stored")
	r.free()

func test_clamp_to_home_keeps_enemy_in_territory() -> void:
	var r := RoamingEnemy.new()
	r.home_rect = Rect2(100, 100, 400, 400)   # spans 100..500
	# A point far outside should clamp back inside (accounting for half-size inset).
	var clamped: Vector2 = r._clamp_to_home(Vector2(9999, 9999))
	assert_true(clamped.x <= 500 and clamped.y <= 500, "clamped within max bound")
	assert_true(clamped.x >= 100 and clamped.y >= 100, "clamped within min bound")
	# A point already inside is unchanged.
	assert_eq(r._clamp_to_home(Vector2(300, 300)), Vector2(300, 300), "inside point unchanged")
	r.free()

func test_freeze_stops_movement() -> void:
	var r := RoamingEnemy.new()
	r.velocity = Vector2(50, 0)
	r.freeze()
	assert_eq(r.velocity, Vector2.ZERO, "freeze zeroes velocity")
	r.free()

func test_player_in_territory_is_strict() -> void:
	# Bug #3: the enemy must NOT consider a player just outside its territory as
	# in-territory (no grow margin) — outside = no tracking/chase/touch.
	var r := RoamingEnemy.new()
	r.home_rect = Rect2(1000, 1000, 400, 400)   # spans 1000..1400
	var inside := Node2D.new()
	inside.global_position = Vector2(1200, 1200)
	r._player = inside
	assert_true(r._player_in_territory(), "player inside the territory is tracked")
	var just_outside := Node2D.new()
	just_outside.global_position = Vector2(1450, 1200)   # 50px past the right edge
	r._player = just_outside
	assert_false(r._player_in_territory(), "player just outside the territory is NOT tracked")
	inside.free()
	just_outside.free()
	r.free()

# --- Persistent region state --------------------------------------------------
func test_region_state_save_and_query() -> void:
	var prev_region: String = GameManager.roamer_region
	var prev_init: bool = GameManager.roamers_initialized
	var prev_states: Array = GameManager.roamer_states.duplicate()

	GameManager.clear_roamer_state()
	assert_false(GameManager.has_roamer_state_for("res://A.tscn"), "no state after clear")

	var states := [
		{"id": 1, "group_index": 0, "position": Vector2(10, 10), "home": Rect2(0, 0, 100, 100)},
		{"id": 2, "group_index": 0, "position": Vector2(20, 20), "home": Rect2(0, 0, 100, 100)},
	]
	GameManager.set_roamer_state("res://A.tscn", states)
	assert_true(GameManager.has_roamer_state_for("res://A.tscn"), "state present for region A")
	assert_false(GameManager.has_roamer_state_for("res://B.tscn"), "different region has no state -> fresh spawn")

	# Restore prior state.
	GameManager.roamer_region = prev_region
	GameManager.roamers_initialized = prev_init
	GameManager.roamer_states = prev_states

func test_remove_defeated_roamer() -> void:
	var prev_region: String = GameManager.roamer_region
	var prev_init: bool = GameManager.roamers_initialized
	var prev_states: Array = GameManager.roamer_states.duplicate()

	GameManager.set_roamer_state("res://A.tscn", [
		{"id": 1, "group_index": 0, "position": Vector2.ZERO, "home": Rect2()},
		{"id": 2, "group_index": 0, "position": Vector2.ZERO, "home": Rect2()},
	])
	GameManager.remove_roamer_state(1)
	assert_eq(GameManager.roamer_states.size(), 1, "defeated roamer removed")
	assert_eq(int(GameManager.roamer_states[0]["id"]), 2, "survivor remains")

	GameManager.roamer_region = prev_region
	GameManager.roamers_initialized = prev_init
	GameManager.roamer_states = prev_states

func test_flee_iframe_flag() -> void:
	var prev: bool = GameManager.pending_flee_iframes
	GameManager.pending_flee_iframes = true
	assert_true(GameManager.pending_flee_iframes, "flee flag set on run")
	GameManager.pending_flee_iframes = prev

func test_roamer_handoff_fields() -> void:
	var prev_id: int = GameManager.pending_roamer_id
	var prev_won: bool = GameManager.last_battle_won
	GameManager.pending_roamer_id = 42
	GameManager.last_battle_won = false
	assert_eq(GameManager.pending_roamer_id, 42, "roamer id handed off to battle")
	GameManager.last_battle_won = true
	assert_true(GameManager.last_battle_won, "win recorded for return check")
	GameManager.pending_roamer_id = prev_id
	GameManager.last_battle_won = prev_won

# --- Roamers in saves (Track C) -------------------------------------------------
# A save remembers the roaming enemies of the map it was made on — which are
# left, where each stands and the area it patrols — so a cleared map stays
# cleared after a quit and load. Leaving a map still refills it.

func _snapshot_roamers() -> Dictionary:
	return {"region": GameManager.roamer_region, "init": GameManager.roamers_initialized,
			"states": GameManager.roamer_states.duplicate(), "hook": GameManager.roamer_snapshot,
			"path": GameManager.save_overworld_scene_path}

func _restore_roamers(s: Dictionary) -> void:
	GameManager.roamer_region = s["region"]
	GameManager.roamers_initialized = s["init"]
	GameManager.roamer_states = s["states"]
	GameManager.roamer_snapshot = s["hook"]
	GameManager.save_overworld_scene_path = s["path"]

func _a_roamer(id: int, pos: Vector2) -> Dictionary:
	return {"id": id, "group_index": 1, "position": pos, "home": Rect2(100, 200, 900, 900),
			"home_poly": PackedVector2Array([Vector2(100, 200), Vector2(1000, 200), Vector2(550, 1100)])}

## Loads a save that differs from the current game only in where it was made and
## its roamers block (null = a save from before roamers were saved), reports the
## roamer state that results, then puts the whole game back.
func _roamers_after_loading(scene: String, roamers) -> Dictionary:
	var party_before: Array[Character] = GameManager.party
	var snap := _snapshot_roamers()
	var original: Dictionary = GameManager._build_save_dict()
	var data: Dictionary = original.duplicate(true)
	data["overworld_scene_path"] = scene
	if roamers == null:
		data.erase("roamers")
	else:
		data["roamers"] = roamers
	GameManager._apply_save_dict(JSON.parse_string(JSON.stringify(data)))
	var got := {"initialized": GameManager.roamers_initialized, "region": GameManager.roamer_region,
			"states": GameManager.roamer_states.duplicate()}
	GameManager._apply_save_dict(original)
	GameManager.party = party_before
	_restore_roamers(snap)
	return got

func test_a_roamer_survives_the_save_file() -> void:
	var s := _a_roamer(7, Vector2(321.5, 654.25))
	var back := SaveSerializer.deserialize_roamer_state(
			JSON.parse_string(JSON.stringify(SaveSerializer.serialize_roamer_state(s))))
	assert_eq(back["id"], 7, "which roamer")
	assert_eq(typeof(back["id"]), TYPE_INT, "as a whole number")
	assert_eq(back["group_index"], 1, "its encounter group")
	assert_eq(back["position"], Vector2(321.5, 654.25), "where it stood")
	assert_eq(back["home"], Rect2(100, 200, 900, 900), "the area it patrols")
	assert_eq(back["home_poly"], s["home_poly"], "and that area's shape")

func test_a_damaged_roamer_entry_is_dropped() -> void:
	var back := SaveSerializer.deserialize_roamer_state({"id": 3, "group_index": 0, "position": "nope"})
	assert_eq(back["group_index"], -1, "skipped on restore, never placed at a made-up spot")

func test_a_save_records_where_the_roamers_are_now() -> void:
	var snap := _snapshot_roamers()
	GameManager.save_overworld_scene_path = "res://A.tscn"
	GameManager.set_roamer_state("res://A.tscn", [_a_roamer(1, Vector2(10, 10))])  # as the last battle left it
	GameManager.roamer_snapshot = func():
		GameManager.set_roamer_state("res://A.tscn", [_a_roamer(1, Vector2(500, 600))])
	var d: Dictionary = GameManager._build_save_dict()
	_restore_roamers(snap)
	assert_eq(d["roamers"]["region"], "res://A.tscn", "the map's roamers are in the save")
	assert_eq(d["roamers"]["states"].size(), 1, "every one of them")
	assert_eq(SaveSerializer.deserialize_roamer_state(d["roamers"]["states"][0])["position"], Vector2(500, 600),
			"where it is now, not where it was after the last battle")

func test_loading_brings_back_the_roamers_of_the_map_you_load_into() -> void:
	var got := _roamers_after_loading("res://A.tscn", {"region": "res://A.tscn",
			"states": [SaveSerializer.serialize_roamer_state(_a_roamer(4, Vector2(70, 80)))]})
	assert_true(got["initialized"], "the map's roamers are restored, not respawned")
	assert_eq(got["region"], "res://A.tscn", "for the map you load into")
	assert_eq(got["states"].size(), 1, "the same ones")
	assert_eq(got["states"][0]["id"], 4, "that roamer")
	assert_eq(got["states"][0]["position"], Vector2(70, 80), "where it stood")

func test_a_cleared_map_stays_cleared_after_loading() -> void:
	var got := _roamers_after_loading("res://A.tscn", {"region": "res://A.tscn", "states": []})
	assert_true(got["initialized"], "the map counts as visited")
	assert_eq(got["states"].size(), 0, "with nobody left, so nothing respawns")

func test_roamers_from_another_map_are_not_restored() -> void:
	var got := _roamers_after_loading("res://B.tscn", {"region": "res://A.tscn",
			"states": [SaveSerializer.serialize_roamer_state(_a_roamer(4, Vector2(70, 80)))]})
	assert_false(got["initialized"], "map B starts fresh")

func test_an_old_save_without_roamers_starts_the_map_fresh() -> void:
	var got := _roamers_after_loading("res://A.tscn", null)
	assert_false(got["initialized"], "a fresh set, as before roamers were saved")
