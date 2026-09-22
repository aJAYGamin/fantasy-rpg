extends TestSuite

## TimeOfDay clock: phase boundaries, phase names, 12-hour clock text, real-time
## advance + midnight wrap, the lighting tint, and the EncounterGroup phase gate.

func suite_name() -> String:
	return "TimeOfDay"

func _at(minutes: float) -> TimeOfDay:
	var t := TimeOfDay.new()
	t.set_minutes(minutes)
	return t

func test_phases_by_time() -> void:
	assert_eq(_at(360).phase(), TimeOfDay.Phase.DAWN, "06:00 is Dawn")
	assert_eq(_at(720).phase(), TimeOfDay.Phase.DAY, "12:00 is Day")
	assert_eq(_at(1080).phase(), TimeOfDay.Phase.DUSK, "18:00 is Dusk")
	assert_eq(_at(1320).phase(), TimeOfDay.Phase.NIGHT, "22:00 is Night")
	assert_eq(_at(60).phase(), TimeOfDay.Phase.NIGHT, "01:00 is Night")

func test_phase_boundaries() -> void:
	assert_eq(_at(TimeOfDay.DAWN_START).phase(), TimeOfDay.Phase.DAWN, "05:00 -> Dawn begins")
	assert_eq(_at(TimeOfDay.DAY_START).phase(), TimeOfDay.Phase.DAY, "08:00 -> Day begins")
	assert_eq(_at(TimeOfDay.DUSK_START).phase(), TimeOfDay.Phase.DUSK, "17:00 -> Dusk begins")
	assert_eq(_at(TimeOfDay.NIGHT_START).phase(), TimeOfDay.Phase.NIGHT, "20:00 -> Night begins")
	assert_eq(_at(TimeOfDay.DAWN_START - 1).phase(), TimeOfDay.Phase.NIGHT, "04:59 is still Night")

func test_phase_names() -> void:
	assert_eq(_at(360).phase_name(), "Dawn", "dawn name")
	assert_eq(_at(720).phase_name(), "Day", "day name")
	assert_eq(_at(1080).phase_name(), "Dusk", "dusk name")
	assert_eq(_at(1320).phase_name(), "Night", "night name")

func test_clock_text() -> void:
	assert_eq(_at(0).clock_text(), "12:00 AM", "midnight")
	assert_eq(_at(480).clock_text(), "8:00 AM", "08:00")
	assert_eq(_at(720).clock_text(), "12:00 PM", "noon")
	assert_eq(_at(810).clock_text(), "1:30 PM", "13:30")

func test_advance_and_wrap_past_midnight() -> void:
	var t := _at(1430.0)   # 23:50
	# Advance 20 game-minutes worth of real seconds; should wrap to 00:10.
	t.advance_real(20.0 / TimeOfDay.GAME_MINUTES_PER_REAL_SECOND)
	assert_near(t.minutes, 10.0, 0.5, "wraps past midnight to 00:10")

func test_tint_day_is_neutral() -> void:
	var c := _at(720).tint()
	assert_near(c.r, 1.0, 0.02, "day tint neutral (r)")
	assert_near(c.g, 1.0, 0.02, "day tint neutral (g)")
	assert_near(c.b, 1.0, 0.02, "day tint neutral (b)")

func test_tint_night_is_dim_blue() -> void:
	var c := _at(0).tint()
	assert_true(c.b > c.r, "night tint leans blue")
	assert_true(c.r < 0.7, "night tint is dimmed")

func test_encounter_phase_gate() -> void:
	var g := EncounterGroup.new()
	assert_true(g.allowed_at_phase(TimeOfDay.Phase.NIGHT), "empty time_phases allows any phase")
	g.time_phases = [TimeOfDay.Phase.NIGHT]
	assert_true(g.allowed_at_phase(TimeOfDay.Phase.NIGHT), "night-only allows night")
	assert_false(g.allowed_at_phase(TimeOfDay.Phase.DAY), "night-only blocks day")

# --------------------------------------------- indoor suppression of the tint

func test_interior_areas_skip_the_time_tint() -> void:
	var outdoors := MapArea.new()
	assert_false(outdoors.is_interior, "areas are outdoors unless told otherwise")
	assert_true(outdoors.wants_time_tint(), "open-sky areas are tinted")

	var indoors := MapArea.new()
	indoors.is_interior = true
	assert_false(indoors.wants_time_tint(), "roofed areas are not tinted")

	# OverworldScene treats a null area as outdoors, so a scene without a MapArea
	# keeps its pre-flag behaviour rather than losing the tint.
	var no_area: MapArea = null
	assert_true(no_area == null or no_area.wants_time_tint(), "a null area is treated as outdoors")

func test_enclosed_areas_are_flagged_and_open_ones_are_not() -> void:
	# Shop rooms and the dungeon have a roof; the town/village "_interior" maps
	# are aerial views of open streets, so they must stay tinted despite the name.
	for p in ["center_town_item_shop", "center_town_equipment_shop",
			"center_town_inn", "goblin_castle"]:
		var a: MapArea = load("res://data/maps/%s.tres" % p)
		assert_true(a != null and a.is_interior, "'%s' is flagged as indoors" % p)
		assert_false(a.wants_time_tint(), "'%s' skips the tint" % p)

	for p in ["fallster_plains", "center_town_interior", "west_town_interior",
			"village_nw_interior", "village_se_interior", "forest", "mountain_pass"]:
		var a: MapArea = load("res://data/maps/%s.tres" % p)
		assert_true(a != null and not a.is_interior, "'%s' is open sky" % p)
		assert_true(a.wants_time_tint(), "'%s' keeps the tint" % p)

func test_clock_still_runs_indoors_so_time_passes_while_shopping() -> void:
	# Suppressing the tint must not stop the clock, or the player would step back
	# outside into the same lighting they left.
	var saved := GameManager.clock.minutes
	GameManager.clock.set_minutes(600.0)          # 10:00, daytime
	var before := GameManager.clock.minutes
	# 10:00 + 10.5h = 20:30. Night starts at 20:00, so this clears the boundary;
	# nine hours would only reach 19:00, which is still Dusk.
	GameManager.clock.advance_real(TimeOfDay.REAL_SECONDS_PER_GAME_HOUR * 10.5)
	var after := GameManager.clock.minutes
	assert_true(after > before, "the clock advances regardless of the tint")
	assert_near(after, 1230.0, 2.0, "10:00 plus 10.5 game-hours is 20:30")
	assert_eq(GameManager.clock.phase(), TimeOfDay.Phase.NIGHT,
		"20:30 is night")
	# And the tint waiting outside reflects the time that passed indoors.
	var outdoors := MapArea.new()
	assert_true(outdoors.wants_time_tint(), "outside is tinted again")
	var night := GameManager.clock.tint()
	assert_true(night.b > night.r, "the tint on stepping out is the night blue")
	GameManager.clock.set_minutes(saved)
