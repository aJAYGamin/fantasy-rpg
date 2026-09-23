## GameManager.gd — Autoload Singleton
## Add to Project > Project Settings > Autoload as "GameManager"
extends Node

signal gold_changed(new_amount: int)
signal party_updated
# Emitted when a quest is accepted from a giver, and when one is turned in (rewarded).
signal quest_accepted(quest: Quest)
signal quest_completed(quest: Quest)
# Fires on ANY quest-state change (accept / turn-in / select active / story change)
# so NPCs can refresh their waypoint markers.
signal quests_changed
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
# In-world clock (time of day). Advances during overworld exploration; paused in
# battles, menus, and dialogue/cutscenes (see _process gating). Persisted in saves.
var clock := TimeOfDay.new()
var _time_in_overworld: bool = false
var _clock_overlay: CanvasLayer = null
# Quest state: live ACTIVE quest instances + COMPLETED ids (see QuestLog).
var quest_log := QuestLog.new()
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
# P7 roaming enemies: the id of the overworld roamer that started this battle, and
# whether the player won. On return, the overworld removes a defeated roamer (won)
# or leaves it (fled/lost). -1 = battle wasn't started by a roamer.
var pending_roamer_id: int = -1
var last_battle_won: bool = false
# Set true when the player FLEES a battle, so the overworld grants a few seconds of
# i-frames on return (no roamer can pull them into another fight immediately).
var pending_flee_iframes: bool = false

# ─── Map-to-Map Transitions (P7p2) ───────────────────────
# Set by a MapTransition zone right before change_scene_to_file; the destination
# OverworldScene consumes them in _ready (spawn at the target + fade back in).
# Transient — both are cleared the instant the destination reads them.
var pending_transition_active: bool = false
var pending_transition_spawn: Vector2 = Vector2.ZERO
var pending_fade_in: bool = false   # destination should start black and fade in
# Where the player last entered a transition from. A "return_to_origin" zone (e.g. a
# shared town-interior exit) sends them back here, so one interior can serve several
# towns and drop the player back at the right one.
var transition_origin_scene: String = ""
var transition_origin_pos: Vector2 = Vector2.ZERO

# Persistent roamer state for the CURRENT region, so roamers survive the battle
# scene reload. A region is identified by its overworld scene path. On battle
# return we restore the survivors (minus the defeated one); moving to a DIFFERENT
# region clears this so the original region repopulates fresh on the next visit.
# Each entry: { "id": int, "group_index": int, "position": Vector2, "home": Rect2 }
var roamer_region: String = ""
var roamers_initialized: bool = false
var roamer_states: Array = []

# True if we have live roamer state for `region` to restore (same region, already
# populated). A different/empty region means "spawn fresh".
func has_roamer_state_for(region: String) -> bool:
	return roamers_initialized and roamer_region == region

# Replaces the saved roamer state for a region (called when the overworld spawns
# fresh or persists its current roamers before a battle/scene change).
func set_roamer_state(region: String, states: Array) -> void:
	roamer_region = region
	roamer_states = states
	roamers_initialized = true

# Removes a defeated roamer (by id) from the saved state so it doesn't come back
# when we restore on battle return.
func remove_roamer_state(id: int) -> void:
	roamer_states = roamer_states.filter(func(s): return int(s.get("id", -1)) != id)

# Clears roamer state (e.g. on a brand-new game) so the next region spawns fresh.
func clear_roamer_state() -> void:
	roamer_region = ""
	roamers_initialized = false
	roamer_states = []

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

# Active input mode flags. Focus-based menu navigation (a moving highlight driven
# by the ui_up/down/left/right + ui_accept actions) is on for BOTH controller AND
# keyboard; only pure-mouse usage turns it off so menus go click-only with no ring.
# `_controller_mode` stays true only for an actual gamepad (it drives the Settings
# device status); for "should menus be arrow/d-pad navigable" use focus_nav_active().
var _controller_mode: bool = false
var _keyboard_nav: bool = false

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
	_create_clock_overlay.call_deferred()

