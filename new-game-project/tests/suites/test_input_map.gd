extends TestSuite

## InputMapConfig: action creation, event (de)serialization, config round-trip,
## per-device rebinding, reset, and the confirm/cancel -> ui_* mirror.

func suite_name() -> String:
	return "InputMap"

func test_defaults_cover_all_actions() -> void:
	var defs := InputMapConfig.defaults()
	for meta in InputMapConfig.ACTIONS:
		var action: String = meta["action"]
		assert_true(defs.has(action), "default events exist for %s" % action)
		assert_true(defs[action].size() > 0, "%s has at least one default binding" % action)

func test_apply_creates_actions() -> void:
	InputMapConfig.apply({})
	for meta in InputMapConfig.ACTIONS:
		var action: String = meta["action"]
		assert_true(InputMap.has_action(action), "InputMap has action %s" % action)
		assert_true(InputMap.action_get_events(action).size() > 0, "%s has bound events" % action)

func test_event_serialization_round_trip() -> void:
	var k := InputEventKey.new()
	k.physical_keycode = KEY_J
	var k2 := InputMapConfig.build_event(InputMapConfig.serialize_event(k)) as InputEventKey
	assert_eq(k2.physical_keycode, KEY_J, "key round-trips")

	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_X
	var b2 := InputMapConfig.build_event(InputMapConfig.serialize_event(b)) as InputEventJoypadButton
	assert_eq(b2.button_index, JOY_BUTTON_X, "joy button round-trips")

	var m := InputEventJoypadMotion.new()
	m.axis = JOY_AXIS_LEFT_X
	m.axis_value = -1.0
	var m2 := InputMapConfig.build_event(InputMapConfig.serialize_event(m)) as InputEventJoypadMotion
	assert_eq(m2.axis, JOY_AXIS_LEFT_X, "joy motion axis round-trips")
	assert_true(m2.axis_value < 0.0, "joy motion sign round-trips")

func test_config_round_trip() -> void:
	InputMapConfig.apply({})
	var cfg := ConfigFile.new()
	InputMapConfig.save_to_config(cfg)
	var custom := InputMapConfig.load_custom(cfg)
	assert_true(custom.has("move_up"), "config persists move_up")
	InputMapConfig.apply(custom)
	assert_true(InputMap.action_get_events("move_up").size() > 0, "re-applied config keeps bindings")

func test_mirror_to_ui_actions() -> void:
	InputMapConfig.apply({})
	assert_eq(InputMap.action_get_events("ui_cancel").size(), InputMap.action_get_events("cancel").size(), "ui_cancel mirrors cancel")
	assert_eq(InputMap.action_get_events("ui_accept").size(), InputMap.action_get_events("confirm").size(), "ui_accept mirrors confirm")

func test_rebind_keyboard_keeps_controller() -> void:
	InputMapConfig.apply({})
	var joy_before := 0
	for e in InputMap.action_get_events("move_up"):
		if e is InputEventJoypadButton or e is InputEventJoypadMotion:
			joy_before += 1
	var ek := InputEventKey.new()
	ek.physical_keycode = KEY_I
	InputMapConfig.rebind_keyboard("move_up", ek)
	var key_count := 0
	var joy_count := 0
	var has_i := false
	for e in InputMap.action_get_events("move_up"):
		if e is InputEventKey:
			key_count += 1
			if (e as InputEventKey).physical_keycode == KEY_I:
				has_i = true
		else:
			joy_count += 1
	assert_eq(key_count, 1, "keyboard collapses to the single new binding")
	assert_true(has_i, "the new key is bound")
	assert_eq(joy_count, joy_before, "controller bindings are preserved")
	InputMapConfig.apply({})

func test_reset_action_restores_default() -> void:
	var ek := InputEventKey.new()
	ek.physical_keycode = KEY_I
	InputMapConfig.rebind_keyboard("move_left", ek)
	InputMapConfig.reset_action("move_left")
	var has_a := false
	for e in InputMap.action_get_events("move_left"):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_A:
			has_a = true
	assert_true(has_a, "reset restores default A key for move_left")

func test_reset_keyboard_action_keeps_controller() -> void:
	InputMapConfig.apply({})
	# Rebind both devices on move_up, then reset only the keyboard.
	var ek := InputEventKey.new()
	ek.physical_keycode = KEY_I
	InputMapConfig.rebind_keyboard("move_up", ek)
	var eb := InputEventJoypadButton.new()
	eb.button_index = JOY_BUTTON_Y
	InputMapConfig.rebind_controller("move_up", eb)
	InputMapConfig.reset_keyboard_action("move_up")
	var has_default_key := false
	var still_has_custom_pad := false
	for e in InputMap.action_get_events("move_up"):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_W:
			has_default_key = true
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == JOY_BUTTON_Y:
			still_has_custom_pad = true
	assert_true(has_default_key, "keyboard reset restores default W")
	assert_true(still_has_custom_pad, "controller binding is untouched by keyboard reset")
	InputMapConfig.apply({})

func test_reset_all_controller_restores_defaults() -> void:
	var eb := InputEventJoypadButton.new()
	eb.button_index = JOY_BUTTON_Y
	InputMapConfig.rebind_controller("confirm", eb)
	InputMapConfig.reset_all_controller()
	var has_a := false
	for e in InputMap.action_get_events("confirm"):
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == JOY_BUTTON_A:
			has_a = true
	assert_true(has_a, "controller reset restores default A on confirm")
	InputMapConfig.apply({})

func test_describe_strings() -> void:
	InputMapConfig.apply({})
	assert_ne(InputMapConfig.describe_keyboard("move_up"), "—", "move_up has a keyboard label")
	assert_ne(InputMapConfig.describe_controller("move_up"), "—", "move_up has a controller label")

func test_focusutil_category_shoulders() -> void:
	# L1 / R1 are the category-cycle buttons in Stats/Items/Equipment.
	var lb := InputEventJoypadButton.new()
	lb.button_index = JOY_BUTTON_LEFT_SHOULDER
	lb.pressed = true
	var rb := InputEventJoypadButton.new()
	rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	rb.pressed = true
	assert_true(FocusUtil.is_prev_category(lb), "L1 is prev-category")
	assert_true(FocusUtil.is_next_category(rb), "R1 is next-category")
	assert_false(FocusUtil.is_next_category(lb), "L1 is not next-category")
	# A face button is not a category cycle.
	var a := InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_A
	a.pressed = true
	assert_false(FocusUtil.is_prev_category(a), "A button does not cycle category")
