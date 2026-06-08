## GameManager.gd — Autoload Singleton
## Add to Project > Project Settings > Autoload as "GameManager"
extends Node

signal gold_changed(new_amount: int)
signal party_updated
# Emitted when a controller connects/disconnects (for the Settings device status).
signal controllers_changed
# Emitted when the active input mode flips between controller and keyboard+mouse.
# Menus listen to this to enable/disable button focus (controller = focusable for
# d-pad/stick nav; keyboard+mouse = mouse-click only).
signal input_mode_changed(is_controller: bool)
# Auto-save lifecycle (P5) — the save-status indicator listens to these.
signal autosave_started
signal autosave_finished(success: bool)

# ─── Party ───────────────────────────────────────────────
var party: Array[Character] = []
const MAX_PARTY_SIZE = 4

# ─── Species Memory ─────────────────────────────────────
var species_memory: Dictionary = {}

# ─── Economy ─────────────────────────────────────────────
var gold: int = 100:
	set(value):
		gold = max(0, value)
		emit_signal("gold_changed", gold)

# ─── World State ─────────────────────────────────────────
var current_map: String = "world_map"
var completed_quests: Array[String] = []
var story_flags: Dictionary = {}   # e.g. {"met_elder": true, "darkwood_cleared": false}
var play_time_seconds: float = 0.0

# ─── Overworld ↔ Battle Handoff ──────────────────────────
# Set by overworld when an encounter triggers; consumed by BattleScene.
# pending_overworld_scene_path is also used by battle screens to know where to return.
# Enemies are pre-instantiated (deep-copied templates with level/HP/MP set) so
# BattleScene doesn't need to know about EncounterGroup or MapArea details.
var in_overworld_battle: bool = false
var pending_battle_enemies: Array[Enemy] = []
var pending_battle_background: String = "fallster_plains"
var pending_overworld_scene_path: String = ""
var pending_overworld_return_position: Vector2 = Vector2.ZERO

# ─── Save/Load ───────────────────────────────────────────
const SAVE_PATH = "user://savegame.json"  # legacy single-file save (still used by old Continue path)

# Phase S1: 3-slot save system.
# Slot files live at user://save_slot_{0,1,2}.json with full party serialization.
const SAVE_SLOT_COUNT: int = 3
const SAVE_VERSION: int = 1
const SAVE_PATH_FORMAT: String = "user://save_slot_%d.json"
const USER_CONFIG_PATH: String = "user://config.cfg"

# active_slot persists across game restarts via USER_CONFIG_PATH.
# Setter writes the config so Continue always knows which slot to resume.
var active_slot: int = -1:
	set(value):
		active_slot = value
		_save_user_config()

var save_overworld_scene_path: String = ""
var save_overworld_position: Vector2 = Vector2.ZERO
# Set true by the Continue/Load flow so OverworldScene._ready spawns at the
# saved position instead of the area's default_spawn.
var resuming_from_save: bool = false

# ─── Settings (audio / autosave / display / performance) ──
# Persisted in USER_CONFIG_PATH alongside the save slot. SettingsScreen edits
# this instance and calls the targeted apply_*_and_save() helpers below.
var settings := SettingsModel.new()
# Global on-screen FPS counter (toggled by settings.show_fps). Lives on its own
# high CanvasLayer under the autoload so it survives scene changes.
var _fps_layer: CanvasLayer = null
var _fps_label: Label = null

# Global UI click SFX. Auto-wired to every Button in the tree (see _on_node_added)
# so any button anywhere makes a sound, on the SFX bus.
const BUTTON_SFX_PATH: String = "res://music/GUI_Sound_Effects_by_Lokif/misc_menu_4.wav"
var _ui_sfx: AudioStreamPlayer = null

# Active input mode. true = controller (menus are focus-navigable); false =
# keyboard+mouse (menu buttons are mouse-only; keyboard is overworld actions).
var _controller_mode: bool = false

func _ready():
	# Run while the tree is paused so the focus guard keeps working in the pause menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_user_config()
	_load_settings()
	_load_input_config()
	_setup_ui_sfx()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	# Start in controller mode if a pad is already connected at launch.
	_controller_mode = not Input.get_connected_joypads().is_empty()

