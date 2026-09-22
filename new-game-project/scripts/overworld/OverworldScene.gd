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
const FADE_TIME := 0.35                 # map-to-map transition fade in/out duration
const ARRIVAL_GRACE := 0.8             # post-arrival window where zone entries are ignored
const DEBUG_TOGGLE_KEY := KEY_F3       # toggles the zone debug overlay
# CanvasLayer stack: the save badge must render ABOVE the transition fade so an
# auto-save stays visible while the screen is black.
const FADE_LAYER := 15
const SAVE_INDICATOR_LAYER := 20

@export var area: MapArea
# Walkable field bounds in world space (matches the boundary walls in the scene).
@export var field_rect: Rect2 = Rect2(0, 0, 3840, 2160)

@onready var player: CharacterBody2D = $Player

var _encounter_in_flight: bool = false
var _pause_menu: Control = null
var _save_indicator: Control = null
# P7 roaming enemies.
var _roamers: Array[RoamingEnemy] = []
var _next_roamer_id: int = 1
var _iframes_remaining: float = 0.0   # >0 = player is invulnerable to roamer touches
# P7p2 map zones (drawable Area2D save / transition / no-spawn regions).
var _zones: Array[MapZone] = []
var _transitioning: bool = false      # true while a fade-out/scene-change is in flight
var _arrival_grace: float = 0.0       # >0 = ignore zone entries (just arrived via a transition)
var _fade_layer: CanvasLayer = null
var _fade_rect: ColorRect = null
# P7p2 debug zone overlay (toggled with F3).
var _zone_debug: ZoneDebugOverlay = null
var _time_modulate: CanvasModulate = null   # tints the world by time of day

func _ready() -> void:
	GameManager.ensure_default_party()
	# Time of day: the clock runs while this scene is active; a CanvasModulate tints
	# the world (map/player/roamers) per phase — UI on CanvasLayers is unaffected.
	#
	# The clock runs in interiors too (time passes while you shop), but the tint is
	# skipped under a roof — see MapArea.wants_time_tint(). Leaving the modulate out
	# entirely rather than setting it to white keeps _process's null check doing the
	# work, so an interior costs nothing per frame. A null area means outdoors.
	GameManager.set_time_overworld(true)
	if area == null or area.wants_time_tint():
		_time_modulate = CanvasModulate.new()
		_time_modulate.color = GameManager.clock.tint()
		add_child(_time_modulate)
	# Depth (P7p2): Y-sort the scene so the player can walk BEHIND structures.
	# DepthOverlay polygons re-draw building pixels at their baseline Y; the
	# player (and roamers) interleave with them by position. Nested overlay
	# containers (e.g. a "Tree_Overlays" group) must ALSO be Y-sorted or their
	# children sort as one unit instead of individually — enable it everywhere
	# under DepthOverlays so any grouping the map author makes just works.
	y_sort_enabled = true
	var depth := get_node_or_null("DepthOverlays")
	if depth != null:
		_enable_ysort_recursive(depth)
		# Tell every walk-behind overlay whose Y decides its depth (the player), so
		# each shows its lifted pixels only while the player is behind that structure.
		_track_depth_for_overlays(depth, player)
	# Fit the camera limits to the actual map image so the WHOLE map is reachable by
	# the camera (no edges cut off). Done in code so it stays correct no matter how
	# the MapImage is scaled/repositioned. Regions with a ColorRect background keep
	# their scene-authored limits.
	_fit_camera_to_map()

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
	elif GameManager.pending_transition_active:
		# Arrived through a map-to-map transition (gate / dungeon entrance / town) —
		# drop the player at the transition's target spawn and briefly ignore zone
		# entries so they don't immediately bounce back through the entrance.
		player.position = GameManager.pending_transition_spawn
		GameManager.pending_transition_active = false
		_arrival_grace = ARRIVAL_GRACE
		print("[Overworld] Arrived via transition at ", player.position)
		# Entering a town interior auto-saves (P7p2). Villages/dungeons leave the
		# flag off; GameManager.can_autosave still gates on the settings toggle.
		if area != null and area.autosave_on_enter:
			GameManager.autosave(scene_file_path, player.position)
	elif area != null:
		# Fresh entry to this area — use the area's default spawn.
		player.position = area.default_spawn

	_ensure_save_indicator()
	# Wire up the scene's MapZone nodes (save / transition / no-spawn) BEFORE spawning
	# roamers so spawn suppression can see them.
	_collect_and_wire_zones()

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

	# Fade in from black if we arrived through a map-to-map transition.
	if GameManager.pending_fade_in:
		GameManager.pending_fade_in = false
		_fade_in()

