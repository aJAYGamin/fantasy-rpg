extends TestSuite

## Settings model: defaults, clamping, config (de)serialization, linear->dB
## conversion, audio-bus creation, and applying volumes to the AudioServer.

func suite_name() -> String:
	return "Settings"

func test_defaults() -> void:
	var s := SettingsModel.new()
	assert_eq(s.volume_master, 1.0, "default master volume")
	assert_eq(s.volume_music, 0.8, "default music volume")
	assert_eq(s.volume_sfx, 0.9, "default sfx volume")
	assert_true(s.autosave_enabled, "autosave on by default")
	assert_eq(s.window_mode, SettingsModel.WindowMode.FULLSCREEN, "fullscreen by default")
	assert_eq(s.fps_cap, 0, "uncapped by default")
	assert_true(s.vsync_enabled, "vsync on by default")
	assert_false(s.show_fps, "fps counter off by default")

func test_clamp_all() -> void:
	var s := SettingsModel.new()
	s.volume_master = 1.5
	s.volume_music = -0.3
	s.volume_sfx = 2.0
	s.window_mode = 99
	s.window_size_index = -5
	s.fps_cap = 999
	s.stick_sensitivity_left = 99.0
	s.stick_sensitivity_right = -3.0
	s.clamp_all()
	assert_eq(s.volume_master, 1.0, "master clamped to 1.0")
	assert_eq(s.volume_music, 0.0, "music clamped to 0.0")
	assert_eq(s.volume_sfx, 1.0, "sfx clamped to 1.0")
	assert_eq(s.window_mode, SettingsModel.WindowMode.WINDOWED, "window_mode clamped to valid range")
	assert_eq(s.window_size_index, 0, "window_size_index clamped to 0")
	assert_eq(s.fps_cap, 0, "invalid fps_cap reset to uncapped")
	assert_eq(s.stick_sensitivity_left, SettingsModel.SENS_MAX, "left stick clamped to max")
	assert_eq(s.stick_sensitivity_right, SettingsModel.SENS_MIN, "right stick clamped to min")

func test_config_round_trip() -> void:
	var a := SettingsModel.new()
	a.volume_master = 0.3
	a.volume_music = 0.6
	a.volume_sfx = 0.15
	a.autosave_enabled = false
	a.window_mode = SettingsModel.WindowMode.WINDOWED
	a.window_size_index = 2
	a.fps_cap = 60
	a.vsync_enabled = false
	a.show_fps = true
	a.difficulty = SettingsModel.Difficulty.HARD
	a.stick_sensitivity_left = 1.5
	a.stick_sensitivity_right = 0.5

	var cfg := ConfigFile.new()
	a.to_config(cfg)

	var b := SettingsModel.new()
	b.from_config(cfg)
	assert_eq(b.difficulty, SettingsModel.Difficulty.HARD, "difficulty round-trips")
	assert_near(b.stick_sensitivity_left, 1.5, 0.0001, "left stick sensitivity round-trips")
	assert_near(b.stick_sensitivity_right, 0.5, 0.0001, "right stick sensitivity round-trips")
	assert_near(b.volume_master, 0.3, 0.0001, "master round-trips")
	assert_near(b.volume_music, 0.6, 0.0001, "music round-trips")
	assert_near(b.volume_sfx, 0.15, 0.0001, "sfx round-trips")
	assert_false(b.autosave_enabled, "autosave round-trips")
	assert_eq(b.window_mode, SettingsModel.WindowMode.WINDOWED, "window_mode round-trips")
	assert_eq(b.window_size_index, 2, "window_size_index round-trips")
	assert_eq(b.fps_cap, 60, "fps_cap round-trips")
	assert_false(b.vsync_enabled, "vsync round-trips")
	assert_true(b.show_fps, "show_fps round-trips")

func test_from_config_uses_defaults_when_missing() -> void:
	var empty := ConfigFile.new()
	var s := SettingsModel.new()
	s.from_config(empty)
	assert_eq(s.volume_master, 1.0, "missing key falls back to default")
	assert_true(s.autosave_enabled, "missing toggle falls back to default")

func test_linear_to_db() -> void:
	assert_near(SettingsModel.linear_volume_to_db(1.0), 0.0, 0.001, "full volume = 0 dB")
	assert_near(SettingsModel.linear_volume_to_db(0.5), -6.0206, 0.01, "half volume ~ -6 dB")
	assert_eq(SettingsModel.linear_volume_to_db(0.0), SettingsModel.SILENCE_DB, "zero volume = silence floor")
	assert_eq(SettingsModel.linear_volume_to_db(0.0002), SettingsModel.SILENCE_DB, "sub-epsilon = silence floor")

func test_ensure_buses() -> void:
	SettingsModel.ensure_buses()
	assert_ne(AudioServer.get_bus_index(SettingsModel.BUS_MUSIC), -1, "Music bus exists")
	assert_ne(AudioServer.get_bus_index(SettingsModel.BUS_SFX), -1, "SFX bus exists")
	# Idempotent: a second call must not add duplicate buses.
	var count_before := AudioServer.bus_count
	SettingsModel.ensure_buses()
	assert_eq(AudioServer.bus_count, count_before, "ensure_buses is idempotent")

func test_apply_audio_sets_bus_volume() -> void:
	var s := SettingsModel.new()
	s.volume_master = 0.5
	s.volume_music = 0.25
	s.volume_sfx = 0.0
	s.apply_audio()

	var master_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(SettingsModel.BUS_MASTER))
	assert_near(master_db, -6.0206, 0.01, "master bus at half volume")

	var sfx_idx := AudioServer.get_bus_index(SettingsModel.BUS_SFX)
	assert_true(AudioServer.is_bus_mute(sfx_idx), "zero-volume bus is muted")

	# Restore the live game settings so this test doesn't leave the engine muted.
	GameManager.settings.apply_audio()

func test_difficulty_defaults_and_modifiers() -> void:
	var s := SettingsModel.new()
	assert_eq(s.difficulty, SettingsModel.Difficulty.NORMAL, "normal difficulty by default")

	s.difficulty = SettingsModel.Difficulty.EASY
	assert_eq(s.enemy_stat_mult(), 0.5, "easy halves enemy stats")
	assert_eq(s.reward_mult(), 1.0, "easy keeps normal rewards")
	assert_false(s.hard_item_caps(), "easy has no item cap")

	s.difficulty = SettingsModel.Difficulty.NORMAL
	assert_eq(s.enemy_stat_mult(), 1.0, "normal enemy stats")
	assert_eq(s.reward_mult(), 1.0, "normal rewards")

	s.difficulty = SettingsModel.Difficulty.HARD
	assert_eq(s.enemy_stat_mult(), 2.0, "hard doubles enemy stats")
	assert_eq(s.reward_mult(), 1.25, "hard gives +25% rewards")
	assert_true(s.shop_price_mult() > 1.0, "hard raises shop prices")
	assert_true(s.hard_item_caps(), "hard caps items")

func test_character_combat_stat_multiplier() -> void:
	var c := Character.new()
	c.base_hp = 100
	c.base_attack = 10
	var base_hp_val := c.max_hp()
	var base_atk_val := c.attack_power()

	c.set_difficulty_multiplier(2.0)
	assert_eq(c.max_hp(), base_hp_val * 2, "max_hp doubles at 2.0x")
	assert_eq(c.attack_power(), base_atk_val * 2, "attack doubles at 2.0x")
	assert_eq(c.current_hp, c.max_hp(), "set_difficulty_multiplier refills HP")

	c.set_difficulty_multiplier(0.5)
	assert_eq(c.max_hp(), int(base_hp_val * 0.5), "max_hp halves at 0.5x")