func _create_clock_overlay() -> void:
	if _clock_overlay != null and is_instance_valid(_clock_overlay):
		return
	# load() (not preload) + deferred so ClockOverlay compiles after this script is
	# fully settled, not re-entrantly during _ready (the dialogue-box trap).
	var clock_script: GDScript = load("res://scripts/ui/ClockOverlay.gd")
	_clock_overlay = clock_script.new()
	add_child(_clock_overlay)

func _process(delta):
	play_time_seconds += delta
	# Advance the in-world clock only while exploring — paused in battle, in any menu
	# (the tree is paused), and during dialogue/cutscenes.
	if _time_in_overworld and not get_tree().paused and not DialogueManager.is_active():
		clock.advance_real(delta)
	if _fps_label != null and _fps_label.visible:
		_fps_label.text = "FPS %d" % Engine.get_frames_per_second()
	_update_focus_guard()
	_update_nav_repeat(delta)

# Called by overworld/interior scenes (true on enter, false on exit) so the clock +
# its overlay only run there, not in battle or the main menu.
func set_time_overworld(active: bool) -> void:
	_time_in_overworld = active

func time_clock_visible() -> bool:
	# Hidden in battle / main menu (not in the overworld) and while the game is
	# paused (a menu is open).
	return _time_in_overworld and not get_tree().paused

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
## Scope Control -> the control the guard should grab the NEXT time it re-grabs
## focus in that scope, instead of the first one. A menu sets this before opening
## a sub-view so that coming back lands on the entry the player left from rather
## than jumping to the top of the list. One-shot: consumed on use, so ordinary
## rebuilds inside the scope don't keep yanking focus backwards.
var _preferred_focus: Dictionary = {}

## Remember where focus should return to in `scope` (see _preferred_focus).
func set_preferred_focus(scope: Control, ctrl: Control) -> void:
	if scope == null or ctrl == null:
		return
	_preferred_focus[scope] = ctrl

func clear_preferred_focus(scope: Control) -> void:
	_preferred_focus.erase(scope)

func has_preferred_focus(scope: Control) -> bool:
	return _preferred_focus.has(scope)

## Consume the remembered control for `scope`, or null if there isn't a usable
## one. Validated here so a freed or now-disabled entry falls back cleanly.
func _take_preferred_focus(scope: Control) -> Control:
	if not _preferred_focus.has(scope):
		return null
	var ctrl: Control = _preferred_focus[scope]
	_preferred_focus.erase(scope)
	if not is_instance_valid(ctrl) or not ctrl.is_visible_in_tree():
		return null
	if ctrl.focus_mode == Control.FOCUS_NONE:
		return null
	if ctrl is BaseButton and (ctrl as BaseButton).disabled:
		return null
	return ctrl

func register_focus_scope(ctrl: Control) -> void:
	if ctrl == null:
		return
	# De-dupe + drop invalid, then push to the top (most recent wins).
	_prune_focus_scopes()
	_focus_scopes = _focus_scopes.filter(func(s): return s["ctrl"] != ctrl)
	_focus_scopes.append({"ctrl": ctrl})
	# In mouse mode, immediately lock the new scope to click-only (no focus ring);
	# in keyboard/controller mode, force the guard to re-evaluate the active scope
	# next tick so the new scope's buttons become navigable.
	if not focus_nav_active():
		_set_scope_focusable(ctrl, false)
	else:
		_focus_top_last = null

func unregister_focus_scope(ctrl: Control) -> void:
	_focus_scopes = _focus_scopes.filter(func(s): return s["ctrl"] != ctrl and is_instance_valid(s["ctrl"]))
	_preferred_focus.erase(ctrl)
	# Drop entries whose scope or target died with the closing menu.
	for key in _preferred_focus.keys():
		if not is_instance_valid(key) or not is_instance_valid(_preferred_focus[key]):
			_preferred_focus.erase(key)

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