# Sets the player camera's limits to the MapImage's world-space rect, so the camera
# can pan to every edge of the map (otherwise the parts of the map beyond the limits
# — e.g. the south tree line — are never visible). No-op for ColorRect regions.
func _fit_camera_to_map() -> void:
	var map := get_node_or_null("MapImage") as Sprite2D
	if map == null or map.texture == null or player == null:
		return
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	var size: Vector2 = map.texture.get_size() * map.scale
	cam.limit_left = int(floor(map.global_position.x))
	cam.limit_top = int(floor(map.global_position.y))
	cam.limit_right = int(ceil(map.global_position.x + size.x))
	cam.limit_bottom = int(ceil(map.global_position.y + size.y))

# Enables Y-sort on the depth-overlay GROUPING containers (DepthOverlays, a
# "Tree_Overlays" sub-group, etc.) so each DepthOverlay leaf flattens into the
# scene's single Y-sort and interleaves with the player.
#
# Crucially it does NOT Y-sort the DepthOverlay leaves themselves. A leaf holds a
# child cutout Sprite2D drawn ABOVE its foot baseline; if the leaf were Y-sorted,
# Godot would flatten that sprite into the parent sort by the SPRITE's own (top-of-
# structure) Y instead of the leaf's baked foot baseline — sorting the whole tree
# as if its pivot were its crown, which is what kept drawing the player in front of
# trees. Leaving the leaf un-sorted makes it sort as one unit at its foot, which is
# correct under both of Godot's nested-Y-sort interpretations.
func _enable_ysort_recursive(node: Node) -> void:
	if node is DepthOverlay:
		(node as Node2D).y_sort_enabled = false
		return  # don't descend into the leaf's cutout sprite
	if node is Node2D:
		(node as Node2D).y_sort_enabled = true
	for child in node.get_children():
		_enable_ysort_recursive(child)

# Walks the depth-overlay subtree and points every DepthOverlay at the node whose
# Y position decides whether the player is in front of or behind that structure.
func _track_depth_for_overlays(node: Node, target: Node2D) -> void:
	if node is DepthOverlay:
		(node as DepthOverlay).track_depth(target)
		return
	for child in node.get_children():
		_track_depth_for_overlays(child, target)

# The auto-save status badge lives on its own CanvasLayer so it renders in
# screen-space (bottom-right) rather than being panned by the player's camera.
func _ensure_save_indicator() -> void:
	if _save_indicator != null and is_instance_valid(_save_indicator):
		return
	var layer := CanvasLayer.new()
	layer.layer = SAVE_INDICATOR_LAYER
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
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == DEBUG_TOGGLE_KEY:
		_toggle_zone_debug()
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

func _exit_tree() -> void:
	# Leaving the overworld (to battle / main menu) stops the clock + hides its overlay.
	GameManager.set_time_overworld(false)