func test_inventory_hard_item_cap() -> void:
	var prev: int = GameManager.settings.difficulty
	GameManager.settings.difficulty = SettingsModel.Difficulty.HARD
	var inv := Inventory.new()
	var potion := Item.new()
	potion.item_name = "Test Tonic"
	potion.item_type = Item.ItemType.HP_RESTORE   # -> HEALING category
	potion.quantity = 15
	inv.add_item(potion)
	var count := 0
	for it in inv.items:
		if it.item_name == "Test Tonic":
			count = it.quantity
	# A general item is NOT capped.
	var junk := Item.new()
	junk.item_name = "Test Rock"
	junk.item_type = Item.ItemType.GENERAL
	junk.quantity = 25
	inv.add_item(junk)
	var junk_count := 0
	for it in inv.items:
		if it.item_name == "Test Rock":
			junk_count = it.quantity
	GameManager.settings.difficulty = prev
	assert_eq(count, 10, "hard caps a healing stack at 10")
	assert_eq(junk_count, 25, "general items are not capped")

func test_ui_button_sfx_autowired() -> void:
	# A button added anywhere in the tree should get the global SFX wired to both
	# its press and its hover (mouse_entered), matching the main-menu feel.
	var btn := Button.new()
	GameManager.add_child(btn)
	GameManager.remove_child(btn)
	assert_true(_connected_to_gm(btn.pressed), "global SFX auto-wires press")
	assert_true(_connected_to_gm(btn.mouse_entered), "global SFX auto-wires hover")
	btn.free()

func _connected_to_gm(sig: Signal) -> bool:
	for conn in sig.get_connections():
		var cb: Callable = conn["callable"]
		if cb.get_object() == GameManager:
			return true
	return false

func test_ui_sfx_stream_loaded() -> void:
	# The global click SFX must actually have its stream loaded, else every button
	# would be silent. Also confirm it's set to play while the tree is paused.
	assert_true(GameManager._ui_sfx != null, "ui sfx player exists")
	assert_true(GameManager._ui_sfx.stream != null, "ui sfx stream loaded")
	assert_eq(GameManager._ui_sfx.process_mode, Node.PROCESS_MODE_ALWAYS, "ui sfx plays while paused")

func test_apply_performance_sets_max_fps() -> void:
	var s := SettingsModel.new()
	s.fps_cap = 60
	s.vsync_enabled = false
	s.apply_performance()
	assert_eq(Engine.max_fps, 60, "max_fps applied from fps_cap")
	# Restore the live settings so we don't leave the engine capped.
	GameManager.settings.apply_performance()

func test_cursor_defaults() -> void:
	var s := SettingsModel.new()
	assert_eq(s.cursor_shape, "A", "Amethyst Arrow by default")
	assert_eq(s.cursor_colour, "amethyst", "in Amethyst")
	assert_near(s.mouse_sensitivity, 1.0, 0.0001, "1.00× by default")

func test_cursor_settings_round_trip_through_config() -> void:
	var a := SettingsModel.new()
	a.cursor_shape = "AK"
	a.cursor_colour = "garnet"
	a.mouse_sensitivity = 2.35
	var cfg := ConfigFile.new()
	a.to_config(cfg)
	var b := SettingsModel.new()
	b.from_config(cfg)
	assert_eq(b.cursor_shape, "AK", "shape survives a restart")
	assert_eq(b.cursor_colour, "garnet", "colour survives")
	assert_near(b.mouse_sensitivity, 2.35, 0.0001, "sensitivity survives")

func test_bad_cursor_values_fall_back() -> void:
	var s := SettingsModel.new()
	s.cursor_shape = "Z"
	s.cursor_colour = "teal"
	s.mouse_sensitivity = 9.0
	s.clamp_all()
	assert_eq(s.cursor_shape, "A", "unknown shape → default")
	assert_eq(s.cursor_colour, "amethyst", "unknown colour → default")
	assert_near(s.mouse_sensitivity, 3.0, 0.0001, "clamped to the top")
	s.mouse_sensitivity = 0.0
	s.clamp_all()
	assert_near(s.mouse_sensitivity, 0.25, 0.0001, "clamped to the bottom")

func test_cursor_shape_and_colour_validate_independently() -> void:
	# A bad colour must not reset a good shape, and a bad shape must not reset a good colour.
	var s := SettingsModel.new()
	s.cursor_shape = "AK"
	s.cursor_colour = "teal"
	s.clamp_all()
	assert_eq(s.cursor_shape, "AK", "a good shape survives a bad colour")
	assert_eq(s.cursor_colour, "amethyst", "the bad colour alone falls back")
	s.cursor_shape = "Z"
	s.cursor_colour = "garnet"
	s.clamp_all()
	assert_eq(s.cursor_shape, "A", "the bad shape alone falls back")
	assert_eq(s.cursor_colour, "garnet", "a good colour survives a bad shape")

# --------------------------------------------------- settings panel layout

## Every settings view — the category lists AND the detail sub-menus (Game,
## Audio, Display, Performance, Keyboard, Controller, Mouse) — keeps its title,
## divider lines and Back button centred in the panel. The detail views used to
## shrink the panel's RIGHT margin to 8px (vs 24px on the left) to tuck the
## scrollbar against the border, which pushed everything else 16px right.
## Only the scroll area may reach into the right padding now.
const _SETTINGS_VIEWS := ["root", "controls", "game", "audio", "display", "performance", "keyboard", "controller", "mouse"]

func _settings_panel(screen: SettingsScreen) -> PanelContainer:
	for c in screen.get_children():
		if c is CenterContainer:
			return c.get_child(0) as PanelContainer
	return null

func test_every_settings_view_is_centred_in_its_panel() -> void:
	var screen := SettingsScreen.new()
	GameManager.add_child(screen)   # _build sizes itself from the viewport
	for view in _SETTINGS_VIEWS:
		screen._view = view
		screen._build()
		var panel := _settings_panel(screen)
		var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
		assert_eq(style.content_margin_left, style.content_margin_right,
				"%s: title, lines and Back sit centred (left margin == right margin)" % view)
	GameManager.remove_child(screen)
	screen.free()

func test_scrolling_settings_content_shares_the_centred_column() -> void:
	# The rows and section lines INSIDE a detail view's scroll area must use the
	# same 24/24 column as the title and Back button. The scroll area reaches
	# SCROLL_REACH into the right padding for its scrollbar, and always reserves
	# that scrollbar's width (visible or not), so the content's right padding is
	# whatever is left of the reach — then the column ends exactly
	# PANEL_MARGIN_X from the border in every view, scrolling or not.
	var screen := SettingsScreen.new()
	GameManager.add_child(screen)
	for view in ["game", "audio", "display", "performance", "keyboard", "controller", "mouse"]:
		screen._view = view
		screen._build()
		var scroll := screen.find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer
		var pad := scroll.get_child(0) as MarginContainer
		var bar_w := scroll.get_v_scroll_bar().get_combined_minimum_size().x
		assert_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_RESERVE,
				"%s: the scrollbar's width is always set aside, visible or not" % view)
		assert_eq(pad.get_theme_constant("margin_right") + bar_w, float(SettingsScreen.SCROLL_REACH),
				"%s: content ends %dpx from the border, like the title and Back" % [view, SettingsScreen.PANEL_MARGIN_X])
	GameManager.remove_child(screen)
	screen.free()

# ------------------------------------------------------ the Cursor Click row

func _texts_of_labels(screen: SettingsScreen) -> PackedStringArray:
	var out := PackedStringArray()
	for l in screen.find_children("*", "Label", true, false):
		out.append((l as Label).text)
	return out

