extends TestSuite

## Three switchable keybind profiles per device: shape and naming, device
## isolation, that switching away preserves an in-progress edit, reset scoping,
## config round-trip, and migration from the pre-profiles flat [input] section.
##
## These touch the global InputMap, so every test restores stock bindings at the
## end via _restore().

func suite_name() -> String:
	return "InputProfiles"

func _fresh() -> InputProfiles:
	InputMapConfig.apply({})          # known baseline in the live InputMap
	return InputProfiles.new()

func _restore() -> void:
	InputMapConfig.apply({})

func _press(keycode: int) -> InputEventKey:
	var ek := InputEventKey.new()
	ek.physical_keycode = keycode
	return ek

# ---------------------------------------------------------------- shape/naming

func test_default_shape() -> void:
	var p := _fresh()
	assert_eq(InputProfiles.COUNT, 3, "three profiles per device")
	assert_eq(p.keyboard_bindings.size(), 3, "three keyboard profiles")
	assert_eq(p.controller_bindings.size(), 3, "three controller profiles")
	assert_eq(p.active_index(true), 0, "keyboard starts on the first profile")
	assert_eq(p.active_index(false), 0, "controller starts on the first profile")
	for i in 3:
		assert_eq(p.name_for(true, i), "Profile %d" % (i + 1), "keyboard profile %d default name" % i)
		assert_eq(p.name_for(false, i), "Profile %d" % (i + 1), "controller profile %d default name" % i)
	_restore()

func test_profiles_hold_only_their_own_device() -> void:
	var p := _fresh()
	# A keyboard profile must contain no joypad events, or switching it would
	# quietly rewrite the controller's bindings too.
	for d in p.bindings_for(true, 0).values():
		for ev in d:
			assert_eq(String(ev.get("type", "")), "key", "keyboard profile holds only key events")
	var saw_pad := false
	for d in p.bindings_for(false, 0).values():
		for ev in d:
			assert_ne(String(ev.get("type", "")), "key", "controller profile holds no key events")
			saw_pad = true
	assert_true(saw_pad, "controller profile actually has bindings")
	_restore()

func test_rename_sanitizes() -> void:
	var p := _fresh()
	assert_eq(p.set_name(true, 0, "  Lefty  "), "Lefty", "surrounding whitespace trimmed")
	assert_eq(p.name_for(true, 0), "Lefty", "stored trimmed")
	var long_name := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var stored := p.set_name(true, 1, long_name)
	assert_true(stored.length() <= InputProfiles.MAX_NAME_LENGTH, "long name capped")
	# Blank falls back to the numbered default so the picker never shows an
	# unlabelled entry.
	assert_eq(p.set_name(true, 2, "    "), "Profile 3", "blank name falls back to the default")
	assert_eq(p.set_name(false, 0, ""), "Profile 1", "empty name falls back to the default")
	_restore()

func test_rename_is_per_device() -> void:
	var p := _fresh()
	p.set_name(true, 0, "Southpaw")
	assert_eq(p.name_for(true, 0), "Southpaw", "keyboard profile renamed")
	assert_eq(p.name_for(false, 0), "Profile 1", "controller profile of the same index is unaffected")
	_restore()

func test_invalid_index_is_ignored() -> void:
	var p := _fresh()
	assert_false(InputProfiles.is_valid_index(-1), "negative index rejected")
	assert_false(InputProfiles.is_valid_index(3), "out-of-range index rejected")
	assert_eq(p.name_for(true, 9), "", "unknown index yields no name")
	assert_true(p.bindings_for(true, 9).is_empty(), "unknown index yields no bindings")
	p.switch_to(true, 7)
	assert_eq(p.active_index(true), 0, "switching to an invalid index does nothing")
	_restore()

# ---------------------------------------------------------------- switching