func _process(delta: float) -> void:
	# Keep the world tint current every frame (even mid-transition for a smooth fade).
	if _time_modulate != null:
		_time_modulate.color = GameManager.clock.tint()

	if _encounter_in_flight or _transitioning:
		return

	# Auto-save + transitions are now event-driven (MapZone.body_entered); the only
	# per-frame work left is counting down the arrival grace + flee i-frames.
	if _arrival_grace > 0.0:
		_arrival_grace = maxf(0.0, _arrival_grace - delta)

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
	var phase: int = GameManager.clock.phase()
	var any_phase: Array[EncounterGroup] = []
	for g in area.encounter_groups:
		if g != null and g.min_party_level <= party_level and not g.enemy_pool.is_empty():
			any_phase.append(g)
			if g.allowed_at_phase(phase):
				available.append(g)
	# If nothing matches the current phase, fall back to all eligible groups so the
	# region is never empty at some time of day.
	return available if not available.is_empty() else any_phase

# --- Spawn (fresh) ---
func _spawn_initial_roamers(count: int) -> void:
	# Drawable territories (P7p2): RoamerTerritory nodes in the scene win — one
	# roamer per polygon, drawn right over the map art in the editor.
	var territories := _gather_territories(self)
	if not territories.is_empty():
		_spawn_territory_roamers(territories)
		return
	# Legacy pinned rects from MapArea.roamer_spawns, then fully-random fallback.
	if area != null and not area.roamer_spawns.is_empty():
		_spawn_pinned_roamers()
		return
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

# --- Spawn (drawable RoamerTerritory polygon nodes, P7p2) ---
func _gather_territories(node: Node) -> Array[RoamerTerritory]:
	var out: Array[RoamerTerritory] = []
	for child in node.get_children():
		if child is RoamerTerritory:
			out.append(child)
		if child.get_child_count() > 0:
			out.append_array(_gather_territories(child))
	return out

func _spawn_territory_roamers(territories: Array[RoamerTerritory]) -> void:
	var groups := _eligible_groups()
	for t in territories:
		var poly := t.world_polygon()
		if poly.size() < 3:
			push_warning("RoamerTerritory '%s' has no CollisionPolygon2D — skipped" % t.name)
			continue
		# An explicit group is used as-is (e.g. a fixed boss); null = weighted pick.
		var group: EncounterGroup = t.group
		if group == null:
			if groups.is_empty():
				continue
			group = _weighted_pick(groups)
		if group == null:
			continue
		# The group must be registered in the area so its index can be persisted.
		var gindex: int = area.encounter_groups.find(group) if area != null else -1
		if gindex < 0:
			push_warning("RoamerTerritory '%s' group '%s' not in area.encounter_groups — skipped" % [t.name, group.group_name])
			continue
		var pos := _random_point_in_poly(poly)
		_add_roamer(_next_roamer_id, group, gindex, pos, RoamerTerritory.bounding_rect(poly), poly)
		_next_roamer_id += 1

# A random point inside the polygon that isn't inside a no-spawn zone.
func _random_point_in_poly(poly: PackedVector2Array) -> Vector2:
	var bb := RoamerTerritory.bounding_rect(poly)
	for _attempt in range(24):
		var p := bb.position + Vector2(randf() * bb.size.x, randf() * bb.size.y)
		if Geometry2D.is_point_in_polygon(p, poly) and not _point_in_suppress_zone(p):
			return p
	return RoamerTerritory.centroid(poly)

# --- Spawn (pinned territories from MapArea.roamer_spawns) ---
func _spawn_pinned_roamers() -> void:
	var groups := _eligible_groups()
	for spawn in area.roamer_spawns:
		if spawn == null:
			continue
		# An explicit group is used as-is (e.g. a fixed boss, regardless of party
		# level); a null group is weighted-picked from the area's eligible groups.
		var group: EncounterGroup = spawn.group
		if group == null:
			if groups.is_empty():
				continue
			group = _weighted_pick(groups)
		if group == null:
			continue
		# The group must be registered in the area so its index can be persisted
		# across battles; an unregistered group can't be restored, so skip it.
		var gindex: int = area.encounter_groups.find(group)
		if gindex < 0:
			push_warning("RoamerSpawn group '%s' not in area.encounter_groups — skipped" % group.group_name)
			continue
		var pos := _random_point_in(spawn.home)
		if pos == Vector2.INF:
			pos = spawn.home.get_center()
		_add_roamer(_next_roamer_id, group, gindex, pos, spawn.home)
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
		var home_poly: PackedVector2Array = s.get("home_poly", PackedVector2Array())
		_add_roamer(id, group, gindex, pos, home, home_poly)
		_next_roamer_id = maxi(_next_roamer_id, id + 1)