func _process(delta):
	play_time_seconds += delta
	if _fps_label != null and _fps_label.visible:
		_fps_label.text = "FPS %d" % Engine.get_frames_per_second()
	_update_focus_guard()

# ─── Centralized controller-focus guard ──────────────────
# The single source of truth for "what does the controller have focus on."
# Menus register a focus scope (a container Control) when they open and
# unregister when they close. Every frame (even while paused) this guard:
#   • in controller mode: makes the topmost visible scope's buttons focusable,
#     disables focus everywhere else (no background leak), and re-grabs focus if
#     it was lost (handles rebuilds, re-entry, the next hero's turn, etc.);
#   • in keyboard+mouse mode: releases focus so no ring shows (menus are click-only).
# Scope entries: { "ctrl": Control }. Buttons tagged BattleUITheme.NO_FOCUS_META
# (category tabs) are never focusable — they cycle with L1/R1.
var _focus_scopes: Array = []
var _focus_top_last: Control = null

func register_focus_scope(ctrl: Control) -> void:
	if ctrl == null:
		return
	# De-dupe + drop invalid, then push to the top (most recent wins).
	_prune_focus_scopes()
	_focus_scopes = _focus_scopes.filter(func(s): return s["ctrl"] != ctrl)
	_focus_scopes.append({"ctrl": ctrl})
	# In keyboard+mouse mode, immediately lock the new scope to click-only so its
	# buttons never become keyboard-navigable; in controller mode, force the guard
	# to re-evaluate the active scope next tick.
	if not _controller_mode:
		_set_scope_focusable(ctrl, false)
	else:
		_focus_top_last = null

func unregister_focus_scope(ctrl: Control) -> void:
	_focus_scopes = _focus_scopes.filter(func(s): return s["ctrl"] != ctrl and is_instance_valid(s["ctrl"]))

func _prune_focus_scopes() -> void:
	_focus_scopes = _focus_scopes.filter(func(s): return is_instance_valid(s["ctrl"]))

# --- Introspection / test hooks ----------------------------------------------
func has_focus_scope(ctrl: Control) -> bool:
	for s in _focus_scopes:
		if s["ctrl"] == ctrl:
			return true
	return false

func focus_scope_count(ctrl: Control) -> int:
	var n := 0
	for s in _focus_scopes:
		if s["ctrl"] == ctrl:
			n += 1
	return n

# Topmost registered scope that is currently visible in the tree (or null).
func top_focus_scope() -> Control:
	_prune_focus_scopes()
	for i in range(_focus_scopes.size() - 1, -1, -1):
		var c: Control = _focus_scopes[i]["ctrl"]
		if is_instance_valid(c) and c.is_visible_in_tree():
			return c
	return null

# Test hook: force the input mode without synthesizing an InputEvent.
func set_controller_mode_for_test(controller: bool) -> void:
	_set_controller_mode(controller)

# Test hook: run one guard tick synchronously.
func update_focus_guard_for_test() -> void:
	_update_focus_guard()

func _update_focus_guard() -> void:
	_prune_focus_scopes()
	var tree := get_tree()
	if tree == null:
		return
	var vp := tree.root.get_viewport()
	if vp == null:
		return

	if not _controller_mode:
		# Mouse/keyboard: menus are click-only. Lock every scope's controls to
		# FOCUS_NONE so the keyboard can't navigate/activate them, and release the
		# focus ring — but ONLY on the transition into mouse mode. Doing
		# release_focus() every frame cancels an in-progress button press (mouse
		# down then up on the next frame), so clicks like the settings Back button
		# silently fail. Once the controls are FOCUS_NONE they can't hold focus
		# anyway, so a one-time release is sufficient.
		if _focus_top_last != null:
			for s in _focus_scopes:
				var c: Control = s["ctrl"]
				if is_instance_valid(c):
					_set_scope_focusable(c, false)
			_focus_top_last = null
			var owner_mouse := vp.gui_get_focus_owner()
			if owner_mouse != null:
				owner_mouse.release_focus()
		return

	# Topmost VISIBLE registered scope wins (later registrations sit on top).
	var top: Control = null
	for i in range(_focus_scopes.size() - 1, -1, -1):
		var c: Control = _focus_scopes[i]["ctrl"]
		if is_instance_valid(c) and c.is_visible_in_tree():
			top = c
			break
	if top == null:
		return

	# Only the top scope is focusable; everything else is locked out so d-pad
	# navigation can't wander onto a background menu. Re-applying the focus_mode
	# tree-walk is only needed when the active scope changes (cheap per-frame
	# otherwise — just the grab check below). Guard against a freed _focus_top_last
	# (e.g. scene change) so the comparison always forces a refresh.
	if not is_instance_valid(_focus_top_last):
		_focus_top_last = null
	if top != _focus_top_last:
		for s in _focus_scopes:
			var c: Control = s["ctrl"]
			if is_instance_valid(c):
				_set_scope_focusable(c, c == top)
		_focus_top_last = top

	# Keep focus inside the top scope. Don't steal it mid-navigation: only grab
	# when nothing valid in the scope currently holds it.
	var owner := vp.gui_get_focus_owner()
	var ok := owner != null and is_instance_valid(owner) and top.is_ancestor_of(owner) \
		and owner.is_visible_in_tree() and owner.focus_mode != Control.FOCUS_NONE \
		and not (owner is BaseButton and (owner as BaseButton).disabled)
	if not ok:
		# Focus was lost — usually the scope rebuilt its content (new item list,
		# next hero's panel, target buttons). Re-apply focusability so the new
		# controls are grabbable, then grab the first.
		_set_scope_focusable(top, true)
		var first := _first_focusable(top)
		if first != null:
			first.grab_focus()