func test_the_keyboard_page_has_no_cursor_click_row_and_the_controller_page_does() -> void:
	var screen := SettingsScreen.new()
	GameManager.add_child(screen)

	screen._view = "keyboard"
	screen._build()
	assert_false("Cursor Click" in _texts_of_labels(screen), "no Cursor Click label on the Keyboard page")
	assert_false(screen._kb_buttons.has("cursor_click"), "no keyboard binding button for it")
	assert_true(screen._kb_buttons.has("confirm"), "the other actions still have rows")
	assert_eq(screen._kb_buttons.size(), InputMapConfig.ACTIONS.size() - 1, "every action but the pad-only one")

	screen._view = "controller"
	screen._build()
	var texts := _texts_of_labels(screen)
	assert_true("Cursor Click" in texts, "a Cursor Click row on the Controller page")
	assert_true(screen._pad_buttons.has("cursor_click"), "with a controller binding button")
	assert_eq(screen._pad_buttons.size(), InputMapConfig.ACTIONS.size(), "alongside every other action")
	assert_true("Right stick moves the cursor — press it to click." in texts, "the note explains the stick")
	assert_false("Right stick is reserved for future camera control." in texts, "the old camera note is gone")

	GameManager.remove_child(screen)
	screen.free()


# ------------------------------------------------ rebinding sees the raw controller

func test_waiting_for_a_button_hands_the_controller_to_the_game_raw() -> void:
	# The cursor takes the right stick and its press for itself, unless a screen is
	# waiting to bind them (VirtualCursor reads raw_input_passthrough).
	var was := GameManager.raw_input_passthrough
	var screen := SettingsScreen.new()
	GameManager.add_child(screen)
	screen._view = "controller"
	screen._build()
	assert_false(GameManager.raw_input_passthrough, "an open Controller page doesn't pass anything through")

	screen._start_listening("cursor_click", false)
	assert_true(GameManager.raw_input_passthrough, "waiting for a button does")
	screen._stop_listening()
	assert_false(GameManager.raw_input_passthrough, "and stops when the binding is done or cancelled")

	screen._start_listening("cursor_click", false)
	screen._build()   # Back, or a click elsewhere, rebuilds the page mid-wait
	assert_false(GameManager.raw_input_passthrough, "a rebuilt page isn't waiting any more")

	screen._start_listening("confirm", false)
	GameManager.remove_child(screen)
	screen.free()
	assert_false(GameManager.raw_input_passthrough, "closing the screen mid-wait lets the right stick move the cursor again")
	GameManager.raw_input_passthrough = was

func test_the_right_stick_cannot_be_bound_to_an_action() -> void:
	# It moves the cursor, which consumes it, so a binding on it would be dead in the menus.
	_protect()   # a binding that did land would save the bindings to the player's config.cfg
	var screen := SettingsScreen.new()
	GameManager.add_child(screen)
	screen._view = "controller"
	screen._build()
	var confirm_before: Array = []
	for ev in InputMap.action_get_events("confirm"):
		confirm_before.append(InputMapConfig.serialize_event(ev))
	screen._start_listening("confirm", false)
	for axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
		for value in [0.9, -0.9]:
			var ev := InputEventJoypadMotion.new()
			ev.axis = axis
			ev.axis_value = value
			screen._capture_rebind(ev)
	assert_true(screen._listening, "pushing the right stick neither binds nor ends the wait")
	assert_true(GameManager.raw_input_passthrough, "so the page is still taking the pad raw")
	var confirm_after: Array = []
	for ev in InputMap.action_get_events("confirm"):
		confirm_after.append(InputMapConfig.serialize_event(ev))
	assert_eq(confirm_after, confirm_before, "Confirm is exactly as it was")
	screen._stop_listening()
	GameManager.remove_child(screen)
	screen.free()
	_restore()


# ------------------------------------------- the Mouse page and the Max FPS row

const _CONFIG := "user://config.cfg"

## What these tests change, put back by _restore(): the live settings (without going
## through an apply_*_and_save helper, which would write the player's config.cfg), the
## engine's frame cap, the input mode, and the config file itself, which the rows'
## apply_*_and_save calls DO write.
var _kept := {}

func _protect() -> void:
	var s := GameManager.settings
	var had := FileAccess.file_exists(_CONFIG)
	_kept = {
		"shape": s.cursor_shape,
		"colour": s.cursor_colour,
		"sensitivity": s.mouse_sensitivity,
		"fps": s.fps_cap,
		"controller": GameManager._controller_mode,
		"keyboard": GameManager._keyboard_nav,
		"had_config": had,
		"config": FileAccess.get_file_as_bytes(_CONFIG) if had else PackedByteArray(),
	}
	# Known starting values, whatever the player has set.
	s.cursor_shape = "A"
	s.cursor_colour = "amethyst"
	s.mouse_sensitivity = 1.0
	s.fps_cap = 0

func _restore() -> void:
	var s := GameManager.settings
	s.cursor_shape = _kept["shape"]
	s.cursor_colour = _kept["colour"]
	s.mouse_sensitivity = _kept["sensitivity"]
	s.fps_cap = _kept["fps"]
	GameManager.virtual_cursor.refresh_style()
	s.apply_performance()
	GameManager._apply_input_mode(_kept["controller"], _kept["keyboard"])
	if _kept["had_config"]:
		var f := FileAccess.open(_CONFIG, FileAccess.WRITE)
		f.store_buffer(_kept["config"])
		f.close()
	elif FileAccess.file_exists(_CONFIG):
		DirAccess.remove_absolute(_CONFIG)

func _open(view: String) -> SettingsScreen:
	var screen := SettingsScreen.new()
	GameManager.add_child(screen)
	screen._view = view
	screen._build()
	return screen

func _close(screen: SettingsScreen) -> void:
	GameManager.remove_child(screen)
	screen.free()

func _cycler(screen: SettingsScreen, label_text: String) -> CyclerRow:
	for r in screen.find_children("*", "CyclerRow", true, false):
		if (r as CyclerRow)._name_label.text == label_text:
			return r
	return null

func _nodes_named_or_labelled(screen: SettingsScreen, word: String) -> int:
	var hits := 0
	for n in screen.find_children("*", "", true, false):
		if word in String(n.name).to_lower():
			hits += 1
		if (n is Label or n is Button) and word in String(n.text).to_lower():
			hits += 1
	return hits

func test_the_controls_page_lists_keyboard_controller_and_mouse() -> void:
	var screen := _open("controls")
	var entries := PackedStringArray()
	for b in screen.find_children("*", "Button", true, false):
		if not (b as Button).text.begins_with("←"):
			entries.append((b as Button).text)
	assert_eq(entries, PackedStringArray(["Keyboard", "Controller", "Mouse"]), "Mouse sits beside the other two")
	assert_eq(screen._parent_of("mouse"), "controls", "the Mouse page backs out to Controls")
	screen._view = "mouse"
	assert_eq(screen._view_title(), "Mouse", "and is titled Mouse")
	_close(screen)

func test_the_mouse_page_says_where_the_right_sticks_speed_is() -> void:
	# Mouse Sensitivity moves only the real mouse; the stick cursor's speed is the
	# Controller page's Right Stick Sensitivity. A play-tester moved the Mouse page's
	# slider, saw the stick unchanged and took it for a bug, so the page says so.
	var screen := _open("mouse")
	var note: Label = null
	for l in screen.find_children("*", "Label", true, false):
		if (l as Label).text == SettingsScreen.STICK_SPEED_NOTE:
			note = l
	assert_true(note != null, "the Mouse page shows the note")
	assert_true("Controller" in SettingsScreen.STICK_SPEED_NOTE and "Right Stick Sensitivity" in SettingsScreen.STICK_SPEED_NOTE,
			"naming the page and the setting")
	var sliders := screen.find_children("*", "HSlider", true, false)
	if note != null and sliders.size() == 1:
		var row := (sliders[0] as HSlider).get_parent()
		assert_eq(note.get_parent(), row.get_parent(), "in the page's column")
		assert_eq(note.get_index(), row.get_index() + 1, "right under Mouse Sensitivity")
		assert_eq(note.get_theme_color("font_color"), SettingsScreen.NOTE_COLOR, "in the note colour")
	_close(screen)

