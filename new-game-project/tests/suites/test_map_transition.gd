extends TestSuite

## Map-to-map transitions + pinned roamer spawns (P7p2).
## Covers the pure MapTransitionTracker enter-detection, the MapTransition /
## RoamerSpawn data resources, and the new MapArea fields.

func suite_name() -> String:
	return "MapTransition"

func _t(rect: Rect2, scene := "res://scenes/Foo.tscn") -> MapTransition:
	var t := MapTransition.new()
	t.trigger_rect = rect
	t.target_scene = scene
	t.target_spawn = Vector2(10, 20)
	return t

# --- Pure transition_at -------------------------------------------------------
func test_transition_at_finds_index() -> void:
	var ts := [_t(Rect2(0, 0, 100, 100)), _t(Rect2(500, 500, 100, 100))]
	assert_eq(MapTransitionTracker.transition_at(Vector2(50, 50), ts), 0, "point in first trigger")
	assert_eq(MapTransitionTracker.transition_at(Vector2(550, 550), ts), 1, "point in second trigger")
	assert_eq(MapTransitionTracker.transition_at(Vector2(300, 300), ts), -1, "point outside all triggers")

func test_transition_at_null_safe() -> void:
	var ts := [null, _t(Rect2(0, 0, 100, 100))]
	assert_eq(MapTransitionTracker.transition_at(Vector2(50, 50), ts), 1, "null entries are skipped")
	assert_eq(MapTransitionTracker.transition_at(Vector2(9, 9), []), -1, "empty list -> -1")

# --- Stateful enter detection (fires once per entry) --------------------------
func test_update_fires_once_on_enter() -> void:
	var tracker := MapTransitionTracker.new()
	var ts := [_t(Rect2(0, 0, 100, 100))]
	# Approaching from outside: no fire.
	assert_eq(tracker.update(Vector2(200, 200), ts), -1, "outside -> no transition")
	# Crossing into the trigger: fires the index.
	assert_eq(tracker.update(Vector2(50, 50), ts), 0, "outside->inside fires once")
	# Staying inside: must NOT re-fire.
	assert_eq(tracker.update(Vector2(60, 60), ts), -1, "staying inside does not re-fire")

func test_update_refires_after_leaving() -> void:
	var tracker := MapTransitionTracker.new()
	var ts := [_t(Rect2(0, 0, 100, 100))]
	assert_eq(tracker.update(Vector2(50, 50), ts), 0, "first entry fires")
	assert_eq(tracker.update(Vector2(300, 300), ts), -1, "left the trigger")
	assert_eq(tracker.update(Vector2(50, 50), ts), 0, "re-entry fires again")

func test_reset_clears_state() -> void:
	var tracker := MapTransitionTracker.new()
	var ts := [_t(Rect2(0, 0, 100, 100))]
	assert_eq(tracker.update(Vector2(50, 50), ts), 0, "entered")
	tracker.reset()
	# After reset the tracker forgets it was inside, so being inside fires again.
	assert_eq(tracker.update(Vector2(50, 50), ts), 0, "reset -> next inside fires")

# --- Resource data holders ----------------------------------------------------
func test_map_transition_defaults() -> void:
	var t := MapTransition.new()
	assert_eq(t.label, "", "label defaults empty")
	assert_eq(t.target_scene, "", "target_scene defaults empty")
	assert_eq(t.target_spawn, Vector2.ZERO, "target_spawn defaults zero")

func test_roamer_spawn_defaults() -> void:
	var rs := RoamerSpawn.new()
	assert_eq(rs.group, null, "group defaults null (weighted pick)")
	assert_true(rs.home.size.x > 0.0 and rs.home.size.y > 0.0, "home has a non-empty default size")

func test_map_area_has_new_arrays() -> void:
	var a := MapArea.new()
	assert_eq(a.roamer_spawns.size(), 0, "roamer_spawns defaults empty")
	assert_eq(a.transitions.size(), 0, "transitions defaults empty")

# --- Authored Fallster Plains data round-trips --------------------------------
func test_fallster_plains_loads() -> void:
	var area: MapArea = load("res://data/maps/fallster_plains.tres")
	assert_ne(area, null, "fallster_plains.tres loads")
	# Zones, transitions AND roamer territories all live as scene nodes now.
	assert_eq(area.roamer_spawns.size(), 0, "plains area data carries no Rect2 roamer spawns")
	assert_eq(area.transitions.size(), 0, "plains area data carries no Rect2 transitions")
	assert_eq(area.safe_zones.size(), 0, "plains area data carries no Rect2 safe zones")

# --- Town/village interiors + autosave-on-enter (P7p2) ------------------------
func test_autosave_on_enter_defaults_false() -> void:
	assert_false(MapArea.new().autosave_on_enter, "autosave_on_enter defaults false")

func test_town_interiors_autosave_villages_dont() -> void:
	var center: MapArea = load("res://data/maps/center_town_interior.tres")
	var west: MapArea = load("res://data/maps/west_town_interior.tres")
	var vnw: MapArea = load("res://data/maps/village_nw_interior.tres")
	var vse: MapArea = load("res://data/maps/village_se_interior.tres")
	assert_true(center.autosave_on_enter, "Center Town interior auto-saves on entry")
	assert_true(west.autosave_on_enter, "West Town interior auto-saves on entry")
	assert_false(vnw.autosave_on_enter, "NW village interior does NOT auto-save")
	assert_false(vse.autosave_on_enter, "SE village interior does NOT auto-save")
	assert_eq(center.encounter_groups.size(), 0, "town interior is a safe zone (no encounters)")
	assert_eq(vnw.encounter_groups.size(), 0, "village interior is a safe zone (no encounters)")

func test_interior_scenes_exit_back_to_overworld() -> void:
	for path in [
		"res://scenes/CenterTownInterior.tscn",
		"res://scenes/WestTownInterior.tscn",
		"res://scenes/VillageNWInterior.tscn",
		"res://scenes/VillageSEInterior.tscn",
		"res://scenes/Forest.tscn",
	]:
		var scene: Node = (load(path) as PackedScene).instantiate()
		var exit: MapZone = scene.get_node_or_null("Zones/Zone_Exit")
		assert_ne(exit, null, "%s has an exit zone" % path)
		if exit != null:
			assert_eq(exit.target_scene, "res://scenes/OverworldScene.tscn",
				"%s exit returns to the overworld" % path)
		scene.free()

func test_goblin_castle_fixed_ambush() -> void:
	var area: MapArea = load("res://data/maps/goblin_castle.tres")
	assert_ne(area, null, "goblin_castle.tres loads")
	# The boss roamer is now a drawable RoamerTerritory node in the castle scene.
	var scene: Node = (load("res://scenes/GoblinCastle.tscn") as PackedScene).instantiate()
	var boss: RoamerTerritory = scene.get_node_or_null("RoamerTerritories/Territory_Boss")
	assert_ne(boss, null, "castle scene has the boss territory")
	if boss != null:
		assert_ne(boss.group, null, "boss territory carries an explicit group")
		assert_true(boss.group.is_fixed, "the boss territory's group is a fixed encounter")
		assert_true(area.encounter_groups.has(boss.group), "boss group registered in the area for persistence")
		var enc := boss.group.instantiate_encounter()
		assert_eq(enc.size(), 3, "goblin ambush spawns exactly its 3-enemy pool")
	scene.free()
