extends TestSuite

## AutoSaveSystem safe-zone enter detection + GameManager.can_autosave gating.

func suite_name() -> String:
	return "AutoSave"

func _zones() -> Array:
	# Two non-overlapping town rects.
	return [Rect2(800, 800, 100, 100), Rect2(1500, 2400, 100, 100)]

func test_zone_at() -> void:
	var z := _zones()
	assert_eq(AutoSaveSystem.zone_at(Vector2(850, 850), z), 0, "inside first zone -> index 0")
	assert_eq(AutoSaveSystem.zone_at(Vector2(1550, 2450), z), 1, "inside second zone -> index 1")
	assert_eq(AutoSaveSystem.zone_at(Vector2(0, 0), z), -1, "outside all zones -> -1")

func test_enter_fires_once() -> void:
	var a := AutoSaveSystem.new()
	var z := _zones()
	# Start outside.
	assert_false(a.update(Vector2(0, 0), z), "no trigger while outside")
	# Step into the first zone -> ENTER fires.
	assert_true(a.update(Vector2(850, 850), z), "entering a zone triggers an auto-save")
	# Staying inside does NOT re-fire.
	assert_false(a.update(Vector2(870, 870), z), "staying inside does not re-trigger")

func test_leave_and_reenter_refires() -> void:
	var a := AutoSaveSystem.new()
	var z := _zones()
	a.update(Vector2(850, 850), z)      # enter
	assert_false(a.update(Vector2(0, 0), z), "leaving does not trigger")
	assert_true(a.update(Vector2(850, 850), z), "re-entering triggers again")

func test_move_between_zones_no_refire() -> void:
	var a := AutoSaveSystem.new()
	var z := _zones()
	a.update(Vector2(850, 850), z)      # enter zone 0
	# Teleport straight into zone 1 without passing outside — still "in a zone",
	# so no fresh ENTER trigger.
	assert_false(a.update(Vector2(1550, 2450), z), "zone-to-zone move does not re-trigger")

func test_in_safe_zone_flag() -> void:
	var a := AutoSaveSystem.new()
	var z := _zones()
	assert_false(a.in_safe_zone(), "not in a zone initially")
	a.update(Vector2(850, 850), z)
	assert_true(a.in_safe_zone(), "in a zone after entering")
	a.update(Vector2(0, 0), z)
	assert_false(a.in_safe_zone(), "not in a zone after leaving")

func test_reset() -> void:
	var a := AutoSaveSystem.new()
	var z := _zones()
	a.update(Vector2(850, 850), z)
	a.reset()
	# After reset, being inside again counts as a fresh enter.
	assert_true(a.update(Vector2(850, 850), z), "reset lets the next entry trigger again")

func test_can_autosave_gating() -> void:
	var prev_enabled: bool = GameManager.settings.autosave_enabled
	var prev_slot: int = GameManager.active_slot

	GameManager.settings.autosave_enabled = true
	GameManager.active_slot = 0
	assert_true(GameManager.can_autosave(), "enabled + valid slot -> can autosave")

	GameManager.settings.autosave_enabled = false
	assert_false(GameManager.can_autosave(), "disabled toggle -> cannot autosave")

	GameManager.settings.autosave_enabled = true
	GameManager.active_slot = -1
	assert_false(GameManager.can_autosave(), "no active slot -> cannot autosave")

	# autosave() must no-op (return false) when not allowed.
	assert_false(GameManager.autosave("res://x.tscn", Vector2.ZERO), "autosave no-ops when not allowed")

	# Restore.
	GameManager.settings.autosave_enabled = prev_enabled
	GameManager.active_slot = prev_slot
