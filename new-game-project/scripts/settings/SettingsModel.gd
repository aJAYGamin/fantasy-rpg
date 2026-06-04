class_name SettingsModel
extends RefCounted

## Player-facing settings (audio volumes, auto-save toggle, fullscreen).
## Pure data + (de)serialization + apply helpers so the values can be unit
## tested headlessly. GameManager owns the single live instance; SettingsScreen
## edits it and calls the targeted GameManager.apply_*_and_save() helpers.
##
## Volumes are stored linear in [0, 1] (slider-friendly) and converted to dB
## when pushed to the AudioServer buses.

const CONFIG_SECTION := "settings"

# Audio routes through three buses. Master is the engine default; Music and SFX
# are created as children of Master on first run (see ensure_buses).
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

# A linear volume at/below this is treated as fully silent (linear_to_db(0) is
# -inf, which the AudioServer dislikes — clamp to a deep floor instead).
const SILENCE_DB := -80.0
const MUTE_EPSILON := 0.0005

# Display ---------------------------------------------------------------------
enum WindowMode { FULLSCREEN, BORDERLESS, WINDOWED }

# Windowed resolutions offered in the dropdown (the game renders at a 1152x648
# base and scales via the canvas_items stretch mode, so any size works). Includes
# common 16:9 sizes plus the larger / HiDPI display modes.
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(1920, 1200),
	Vector2i(2336, 1460),
	Vector2i(2560, 1600),
	Vector2i(2624, 1640),
	Vector2i(2624, 1696),
	Vector2i(2992, 1870),
	Vector2i(2992, 1934),
	Vector2i(3456, 2160),
	Vector2i(3456, 2234),
]

# Framerate caps offered in the dropdown; 0 == uncapped (Engine.max_fps = 0).
const FPS_OPTIONS: Array[int] = [0, 30, 60, 120, 144]

# Difficulty -------------------------------------------------------------------
# Easy: enemy combat stats ×0.5. Normal: baseline. Hard: enemy stats ×2.0, plus
# +25% gold/XP, healing/battle item stacks capped (see HARD_ITEM_CAP in
# Inventory), and pricier shops (when shops exist).
enum Difficulty { EASY, NORMAL, HARD }

var volume_master: float = 1.0
var volume_music: float = 0.8
var volume_sfx: float = 0.9
var autosave_enabled: bool = true

var window_mode: int = WindowMode.FULLSCREEN
var window_size_index: int = 0          # index into RESOLUTIONS (windowed only)
var fps_cap: int = 0                     # 0 = uncapped
var vsync_enabled: bool = true
var show_fps: bool = false

var difficulty: int = Difficulty.NORMAL

# Analog stick sensitivity multipliers (controller). Left scales movement; right
# is reserved until a free/rotatable camera exists.
const SENS_MIN := 0.25
const SENS_MAX := 2.0
var stick_sensitivity_left: float = 1.0
var stick_sensitivity_right: float = 1.0

# --- Difficulty-derived modifiers --------------------------------------------
# Multiplier applied to every enemy combat stat at battle start.
func enemy_stat_mult() -> float:
	match difficulty:
		Difficulty.EASY: return 0.5
		Difficulty.HARD: return 2.0
		_: return 1.0

# Gold & XP reward multiplier (Hard gives a little more).
func reward_mult() -> float:
	return 1.25 if difficulty == Difficulty.HARD else 1.0

# Shop price multiplier — reserved for when shops exist (Hard makes them pricier).
func shop_price_mult() -> float:
	return 1.5 if difficulty == Difficulty.HARD else 1.0

# Whether healing/battle item stacks are capped (Hard only).
func hard_item_caps() -> bool:
	return difficulty == Difficulty.HARD

# Keep every value in its valid domain (called before apply/save).
func clamp_all() -> void:
	volume_master = clampf(volume_master, 0.0, 1.0)
	volume_music = clampf(volume_music, 0.0, 1.0)
	volume_sfx = clampf(volume_sfx, 0.0, 1.0)
	window_mode = clampi(window_mode, 0, WindowMode.size() - 1)
	window_size_index = clampi(window_size_index, 0, RESOLUTIONS.size() - 1)
	if not FPS_OPTIONS.has(fps_cap):
		fps_cap = 0
	difficulty = clampi(difficulty, 0, Difficulty.size() - 1)
	stick_sensitivity_left = clampf(stick_sensitivity_left, SENS_MIN, SENS_MAX)
	stick_sensitivity_right = clampf(stick_sensitivity_right, SENS_MIN, SENS_MAX)

