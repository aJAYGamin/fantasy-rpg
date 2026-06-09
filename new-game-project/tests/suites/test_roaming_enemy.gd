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
