extends TestSuite

func suite_name() -> String:
	return "CursorMotion"

func test_the_mouse_moves_the_cursor_at_its_sensitivity() -> void:
	var b := Vector2(1152, 648)
	assert_eq(CursorMotion.mouse_step(Vector2(100, 100), Vector2(20, 0), Vector2(2, 2), 1.0, b), Vector2(110, 100), "window pixels → base pixels")
	assert_eq(CursorMotion.mouse_step(Vector2(100, 100), Vector2(20, 0), Vector2(2, 2), 3.0, b), Vector2(130, 100), "3.00× is three times as far")
	assert_eq(CursorMotion.mouse_step(Vector2(5, 5), Vector2(-100, -100), Vector2.ONE, 1.0, b), Vector2.ZERO, "clamped at the corner")
	assert_eq(CursorMotion.mouse_step(Vector2(1150, 600), Vector2(50, 50), Vector2.ONE, 1.0, b), Vector2(1151, 647), "clamped to the last pixel, bounds - 1")

func test_the_stick_has_a_dead_zone_a_curve_and_a_full_speed() -> void:
	assert_eq(CursorMotion.stick_velocity(Vector2(0.15, 0), 1.0), Vector2.ZERO, "inside the dead zone")
	assert_eq(CursorMotion.stick_velocity(Vector2(0.24, 0), 1.0), Vector2.ZERO,
			"so is a worn stick resting at 0.24 (the dead zone is 0.25, near XInput's 0.27 for a right stick)")
	assert_near(CursorMotion.stick_velocity(Vector2(1, 0), 1.0).x, 768.0, 0.01, "full tilt: 1152 px in 1.5 s")
	assert_true(CursorMotion.stick_velocity(Vector2(0.6, 0), 1.0).x < 768.0 * 0.5, "finer control near the centre")
	assert_near(CursorMotion.stick_velocity(Vector2(1, 0), 2.0).x, 1536.0, 0.01, "Right Stick Sensitivity scales it")

func test_the_dead_zone_is_on_the_stick_magnitude_not_each_axis() -> void:
	# (0.2, 0.2) is about 0.28 from centre: outside the 0.25 dead zone even though each axis is inside it.
	assert_true(CursorMotion.stick_velocity(Vector2(0.2, 0.2), 1.0) != Vector2.ZERO, "a diagonal past the dead zone moves")
	assert_eq(CursorMotion.stick_velocity(Vector2(0.17, 0.17), 1.0), Vector2.ZERO, "a small diagonal inside it does not")

func test_a_stick_past_full_tilt_runs_at_full_speed_in_its_own_direction() -> void:
	# (3, 4) has magnitude 5, treated as full tilt: 768 px/s along (0.6, 0.8).
	var v := CursorMotion.stick_velocity(Vector2(3, 4), 1.0)
	assert_near(v.x, 460.8, 0.01, "x is 768 × 0.6")
	assert_near(v.y, 614.4, 0.01, "y is 768 × 0.8")

func test_overshoot_only_counts_pushing_past_an_edge() -> void:
	var b := Vector2(1152, 648)
	assert_near(CursorMotion.overshoot(Vector2(1151, 300), Vector2(10, 0), b), 10.0, 0.01, "pushing out the right edge")
	assert_near(CursorMotion.overshoot(Vector2(1151, 300), Vector2(-10, 0), b), 0.0, 0.01, "moving back in")
	assert_near(CursorMotion.overshoot(Vector2(500, 300), Vector2(10, 0), b), 0.0, 0.01, "not at an edge")
	assert_near(CursorMotion.overshoot(Vector2(1150, 300), Vector2(10, 0), b), 0.0, 0.01, "one pixel short of the edge is not at it")

func test_a_corner_push_counts_both_axes() -> void:
	var b := Vector2(1152, 648)
	assert_near(CursorMotion.overshoot(Vector2(1151, 647), Vector2(10, 7), b), 17.0, 0.01, "bottom-right corner: x and y both count")
	assert_near(CursorMotion.overshoot(Vector2(0, 0), Vector2(-4, -3), b), 7.0, 0.01, "top-left corner too")
	assert_near(CursorMotion.overshoot(Vector2(1151, 300), Vector2(10, -5), b), 10.0, 0.01, "motion along an edge does not count")

func test_a_hidden_cursor_wakes_only_for_a_firm_push() -> void:
	assert_false(CursorMotion.stick_wakes(Vector2(0.4, 0)), "a stick drifting at 0.4 doesn't")
	assert_false(CursorMotion.stick_wakes(Vector2(0.5, 0)), "half tilt is the bar, not past it")
	assert_true(CursorMotion.stick_wakes(Vector2(0.55, 0)), "past half tilt does")
	assert_true(CursorMotion.stick_wakes(Vector2(0.4, 0.4)), "measured on the stick's magnitude (0.57), not each axis")