# Recursively set focus_mode on the interactive controls under `root`.
func _set_scope_focusable(root: Node, focusable: bool) -> void:
	for child in root.get_children():
		if child is BaseButton or child is Slider or child is OptionButton:
			var ctl := child as Control
			if ctl.has_meta(BattleUITheme.NO_FOCUS_META):
				ctl.focus_mode = Control.FOCUS_NONE
			else:
				ctl.focus_mode = Control.FOCUS_ALL if focusable else Control.FOCUS_NONE
		_set_scope_focusable(child, focusable)

# First focusable, enabled, visible control under `root`, preferring a non-Back
# button so opening a menu doesn't land on Back.
func _first_focusable(root: Node) -> Control:
	var candidates: Array = []
	_collect_focusable(root, candidates)
	if candidates.is_empty():
		return null
	for c in candidates:
		if not (c is BaseButton and String((c as BaseButton).text).begins_with("←")):
			return c
	return candidates[0]

func _collect_focusable(root: Node, out: Array) -> void:
	for child in root.get_children():
		if child is Control:
			var ctl := child as Control
			# Use is_visible_in_tree(): a button inside a hidden container is itself
			# still .visible==true, but must NOT be treated as focusable (else it
			# would steal the controller's A press, e.g. during the level-up spin).
			if ctl.is_visible_in_tree() and ctl.focus_mode != Control.FOCUS_NONE \
					and not (ctl is BaseButton and (ctl as BaseButton).disabled):
				out.append(ctl)
		_collect_focusable(child, out)

# ─── User Config (persists last-used slot) ───────────────
func _load_user_config():
	var cfg = ConfigFile.new()
	if cfg.load(USER_CONFIG_PATH) != OK:
		return
	# Use the backing var directly to avoid triggering setter -> save (cycle is safe but noisy).
	var saved_slot: int = int(cfg.get_value("save", "last_slot", -1))
	if saved_slot >= 0 and saved_slot < SAVE_SLOT_COUNT and FileAccess.file_exists(SAVE_PATH_FORMAT % saved_slot):
		active_slot = saved_slot
	else:
		active_slot = -1

func _save_user_config():
	var cfg = ConfigFile.new()
	# Re-load existing to preserve other future keys
	cfg.load(USER_CONFIG_PATH)
	cfg.set_value("save", "last_slot", active_slot)
	cfg.save(USER_CONFIG_PATH)

# ─── Settings ────────────────────────────────────────────
# Loads persisted settings (or defaults), creates the audio buses, and applies
# volumes, window mode, framerate, and the FPS overlay. Called once on launch.
func _load_settings():
	var cfg = ConfigFile.new()
	if cfg.load(USER_CONFIG_PATH) == OK:
		settings.from_config(cfg)
	SettingsModel.ensure_buses()
	settings.apply_audio()
	settings.apply_performance()
	_update_fps_overlay()
	# Apply the window mode a couple frames late: doing it during autoload _ready
	# is too early — the window isn't fully presented yet (esp. the macOS
	# fullscreen transition), so the saved mode would be ignored and the game
	# always booted fullscreen. Deferring makes the saved display mode stick.
	_apply_display_deferred()