func test_switching_preserves_the_edit_you_were_making() -> void:
	# The live InputMap is the source of truth while editing, so switching away
	# must capture it first — otherwise the player's change is discarded.
	var p := _fresh()
	InputMapConfig.rebind_keyboard("confirm", _press(KEY_Q))
	assert_eq(InputMapConfig.describe_keyboard("confirm"), "Q", "edit is live")

	p.switch_to(true, 1)
	assert_eq(p.active_index(true), 1, "now on profile 2")
	assert_ne(InputMapConfig.describe_keyboard("confirm"), "Q", "profile 2 has its own binding")

	p.switch_to(true, 0)
	assert_eq(InputMapConfig.describe_keyboard("confirm"), "Q", "returning restores the edit")
	_restore()

func test_switching_one_device_leaves_the_other_alone() -> void:
	var p := _fresh()
	var pad_before := InputMapConfig.describe_controller("confirm")
	InputMapConfig.rebind_controller("confirm", _press_button(JOY_BUTTON_Y))
	var pad_custom := InputMapConfig.describe_controller("confirm")
	assert_ne(pad_custom, pad_before, "controller binding changed")

	p.switch_to(true, 2)   # keyboard profile change
	assert_eq(InputMapConfig.describe_controller("confirm"), pad_custom,
		"changing keyboard profile does not touch the controller binding")
	_restore()

func _press_button(idx: int) -> InputEventJoypadButton:
	var eb := InputEventJoypadButton.new()
	eb.button_index = idx
	return eb

func test_profiles_are_independent_per_device() -> void:
	var p := _fresh()
	p.switch_to(true, 2)
	assert_eq(p.active_index(true), 2, "keyboard on profile 3")
	assert_eq(p.active_index(false), 0, "controller still on profile 1")
	_restore()

func test_sync_from_input_map_captures_both_devices() -> void:
	var p := _fresh()
	InputMapConfig.rebind_keyboard("pause", _press(KEY_P))
	p.sync_from_input_map()
	var stored: Array = p.bindings_for(true, 0).get("pause", [])
	var found := false
	for d in stored:
		if int(d.get("keycode", 0)) == KEY_P:
			found = true
	assert_true(found, "the live rebind was captured into the active profile")
	_restore()

# ---------------------------------------------------------------- reset scope

func test_reset_active_leaves_other_profiles_alone() -> void:
	var p := _fresh()
	# Customise profile 1, then profile 2.
	InputMapConfig.rebind_keyboard("confirm", _press(KEY_Q))
	p.switch_to(true, 1)
	InputMapConfig.rebind_keyboard("confirm", _press(KEY_Z))
	assert_eq(InputMapConfig.describe_keyboard("confirm"), "Z", "profile 2 customised")

	p.reset_active(true)
	assert_ne(InputMapConfig.describe_keyboard("confirm"), "Z", "active profile was reset")

	p.switch_to(true, 0)
	assert_eq(InputMapConfig.describe_keyboard("confirm"), "Q",
		"the other profile kept its custom binding")
	_restore()

func test_reset_active_is_per_device() -> void:
	var p := _fresh()
	InputMapConfig.rebind_controller("confirm", _press_button(JOY_BUTTON_Y))
	var pad_custom := InputMapConfig.describe_controller("confirm")
	p.reset_active(true)          # reset the KEYBOARD profile
	assert_eq(InputMapConfig.describe_controller("confirm"), pad_custom,
		"resetting the keyboard profile leaves the controller binding intact")
	_restore()

# ---------------------------------------------------------------- persistence

func test_config_round_trip() -> void:
	var p := _fresh()
	p.set_name(true, 1, "Lefty")
	p.set_name(false, 2, "Racing")
	InputMapConfig.rebind_keyboard("confirm", _press(KEY_Q))
	p.switch_to(true, 1)          # captures the Q into profile 1, moves to 2
	p.sync_from_input_map()

	var cfg := ConfigFile.new()
	p.to_config(cfg)

	var loaded := InputProfiles.new()
	loaded.from_config(cfg)
	assert_eq(loaded.active_index(true), 1, "active keyboard profile survives")
	assert_eq(loaded.name_for(true, 1), "Lefty", "keyboard name survives")
	assert_eq(loaded.name_for(false, 2), "Racing", "controller name survives")

	var stored: Array = loaded.bindings_for(true, 0).get("confirm", [])
	var found := false
	for d in stored:
		if int(d.get("keycode", 0)) == KEY_Q:
			found = true
	assert_true(found, "the custom binding survives the round trip")
	_restore()