# Test hook: force keyboard-navigation mode (focus nav on, gamepad bit off).
func set_keyboard_nav_for_test(on: bool) -> void:
	_apply_input_mode(false, on)

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

	if not focus_nav_active():
		# Pure mouse: menus are click-only. Lock every scope's controls to
		# FOCUS_NONE so no focus ring shows, and release the focus owner — but ONLY
		# on the transition into mouse mode. Doing release_focus() every frame
		# cancels an in-progress button press (mouse down then up on the next
		# frame), so clicks like the settings Back button silently fail. Once the
		# controls are FOCUS_NONE they can't hold focus anyway, so a one-time
		# release is sufficient.
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
	else:
		# Refresh the TOP scope every frame even when it hasn't changed. Menus
		# rebuild their contents constantly (item tabs, the next hero's page, the
		# skill grid after a reorder) and those fresh controls are born FOCUS_ALL,
		# so a walk that only ran on scope change left them inconsistent — the "?"
		# buttons were reachable in whichever tab happened to be built last and
		# nowhere else. Buttons also enable/disable at runtime. Control's setter
		# early-returns when the mode is unchanged, so this costs almost nothing.
		_set_scope_focusable(top, true)
	# Recomputed every frame off the same fresh state: a rebuilt list has new
	# controls at new positions, so yesterday's edges are not today's.
	_wire_focus_wrap(top)

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
		# A scope that just came back from a sub-view names where focus belongs;
		# everything else starts at the first entry.
		var want := _take_preferred_focus(top)
		if want == null:
			want = _first_focusable(top)
		if want != null:
			want.grab_focus()

# ─── Held-direction auto-repeat ──────────────────────────
# Godot moves focus once per press and then stops: holding the d-pad or an arrow
# key does nothing more, so getting down a long list means tapping once per row.
# This repeats the move while the direction is held, accelerating after a few
# seconds (see HoldRepeat). It drives focus directly through the neighbor search
# rather than synthesizing input events, so it obeys exactly the same skip rules
# as a real press — including stepping over disabled and no-focus controls.
#
# Keyboard and controller both get this: `ui_up`/`ui_down`/`ui_left`/`ui_right`
# are bound for both devices, and the repeat only runs while focus navigation is
# active, so it never fires during pure mouse play.
const _NAV_SIDES := {
	"ui_up": SIDE_TOP,
	"ui_down": SIDE_BOTTOM,
	"ui_left": SIDE_LEFT,
	"ui_right": SIDE_RIGHT,
}
var _nav_repeats: Dictionary = {}

func _update_nav_repeat(delta: float) -> void:
	if not focus_nav_active():
		for r in _nav_repeats.values():
			r.reset()
		return
	var tree := get_tree()
	if tree == null:
		return
	var vp := tree.root.get_viewport()
	if vp == null:
		return

	for action in _NAV_SIDES:
		if not _nav_repeats.has(action):
			_nav_repeats[action] = HoldRepeat.new()
		var rep: HoldRepeat = _nav_repeats[action]
		var pressed := InputMap.has_action(action) and Input.is_action_pressed(action)
		if not rep.poll(pressed, delta):
			continue
		# Only steer focus that is already inside the active scope; the guard owns
		# everything else, and stealing focus from outside it would let a held
		# direction wander into a background menu.
		var owner := vp.gui_get_focus_owner()
		if owner == null or not is_instance_valid(owner):
			continue
		var top := top_focus_scope()
		if top == null or not top.is_ancestor_of(owner):
			continue
		var next := owner.find_valid_focus_neighbor(_NAV_SIDES[action])
		if next != null and next != owner:
			next.grab_focus()

## Test hook: run one auto-repeat tick synchronously.
func update_nav_repeat_for_test(delta: float) -> void:
	_update_nav_repeat(delta)