func test_the_mouse_page_offers_shape_colour_and_sensitivity() -> void:
	_protect()
	var s := GameManager.settings
	var screen := _open("mouse")
	var shape := _cycler(screen, "Cursor Shape")
	var colour := _cycler(screen, "Cursor Colour")
	assert_true(shape != null and colour != null, "a Cursor Shape row and a Cursor Colour row")
	assert_true("Mouse Sensitivity" in _texts_of_labels(screen), "a Mouse Sensitivity row")
	var sliders := screen.find_children("*", "HSlider", true, false)
	assert_eq(sliders.size(), 1, "with its slider")

	if shape != null and colour != null and sliders.size() == 1:
		var slider := sliders[0] as HSlider
		var column := shape.get_parent()
		assert_true(colour.get_parent() == column and slider.get_parent().get_parent() == column,
				"the three rows share one column")
		assert_true(shape.get_index() < colour.get_index() and colour.get_index() < slider.get_parent().get_index(),
				"in order: shape, colour, sensitivity")

		var shape_names := PackedStringArray()
		for id in CursorArt.SHAPES:
			shape_names.append(CursorArt.shape_name(id))
		var colour_names := PackedStringArray()
		for id in CursorArt.COLOURS:
			colour_names.append(CursorArt.colour_name(id))
		assert_eq(shape.labels, shape_names, "the shape row steps through the ten shapes by name")
		assert_eq(colour.labels, colour_names, "the colour row steps through the twenty colours by name")
		assert_eq(shape.index, 0, "starting on the saved shape")
		assert_eq(colour.index, 0, "and the saved colour")

		shape.step(1)
		assert_eq(s.cursor_shape, "B", "stepping the shape forward picks Crystal Shard")
		assert_eq(GameManager.virtual_cursor.sprite.texture, CursorArt.texture("B", "amethyst"),
				"and the live cursor follows at once")
		shape.step(-1)
		shape.step(-1)
		assert_eq(s.cursor_shape, "AV", "it wraps round to the last shape")
		assert_eq(GameManager.virtual_cursor.sprite.texture, CursorArt.texture("AV", "amethyst"), "live cursor again")

		colour.step(1)
		assert_eq(s.cursor_colour, "arcane", "stepping the colour forward picks Arcane")
		assert_eq(GameManager.virtual_cursor.sprite.texture, CursorArt.texture("AV", "arcane"),
				"the live cursor takes the new colour")
	assert_eq(_nodes_named_or_labelled(screen, "preview"), 0, "no preview section: the real cursor is the preview")
	_close(screen)
	_restore()

func test_the_shape_row_wears_the_current_colour_and_the_colour_row_a_dot() -> void:
	_protect()
	var s := GameManager.settings
	s.cursor_shape = "K"
	s.cursor_colour = "garnet"
	var screen := _open("mouse")
	var shape := _cycler(screen, "Cursor Shape")
	var colour := _cycler(screen, "Cursor Colour")
	assert_eq(shape.index, CursorArt.SHAPES.find("K"), "the shape row opens on the saved shape")
	assert_eq(colour.index, CursorArt.COLOURS.find("garnet"), "the colour row on the saved colour")

	assert_true(shape._icon.visible, "the shape row shows an icon")
	assert_true(_is_cursor_icon(shape._icon.texture, "K", "garnet"), "CursorArt's icon of the saved shape in the saved colour")
	var dot := colour._dot.get_theme_stylebox("panel") as StyleBoxFlat
	assert_true(colour._dot.visible, "the colour row shows a dot")
	assert_eq(dot.bg_color, CursorArt.swatch("garnet"), "in the saved colour")

	colour.step(1)
	assert_eq(dot.bg_color, CursorArt.swatch("ember"), "stepping the colour recolours the dot")
	assert_true(_is_cursor_icon(shape._icon.texture, "K", "ember"), "and re-tints the shape row's icon")
	shape.step(1)
	assert_true(_is_cursor_icon(shape._icon.texture, "L", "ember"), "stepping the shape swaps the icon, in the same colour")
	_close(screen)
	_restore()

## True when `tex` is CursorArt.icon(shape, colour): the cursor's art, cropped, with mipmaps.
func _is_cursor_icon(tex: Texture2D, shape: String, colour: String) -> bool:
	var want := CursorArt.icon(shape, colour)
	return tex is ImageTexture and want != null and tex.get_image().get_data() == want.get_image().get_data()

func test_dark_swatches_get_their_ring() -> void:
	_protect()
	var s := GameManager.settings
	s.cursor_colour = "void"
	var screen := _open("mouse")
	var colour := _cycler(screen, "Cursor Colour")
	var dot := colour._dot.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(dot.border_width_left, 1, "Void's dot shows against the dark panel")
	colour.step(1)
	assert_eq(s.cursor_colour, "obsidian", "the next colour is Obsidian")
	assert_eq(dot.border_width_left, 1, "whose dot is ringed too")
	colour.step(1)
	assert_eq(dot.border_width_left, 0, "Steel is light enough without one")
	_close(screen)
	_restore()

func test_the_mouse_sensitivity_slider() -> void:
	_protect()
	var s := GameManager.settings
	var screen := _open("mouse")
	var slider := screen.find_children("*", "HSlider", true, false)[0] as HSlider
	assert_near(slider.min_value, SettingsModel.MOUSE_SENS_MIN, 0.0001, "from 0.25×")
	assert_near(slider.max_value, SettingsModel.MOUSE_SENS_MAX, 0.0001, "to 3.00×")
	assert_near(slider.step, SettingsModel.MOUSE_SENS_STEP, 0.0001, "in 0.05 steps")
	assert_near(slider.value, 1.0, 0.0001, "starting at the saved sensitivity")
	assert_true("1.00×" in _texts_of_labels(screen), "shown as 1.00×")

	slider.value = 2.5
	assert_near(s.mouse_sensitivity, 2.5, 0.0001, "moving the slider sets the mouse's speed")
	assert_true("2.50×" in _texts_of_labels(screen), "and the readout follows")
	slider.value = 99.0
	assert_near(s.mouse_sensitivity, 3.0, 0.0001, "never past the top")
	_close(screen)

	# The stick sliders keep their own range.
	var pad_page := _open("controller")
	for sl in pad_page.find_children("*", "HSlider", true, false):
		assert_near((sl as HSlider).max_value, SettingsModel.SENS_MAX, 0.0001, "stick sliders still top out at 2.00×")
		assert_near((sl as HSlider).min_value, SettingsModel.SENS_MIN, 0.0001, "and start at 0.25×")
	_close(pad_page)
	_restore()

func test_max_fps_is_a_left_right_row() -> void:
	_protect()
	var s := GameManager.settings
	s.fps_cap = 144
	var screen := _open("performance")
	assert_eq(screen.find_children("*", "OptionButton", true, false).size(), 0, "no dropdown left on the Performance page")
	var row := _cycler(screen, "Max FPS")
	assert_true(row != null, "Max FPS is a left/right row")
	if row != null:
		assert_eq(row.labels, PackedStringArray(["Uncapped", "30", "60", "120", "144"]), "the same choices the dropdown had")
		assert_eq(row.index, 4, "opening on the saved cap")
		row.step(1)
		assert_eq(row.index, 0, "stepping on from 144 wraps to Uncapped")
		assert_eq(s.fps_cap, 0, "and sets the cap")
		assert_eq(Engine.max_fps, 0, "which applies at once")
		row.step(1)
		assert_eq(s.fps_cap, 30, "next is 30")
		assert_eq(Engine.max_fps, 30, "applied")
	assert_eq(screen.find_children("*", "CheckButton", true, false).size(), 2, "V-Sync and the FPS counter keep their toggles")
	_close(screen)
	_restore()