func test_missing_section_yields_defaults() -> void:
	var cfg := ConfigFile.new()
	var p := InputProfiles.new()
	p.from_config(cfg)
	assert_eq(p.active_index(true), 0, "no config means the first profile")
	assert_eq(p.name_for(true, 0), "Profile 1", "names fall back to defaults")
	assert_false(p.bindings_for(true, 0).is_empty(), "default bindings are present")
	_restore()

func test_legacy_flat_config_migrates_into_profile_one() -> void:
	# An existing player upgrading has [input] but no [input_profiles]; their
	# bindings must land in profile 1 rather than silently reverting.
	_fresh()
	InputMapConfig.rebind_keyboard("confirm", _press(KEY_Q))
	InputMapConfig.rebind_controller("confirm", _press_button(JOY_BUTTON_Y))
	var cfg := ConfigFile.new()
	InputMapConfig.save_to_config(cfg)     # writes the flat [input] section only
	assert_false(cfg.has_section(InputProfiles.SECTION), "no profiles section yet")

	var p := InputProfiles.new()
	p.from_config(cfg)

	var kb: Array = p.bindings_for(true, 0).get("confirm", [])
	var kb_found := false
	for d in kb:
		if int(d.get("keycode", 0)) == KEY_Q:
			kb_found = true
	assert_true(kb_found, "legacy keyboard binding migrated into profile 1")

	var pad: Array = p.bindings_for(false, 0).get("confirm", [])
	var pad_found := false
	for d in pad:
		if int(d.get("button", -1)) == JOY_BUTTON_Y:
			pad_found = true
	assert_true(pad_found, "legacy controller binding migrated into profile 1")

	# And the split is clean — no joypad events in the keyboard profile.
	for d in kb:
		assert_eq(String(d.get("type", "")), "key", "migrated keyboard profile holds only keys")
	_restore()

func test_corrupt_config_entries_are_dropped() -> void:
	var cfg := ConfigFile.new()
	var p := InputProfiles.new()
	p.to_config(cfg)
	# Hand-edited nonsense: a non-dict entry and a wrong-device event.
	cfg.set_value(InputProfiles.SECTION, "keyboard_0", {
		"confirm": ["not a dict", {"type": "joyb", "button": 0}, {"type": "key", "keycode": KEY_J}],
	})
	var loaded := InputProfiles.new()
	loaded.from_config(cfg)
	var arr: Array = loaded.bindings_for(true, 0).get("confirm", [])
	assert_eq(arr.size(), 1, "only the valid keyboard event survives")
	assert_eq(int(arr[0].get("keycode", 0)), KEY_J, "and it is the right one")
	# Every action still has an entry, so the UI can render a row for each.
	for meta in InputMapConfig.ACTIONS:
		assert_true(loaded.bindings_for(true, 0).has(meta["action"]),
			"'%s' still has an entry" % meta["action"])
	_restore()

## A stored controller profile with `cursor_click` taken out — what an older save
## holds, written before that action existed.
func _cfg_with_controller_profile_lacking_cursor_click() -> ConfigFile:
	var cfg := ConfigFile.new()
	InputProfiles.new().to_config(cfg)
	var stored: Dictionary = cfg.get_value(InputProfiles.SECTION, "controller_0").duplicate(true)
	stored.erase("cursor_click")
	cfg.set_value(InputProfiles.SECTION, "controller_0", stored)
	return cfg

func test_a_stored_profile_with_no_cursor_click_gets_the_default() -> void:
	# An action absent from the stored data takes its default, so an upgraded save
	# still clicks with the stick. Unbind it live first so the assert can't pass
	# on a binding left over from earlier.
	_fresh()
	InputMap.action_erase_events("cursor_click")
	var loaded := InputProfiles.new()
	loaded.from_config(_cfg_with_controller_profile_lacking_cursor_click())
	var stored: Array = loaded.bindings_for(false, 0).get("cursor_click", [])
	assert_eq(stored.size(), 1, "the loaded profile holds the default")
	loaded.apply_active()
	var evs := InputMap.action_get_events("cursor_click")
	assert_eq(evs.size(), 1, "bound once applied")
	assert_true(evs.size() > 0 and evs[0] is InputEventJoypadButton and evs[0].button_index == JOY_BUTTON_RIGHT_STICK, "to R3")
	_restore()