func _apply_display_deferred() -> void:
	# Let the window finish presenting before changing its mode. A short delay is
	# more reliable than a frame or two, especially for the macOS fullscreen
	# transition, which otherwise swallows the mode change and boots fullscreen.
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
	settings.apply_display()

# Persists the [settings] section, merge-preserving the [save] section.
func _write_settings_config() -> void:
	var cfg = ConfigFile.new()
	cfg.load(USER_CONFIG_PATH)
	settings.to_config(cfg)
	cfg.save(USER_CONFIG_PATH)

# Targeted apply+save helpers so changing one group of settings doesn't trigger
# unrelated side effects (e.g. tweaking volume must NOT re-apply the window mode,
# which visibly flickers the window). SettingsScreen calls the matching one.
func apply_audio_and_save() -> void:
	settings.clamp_all()
	settings.apply_audio()
	_write_settings_config()

func apply_display_and_save() -> void:
	settings.clamp_all()
	settings.apply_display()
	_write_settings_config()

func apply_performance_and_save() -> void:
	settings.clamp_all()
	settings.apply_performance()
	_write_settings_config()

func apply_fps_overlay_and_save() -> void:
	settings.clamp_all()
	_update_fps_overlay()
	_write_settings_config()

# For settings with no engine side effect (e.g. the auto-save toggle).
func save_settings() -> void:
	settings.clamp_all()
	_write_settings_config()

# ─── On-screen FPS counter ───────────────────────────────
func _ensure_fps_overlay():
	if _fps_layer != null and is_instance_valid(_fps_layer):
		return
	_fps_layer = CanvasLayer.new()
	_fps_layer.layer = 128
	add_child(_fps_layer)
	_fps_label = Label.new()
	_fps_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_fps_label.offset_left = 12
	_fps_label.offset_right = -12
	_fps_label.offset_top = 6
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := BattleUITheme.font_bold()
	if f: _fps_label.add_theme_font_override("font", f)
	_fps_label.add_theme_font_size_override("font_size", 14)
	_fps_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
	_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_fps_label.add_theme_constant_override("outline_size", 4)
	_fps_layer.add_child(_fps_label)

func _update_fps_overlay():
	_ensure_fps_overlay()
	_fps_label.visible = settings.show_fps

# ─── Input remapping ─────────────────────────────────────
func _load_input_config() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(USER_CONFIG_PATH) == OK:
		InputMapConfig.apply(InputMapConfig.load_custom(cfg))
	else:
		InputMapConfig.apply({})

# Writes the current InputMap bindings to config (merge-preserving other sections).
func save_input_config() -> void:
	var cfg = ConfigFile.new()
	cfg.load(USER_CONFIG_PATH)
	InputMapConfig.save_to_config(cfg)
	cfg.save(USER_CONFIG_PATH)

func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	controllers_changed.emit()

# Human-readable summary of connected controllers for the Settings screen.
func connected_controllers_text() -> String:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return "No Controller Found"
	var names: Array[String] = []
	for id in pads:
		var nm := Input.get_joy_name(id)
		names.append(nm if nm != "" else "Controller %d" % id)
	return ", ".join(names)

# ─── Live keyboard / mouse activity ──────────────────────
# Godot can't enumerate keyboards/mice or tell external from built-in, so we
# report live activity instead: "detected" while input is flowing, otherwise the
# "no external … found" default.
const _INPUT_ACTIVE_MS := 2500
var _last_kb_ms: int = -100000
var _last_mouse_ms: int = -100000

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		_last_kb_ms = Time.get_ticks_msec()
		_set_controller_mode(false)
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		_last_mouse_ms = Time.get_ticks_msec()
		_set_controller_mode(false)
	elif event is InputEventJoypadButton and event.pressed:
		_set_controller_mode(true)
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		_set_controller_mode(true)

# --- Input mode (controller vs keyboard+mouse) ---------------------------------
func is_controller_mode() -> bool:
	return _controller_mode

func _set_controller_mode(controller: bool) -> void:
	if _controller_mode == controller:
		return
	_controller_mode = controller
	input_mode_changed.emit(controller)