func test_window_mode_and_resolution_keep_their_dropdowns() -> void:
	var screen := _open("display")
	assert_eq(screen.find_children("*", "OptionButton", true, false).size(), 2, "Window Mode and Resolution are still dropdowns")
	assert_eq(screen.find_children("*", "CyclerRow", true, false).size(), 0, "and the Display page has no left/right rows")
	_close(screen)

func test_backing_out_of_the_mouse_page_returns_to_the_mouse_entry() -> void:
	_protect()
	var screen := _open("controls")
	GameManager.register_focus_scope(screen)
	screen._open_category("mouse")
	assert_eq(screen._view, "mouse", "the Mouse entry opens the page")
	screen._on_back()
	assert_eq(screen._view, "controls", "Back returns to Controls")
	GameManager.set_controller_mode_for_test(true)
	GameManager.update_focus_guard_for_test()
	var owner := screen.get_viewport().gui_get_focus_owner()
	assert_true(owner is Button and (owner as Button).text == "Mouse", "with focus back on the Mouse entry, not the top of the list")

	# Esc / controller B does the same.
	screen._open_category("mouse")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	screen._input(cancel)
	assert_eq(screen._view, "controls", "Esc backs out of the Mouse page too")
	_close(screen)
	_restore()

func test_the_mouse_page_is_reachable_by_focus_navigation() -> void:
	# d-pad / left stick / keyboard: the two rows and the slider are the stops (the
	# arrows are click-only), then Back.
	_protect()
	var screen := _open("mouse")
	GameManager.register_focus_scope(screen)
	GameManager.set_controller_mode_for_test(true)
	GameManager.update_focus_guard_for_test()
	var stops: Array = []
	GameManager._collect_focusable(screen, stops)
	assert_eq(stops.size(), 4, "shape row, colour row, slider, Back")
	if stops.size() == 4:
		assert_eq(stops[0], _cycler(screen, "Cursor Shape"), "the shape row first")
		assert_eq(stops[1], _cycler(screen, "Cursor Colour"), "then the colour row")
		assert_true(stops[2] is HSlider, "then the sensitivity slider")
		assert_true(stops[3] is Button and (stops[3] as Button).text.begins_with("←"), "then Back")
	assert_eq(screen.get_viewport().gui_get_focus_owner(), _cycler(screen, "Cursor Shape"), "focus opens on the first row")

	GameManager.set_controller_mode_for_test(false)
	GameManager.update_focus_guard_for_test()
	assert_eq(_cycler(screen, "Cursor Shape").focus_mode, Control.FOCUS_NONE, "mouse play leaves the rows click-only")
	for b in _cycler(screen, "Cursor Shape").find_children("*", "Button", true, false):
		assert_eq((b as Button).focus_mode, Control.FOCUS_NONE, "and the arrows stay clickable but unfocusable")
	_close(screen)
	_restore()


# ------------------------------------------- every page, every input (Task 10)

func test_the_long_settings_pages_scroll_to_the_highlighted_row() -> void:
	# The Keyboard and Controller pages are taller than their scroll area. Godot's
	# ScrollContainer only scrolls to the focused control when follow_focus is on, so
	# without it the d-pad / arrow keys walked the highlight off the bottom of the
	# page and it went on moving out of sight.
	for view in ["keyboard", "controller"]:
		var screen := _open(view)
		var scroll := screen.find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer
		var content := scroll.get_child(0) as Control
		assert_true(content.get_combined_minimum_size().y > scroll.custom_minimum_size.y,
				"%s: the page is taller than its scroll area, so it scrolls" % view)
		_close(screen)
	for view in ["game", "audio", "display", "performance", "keyboard", "controller", "mouse"]:
		var screen := _open(view)
		var scroll := screen.find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer
		assert_true(scroll.follow_focus, "%s: the page scrolls to the highlighted row" % view)
		_close(screen)

func test_a_controller_backs_out_of_waiting_for_a_key() -> void:
	# A pad player who presses A on a Keyboard-page binding has no key to press. Their
	# Cancel (B) ends the wait without binding anything, as Esc does; before, nothing
	# on the pad did, and the right stick's cursor is off while the page waits.
	_protect()   # binding B below saves the bindings to config.cfg
	var kept_cancel := InputMap.action_get_events("ui_cancel")
	InputMap.action_erase_events("ui_cancel")
	var pad_b := InputEventJoypadButton.new()
	pad_b.button_index = JOY_BUTTON_B
	InputMap.action_add_event("ui_cancel", pad_b)
	var kept_click := InputMap.action_get_events("cursor_click")
	var was_passthrough := GameManager.raw_input_passthrough

	var screen := _open("keyboard")
	var confirm_before: Array = []
	for ev in InputMap.action_get_events("confirm"):
		confirm_before.append(InputMapConfig.serialize_event(ev))
	screen._start_listening("confirm", true)
	assert_true(screen._listening, "the page waits for a key")
	var press := pad_b.duplicate() as InputEventJoypadButton
	press.pressed = true
	screen._input(press)
	assert_false(screen._listening, "the pad's Cancel ends the wait")
	assert_false(GameManager.raw_input_passthrough, "and hands the right stick back to the cursor")
	assert_true(GameManager.has_focus_scope(screen), "and gives the page its highlight back")
	assert_eq(screen._kb_buttons["confirm"].text, InputMapConfig.describe_keyboard("confirm"), "the row shows its key again, not \"Press…\"")
	var confirm_after: Array = []
	for ev in InputMap.action_get_events("confirm"):
		confirm_after.append(InputMapConfig.serialize_event(ev))
	assert_eq(confirm_after, confirm_before, "nothing was bound")

	# Waiting for a CONTROLLER button, B is just another button to bind.
	screen._view = "controller"
	screen._build()
	screen._start_listening("cursor_click", false)
	screen._input(press)
	assert_false(screen._listening, "on the Controller page B binds")
	var bound_b := false
	for ev in InputMap.action_get_events("cursor_click"):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_B:
			bound_b = true
	assert_true(bound_b, "Cursor Click is now on B")

	_close(screen)
	InputMap.action_erase_events("cursor_click")
	for ev in kept_click:
		InputMap.action_add_event("cursor_click", ev)
	InputMap.action_erase_events("ui_cancel")
	for ev in kept_cancel:
		InputMap.action_add_event("ui_cancel", ev)
	GameManager.input_profiles.sync_from_input_map()   # the profile took the B binding too
	GameManager.raw_input_passthrough = was_passthrough
	_restore()

func test_backing_out_mid_wait_hands_the_page_back_to_the_focus_guard() -> void:
	# Waiting for a binding takes the page out of the focus guard. Clicking "← Back" (or
	# anything else that rebuilds the page) ended the wait but left it out, so after the
	# player went back to the arrows / d-pad nothing on the page could be highlighted —
	# and over the main menu the highlight landed on a main-menu button behind the panel.
	var was_passthrough := GameManager.raw_input_passthrough
	var screen := _open("keyboard")
	GameManager.register_focus_scope(screen)   # as setup() does
	screen._start_listening("confirm", true)
	assert_false(GameManager.has_focus_scope(screen), "waiting for a key takes the page out of the guard")
	screen._on_back()
	assert_eq(screen._view, "controls", "Back went up to Controls")
	assert_false(screen._listening, "and ended the wait")
	assert_true(GameManager.has_focus_scope(screen), "and handed the page back to the focus guard")
	assert_false(GameManager.raw_input_passthrough, "with the right stick back on the cursor")

	# Any other rebuild mid-wait does the same.
	screen._open_category("controller")
	screen._start_listening("cursor_click", false)
	screen._build()
	assert_true(GameManager.has_focus_scope(screen), "a rebuild mid-wait hands it back too")
	assert_eq(GameManager.focus_scope_count(screen), 1, "registered once, not twice")
	_close(screen)
	GameManager.raw_input_passthrough = was_passthrough