func test_a_stored_empty_cursor_click_stays_unbound() -> void:
	# Present-but-empty is the player having cleared it — the fallback must not
	# bring the default back.
	_fresh()
	var cfg := _cfg_with_controller_profile_lacking_cursor_click()
	var stored: Dictionary = cfg.get_value(InputProfiles.SECTION, "controller_0").duplicate(true)
	stored["cursor_click"] = []
	cfg.set_value(InputProfiles.SECTION, "controller_0", stored)
	var loaded := InputProfiles.new()
	loaded.from_config(cfg)
	assert_true(loaded.bindings_for(false, 0).get("cursor_click", [null]).is_empty(), "loaded profile keeps it cleared")
	loaded.apply_active()
	assert_eq(InputMap.action_get_events("cursor_click").size(), 0, "left unbound once applied")
	_restore()

func test_a_legacy_config_with_no_cursor_click_gets_the_default() -> void:
	# Same for the pre-profiles flat [input] section: migrated profile 1 takes the
	# default for an action the old file never had, on each device.
	_fresh()
	var cfg := ConfigFile.new()
	InputMapConfig.save_to_config(cfg)
	cfg.erase_section_key(InputMapConfig.CONFIG_SECTION, "cursor_click")
	var loaded := InputProfiles.new()
	loaded.from_config(cfg)
	var pad: Array = loaded.bindings_for(false, 0).get("cursor_click", [])
	assert_eq(pad.size(), 1, "controller profile 1 gets the default")
	assert_eq(int(pad[0].get("button", -1)), JOY_BUTTON_RIGHT_STICK, "R3")
	assert_true(loaded.bindings_for(true, 0).get("cursor_click", [null]).is_empty(), "keyboard profile gets none")
	_restore()

# ---------------------------------------------------------- device snapshots

func test_apply_device_keeps_the_other_device() -> void:
	InputMapConfig.apply({})
	InputMapConfig.rebind_controller("confirm", _press_button(JOY_BUTTON_Y))
	var pad := InputMapConfig.describe_controller("confirm")
	InputMapConfig.apply_device(InputMapConfig.device_defaults(true), true)
	assert_eq(InputMapConfig.describe_controller("confirm"), pad,
		"applying keyboard bindings leaves controller events untouched")
	_restore()

func test_capture_device_is_device_scoped() -> void:
	InputMapConfig.apply({})
	var kb := InputMapConfig.capture_device(true)
	for action in kb:
		for d in kb[action]:
			assert_eq(String(d.get("type", "")), "key", "capture(keyboard) yields only key events")
	var pad := InputMapConfig.capture_device(false)
	for action in pad:
		for d in pad[action]:
			assert_ne(String(d.get("type", "")), "key", "capture(controller) yields no key events")
	_restore()

func test_a_profile_saved_before_cursor_click_still_clicks_with_the_stick() -> void:
	# `bindings` lacking an action means "never saved", so it takes the default;
	# an action present with [] stays unbound.
	var old_profile := InputMapConfig.device_defaults(false)
	old_profile.erase("cursor_click")             # what an older save holds
	InputMapConfig.apply_device(old_profile, false)
	var evs := InputMap.action_get_events("cursor_click")
	assert_eq(evs.size(), 1, "falls back to the default binding")
	assert_true(evs.size() > 0 and evs[0] is InputEventJoypadButton and evs[0].button_index == JOY_BUTTON_RIGHT_STICK, "R3")
	old_profile["cursor_click"] = []
	InputMapConfig.apply_device(old_profile, false)
	assert_eq(InputMap.action_get_events("cursor_click").size(), 0, "a cleared binding stays cleared")
	_restore()