func keyboard_status_text() -> String:
	return "Keyboard detected" if (Time.get_ticks_msec() - _last_kb_ms) < _INPUT_ACTIVE_MS else "No external keyboard found"

func mouse_status_text() -> String:
	return "Mouse detected" if (Time.get_ticks_msec() - _last_mouse_ms) < _INPUT_ACTIVE_MS else "No external mouse found"

# ─── Global UI button SFX ────────────────────────────────
# One SFX player on the SFX bus, auto-connected to every Button added to the
# tree so any button click anywhere plays the menu sound — no per-button wiring.
func _setup_ui_sfx() -> void:
	_ui_sfx = AudioStreamPlayer.new()
	_ui_sfx.bus = SettingsModel.BUS_SFX
	_ui_sfx.max_polyphony = 4
	# Must play even while the SceneTree is paused — otherwise pause-menu buttons
	# (and its sub-screens) would be silent because a pausable player is frozen.
	_ui_sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists(BUTTON_SFX_PATH):
		_ui_sfx.stream = load(BUTTON_SFX_PATH)
	add_child(_ui_sfx)
	# Wire buttons added from now on, plus any already present.
	get_tree().node_added.connect(_on_node_added)
	_wire_buttons_under(get_tree().root)

func _wire_buttons_under(node: Node) -> void:
	if node is BaseButton:
		_wire_button(node)
	for child in node.get_children():
		_wire_buttons_under(child)

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_wire_button(node)

func _wire_button(b: BaseButton) -> void:
	if not b.pressed.is_connected(_play_ui_sfx):
		b.pressed.connect(_play_ui_sfx)
	# Hover SFX too, matching the main-menu feel — for every button everywhere.
	if not b.mouse_entered.is_connected(_play_ui_sfx):
		b.mouse_entered.connect(_play_ui_sfx)

func _play_ui_sfx() -> void:
	if _ui_sfx != null and _ui_sfx.stream != null:
		_ui_sfx.play()

# ─── Party Management ────────────────────────────────────
func ensure_default_party():
	if party.is_empty():
		for hero in PartyFactory.create_default_party():
			party.append(hero)

# Resets per-playthrough state and binds the given slot as active.
# Called from the New Game flow before transitioning to the overworld.
func start_new_game(slot: int):
	party = [] as Array[Character]
	gold = 100
	species_memory = {}
	completed_quests = [] as Array[String]
	story_flags = {}
	play_time_seconds = 0.0
	save_overworld_scene_path = ""
	save_overworld_position = Vector2.ZERO
	resuming_from_save = false
	in_overworld_battle = false
	pending_battle_enemies = [] as Array[Enemy]
	active_slot = slot  # setter persists last_slot to config
	ensure_default_party()

func add_to_party(character: Character) -> bool:
	if party.size() >= MAX_PARTY_SIZE:
		print("Party is full!")
		return false
	party.append(character)
	emit_signal("party_updated")
	return true

func remove_from_party(character: Character):
	party.erase(character)
	emit_signal("party_updated")

func get_party_leader() -> Character:
	return party[0] if not party.is_empty() else null

func is_party_alive() -> bool:
	return party.any(func(c): return c.is_alive())

func revive_party():
	for c in party:
		if not c.is_alive():
			c.current_hp = int(c.max_hp() * 0.5)

# ─── Gold ────────────────────────────────────────────────
func earn_gold(amount: int):
	gold += amount
	print("Earned %d gold. Total: %d" % [amount, gold])

func spend_gold(amount: int) -> bool:
	if gold >= amount:
		gold -= amount
		return true
	print("Not enough gold!")
	return false

# ─── Quest & Flags ───────────────────────────────────────
func complete_quest(quest_id: String):
	if not quest_id in completed_quests:
		completed_quests.append(quest_id)

func is_quest_done(quest_id: String) -> bool:
	return quest_id in completed_quests

func set_flag(flag: String, value = true):
	story_flags[flag] = value

func get_flag(flag: String, default = false):
	return story_flags.get(flag, default)