# ─── Wrap-around menu navigation ─────────────────────────
# Godot's focus search is purely geometric and stops dead at the edge of a menu,
# so the last entry had nowhere to go — you could not get from "Quit to Main
# Menu" back round to "Resume" without walking all the way up.
#
# Rather than intercepting the navigation keys (which would have to duplicate
# Godot's own edge cases), this wires an explicit `focus_neighbor_*` ONLY onto
# the controls that have no geometric neighbour on that side. Everything in the
# middle keeps the normal search, so 2-column grids and side-by-side rows still
# navigate naturally — and because Godot's own navigation and this file's
# auto-repeat both go through find_valid_focus_neighbor, they wrap identically.
#
# The links we add are recorded in meta so they can be cleared before each
# recompute: a stale link would otherwise make the "has no neighbour" test lie,
# and hand-authored neighbours from a .tscn are never touched.
const _WRAP_META := "focus_wrap_sides"
const _WRAP_SIDES := [SIDE_TOP, SIDE_BOTTOM, SIDE_LEFT, SIDE_RIGHT]

func _wire_focus_wrap(scope: Control) -> void:
	var items: Array = []
	_collect_focusable(scope, items)

	# Clear the links we added last time, so the geometric test below is honest.
	for c in items:
		if c.has_meta(_WRAP_META):
			for side in c.get_meta(_WRAP_META):
				c.set_focus_neighbor(side, NodePath())
			c.remove_meta(_WRAP_META)
	if items.size() < 2:
		return

	for side in _WRAP_SIDES:
		for c in items:
			if c.find_valid_focus_neighbor(side) != null:
				continue  # not an edge on this side — leave it alone
			var target := _wrap_target(items, c, side)
			if target == null or target == c:
				continue
			c.set_focus_neighbor(side, c.get_path_to(target))
			var sides: Array = c.get_meta(_WRAP_META) if c.has_meta(_WRAP_META) else []
			sides.append(side)
			c.set_meta(_WRAP_META, sides)

## The control to jump to when `from` runs off the `side` edge: the far end of
## the menu in that direction. Ties are broken by staying closest on the other
## axis, so wrapping down the left column of a grid lands back at its top rather
## than skipping across to the other column.
func _wrap_target(items: Array, from: Control, side: int) -> Control:
	var from_rect := from.get_global_rect()
	var from_mid := from_rect.position + from_rect.size * 0.5
	var best: Control = null
	var best_extreme := 0.0
	var best_offset := 0.0
	for c in items:
		if c == from:
			continue
		var r: Rect2 = c.get_global_rect()
		var extreme: float
		var offset: float
		match side:
			SIDE_BOTTOM:  # fell off the bottom -> go to the topmost
				extreme = -r.position.y
				offset = absf(r.position.x + r.size.x * 0.5 - from_mid.x)
			SIDE_TOP:
				extreme = r.end.y
				offset = absf(r.position.x + r.size.x * 0.5 - from_mid.x)
			SIDE_RIGHT:  # fell off the right -> go to the leftmost
				extreme = -r.position.x
				offset = absf(r.position.y + r.size.y * 0.5 - from_mid.y)
			_:  # SIDE_LEFT
				extreme = r.end.x
				offset = absf(r.position.y + r.size.y * 0.5 - from_mid.y)
		if best == null or extreme > best_extreme \
				or (is_equal_approx(extreme, best_extreme) and offset < best_offset):
			best = c
			best_extreme = extreme
			best_offset = offset
	return best

