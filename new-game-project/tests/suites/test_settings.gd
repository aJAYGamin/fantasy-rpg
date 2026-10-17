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
	var icon := shape._icon.texture as AtlasTexture
	assert_true(icon != null and icon.atlas == CursorArt.texture("K", "garnet"),
			"of the saved shape in the saved colour")
	var dot := colour._dot.get_theme_stylebox("panel") as StyleBoxFlat
	assert_true(colour._dot.visible, "the colour row shows a dot")
	assert_eq(dot.bg_color, CursorArt.swatch("garnet"), "in the saved colour")

	colour.step(1)
	assert_eq(dot.bg_color, CursorArt.swatch("ember"), "stepping the colour recolours the dot")
	assert_true((shape._icon.texture as AtlasTexture).atlas == CursorArt.texture("K", "ember"),
			"and re-tints the shape row's icon")
	shape.step(1)
	assert_true((shape._icon.texture as AtlasTexture).atlas == CursorArt.texture("L", "ember"),
			"stepping the shape swaps the icon, in the same colour")
	_close(screen)
	_restore()

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