# ─── Award battle rewards to party ───────────────────────
# Note: EXP is intentionally NOT applied here. VictoryScreen owns the EXP+level-up
# animation/UX and calls Character.gain_experience() itself. Applying it here too
# would double-count the EXP and silently level heroes past the LevelUpScreen.
func award_rewards(rewards: Dictionary):
	if rewards.has("gold"):
		earn_gold(rewards["gold"])

	if rewards.has("items"):
		for item in rewards["items"]:
			if not party.is_empty():
				party[0].inventory.add_item(item)

	if rewards.has("equipment"):
		for eq in rewards["equipment"]:
			if not party.is_empty():
				party[0].inventory.add_equipment(eq)

# ─── Save System ─────────────────────────────────────────
func save_game():
	var save_data = {
		"gold": gold,
		"current_map": current_map,
		"completed_quests": completed_quests,
		"story_flags": story_flags,
		"play_time": play_time_seconds,
		"species_memory": species_memory,
		"party": []
	}
	for c in party:
		save_data["party"].append({
			"name": c.character_name,
			"level": c.level,
			"exp": c.experience,
			"current_hp": c.current_hp,
			"current_mp": c.current_mp
		})

	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	print("Game saved!")

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()

	if err != OK:
		push_error("Failed to parse save file.")
		return false

	var data = json.data
	gold = data.get("gold", 100)
	current_map = data.get("current_map", "world_map")
	completed_quests = data.get("completed_quests", [])
	story_flags = data.get("story_flags", {})
	species_memory = data.get("species_memory", {})
	play_time_seconds = data.get("play_time", 0.0)
	print("Game loaded!")
	return true

func delete_save():
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

# ─── Slot Save System (Phase S1) ─────────────────────────
func _slot_path(slot: int) -> String:
	return SAVE_PATH_FORMAT % slot

func _is_valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < SAVE_SLOT_COUNT

func slot_exists(slot: int) -> bool:
	if not _is_valid_slot(slot):
		return false
	return FileAccess.file_exists(_slot_path(slot))

# Builds the full save payload for the current GameManager state.
# Separated from save_to_slot so tests/UI previews can introspect without writing.
func _build_save_dict() -> Dictionary:
	var max_lv: int = 1
	var heroes_meta: Array = []
	for c in party:
		if c.level > max_lv:
			max_lv = c.level
		heroes_meta.append({
			"name": c.character_name,
			"class": c.character_class,
			"level": c.level,
		})
	var area_name: String = ""
	if save_overworld_scene_path != "":
		area_name = save_overworld_scene_path.get_file().get_basename()
	return {
		"version": SAVE_VERSION,
		"timestamp": Time.get_datetime_string_from_system(),
		"metadata": {
			"playtime_seconds": play_time_seconds,
			"max_party_level": max_lv,
			"party_size": party.size(),
			"area_name": area_name,
			"heroes": heroes_meta,
		},
		"gold": gold,
		"party": SaveSerializer.serialize_party(party),
		"species_memory": species_memory,
		"completed_quests": completed_quests,
		"story_flags": story_flags,
		"current_map": current_map,
		"overworld_scene_path": save_overworld_scene_path,
		"overworld_position": {
			"x": save_overworld_position.x,
			"y": save_overworld_position.y,
		},
	}

func save_to_slot(slot: int) -> bool:
	if not _is_valid_slot(slot):
		push_error("Invalid save slot: %d" % slot)
		return false
	var data = _build_save_dict()
	var file = FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("Failed to open save slot %d for write" % slot)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	active_slot = slot
	print("Game saved to slot %d." % slot)
	return true

# ─── Auto-save (P5) ──────────────────────────────────────
# True if auto-save is allowed to run right now: enabled in settings AND there's
# a bound save slot (a New Game / loaded game). A fresh boot with no slot won't
# auto-save (nothing to overwrite).
func can_autosave() -> bool:
	return settings.autosave_enabled and _is_valid_slot(active_slot)

# Auto-saves the current overworld position to the active slot. The caller passes
# its scene path + the player's world position (same as a manual pause-menu save).
# Emits autosave_started / autosave_finished(success) for the status indicator.
# No-ops (and emits nothing) when auto-save isn't allowed.
func autosave(scene_path: String, position: Vector2) -> bool:
	if not can_autosave():
		return false
	autosave_started.emit()
	save_overworld_scene_path = scene_path
	save_overworld_position = position
	var ok := save_to_slot(active_slot)
	autosave_finished.emit(ok)
	return ok