# Recursively set focus_mode on the interactive controls under `root`.
func _set_scope_focusable(root: Node, focusable: bool) -> void:
	for child in root.get_children():
		if child is BaseButton or child is Slider or child is OptionButton:
			var ctl := child as Control
			# A DISABLED button must be FOCUS_NONE, not merely un-grabbable:
			# Godot's neighbor search only skips FOCUS_NONE controls, so a greyed
			# button left at FOCUS_ALL becomes a dead end that swallows the d-pad
			# (the main menu's greyed-out Continue blocked every option under it).
			var blocked := ctl.has_meta(BattleUITheme.NO_FOCUS_META) \
				or (ctl is BaseButton and (ctl as BaseButton).disabled)
			if blocked:
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
# Three switchable keybind profiles per device; the live InputMap mirrors the
# two active ones. SettingsScreen edits these.
var input_profiles := InputProfiles.new()

func _load_input_config() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(USER_CONFIG_PATH) == OK:
		# from_config migrates a pre-profiles [input] section into profile 1, so
		# an existing player keeps the bindings they already set.
		input_profiles.from_config(cfg)
	else:
		input_profiles.reset_everything()
	input_profiles.apply_active()

# Writes the current bindings to config (merge-preserving other sections). The
# live InputMap is captured into the active profiles first, so an edit made
# since the last switch is included.
func save_input_config() -> void:
	var cfg = ConfigFile.new()
	cfg.load(USER_CONFIG_PATH)
	input_profiles.sync_from_input_map()
	input_profiles.to_config(cfg)
	# Keep the flat [input] section in step so anything still reading it (and a
	# downgrade to an older build) sees the active bindings.
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
		_apply_input_mode(false, true)    # keyboard → focus navigation
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		_last_mouse_ms = Time.get_ticks_msec()
		_apply_input_mode(false, false)   # mouse → click-only, no focus ring
	elif event is InputEventJoypadButton and event.pressed:
		_apply_input_mode(true, false)    # controller → focus navigation
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		_apply_input_mode(true, false)

# --- Input mode (controller vs keyboard vs mouse) ------------------------------
func is_controller_mode() -> bool:
	return _controller_mode

# True when menus should be focus-navigable (moving highlight + ui_accept). On for
# controller AND keyboard; off for pure mouse. This is what the focus guard and the
# per-screen "grab initial focus" helpers key off of.
func focus_nav_active() -> bool:
	return _controller_mode or _keyboard_nav

func _set_controller_mode(controller: bool) -> void:
	# Setting controller mode explicitly (e.g. the test hook) clears keyboard nav,
	# so `false` means "mouse mode / click-only", matching the prior behavior.
	_apply_input_mode(controller, false)

func _apply_input_mode(controller: bool, keyboard: bool) -> void:
	if controller == _controller_mode and keyboard == _keyboard_nav:
		return
	var ctrl_changed := controller != _controller_mode
	_controller_mode = controller
	_keyboard_nav = keyboard
	# Emit only when the gamepad bit flips (device status listeners care about that);
	# the focus guard re-applies focusability on its own via _focus_top_last tracking.
	if ctrl_changed:
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
	quest_log.reset()
	quest_log.set_story(QuestFactory.create(QuestFactory.STORY_START))
	clock.set_minutes(TimeOfDay.START_MINUTES)
	rest_swaps_remaining = REST_SWAP_ALLOWANCE
	battles_since_rest_refresh = 0
	rest_available = true
	story_flags = {}
	play_time_seconds = 0.0
	save_overworld_scene_path = ""
	save_overworld_position = Vector2.ZERO
	resuming_from_save = false
	in_overworld_battle = false
	pending_battle_enemies = [] as Array[Enemy]
	pending_roamer_id = -1
	pending_flee_iframes = false
	pending_transition_active = false
	pending_fade_in = false
	transition_origin_scene = ""
	transition_origin_pos = Vector2.ZERO
	clear_roamer_state()
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

# ─── Shops & Inn ─────────────────────────────────────────
# All shop transactions use the shared party inventory (party[0].inventory).

func _shared_inventory() -> Inventory:
	return party[0].inventory if not party.is_empty() else null

