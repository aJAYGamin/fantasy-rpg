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