# ------------------------------------ the Controller page's on-screen keyboard
# The Rename field on the Controller page opens the on-screen keyboard (OnScreenKeyboard)
# when the pad's Confirm is pressed on it. These tests press the pad's buttons and keys
# through the real pipeline (`push_input` on the root) and read what a node behind the
# keyboard would have heard with an InputReader added to GameManager BEFORE the screen: the
# engine calls `_input` in reverse tree order and stops at the first handler that marks the
# event handled.

## Records the pad buttons and keys that reach it, which is everything a node behind the
## keyboard (a page, the pause menu, the overworld's pause handler) would have heard.
class InputReader extends Node:
	var heard: Array = []

	func _input(ev: InputEvent) -> void:
		if (ev is InputEventJoypadButton or ev is InputEventKey) and ev.pressed:
			heard.append(ev)

## The bindings these tests press, so they hold whatever the player has remapped.
const _PAD_ACTIONS := ["confirm", "cancel", "pause", "cursor_click", "move_up", "move_down",
	"move_left", "move_right", "ui_accept", "ui_cancel"]

var _kept_pad := {}

## _protect()s the config (a rename saves the bindings and the name to config.cfg), keeps the
## active controller profile's name and the live bindings, puts the pad on its stock buttons
## (A confirms, B cancels, Start pauses) and switches to the controller's highlight.
func _pad_begin() -> void:
	_protect()
	var profiles := GameManager.input_profiles
	_kept_pad = {"name": profiles.name_for(false, profiles.active_index(false)), "bindings": {}}
	for action: String in _PAD_ACTIONS:
		_kept_pad["bindings"][action] = InputMap.action_get_events(action)
	InputMapConfig.reset_all_controller()
	GameManager.set_controller_mode_for_test(true)

func _pad_end() -> void:
	var profiles := GameManager.input_profiles
	profiles.set_name(false, profiles.active_index(false), _kept_pad["name"])
	for action: String in _kept_pad["bindings"]:
		InputMap.action_erase_events(action)
		for ev: InputEvent in _kept_pad["bindings"][action]:
			InputMap.action_add_event(action, ev)
	profiles.sync_from_input_map()   # a save while the stock buttons were live captured them
	_restore()

## A pad button into the root, as the engine delivers it.
func _pad(button: JoyButton, pressed := true) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = pressed
	GameManager.get_viewport().push_input(ev)

## A key into the root.
func _key(keycode: Key, pressed := true) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = pressed
	GameManager.get_viewport().push_input(ev)

## The Controller page's Rename field holds the highlight and the pad's Confirm is pressed
## on it. Returns the keyboard that opens (null when none does).
func _press_confirm_on_the_field(screen: SettingsScreen) -> OnScreenKeyboard:
	screen._pad_profile_name.grab_focus()
	_pad(JOY_BUTTON_A)
	return screen._keyboard_panel

func _focus_owner() -> Control:
	return GameManager.get_viewport().gui_get_focus_owner()

func _keyboards_under(screen: SettingsScreen) -> Array:
	return screen.find_children("*", "OnScreenKeyboard", true, false)

func test_confirm_on_the_controller_rename_field_opens_the_keyboard() -> void:  # Review Focus 1
	_pad_begin()
	var profiles := GameManager.input_profiles
	profiles.set_name(false, profiles.active_index(false), "Couch")
	var screen := _open("controller")
	assert_true(screen._keyboard_panel == null, "no keyboard until the field is pressed")
	var panel := _press_confirm_on_the_field(screen)
	assert_true(is_instance_valid(panel), "Confirm on the highlighted Rename field opens the keyboard")
	assert_eq(panel.get_text(), "Couch", "it opens on the profile's current name, and the press that opened it typed nothing")
	assert_eq(screen.get_child(screen.get_child_count() - 1), panel,
		"it is the screen's last child, so it hears every press before the screen does")
	GameManager.update_focus_guard_for_test()
	assert_eq(_focus_owner(), panel.key_button("Q"), "the highlight lands on its Q key")
	_pad(JOY_BUTTON_A, false)
	assert_eq(panel.get_text(), "Couch", "the release of the press that opened it lands on Q and types nothing")
	_close(screen)
	_pad_end()

func test_the_keyboard_page_field_never_opens_it() -> void:
	_pad_begin()
	var screen := _open("keyboard")
	screen._kb_profile_name.grab_focus()
	assert_true(screen._kb_profile_name.has_focus(), "the Keyboard page's Rename field holds the highlight")
	_pad(JOY_BUTTON_A)
	_pad(JOY_BUTTON_A, false)
	assert_true(screen._keyboard_panel == null, "Confirm on it opens no keyboard")
	assert_eq(_keyboards_under(screen).size(), 0, "and none is anywhere under the screen")
	_close(screen)

	# Having been on the Controller page first changes nothing: its field is gone with the
	# page, and its name is no reason to open the keyboard from this one.
	var visited := _open("controller")
	visited._view = "keyboard"
	visited._build()
	visited._kb_profile_name.grab_focus()
	_pad(JOY_BUTTON_A)
	_pad(JOY_BUTTON_A, false)
	assert_eq(_keyboards_under(visited).size(), 0, "after a visit to the Controller page, still none")
	assert_true(visited._keyboard_panel == null, "and it is not open")
	_close(visited)
	_pad_end()

func test_the_press_that_opens_it_is_the_pad_taking_over() -> void:
	# The page takes the press, so GameManager's own _input never sees it: the page says so.
	_pad_begin()
	var screen := _open("controller")
	GameManager.set_keyboard_nav_for_test(true)   # the field was reached with the arrow keys
	assert_false(GameManager.is_controller_mode(), "starting on the keyboard's highlight")
	var panel := _press_confirm_on_the_field(screen)
	assert_true(is_instance_valid(panel), "Confirm opens the keyboard from there too")
	assert_true(GameManager.is_controller_mode(), "and the game now follows the pad")
	_close(screen)
	_pad_end()

func test_only_a_confirm_press_on_the_controller_field_opens_it() -> void:
	# Enter on the field commits the name as it always did; other buttons, and a Confirm
	# release with no press, open nothing.
	_pad_begin()
	var screen := _open("controller")
	screen._pad_profile_name.grab_focus()
	_key(KEY_ENTER)
	_key(KEY_ENTER, false)
	_pad(JOY_BUTTON_Y)
	_pad(JOY_BUTTON_Y, false)
	_pad(JOY_BUTTON_X)
	_pad(JOY_BUTTON_X, false)
	screen._pad_profile_name.grab_focus()
	_pad(JOY_BUTTON_A, false)
	assert_eq(_keyboards_under(screen).size(), 0, "no other press opens it")
	assert_true(screen._keyboard_panel == null, "and it is not open")
	_close(screen)
	_pad_end()