func can_afford(cost: int) -> bool:
	return gold >= cost

# Buys one of a named ItemFactory item if affordable; returns true on success.
func buy_item(item_name: String) -> bool:
	var it := ItemFactory.create(item_name)
	var inv := _shared_inventory()
	if it == null or inv == null or it.price <= 0 or not can_afford(it.price):
		return false
	spend_gold(it.price)
	inv.add_item(it)
	return true

# Buys a named EquipmentFactory piece (added to the shared pool) if affordable.
func buy_equipment(eq_name: String) -> bool:
	var eq := EquipmentFactory.create(eq_name)
	var inv := _shared_inventory()
	if eq == null or inv == null or eq.price <= 0 or not can_afford(eq.price):
		return false
	spend_gold(eq.price)
	inv.add_equipment(eq)
	return true

# Sells one of an item instance from the shared inventory; returns gold earned (0 if
# it isn't sellable — e.g. key items).
func sell_item(item: Item) -> int:
	var inv := _shared_inventory()
	if inv == null or item == null or item.sell_price() <= 0:
		return 0
	var earned := item.sell_price()
	inv.remove_item(item, 1)
	earn_gold(earned)
	return earned

func sell_equipment(eq: Equipment) -> int:
	var inv := _shared_inventory()
	if inv == null or eq == null or eq.sell_price() <= 0:
		return 0
	var earned := eq.sell_price()
	inv.remove_equipment(eq)
	earn_gold(earned)
	return earned

# Bumped by story progression to raise inn prices over the game (0 = the starting
# 20-gold rate). The story system will set this as the player advances.
var inn_cost_tier: int = 0

# Inn: pay gold to fully restore the party's HP/MP. Starts at 20 gold and only goes
# up at story milestones (via inn_cost_tier), not with party level.
func inn_rest_cost() -> int:
	return 20 + inn_cost_tier * 20

func inn_rest() -> bool:
	var cost := inn_rest_cost()
	if not can_afford(cost):
		return false
	spend_gold(cost)
	for c in party:
		c.current_hp = c.max_hp()
		c.current_mp = c.max_mp()
	return true

# ─── Quest & Flags ───────────────────────────────────────
func complete_quest(quest_id: String):
	if not quest_id in quest_log.completed:
		quest_log.completed.append(quest_id)

func is_quest_done(quest_id: String) -> bool:
	return quest_log.is_completed(quest_id)

# Accept a SIDE quest from a giver (by id or a built Quest). Returns the accepted
# Quest, or null if it couldn't be accepted (already had / completed / unknown id).
func accept_quest(quest_or_id) -> Quest:
	var quest: Quest = quest_or_id if quest_or_id is Quest else QuestFactory.create(String(quest_or_id))
	if quest == null:
		return null
	if quest_log.accept_side(quest):
		emit_signal("quest_accepted", quest)
		emit_signal("quests_changed")
		return quest
	return null

# Sets the always-active story quest (by id or a built Quest). Called on new game and
# whenever the story advances.
func set_story_quest(quest_or_id) -> Quest:
	var quest: Quest = quest_or_id if quest_or_id is Quest else QuestFactory.create(String(quest_or_id))
	quest_log.set_story(quest)
	emit_signal("quests_changed")
	return quest

# Picks which accepted side quest is the highlighted "active side quest".
func select_active_side_quest(quest_id: String) -> bool:
	var ok := quest_log.select_active_side(quest_id)
	if ok:
		emit_signal("quests_changed")
	return ok

# Advance counter quests whose objective_key matches (e.g. "defeat:goblin"). Combat
# and other systems call this; the Quests menu reflects it.
func report_quest_event(event_key: String, amount: int = 1) -> void:
	quest_log.report(event_key, amount)

func can_turn_in_quest(quest_id: String) -> bool:
	return quest_log.can_turn_in(quest_id)

