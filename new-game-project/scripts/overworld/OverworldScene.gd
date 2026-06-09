extends Node2D

## OverworldScene — Phase 7
## Reads its area config from a MapArea resource (assigned per-scene). Enemies are
## VISIBLE roaming sprites (Mario & Luigi style): they wander and chase the player,
## and touching one starts that enemy's specific battle. Defeated roamers stay gone
## but the population refills over time via a respawn timer.

const BATTLE_SCENE_PATH := "res://scenes/BattleScene.tscn"
const MAIN_MENU_SCENE_PATH := "res://scenes/MainMenu.tscn"
const PAUSE_MENU_SCENE_PATH := "res://scenes/PauseMenu.tscn"

# Roaming-enemy population tuning.
const MAX_ROAMERS := 4
const SPAWN_MIN_DIST_FROM_PLAYER := 600.0   # never spawn on top of the player
const FIELD_MARGIN := 200.0            # keep spawns away from the boundary walls
const TERRITORY_SIZE := Vector2(900, 900)   # each roamer's wander/chase area
const FLEE_IFRAME_TIME := 3.0          # seconds of post-flee invulnerability

@export var area: MapArea
# Walkable field bounds in world space (matches the boundary walls in the scene).
@export var field_rect: Rect2 = Rect2(0, 0, 4000, 3000)

@onready var player: CharacterBody2D = $Player

var _encounter_in_flight: bool = false
var _pause_menu: Control = null
# P5 auto-save: tracks safe-zone (town) entry to trigger an auto-save.
var _auto_save := AutoSaveSystem.new()
var _save_indicator: Control = null
# P7 roaming enemies.
var _roamers: Array[RoamingEnemy] = []
var _next_roamer_id: int = 1
var _iframes_remaining: float = 0.0   # >0 = player is invulnerable to roamer touches

func _ready() -> void:
	GameManager.ensure_default_party()

	if GameManager.in_overworld_battle:
		# Returning from a battle — drop player at the saved spot.
		player.position = GameManager.pending_overworld_return_position
		GameManager.in_overworld_battle = false
		print("[Overworld] Returned from battle at ", player.position)
	elif GameManager.resuming_from_save:
		# Continue from a save — spawn at the saved position.
		player.position = GameManager.save_overworld_position
		GameManager.resuming_from_save = false
		print("[Overworld] Resumed from save at ", player.position)
	elif area != null:
		# Fresh entry to this area — use the area's default spawn.
		player.position = area.default_spawn

	# Seed the auto-save tracker to the spawn position so spawning inside a town
	# (e.g. resuming a save made in one) doesn't immediately re-trigger an auto-save.
	if area != null:
		_auto_save.update(player.position, area.safe_zones)
	_ensure_save_indicator()

	if area == null:
		push_warning("OverworldScene has no MapArea assigned — encounters will not trigger")

	# --- Roaming enemies (region-scoped, persistent across battles) ---
	# A region is identified by its overworld scene path. If we already have live
	# roamer state for THIS region (returning from a battle, or re-entering), we
	# restore the survivors; the defeated roamer (if the player won) is removed
	# permanently. If this is a fresh region — first visit, or returning after
	# having gone somewhere else — we spawn a new population. So: leaving Fallster
	# Plains and coming back repopulates it; fighting within it does not.
	var region := scene_file_path
	# A roamer fight the player WON: drop that roamer from the saved state for good.
	if GameManager.pending_roamer_id != -1 and GameManager.last_battle_won:
		GameManager.remove_roamer_state(GameManager.pending_roamer_id)
	GameManager.pending_roamer_id = -1

	if GameManager.has_roamer_state_for(region):
		_restore_roamers()
	else:
		_spawn_initial_roamers(MAX_ROAMERS)
		_persist_roamers()

	# Flee i-frames: if the player ran from the last battle, grant a short grace
	# period where no roamer can pull them into another fight, and fade the player.
	# The fled enemy keeps its exact position + normal behavior — once the grace
	# window ends, an enemy already touching the player starts a fresh battle.
	if GameManager.pending_flee_iframes:
		GameManager.pending_flee_iframes = false
		_start_flee_iframes()

# The auto-save status badge lives on its own CanvasLayer so it renders in
# screen-space (bottom-right) rather than being panned by the player's camera.
func _ensure_save_indicator() -> void:
	if _save_indicator != null and is_instance_valid(_save_indicator):
		return
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_save_indicator = SaveIndicator.new()
	layer.add_child(_save_indicator)

