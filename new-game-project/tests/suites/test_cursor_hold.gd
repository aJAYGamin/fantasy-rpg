extends TestSuite

func suite_name() -> String:
	return "CursorHold"

func test_windowed_slip_out_needs_a_deliberate_push() -> void:
	var h := CursorHold.new()
	assert_false(h.on_motion(10.0, true), "a nudge doesn't release")
	assert_true(h.on_motion(15.0, true), "24 px of push does")
	assert_eq(h.state, CursorHold.State.RELEASED, "let go")

func test_fullscreen_never_slips_out() -> void:
	var h := CursorHold.new()
	assert_false(h.on_motion(500.0, false), "fullscreen holds")
	assert_eq(h.state, CursorHold.State.HELD, "still held after a big push")

func test_fullscreen_pushes_do_not_build_towards_a_windowed_release() -> void:
	var h := CursorHold.new()
	for i in 10:
		h.on_motion(10.0, false)
	assert_false(h.on_motion(10.0, true), "ten fullscreen pushes did not count")
	assert_eq(h.state, CursorHold.State.HELD, "still held")

func test_a_motion_back_inside_starts_the_push_again() -> void:
	var h := CursorHold.new()
	h.on_motion(20.0, true)
	h.on_motion(0.0, true)
	assert_false(h.on_motion(20.0, true), "20 px after a reset is not 24 px")
	assert_eq(h.state, CursorHold.State.HELD, "still held")

func test_once_released_further_motion_changes_nothing() -> void:
	var h := CursorHold.new()
	h.on_motion(30.0, true)
	assert_false(h.on_motion(30.0, true), "already let go, so nothing changes")
	assert_eq(h.state, CursorHold.State.RELEASED, "still released")

func test_focus_and_pick_up() -> void:
	var h := CursorHold.new()
	h.on_focus(false, false)
	assert_eq(h.state, CursorHold.State.RELEASED, "switching away lets go")
	h.on_focus(true, false)
	assert_eq(h.state, CursorHold.State.HELD, "fullscreen picks up on return")
	h.on_focus(false, true)
	h.on_focus(true, true)
	assert_eq(h.state, CursorHold.State.RELEASED, "windowed waits for a click")
	h.on_click_while_released()
	assert_eq(h.state, CursorHold.State.HELD, "the click picks it up")
	h.on_focus(false, true)
	h.on_focus(true, true)
	h.on_stick()
	assert_eq(h.state, CursorHold.State.HELD, "the right stick picks it up too")
	assert_eq(h.mouse_mode(), Input.MOUSE_MODE_CAPTURED, "held = captured")

func test_a_pick_up_starts_the_push_again_from_zero() -> void:
	var h := CursorHold.new()
	h.on_motion(30.0, true)
	h.on_click_while_released()
	assert_false(h.on_motion(20.0, true), "the earlier push does not count towards this one")
	assert_true(h.on_motion(4.0, true), "a further 4 px completes it")

func test_released_shows_the_system_pointer() -> void:
	var h := CursorHold.new()
	h.on_focus(false, false)
	assert_eq(h.mouse_mode(), Input.MOUSE_MODE_VISIBLE, "released = visible")

func test_the_pointer_coming_back_in_picks_the_mouse_up() -> void:
	var h := CursorHold.new()
	h.on_motion(30.0, true)
	assert_false(h.on_pointer_back(), "coming in without having left is the let-go itself, just inside the edge")
	assert_eq(h.state, CursorHold.State.RELEASED, "so it is still let go")
	h.on_pointer_left()
	assert_true(h.on_pointer_back(), "out of the window and back in picks the mouse up")
	assert_eq(h.state, CursorHold.State.HELD, "held again")

func test_only_a_leave_since_letting_go_counts() -> void:
	var h := CursorHold.new()
	h.on_pointer_left()   # while held: says nothing about a later let-go
	h.on_motion(30.0, true)
	assert_false(h.on_pointer_back(), "a leave from before the let-go doesn't count")
	h.on_pointer_left()
	h.on_click_while_released()
	h.on_motion(30.0, true)
	assert_false(h.on_pointer_back(), "nor one from before the last pick-up")
	h.on_pointer_left()
	assert_true(h.on_pointer_back(), "a fresh leave does")
	assert_false(h.on_pointer_back(), "and once held, coming in again changes nothing")