func test_done_saves_through_the_profile_rules_and_returns_the_highlight() -> void:
	_pad_begin()
	var screen := _open("controller")
	GameManager.register_focus_scope(screen)   # as setup() does
	var profiles := GameManager.input_profiles
	var active := profiles.active_index(false)
	var panel := _press_confirm_on_the_field(screen)
	assert_true(is_instance_valid(panel), "the keyboard opens")
	while not panel.get_text().is_empty():
		panel.delete_last()
	for c in "  Couch  ":
		panel.type_char(c)
	panel.finish()
	assert_eq(screen._pad_profile_name.text, "Couch", "the field shows the name cleaned up, as a typed one is")
	assert_eq(screen._pad_profile_pick.get_item_text(active), "Couch", "so does the Active Profile picker")
	assert_eq(profiles.name_for(false, active), "Couch", "and the profile stores it")
	assert_true(screen._keyboard_panel == null, "the keyboard is no longer open")
	GameManager.update_focus_guard_for_test()
	assert_eq(_focus_owner(), screen._pad_profile_name, "the highlight is back on the Rename field")

	# A blank name falls back to the numbered default, as it does for a typed one.
	var second := _press_confirm_on_the_field(screen)
	assert_true(is_instance_valid(second), "it opens again")
	while not second.get_text().is_empty():
		second.delete_last()
	second.finish()
	assert_eq(profiles.name_for(false, active), InputProfiles.default_name(active), "an empty name becomes the default")
	assert_eq(screen._pad_profile_name.text, InputProfiles.default_name(active), "which the field shows")
	GameManager.update_focus_guard_for_test()
	assert_eq(_focus_owner(), screen._pad_profile_name, "and the highlight is back on the field again")
	GameManager.unregister_focus_scope(screen)
	_close(screen)
	_pad_end()

func test_cancel_leaves_the_name() -> void:
	_pad_begin()
	var screen := _open("controller")
	GameManager.register_focus_scope(screen)
	var profiles := GameManager.input_profiles
	var active := profiles.active_index(false)
	profiles.set_name(false, active, "Couch")
	screen._refresh_profile_name_field(false)
	var panel := _press_confirm_on_the_field(screen)
	assert_true(is_instance_valid(panel), "the keyboard opens")
	for c in "zzz":
		panel.type_char(c)
	panel.cancel()
	assert_eq(profiles.name_for(false, active), "Couch", "Cancel leaves the stored name")
	assert_eq(screen._pad_profile_name.text, "Couch", "and the field")
	assert_true(screen._keyboard_panel == null, "the keyboard is no longer open")
	GameManager.update_focus_guard_for_test()
	assert_eq(_focus_owner(), screen._pad_profile_name, "the highlight is back on the Rename field")
	GameManager.unregister_focus_scope(screen)
	_close(screen)
	_pad_end()

func test_nothing_behind_the_keyboard_hears_its_buttons() -> void:  # Review Focus 1
	_pad_begin()
	var reader := InputReader.new()
	GameManager.add_child(reader)   # before the screen: it hears only what the keyboard and the screen let by
	var screen := _open("controller")
	var backed_out := [0]
	screen.back_requested.connect(func() -> void: backed_out[0] += 1)
	var profiles := GameManager.input_profiles
	profiles.set_name(false, profiles.active_index(false), "Couch")
	screen._refresh_profile_name_field(false)

	var first := _press_confirm_on_the_field(screen)
	assert_true(is_instance_valid(first), "the keyboard opens")
	_pad(JOY_BUTTON_B)
	assert_eq(first.get_text(), "Couc", "B deletes a letter")
	assert_eq(screen._view, "controller", "and does not back the page out")
	_pad(JOY_BUTTON_START)
	assert_true(screen._keyboard_panel == null, "Start finishes it")
	assert_eq(profiles.name_for(false, profiles.active_index(false)), "Couc", "saving the name")

	var second := _press_confirm_on_the_field(screen)   # a fresh keyboard for each closing press
	assert_true(is_instance_valid(second), "it opens again")
	_pad(JOY_BUTTON_X)
	assert_true(screen._keyboard_panel == null, "X closes it")

	var third := _press_confirm_on_the_field(screen)
	assert_true(is_instance_valid(third), "and again")
	_key(KEY_ESCAPE)
	assert_true(screen._keyboard_panel == null, "Esc closes it")

	assert_eq(reader.heard.size(), 0, "nothing behind the keyboard heard Confirm, B, Start, X or Esc")
	assert_eq(screen._view, "controller", "the page is still the Controller page")
	assert_eq(backed_out[0], 0, "the screen never asked to close")
	assert_true(screen.is_inside_tree() and screen.visible, "and it is still open")
	_pad(JOY_BUTTON_RIGHT_SHOULDER)
	assert_eq(reader.heard.size(), 1, "once the keyboard is closed a button the page does not use reaches whatever is behind it")
	_close(screen)
	GameManager.remove_child(reader)
	reader.free()
	_pad_end()

func test_while_the_keyboard_is_open_the_page_takes_nothing_for_itself() -> void:
	# What the keyboard lets by (Confirm, the d-pad) is its keys' to use. A caret left in the
	# Rename field (a click with the stick cursor leaves one) must not make the page take a
	# Confirm for a second keyboard.
	_pad_begin()
	var reader := InputReader.new()
	GameManager.add_child(reader)
	var screen := _open("controller")
	var panel := _press_confirm_on_the_field(screen)
	assert_true(is_instance_valid(panel), "the keyboard opens")
	screen._pad_profile_name.grab_focus()
	_pad(JOY_BUTTON_A)
	assert_eq(reader.heard.size(), 1, "Confirm went by, for the highlighted key to press")
	assert_eq(_keyboards_under(screen).size(), 1, "and there is still only the one keyboard")
	assert_true(screen._keyboard_panel == panel, "the same one")
	_close(screen)
	GameManager.remove_child(reader)
	reader.free()
	_pad_end()

func test_a_rebuild_while_open_closes_the_keyboard() -> void:  # Review Focus 5
	_pad_begin()
	var screen := _open("controller")
	var panel := _press_confirm_on_the_field(screen)
	assert_true(is_instance_valid(panel), "the keyboard opens")
	var old: WeakRef = weakref(panel)
	assert_true(GameManager.has_focus_scope(panel), "it is a focus scope while open")
	screen._build()   # as Back or any change of view does (nothing rebuilds the page when a controller connects)
	assert_true(screen._keyboard_panel == null, "a rebuild closes the keyboard")
	assert_eq(_keyboards_under(screen).size(), 0, "and leaves none under the screen")
	var dead: Object = old.get_ref()   # still there until the end of the frame
	assert_false(dead != null and GameManager.has_focus_scope(dead as Control), "nor its focus scope")

	var fresh := _press_confirm_on_the_field(screen)
	assert_true(is_instance_valid(fresh), "the next Confirm on the field opens a new keyboard")
	assert_true(fresh != dead, "a different one")
	assert_eq(GameManager.focus_scope_count(fresh), 1, "with its own focus scope")
	_close(screen)
	_pad_end()

# ------------------------- the Rename field stays out of the keyboard's way (final review I1)
# The focus guard locks the page's buttons, sliders and dropdowns while the keyboard is the top
# scope, but it never touches a LineEdit, and Godot's neighbour search starts from the top
# Control and looks through the whole screen: with the Rename field above the keys, a d-pad
# push up from the number row put the highlight on the field behind the dim. Leaving it
# committed the field (a config.cfg write) and the guard then snapped the highlight back.

## A frame lays containers out on a deferred call and none runs inside a test, so sort
## them here, top-down, the way the engine would.
func _lay_out(node: Node) -> void:
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child in node.get_children():
		_lay_out(child)

func _config_bytes() -> PackedByteArray:
	return FileAccess.get_file_as_bytes(_CONFIG) if FileAccess.file_exists(_CONFIG) else PackedByteArray()