func _input(event: InputEvent) -> void:
	# Use _input (not _unhandled_input) so the pause key is caught before Godot's
	# GUI pipeline can consume it. The remappable "pause" action (default Esc /
	# controller Start) is honored here automatically.
	if event.is_action_pressed("pause"):
		_open_pause_menu()
		get_viewport().set_input_as_handled()

func _open_pause_menu() -> void:
	if _pause_menu == null:
		# Wrap in a CanvasLayer so the menu renders in screen-space and isn't
		# panned around by the player's Camera2D. Matches how BattleScene's UI
		# is parented to a CanvasLayer.
		var layer = CanvasLayer.new()
		layer.layer = 10
		add_child(layer)
		_pause_menu = load(PAUSE_MENU_SCENE_PATH).instantiate()
		layer.add_child(_pause_menu)
		_pause_menu.save_requested.connect(_on_pause_save)
		_pause_menu.quit_requested.connect(_on_pause_quit)
	_pause_menu.open()

func _on_pause_save() -> void:
	if GameManager.active_slot < 0:
		_pause_menu.show_toast("No active slot — start a New Game first.", true)
		return
	GameManager.save_overworld_scene_path = scene_file_path
	GameManager.save_overworld_position = player.position
	if GameManager.save_to_slot(GameManager.active_slot):
		_pause_menu.show_toast("Saved to Slot %d" % (GameManager.active_slot + 1))
	else:
		_pause_menu.show_toast("Save failed.", true)

func _on_pause_quit() -> void:
	# Must unpause before scene change; the tree carries pause state across scenes.
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)

func _process(delta: float) -> void:
	if _encounter_in_flight:
		return

	# Auto-save on entering a town/safe zone (P5). Fires once per entry.
	if area != null and _auto_save.update(player.position, area.safe_zones):
		GameManager.autosave(scene_file_path, player.position)

	# Count down post-flee i-frames; clear the faded look on player + roamers when done.
	if _iframes_remaining > 0.0:
		_iframes_remaining -= delta
		if _iframes_remaining <= 0.0:
			_iframes_remaining = 0.0
			_set_roamers_faded(false)
			_set_player_faded(false)

# --- Roaming enemies ----------------------------------------------------------

func _eligible_groups() -> Array[EncounterGroup]:
	var available: Array[EncounterGroup] = []
	if area == null:
		return available
	var party_level: int = _get_party_max_level()
	for g in area.encounter_groups:
		if g != null and g.min_party_level <= party_level and not g.enemy_pool.is_empty():
			available.append(g)
	return available

# --- Spawn (fresh) ---
func _spawn_initial_roamers(count: int) -> void:
	var groups := _eligible_groups()
	if groups.is_empty():
		return
	for i in range(count):
		var group := _weighted_pick(groups)
		if group == null:
			continue
		var gindex: int = area.encounter_groups.find(group)
		var territory := _random_territory()
		var pos := _random_point_in(territory)
		if pos == Vector2.INF:
			continue
		_add_roamer(_next_roamer_id, group, gindex, pos, territory)
		_next_roamer_id += 1

# --- Restore (returning to a region with live state) ---
func _restore_roamers() -> void:
	for s in GameManager.roamer_states:
		var gindex: int = int(s.get("group_index", -1))
		if gindex < 0 or gindex >= area.encounter_groups.size():
			continue
		var group: EncounterGroup = area.encounter_groups[gindex]
		var id: int = int(s.get("id", _next_roamer_id))
		var pos: Vector2 = s.get("position", Vector2.ZERO)
		var home: Rect2 = s.get("home", _random_territory())
		_add_roamer(id, group, gindex, pos, home)
		_next_roamer_id = maxi(_next_roamer_id, id + 1)

func _add_roamer(id: int, group: EncounterGroup, gindex: int, pos: Vector2, territory: Rect2) -> void:
	var roamer := RoamingEnemy.new()
	roamer.position = pos
	roamer.setup(id, group, gindex, player, territory)
	roamer.touched_player.connect(_on_roamer_touched)
	add_child(roamer)
	_roamers.append(roamer)

# Saves the current roamers (id, group, position, territory) to GameManager so
# they survive the battle scene reload.
func _persist_roamers() -> void:
	var states: Array = []
	for r in _roamers:
		if not is_instance_valid(r):
			continue
		states.append({
			"id": r.spawn_id,
			"group_index": r.group_index,
			"position": r.global_position,
			"home": r.home_rect,
		})
	GameManager.set_roamer_state(scene_file_path, states)

