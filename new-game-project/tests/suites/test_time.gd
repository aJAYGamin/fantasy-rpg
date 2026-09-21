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