func from_config(cfg: ConfigFile) -> void:
	volume_master = float(cfg.get_value(CONFIG_SECTION, "volume_master", volume_master))
	volume_music = float(cfg.get_value(CONFIG_SECTION, "volume_music", volume_music))
	volume_sfx = float(cfg.get_value(CONFIG_SECTION, "volume_sfx", volume_sfx))
	autosave_enabled = bool(cfg.get_value(CONFIG_SECTION, "autosave_enabled", autosave_enabled))
	window_mode = int(cfg.get_value(CONFIG_SECTION, "window_mode", window_mode))
	window_size_index = int(cfg.get_value(CONFIG_SECTION, "window_size_index", window_size_index))
	fps_cap = int(cfg.get_value(CONFIG_SECTION, "fps_cap", fps_cap))
	vsync_enabled = bool(cfg.get_value(CONFIG_SECTION, "vsync_enabled", vsync_enabled))
	show_fps = bool(cfg.get_value(CONFIG_SECTION, "show_fps", show_fps))
	difficulty = int(cfg.get_value(CONFIG_SECTION, "difficulty", difficulty))
	stick_sensitivity_left = float(cfg.get_value(CONFIG_SECTION, "stick_sensitivity_left", stick_sensitivity_left))
	stick_sensitivity_right = float(cfg.get_value(CONFIG_SECTION, "stick_sensitivity_right", stick_sensitivity_right))
	clamp_all()

func to_config(cfg: ConfigFile) -> void:
	cfg.set_value(CONFIG_SECTION, "volume_master", volume_master)
	cfg.set_value(CONFIG_SECTION, "volume_music", volume_music)
	cfg.set_value(CONFIG_SECTION, "volume_sfx", volume_sfx)
	cfg.set_value(CONFIG_SECTION, "autosave_enabled", autosave_enabled)
	cfg.set_value(CONFIG_SECTION, "window_mode", window_mode)
	cfg.set_value(CONFIG_SECTION, "window_size_index", window_size_index)
	cfg.set_value(CONFIG_SECTION, "fps_cap", fps_cap)
	cfg.set_value(CONFIG_SECTION, "vsync_enabled", vsync_enabled)
	cfg.set_value(CONFIG_SECTION, "show_fps", show_fps)
	cfg.set_value(CONFIG_SECTION, "difficulty", difficulty)
	cfg.set_value(CONFIG_SECTION, "stick_sensitivity_left", stick_sensitivity_left)
	cfg.set_value(CONFIG_SECTION, "stick_sensitivity_right", stick_sensitivity_right)

# Linear [0,1] -> dB, with a silent floor so 0 doesn't become -inf.
static func linear_volume_to_db(linear: float) -> float:
	if linear <= MUTE_EPSILON:
		return SILENCE_DB
	return linear_to_db(clampf(linear, 0.0, 1.0))

# Creates the Music and SFX buses (routed to Master) if they don't exist yet.
# Idempotent — safe to call every launch. Returns the SFX bus index.
static func ensure_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, BUS_MASTER)

func apply_audio() -> void:
	ensure_buses()
	_set_bus_volume(BUS_MASTER, volume_master)
	_set_bus_volume(BUS_MUSIC, volume_music)
	_set_bus_volume(BUS_SFX, volume_sfx)

func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_volume_to_db(linear))
	AudioServer.set_bus_mute(idx, linear <= MUTE_EPSILON)

func apply_display() -> void:
	# Only change what isn't already in effect. Re-issuing window_set_mode while the
	# window is already in that mode (esp. macOS native fullscreen) can crash, so we
	# guard every transition on the current state.
	var cur_mode := DisplayServer.window_get_mode()
	var is_fullscreen := cur_mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or cur_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	match window_mode:
		WindowMode.FULLSCREEN:
			if not is_fullscreen:
				DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WindowMode.BORDERLESS:
			# Borderless "fullscreen window": a windowed mode filling the screen
			# with no title bar.
			if is_fullscreen:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			var screen := DisplayServer.window_get_current_screen()
			DisplayServer.window_set_size(DisplayServer.screen_get_size(screen))
			DisplayServer.window_set_position(DisplayServer.screen_get_position(screen))
		WindowMode.WINDOWED:
			if is_fullscreen:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			var size: Vector2i = RESOLUTIONS[clampi(window_size_index, 0, RESOLUTIONS.size() - 1)]
			DisplayServer.window_set_size(size)
			_center_window(size)

func _center_window(size: Vector2i) -> void:
	var screen := DisplayServer.window_get_current_screen()
	var screen_size := DisplayServer.screen_get_size(screen)
	var screen_pos := DisplayServer.screen_get_position(screen)
	DisplayServer.window_set_position(screen_pos + (screen_size - size) / 2)

# Framerate cap + V-Sync (engine-level; the on-screen FPS counter is UI and
# lives in GameManager).
func apply_performance() -> void:
	Engine.max_fps = fps_cap
	var vmode := DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(vmode)