# Turn in an objective-met quest: moves it to completed and grants its rewards
# (gold, XP to the whole party, and any reward items). Returns the quest or null.
func turn_in_quest(quest_id: String) -> Quest:
	var q := quest_log.mark_completed(quest_id)
	if q == null:
		return null
	if q.reward_gold > 0:
		earn_gold(q.reward_gold)
	for n in q.reward_items:
		var it := ItemFactory.create(String(n))
		if it != null and not party.is_empty():
			party[0].inventory.add_item(it)
	emit_signal("quest_completed", q)
	emit_signal("quests_changed")
	return q

# Restores quest state from a save dict. New saves carry a structured "quests" dict
# (story + side quests + active selection + completed); older saves only had a
# "completed_quests" id list. Either way the story quest is guaranteed present after.
func _load_quests(data: Dictionary) -> void:
	if data.has("quests") and data["quests"] is Dictionary:
		quest_log.from_save(data["quests"])
	else:
		quest_log.reset()
		for q in data.get("completed_quests", []):
			var s := str(q)
			if not (s in quest_log.completed):
				quest_log.completed.append(s)
	if quest_log.story == null:
		quest_log.set_story(QuestFactory.create(QuestFactory.STORY_START))

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

# ─── Rest areas & loadout swaps ──────────────────────────
# A campfire tops the party up and lets the player rethink their moveset a
# couple of times. Only EQUIPPING a move costs an allowance — deleting a move
# from a slot and rearranging slots are free and unlimited, since neither
# changes what the character can actually do.
#
# Town NPCs are unrestricted; the allowance only gates rest areas.
const REST_SWAP_ALLOWANCE := 2
# Battles that must be fought before a rest area's swap allowance refills, so a
# campfire can't be farmed for unlimited loadout changes.
const REST_REFRESH_BATTLES := 5
## Fractions restored by a rest, of each character's maximum.
const REST_HP_FRACTION := 0.25
const REST_MP_FRACTION := 0.25
## Flat resonance points restored, on the 0-100 meter.
const REST_RESONANCE := 10.0

var rest_swaps_remaining: int = REST_SWAP_ALLOWANCE
var battles_since_rest_refresh: int = 0
## False once a campfire has been used, until REST_REFRESH_BATTLES more battles
## are fought. Gates the whole campfire interaction, not just the swaps.
var rest_available: bool = true

signal rest_swaps_changed(remaining: int)

## Can the party use a rest area right now?
func can_rest() -> bool:
	return rest_available

## Prompt shown when a campfire is approached but is still on cooldown.
func rest_unavailable_text() -> String:
	return "Cannot rest now"


func can_spend_rest_swap() -> bool:
	return rest_swaps_remaining > 0

## Consumes one allowance. Returns false when empty so the caller can refuse the
## edit rather than silently letting it through.
func spend_rest_swap() -> bool:
	if rest_swaps_remaining <= 0:
		return false
	rest_swaps_remaining -= 1
	rest_swaps_changed.emit(rest_swaps_remaining)
	return true

## Called once per completed battle (win, loss or flee). Every
## REST_REFRESH_BATTLES the allowance refills, so campfires stay useful without
## being farmable by walking in and out of one.
func register_battle_completed() -> void:
	battles_since_rest_refresh += 1
	if battles_since_rest_refresh >= REST_REFRESH_BATTLES:
		battles_since_rest_refresh = 0
		rest_available = true
		refill_rest_swaps()

func refill_rest_swaps() -> void:
	if rest_swaps_remaining == REST_SWAP_ALLOWANCE:
		return
	rest_swaps_remaining = REST_SWAP_ALLOWANCE
	rest_swaps_changed.emit(rest_swaps_remaining)

## Battles still to fight before the allowance comes back.
func battles_until_rest_refresh() -> int:
	return maxi(0, REST_REFRESH_BATTLES - battles_since_rest_refresh)

