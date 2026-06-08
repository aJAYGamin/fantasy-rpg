extends TestSuite

## Defeat → load flow (P6): has_active_save gating + load_active_slot returns the
## saved overworld scene path and sets resuming_from_save. Uses a real save slot
## and restores GameManager state afterward so it doesn't disturb the user's saves.

func suite_name() -> String:
	return "DefeatFlow"

const TEST_SLOT := 2

func _snapshot() -> Dictionary:
	return {
		"active_slot": GameManager.active_slot,
		"resuming": GameManager.resuming_from_save,
		"party": GameManager.party,
		"gold": GameManager.gold,
		"scene_path": GameManager.save_overworld_scene_path,
		"slot_existed": GameManager.slot_exists(TEST_SLOT),
	}

func _restore(snap: Dictionary) -> void:
	# Remove the test save unless it existed before we started.
	if not snap["slot_existed"] and GameManager.slot_exists(TEST_SLOT):
		GameManager.delete_slot(TEST_SLOT)
	GameManager.party = snap["party"]
	GameManager.gold = snap["gold"]
	GameManager.active_slot = snap["active_slot"]
	GameManager.resuming_from_save = snap["resuming"]
	GameManager.save_overworld_scene_path = snap["scene_path"]

func test_has_active_save_false_without_slot() -> void:
	var snap := _snapshot()
	GameManager.active_slot = -1
	assert_false(GameManager.has_active_save(), "no active slot -> no active save")
	_restore(snap)

func test_load_active_slot_returns_empty_without_save() -> void:
	var snap := _snapshot()
	GameManager.active_slot = -1
	GameManager.resuming_from_save = false
	assert_eq(GameManager.load_active_slot(), "", "no save -> empty path")
	assert_false(GameManager.resuming_from_save, "no save -> resuming flag untouched")
	_restore(snap)

func test_load_active_slot_loads_and_returns_path() -> void:
	var snap := _snapshot()

	# Make a real save in the test slot with a known overworld scene path.
	GameManager.ensure_default_party()
	GameManager.save_overworld_scene_path = "res://scenes/OverworldScene.tscn"
	GameManager.save_overworld_position = Vector2(123, 456)
	assert_true(GameManager.save_to_slot(TEST_SLOT), "test save written")

	assert_true(GameManager.has_active_save(), "active save present after saving")

	GameManager.resuming_from_save = false
	var path := GameManager.load_active_slot()
	assert_eq(path, "res://scenes/OverworldScene.tscn", "returns the saved overworld scene path")
	assert_true(GameManager.resuming_from_save, "sets resuming_from_save so the overworld spawns at the save")

	_restore(snap)

func test_load_active_slot_defaults_path_when_blank() -> void:
	var snap := _snapshot()

	GameManager.ensure_default_party()
	GameManager.save_overworld_scene_path = ""   # blank -> should default
	assert_true(GameManager.save_to_slot(TEST_SLOT), "test save written")

	var path := GameManager.load_active_slot()
	assert_eq(path, "res://scenes/OverworldScene.tscn", "blank saved path falls back to the overworld scene")

	_restore(snap)
