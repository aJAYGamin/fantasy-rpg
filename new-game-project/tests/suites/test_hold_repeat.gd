extends TestSuite

## HoldRepeat: the auto-repeat timing behind held-direction menu scrolling and
## held L1/R1 category cycling. Pure timing, no scene tree.

func suite_name() -> String:
	return "HoldRepeat"

## Drive `r` for `seconds` of continuous holding and count the repeats.
func _hold(r: HoldRepeat, seconds: float, delta: float = 1.0 / 60.0) -> int:
	var fired := 0
	var t := 0.0
	while t < seconds:
		if r.poll(true, delta):
			fired += 1
		t += delta
	return fired

# ------------------------------------------------------------ the initial press

func test_first_press_never_repeats() -> void:
	# The caller already acts on the initial press; reporting it here would make
	# every single tap count twice.
	var r := HoldRepeat.new()
	assert_false(r.poll(true, 0.016), "the press itself is not a repeat")

func test_a_short_tap_never_repeats() -> void:
	var r := HoldRepeat.new()
	var fired := _hold(r, HoldRepeat.INITIAL_DELAY * 0.5)
	assert_eq(fired, 0, "a tap shorter than the initial delay does nothing extra")

func test_releasing_resets() -> void:
	var r := HoldRepeat.new()
	_hold(r, 1.0)
	assert_false(r.poll(false, 0.016), "release reports no repeat")
	assert_eq(r.held_for(), 0.0, "release clears the hold clock")
	assert_false(r.poll(true, 0.016), "the next press starts over as an initial press")

func test_tapping_repeatedly_never_repeats() -> void:
	# press/release/press/release... must stay one action per press.
	var r := HoldRepeat.new()
	var fired := 0
	for i in 20:
		if r.poll(true, 0.016):
			fired += 1
		r.poll(false, 0.016)
	assert_eq(fired, 0, "20 quick taps produce no repeats")

# ------------------------------------------------------------ the normal stage

func test_repeat_starts_after_the_initial_delay() -> void:
	var r := HoldRepeat.new()
	# Just before the delay elapses, nothing; just after, exactly one.
	var fired_early := _hold(r, HoldRepeat.INITIAL_DELAY - 0.05)
	assert_eq(fired_early, 0, "nothing fires before the initial delay")
	var fired_late := _hold(r, 0.1)
	assert_true(fired_late >= 1, "the first repeat lands once the delay passes")

func test_normal_cadence_is_roughly_the_repeat_interval() -> void:
	var r := HoldRepeat.new()
	# One second of holding, minus the initial delay, at REPEAT_INTERVAL each.
	var fired := _hold(r, 1.0)
	var expected := int((1.0 - HoldRepeat.INITIAL_DELAY) / HoldRepeat.REPEAT_INTERVAL)
	assert_true(abs(fired - expected) <= 1,
		"about %d repeats in the first second (got %d)" % [expected, fired])

func test_holding_scrolls_a_long_list() -> void:
	# The point of the feature: one held press must cover many rows.
	var r := HoldRepeat.new()
	var fired := _hold(r, 2.0)
	assert_true(fired >= 8, "two seconds of holding moves through at least 8 rows (got %d)" % fired)

# ------------------------------------------------------------ the fast stage

func test_not_accelerated_before_the_threshold() -> void:
	var r := HoldRepeat.new()
	_hold(r, HoldRepeat.ACCELERATE_AFTER - 0.5)
	assert_false(r.is_accelerated(), "still at the normal cadence before the threshold")

func test_accelerates_after_a_long_hold() -> void:
	var r := HoldRepeat.new()
	_hold(r, HoldRepeat.ACCELERATE_AFTER + 0.5)
	assert_true(r.is_accelerated(), "keeps scrolling faster after a long hold")

func test_fast_stage_is_actually_faster() -> void:
	var slow := HoldRepeat.new()
	# Repeats during one second at the normal cadence, measured from the start.
	_hold(slow, 1.0)
	var normal_rate := _hold(slow, 1.0)

	var fast := HoldRepeat.new()
	_hold(fast, HoldRepeat.ACCELERATE_AFTER + 0.1)
	var fast_rate := _hold(fast, 1.0)

	assert_true(fast_rate > normal_rate,
		"a long hold scrolls faster (%d/s accelerated vs %d/s normal)" % [fast_rate, normal_rate])

func test_acceleration_needs_a_continuous_hold() -> void:
	# Letting go resets the clock, so repeated partial holds never reach the fast
	# stage — otherwise a series of taps would suddenly start racing.
	var r := HoldRepeat.new()
	for i in 4:
		_hold(r, HoldRepeat.ACCELERATE_AFTER * 0.5)
		r.poll(false, 0.016)
	assert_false(r.is_accelerated(), "interrupted holds never accelerate")

# ------------------------------------------------------------ constants sanity

func test_timings_are_sane() -> void:
	assert_true(HoldRepeat.INITIAL_DELAY > 0.0, "a tap must not repeat instantly")
	assert_true(HoldRepeat.REPEAT_INTERVAL < HoldRepeat.INITIAL_DELAY,
		"repeats come faster than the initial delay")
	assert_true(HoldRepeat.FAST_INTERVAL < HoldRepeat.REPEAT_INTERVAL,
		"the fast stage is faster than the normal one")
	assert_true(HoldRepeat.ACCELERATE_AFTER > HoldRepeat.INITIAL_DELAY,
		"acceleration comes after repeating has already started")