func _add_roamer(id: int, group: EncounterGroup, gindex: int, pos: Vector2, territory: Rect2,
		territory_poly: PackedVector2Array = PackedVector2Array()) -> void:
	var roamer := RoamingEnemy.new()
	roamer.position = pos
	roamer.setup(id, group, gindex, player, territory, territory_poly)
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
			"home_poly": r.home_polygon,
		})
	GameManager.set_roamer_state(scene_file_path, states)

# A random territory rect inside the field, clear of safe zones, for one roamer.
func _random_territory() -> Rect2:
	var size := TERRITORY_SIZE
	var lo := field_rect.position + Vector2(FIELD_MARGIN, FIELD_MARGIN)
	var hi := field_rect.position + field_rect.size - Vector2(FIELD_MARGIN, FIELD_MARGIN) - size
	if hi.x < lo.x: hi.x = lo.x
	if hi.y < lo.y: hi.y = lo.y
	for _attempt in range(12):
		var origin := Vector2(randf_range(lo.x, hi.x), randf_range(lo.y, hi.y))
		var rect := Rect2(origin, size)
		# Keep the territory away from the player's spawn and out of no-spawn zones.
		if rect.get_center().distance_to(player.position) < SPAWN_MIN_DIST_FROM_PLAYER:
			continue
		if _point_in_suppress_zone(rect.get_center()):
			continue
		return rect
	# Fallback: a territory at the field center.
	return Rect2(field_rect.position + (field_rect.size - size) * 0.5, size)

# A random point inside `rect` that isn't inside a no-spawn zone.
func _random_point_in(rect: Rect2) -> Vector2:
	for _attempt in range(12):
		var p := rect.position + Vector2(randf() * rect.size.x, randf() * rect.size.y)
		if not _point_in_suppress_zone(p):
			return p
	return rect.get_center()

# True if a world point sits inside any MapZone that suppresses roamer spawns.
func _point_in_suppress_zone(p: Vector2) -> bool:
	for z in _zones:
		if z != null and is_instance_valid(z) and z.suppress_spawns and z.contains_point(p):
			return true
	return false

# Kept for the test suite: pure Rect2 helpers (no longer used by the zone flow).
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

# --- Map zones (P7p2): drawable Area2D save / transition / no-spawn regions ------

# Finds every MapZone in the scene and connects its body_entered to the player check.
func _collect_and_wire_zones() -> void:
	_zones.clear()
	_gather_zones(self)
	for z in _zones:
		z.body_entered.connect(_on_zone_body_entered.bind(z))

func _gather_zones(node: Node) -> void:
	for child in node.get_children():
		if child is MapZone:
			_zones.append(child)
		if child.get_child_count() > 0:
			_gather_zones(child)

# Fires when a body enters a zone. We only care about the player; roamers and walls
# (also on layer 1) are ignored. During the post-arrival grace, zone effects are
# skipped so the player can step off an entrance without instantly re-triggering it.
func _on_zone_body_entered(body: Node, zone: MapZone) -> void:
	if body != player:
		return
	if _transitioning or _encounter_in_flight or _arrival_grace > 0.0:
		return
	if zone.save_on_enter:
		GameManager.autosave(scene_file_path, player.position)
	if zone.is_transition():
		_begin_transition(zone)

# --- Map-to-map transitions (P7p2) --------------------------------------------