## Restores a quarter of each living hero's max HP and MP and a little
## resonance. Returns per-hero totals so the campfire dialogue can report them.
## The downed are not revived — a rest is a top-up, not a full heal.
## Rests until the start of `until_phase`, restoring a quarter of each living
## hero's max HP and MP and a flat +10 resonance, then putting the campfire on
## cooldown for REST_REFRESH_BATTLES battles. Returns per-hero totals plus how
## much game time passed, for the confirmation text.
func rest_at_camp(until_phase: int = TimeOfDay.Phase.DAY) -> Dictionary:
	var elapsed := clock.advance_to_phase(until_phase)
	rest_available = false
	battles_since_rest_refresh = 0
	return {
		"healed": _apply_rest_heal(),
		"minutes_passed": elapsed,
		"phase": until_phase,
	}

func _apply_rest_heal() -> Dictionary:
	var healed := {}
	for c in party:
		if not c.is_alive():
			continue
		var hp_gain := int(round(c.max_hp() * REST_HP_FRACTION))
		var mp_gain := int(round(c.max_mp() * REST_MP_FRACTION))
		var before_hp := c.current_hp
		var before_mp := c.current_mp
		c.current_hp = mini(c.max_hp(), c.current_hp + hp_gain)
		c.current_mp = mini(c.max_mp(), c.current_mp + mp_gain)
		c.resonance_meter = minf(100.0, c.resonance_meter + REST_RESONANCE)
		healed[c.character_name] = {
			"hp": c.current_hp - before_hp,
			"mp": c.current_mp - before_mp,
		}
	return healed

# ─── Save System ─────────────────────────────────────────
func save_game():
	var save_data = {
		"gold": gold,
		"current_map": current_map,
		"quests": quest_log.to_save(),
		"time_minutes": clock.minutes,
		"rest_swaps_remaining": rest_swaps_remaining,
		"battles_since_rest_refresh": battles_since_rest_refresh,
		"rest_available": rest_available,
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
	_load_quests(data)
	clock.set_minutes(float(data.get("time_minutes", TimeOfDay.START_MINUTES)))
	rest_swaps_remaining = clampi(int(data.get("rest_swaps_remaining", REST_SWAP_ALLOWANCE)), 0, REST_SWAP_ALLOWANCE)
	battles_since_rest_refresh = maxi(0, int(data.get("battles_since_rest_refresh", 0)))
	rest_available = bool(data.get("rest_available", true))
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
		"quests": quest_log.to_save(),
		"time_minutes": clock.minutes,
		"rest_swaps_remaining": rest_swaps_remaining,
		"battles_since_rest_refresh": battles_since_rest_refresh,
		"rest_available": rest_available,
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
	_load_quests(data)
	clock.set_minutes(float(data.get("time_minutes", TimeOfDay.START_MINUTES)))
	rest_swaps_remaining = clampi(int(data.get("rest_swaps_remaining", REST_SWAP_ALLOWANCE)), 0, REST_SWAP_ALLOWANCE)
	battles_since_rest_refresh = maxi(0, int(data.get("battles_since_rest_refresh", 0)))
	rest_available = bool(data.get("rest_available", true))
	story_flags = data.get("story_flags", {})
	current_map = data.get("current_map", "world_map")
	play_time_seconds = float(data.get("metadata", {}).get("playtime_seconds", 0.0))
	save_overworld_scene_path = data.get("overworld_scene_path", "")
	var pos_data = data.get("overworld_position", {"x": 0, "y": 0})
	save_overworld_position = Vector2(float(pos_data.get("x", 0)), float(pos_data.get("y", 0)))
	party = SaveSerializer.deserialize_party(data.get("party", []))
	active_slot = slot
	# Loading a save enters its region fresh — drop any in-memory roamer state so
	# the loaded area repopulates instead of restoring a different session's roamers.
	pending_roamer_id = -1
	pending_flee_iframes = false
	clear_roamer_state()
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