# A random territory rect inside the field, clear of safe zones, for one roamer.
func _random_territory() -> Rect2:
	var size := TERRITORY_SIZE
	var lo := field_rect.position + Vector2(FIELD_MARGIN, FIELD_MARGIN)
	var hi := field_rect.position + field_rect.size - Vector2(FIELD_MARGIN, FIELD_MARGIN) - size
	if hi.x < lo.x: hi.x = lo.x
	if hi.y < lo.y: hi.y = lo.y
	var zones: Array = area.safe_zones if area != null else []
	for _attempt in range(12):
		var origin := Vector2(randf_range(lo.x, hi.x), randf_range(lo.y, hi.y))
		var rect := Rect2(origin, size)
		# Keep the territory away from the player's spawn and off the towns.
		if rect.get_center().distance_to(player.position) < SPAWN_MIN_DIST_FROM_PLAYER:
			continue
		if _rect_overlaps_any(rect, zones):
			continue
		return rect
	# Fallback: a territory at the field center.
	return Rect2(field_rect.position + (field_rect.size - size) * 0.5, size)

# A random point inside `rect` that isn't inside a safe zone. Vector2.INF if none.
func _random_point_in(rect: Rect2) -> Vector2:
	var zones: Array = area.safe_zones if area != null else []
	for _attempt in range(12):
		var p := rect.position + Vector2(randf() * rect.size.x, randf() * rect.size.y)
		if not _point_in_zones(p, zones):
			return p
	return rect.get_center()

static func _point_in_zones(p: Vector2, zones: Array) -> bool:
	for z in zones:
		if (z as Rect2).has_point(p):
			return true
	return false

static func _rect_overlaps_any(rect: Rect2, zones: Array) -> bool:
	for z in zones:
		if rect.intersects(z as Rect2):
			return true
	return false

# --- Flee i-frames ---
func _start_flee_iframes() -> void:
	_iframes_remaining = FLEE_IFRAME_TIME
	_set_roamers_faded(true)
	_set_player_faded(true)

func _set_roamers_faded(faded: bool) -> void:
	for r in _roamers:
		if is_instance_valid(r):
			r.set_faded(faded)

# Fades the player sprite during the post-flee grace window (same feedback as the
# roamers), then restores it when i-frames end.
func _set_player_faded(faded: bool) -> void:
	var sprite := player.get_node_or_null("Sprite")
	if sprite is CanvasItem:
		(sprite as CanvasItem).modulate.a = 0.4 if faded else 1.0

func _on_roamer_touched(roamer: RoamingEnemy) -> void:
	# Ignore touches during post-flee i-frames or if a battle is already starting.
	if _encounter_in_flight or area == null or _iframes_remaining > 0.0:
		return
	var enemies := roamer.encounter_group.instantiate_encounter()
	if enemies.is_empty():
		return

	_encounter_in_flight = true
	# Now that the battle is accepted, freeze the roamer (the enemy no longer
	# freezes itself on contact — see RoamingEnemy).
	roamer.freeze()
	# Persist the current roamers (positions/territories) so the survivors come
	# back exactly where they were when we return from the battle.
	_persist_roamers()
	GameManager.in_overworld_battle = true
	GameManager.pending_battle_enemies = enemies
	GameManager.pending_battle_background = area.battle_background_id
	GameManager.pending_overworld_scene_path = scene_file_path
	GameManager.pending_overworld_return_position = player.position
	# Tag which roamer started this fight + reset the outcome (BattleScene sets it).
	GameManager.pending_roamer_id = roamer.spawn_id
	GameManager.last_battle_won = false

	print("[Overworld] Roaming '%s' encounter (%d enemies)" % [
		roamer.encounter_group.group_name, enemies.size()
	])
	get_tree().change_scene_to_file(BATTLE_SCENE_PATH)

func _get_party_max_level() -> int:
	var max_lv: int = 1
	for c in GameManager.party:
		if c.level > max_lv:
			max_lv = c.level
	return max_lv

# Weighted random pick. Groups with weight <= 0 are skipped.
func _weighted_pick(groups: Array[EncounterGroup]) -> EncounterGroup:
	var total: float = 0.0
	for g in groups:
		total += maxf(0.0, g.weight)
	if total <= 0.0:
		return null
	var roll: float = randf() * total
	var acc: float = 0.0
	for g in groups:
		acc += maxf(0.0, g.weight)
		if roll < acc:
			return g
	return groups[groups.size() - 1]