# Fades to black, then loads the zone's target scene. The destination reads the
# pending_* flags in _ready to spawn at the target and fade back in. A
# return_to_origin zone sends the player back to wherever they last entered from.
func _begin_transition(zone: MapZone) -> void:
	if _transitioning:
		return
	var target_scene: String
	var target_spawn: Vector2
	if zone.return_to_origin and GameManager.transition_origin_scene != "":
		target_scene = GameManager.transition_origin_scene
		target_spawn = GameManager.transition_origin_pos
	else:
		target_scene = zone.target_scene
		target_spawn = zone.target_spawn
		# Remember where we came from so a return_to_origin zone can send us back.
		GameManager.transition_origin_scene = scene_file_path
		GameManager.transition_origin_pos = player.position
	if target_scene == "":
		return
	_transitioning = true
	player.set_physics_process(false)   # lock movement during the fade
	_ensure_fade_overlay()
	print("[Overworld] Transition '%s' -> %s" % [zone.label, target_scene])
	var tw := create_tween()
	tw.tween_property(_fade_rect, "modulate:a", 1.0, FADE_TIME)
	tw.tween_callback(func ():
		GameManager.pending_transition_active = true
		GameManager.pending_transition_spawn = target_spawn
		GameManager.pending_fade_in = true
		get_tree().change_scene_to_file(target_scene)
	)

# --- Debug zone overlay (P7p2): toggle with F3 --------------------------------
func _toggle_zone_debug() -> void:
	if _zone_debug == null:
		_zone_debug = ZoneDebugOverlay.new()
		_zone_debug.z_index = 6
		add_child(_zone_debug)
		_zone_debug.visible = false
	_zone_debug.visible = not _zone_debug.visible
	if _zone_debug.visible:
		# Territories as polygons: drawable RoamerTerritory nodes first, plus any
		# legacy MapArea.roamer_spawns rects (converted to 4-point polygons).
		var homes: Array = []
		for t in _gather_territories(self):
			var poly := t.world_polygon()
			if poly.size() >= 3:
				homes.append(poly)
		if homes.is_empty() and area != null:
			for s in area.roamer_spawns:
				if s != null:
					var r: Rect2 = s.home
					homes.append(PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0),
						r.end, r.position + Vector2(0, r.size.y)]))
		var spawn := area.default_spawn if area != null else Vector2.ZERO
		_zone_debug.refresh(_zones, homes, _terrain_polygons(self), spawn, area != null)

# World-space polygons of every StaticBody2D CollisionPolygon2D in the scene
# (terrain walls), for the debug overlay. Excludes Area2D zones and the player.
func _terrain_polygons(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is CollisionPolygon2D and child.get_parent() is StaticBody2D:
			var cp := child as CollisionPolygon2D
			var xf := cp.global_transform
			var pts := PackedVector2Array()
			for p in cp.polygon:
				pts.append(xf * p)
			out.append(pts)
		if child.get_child_count() > 0:
			out.append_array(_terrain_polygons(child))
	return out

# Starts fully black and fades in (used on arrival through a transition).
func _fade_in() -> void:
	_ensure_fade_overlay()
	_fade_rect.modulate.a = 1.0
	player.set_physics_process(false)
	var tw := create_tween()
	tw.tween_property(_fade_rect, "modulate:a", 0.0, FADE_TIME)
	tw.tween_callback(func (): player.set_physics_process(true))

# Lazily builds the full-screen black fade overlay on its own CanvasLayer (so it
# isn't panned by the player's camera and sits above the map + roamers).
func _ensure_fade_overlay() -> void:
	if _fade_rect != null and is_instance_valid(_fade_rect):
		return
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = FADE_LAYER
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_rect.modulate.a = 0.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_layer.add_child(_fade_rect)

func _on_roamer_touched(roamer: RoamingEnemy) -> void:
	# Ignore touches during post-flee i-frames or if a battle is already starting.
	if _encounter_in_flight or area == null or _iframes_remaining > 0.0:
		return
	# Pass the party's max level so the encounter can scale enemy levels to it.
	var enemies := roamer.encounter_group.instantiate_encounter(_get_party_max_level())
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