func load_from_slot(slot: int) -> bool:
	if not slot_exists(slot):
		return false
	var file = FileAccess.open(_slot_path(slot), FileAccess.READ)
	if file == null:
		return false
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("Failed to parse save slot %d" % slot)
		return false
	var data = json.data
	gold = int(data.get("gold", 100))
	species_memory = data.get("species_memory", {})
	# JSON.parse returns untyped Array, so quests must be re-typed before assignment.
	var typed_quests: Array[String] = []
	for q in data.get("completed_quests", []):
		typed_quests.append(str(q))
	completed_quests = typed_quests
	story_flags = data.get("story_flags", {})
	current_map = data.get("current_map", "world_map")
	play_time_seconds = float(data.get("metadata", {}).get("playtime_seconds", 0.0))
	save_overworld_scene_path = data.get("overworld_scene_path", "")
	var pos_data = data.get("overworld_position", {"x": 0, "y": 0})
	save_overworld_position = Vector2(float(pos_data.get("x", 0)), float(pos_data.get("y", 0)))
	party = SaveSerializer.deserialize_party(data.get("party", []))
	active_slot = slot
	emit_signal("party_updated")
	emit_signal("gold_changed", gold)
	print("Game loaded from slot %d." % slot)
	return true

# True when the active slot holds a loadable save (used by the defeat→load flow
# to decide whether "Load Last Save" is available).
func has_active_save() -> bool:
	return slot_exists(active_slot)

# Loads the active slot and prepares a return to the saved overworld. Returns the
# scene path to change to (the saved overworld scene, or a sensible default), or
# "" if there's nothing to load. Mirrors the MainMenu Continue flow so the defeat
# screen reuses the canonical load path.
func load_active_slot() -> String:
	if not has_active_save():
		return ""
	if not load_from_slot(active_slot):
		return ""
	resuming_from_save = true
	var path: String = save_overworld_scene_path
	if path == "":
		path = "res://scenes/OverworldScene.tscn"
	return path

# Reads just the metadata block (cheap — no party deserialization) for slot pickers.
# Returns {} if the slot is empty/invalid/unparseable.
func get_slot_metadata(slot: int) -> Dictionary:
	if not slot_exists(slot):
		return {}
	var file = FileAccess.open(_slot_path(slot), FileAccess.READ)
	if file == null:
		return {}
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		return {}
	var data = json.data
	var meta: Dictionary = data.get("metadata", {}).duplicate()
	meta["timestamp"] = data.get("timestamp", "")
	return meta

func delete_slot(slot: int) -> bool:
	if not slot_exists(slot):
		return false
	DirAccess.remove_absolute(_slot_path(slot))
	if active_slot == slot:
		active_slot = -1
	return true

# Copies an existing slot's file to another slot index. Overwrites destination.
func copy_slot(from_slot: int, to_slot: int) -> bool:
	if from_slot == to_slot:
		return false
	if not _is_valid_slot(from_slot) or not _is_valid_slot(to_slot):
		return false
	if not slot_exists(from_slot):
		return false
	var src = FileAccess.open(_slot_path(from_slot), FileAccess.READ)
	if src == null:
		return false
	var bytes = src.get_buffer(src.get_length())
	src.close()
	var dst = FileAccess.open(_slot_path(to_slot), FileAccess.WRITE)
	if dst == null:
		return false
	dst.store_buffer(bytes)
	dst.close()
	return true

func get_formatted_playtime() -> String:
	var hours = int(play_time_seconds / 3600)
	var minutes = int(fmod(play_time_seconds, 3600) / 60)
	var seconds = int(fmod(play_time_seconds, 60))
	return "%02d:%02d:%02d" % [hours, minutes, seconds]

func get_species_memory(species: String) -> int:
	return species_memory.get(species, 0)
 
func record_battle_against(species: String):
	if not species_memory.has(species):
		species_memory[species] = 0
	species_memory[species] += 1
	print("Memory Echo: %s has been fought %d times" % [species, species_memory[species]])
 
func get_memory_level_description(species: String) -> String:
	var count = get_species_memory(species)
	if count < 3:
		return ""
	elif count < 7:
		return "%s senses something familiar..." % species
	elif count < 15:
		return "%s has learned from past encounters!" % species
	else:
		return "%s has fully adapted to your tactics!" % species