## The Controller page with its Rename field scrolled to the top of the scroll area, as it is
## when the player has come up to it from the bindings below (follow_focus puts the control
## being reached at the edge it came from).
func _controller_page_with_rename_on_top() -> SettingsScreen:
	var screen := _open("controller")
	GameManager.register_focus_scope(screen)   # as setup() does
	var scroll := screen.find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer
	_lay_out(screen)
	scroll.scroll_vertical = 100000   # all the way down, to the last binding
	_lay_out(screen)
	scroll.ensure_control_visible(screen._pad_profile_name)   # and back up to Rename
	_lay_out(screen)
	return screen

func test_the_highlight_cannot_leave_the_keyboard_for_the_rename_field_behind_it() -> void:  # final review I1
	_pad_begin()
	var profiles := GameManager.input_profiles
	var active := profiles.active_index(false)
	var screen := _controller_page_with_rename_on_top()
	var field := screen._pad_profile_name
	var panel := _press_confirm_on_the_field(screen)
	assert_true(is_instance_valid(panel), "the keyboard opens")
	_lay_out(screen)
	GameManager.update_focus_guard_for_test()
	assert_eq(_focus_owner(), panel.key_button("Q"), "the highlight is on Q")
	assert_true(field.get_global_rect().end.y < panel.key_button("1").get_global_rect().position.y,
		"the Rename field sits above the number row, in the way of a push up")
	assert_eq(field.focus_mode, Control.FOCUS_CLICK, "the field cannot take the highlight while the keyboard is open")

	# Anything that did reach the field would commit what it holds when the highlight left it,
	# so make that visible: a name that is not the stored one.
	var stored := profiles.name_for(false, active)
	field.text = "Leaked"
	var landed := [0]
	field.focus_entered.connect(func() -> void: landed[0] += 1)
	var bytes := _config_bytes()
	for id: String in ["5", "1", "0"]:
		panel.key_button(id).grab_focus()
		_pad(JOY_BUTTON_DPAD_UP)
		_pad(JOY_BUTTON_DPAD_UP, false)
		var held := _focus_owner()
		assert_true(held != null and held != field and panel.is_ancestor_of(held),
			"a d-pad push up from \"%s\" stays inside the keyboard" % id)
		GameManager.update_focus_guard_for_test()   # the next frame
		held = _focus_owner()
		assert_true(held != null and held != field and panel.is_ancestor_of(held),
			"and a frame later too")
	panel.key_button("5").grab_focus()
	_key(KEY_UP)
	_key(KEY_UP, false)
	assert_true(_focus_owner() != field and panel.is_ancestor_of(_focus_owner()), "so does the arrow key up")

	assert_eq(landed[0], 0, "the highlight never touched the field")
	assert_eq(profiles.name_for(false, active), stored, "so nothing committed to the profile")
	assert_true(_config_bytes() == bytes, "and config.cfg was not written")
	_close(screen)
	_pad_end()

# ----------------------- opening the keyboard saves nothing (triage item 13)
# Taking the highlight off a text box commits what it holds. Opening the keyboard moves the
# highlight off the Rename field, so a name typed into the field on a real keyboard and never
# committed was saved by the very press that opened the keyboard, which opened on the stale
# stored name; Cancel then left the typed text saved. The field is put back to the stored name
# first, so that commit has nothing to change.

func test_opening_the_keyboard_does_not_save_a_name_typed_into_the_field() -> void:  # triage item 13
	_pad_begin()
	var profiles := GameManager.input_profiles
	var active := profiles.active_index(false)
	profiles.set_name(false, active, "Couch")
	# A config.cfg holding none of the bindings: any save adds them, so its bytes say whether
	# anything saved.
	var probe := ConfigFile.new()
	probe.set_value("probe", "untouched", true)
	probe.save(_CONFIG)
	var bytes := _config_bytes()
	var screen := _open("controller")
	GameManager.register_focus_scope(screen)   # as setup() does
	var field := screen._pad_profile_name
	assert_eq(field.text, "Couch", "the field shows the stored name")
	field.text = "half"   # typed on a real keyboard, never committed (no Enter, no click away)

	var panel := _press_confirm_on_the_field(screen)
	assert_true(is_instance_valid(panel), "Confirm opens the keyboard")
	assert_eq(panel.get_text(), "Couch", "it opens on the stored name")
	GameManager.update_focus_guard_for_test()   # the highlight leaves the field for Q
	assert_eq(_focus_owner(), panel.key_button("Q"), "the highlight is on Q")
	panel.cancel()
	assert_eq(profiles.name_for(false, active), "Couch", "Cancel leaves the stored name as it was")
	assert_eq(field.text, "Couch", "and the field shows it, not the half-typed text")
	assert_true(_config_bytes() == bytes, "config.cfg was not written: opening and cancelling saves nothing")

	# Done with the name as it stood is no change either.
	var second := _press_confirm_on_the_field(screen)
	assert_true(is_instance_valid(second), "it opens again")
	GameManager.update_focus_guard_for_test()
	second.finish()
	assert_eq(profiles.name_for(false, active), "Couch", "Done on an unchanged name leaves it")
	assert_true(_config_bytes() == bytes, "and writes nothing")

	# A real change still saves.
	var third := _press_confirm_on_the_field(screen)
	assert_true(is_instance_valid(third), "and again")
	third.type_char("!")
	third.finish()
	assert_eq(profiles.name_for(false, active), "Couch!", "a changed name is stored")
	assert_true(_config_bytes() != bytes, "and saved")
	GameManager.unregister_focus_scope(screen)
	_close(screen)
	_pad_end()

# ------------------------- a trigger bound to Confirm opens the keyboard (final review M2)
# The pull that opens the keyboard keeps sending samples after the one that opened it, and the
# one that lets go. Reaching the highlighted key (a Button that acts on release), they typed
# its letter: a player who pulled to open the keyboard got a "q" they never chose.

## A stick or trigger sample into the root.
func _motion(axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	GameManager.get_viewport().push_input(ev)

func test_the_pull_of_a_trigger_bound_to_confirm_that_opens_the_keyboard_types_nothing() -> void:  # final review M2
	_pad_begin()
	var bound := InputEventJoypadMotion.new()
	bound.axis = JOY_AXIS_TRIGGER_RIGHT
	bound.axis_value = 1.0
	InputMapConfig.rebind_controller("confirm", bound)   # the trigger alone is Confirm now, and ui_accept
	var profiles := GameManager.input_profiles
	profiles.set_name(false, profiles.active_index(false), "Couch")
	var screen := _open("controller")
	GameManager.register_focus_scope(screen)   # as setup() does
	screen._pad_profile_name.grab_focus()
	_motion(JOY_AXIS_TRIGGER_RIGHT, 0.3)
	assert_true(screen._keyboard_panel == null, "a light touch opens nothing")
	_motion(JOY_AXIS_TRIGGER_RIGHT, 0.6)
	var panel := screen._keyboard_panel
	assert_true(is_instance_valid(panel), "the pull past the threshold opens the keyboard")
	GameManager.update_focus_guard_for_test()
	assert_eq(_focus_owner(), panel.key_button("Q"), "the highlight is on Q")
	_motion(JOY_AXIS_TRIGGER_RIGHT, 0.9)
	_motion(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_motion(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	assert_eq(panel.get_text(), "Couch", "the rest of that pull, and its release, typed nothing")
	assert_true(screen._keyboard_panel == panel, "and the keyboard is still the one open")

	# The next pull is the player's: it presses the highlighted key.
	_motion(JOY_AXIS_TRIGGER_RIGHT, 0.3)
	_motion(JOY_AXIS_TRIGGER_RIGHT, 0.7)
	_motion(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	assert_eq(panel.get_text(), "Couch", "a key acts on release")
	_motion(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	assert_eq(panel.get_text(), "Couchq", "a later pull presses the highlighted key, Q")
	GameManager.unregister_focus_scope(screen)
	_close(screen)
	_pad_end()
