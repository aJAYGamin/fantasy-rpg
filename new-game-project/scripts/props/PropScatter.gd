@tool
class_name PropScatter
extends Node2D

## Scatters props across a region so you don't hand-place fifty trees.
##
## Placement is DETERMINISTIC from `scatter_seed`: the same seed always produces
## the same forest. That means nothing is baked into the .tscn (no scene bloat,
## no 500-node diffs) yet the map looks identical every run and every session.
## Change the seed to reroll the whole arrangement, nudge `count` for density.
##
## The math lives in static functions so it can be unit-tested without a tree.

@export var region: Rect2 = Rect2(0, 0, 800, 600):
	set(v):
		region = v
		_refresh()

## Prop names from PropLibrary. Picked uniformly unless `weights` is given.
@export var prop_names: PackedStringArray = PackedStringArray():
	set(v):
		prop_names = v
		_refresh()

## Optional per-name weights, parallel to prop_names. Shorter/empty = uniform.
@export var weights: PackedFloat32Array = PackedFloat32Array():
	set(v):
		weights = v
		_refresh()

@export var count: int = 20:
	set(v):
		count = maxi(0, v)
		_refresh()

@export var scatter_seed: int = 1:
	set(v):
		scatter_seed = v
		_refresh()

## Per-prop size jitter, e.g. 0.15 = each prop is 85%-115% of its library height.
@export_range(0.0, 0.8) var scale_jitter: float = 0.15:
	set(v):
		scale_jitter = v
		_refresh()

## Randomly mirror props so repeats of one texture read as different plants.
@export var random_flip: bool = true:
	set(v):
		random_flip = v
		_refresh()

## Keep-out rectangles: rivers, roads, buildings, town squares.
@export var avoid_rects: Array[Rect2] = []:
	set(v):
		avoid_rects = v
		_refresh()

## Minimum gap between two props' feet. Stops clumping into a single blob.
@export var min_spacing: float = 48.0:
	set(v):
		min_spacing = maxf(0.0, v)
		_refresh()

@export var enabled: bool = true:
	set(v):
		enabled = v
		_refresh()

@export_group("Terrain")
## The map art to sample. With this set, the scatter reads the painted ground
## under each candidate point and refuses to plant trees in the river or on a
## road — far more robust than hand-tuning keep-out rectangles per region.
@export var terrain_texture: Texture2D = null:
	set(v):
		terrain_texture = v
		_terrain_image = null
		_refresh()
## World-space position of the map sprite's top-left corner.
@export var terrain_offset: Vector2 = Vector2.ZERO:
	set(v):
		terrain_offset = v
		_refresh()
## The map sprite's scale, so world points convert back to texture pixels.
@export var terrain_scale: Vector2 = Vector2.ONE:
	set(v):
		terrain_scale = v
		_refresh()
@export var avoid_water: bool = true:
	set(v):
		avoid_water = v
		_refresh()
@export var avoid_roads: bool = true:
	set(v):
		avoid_roads = v
		_refresh()

var _terrain_image: Image = null

## Lazily decodes the map art once. Imported textures can be VRAM-compressed,
## so decompress before sampling or get_pixel returns garbage.
func _terrain_img() -> Image:
	if _terrain_image != null:
		return _terrain_image
	if terrain_texture == null:
		return null
	var img := terrain_texture.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img = img.duplicate()
		if img.decompress() != OK:
			return null
	_terrain_image = img
	return _terrain_image

func _terrain_rules() -> Dictionary:
	var img := _terrain_img()
	if img == null or (not avoid_water and not avoid_roads):
		return {}
	return {
		"image": img,
		"offset": terrain_offset,
		"scale": terrain_scale,
		"avoid_water": avoid_water,
		"avoid_roads": avoid_roads,
	}

## Classifies a pixel of the painted map into the broad ground types that matter
## for planting. Tuned for this game's saturated painted art: water is blue-
## dominant, grass green-dominant, roads a warm desaturated tan.
static func classify_terrain(c: Color) -> String:
	if c.b > c.r and c.b > c.g * 1.05 and c.b > 0.35:
		return "water"
	if c.g > c.r and c.g > c.b:
		return "grass"
	if c.r > 0.55 and c.g > 0.45 and c.b < 0.55:
		return "road"
	return "other"

## True when a world point is plantable under the given terrain rules.
static func terrain_allows(rules: Dictionary, world_pos: Vector2) -> bool:
	if rules.is_empty():
		return true
	var img: Image = rules["image"]
	var sc: Vector2 = rules["scale"]
	if sc.x == 0.0 or sc.y == 0.0:
		return true
	var t: Vector2 = (world_pos - Vector2(rules["offset"])) / sc
	var x := int(t.x)
	var y := int(t.y)
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return false     # off-map is never plantable
	var kind := classify_terrain(img.get_pixel(x, y))
	if bool(rules["avoid_water"]) and kind == "water":
		return false
	if bool(rules["avoid_roads"]) and kind == "road":
		return false
	return true

func _ready() -> void:
	y_sort_enabled = true   # children sort individually against the player
	_refresh()

func _refresh() -> void:
	if not is_inside_tree():
		return
	for c in get_children():
		c.queue_free()
	if not enabled:
		return
	for p in build_props(region, prop_names, weights, count, scatter_seed,
			scale_jitter, random_flip, avoid_rects, min_spacing, _terrain_rules()):
		add_child(p)

## Builds the StaticProp nodes for a scatter. Kept separate from _refresh so a
## caller (or a test) can get nodes without mounting a scene.
static func build_props(p_region: Rect2, names: PackedStringArray, p_weights: PackedFloat32Array,
		p_count: int, p_seed: int, jitter: float, flip: bool,
		avoid: Array[Rect2], spacing: float, terrain: Dictionary = {}) -> Array:
	var out: Array = []
	for pl in compute_placements(p_region, names, p_weights, p_count, p_seed, jitter, flip, avoid, spacing, terrain):
		out.append(StaticProp.create(pl["name"], pl["position"], pl["height"], pl["flip_h"]))
	return out

## Pure placement solver — the testable core.
##
## Returns an array of { name, position, height, flip_h }. Positions are the
## props' FOOT points, in this node's local space. May return fewer than
## `p_count` entries when spacing and keep-out rects leave no room; that is
## intentional — a thinner copse beats props stacked on each other or standing
## in the river.
static func compute_placements(p_region: Rect2, names: PackedStringArray, p_weights: PackedFloat32Array,
		p_count: int, p_seed: int, jitter: float, flip: bool,
		avoid: Array[Rect2], spacing: float, terrain: Dictionary = {}) -> Array:
	var out: Array = []
	if names.is_empty() or p_count <= 0 or p_region.size.x <= 0.0 or p_region.size.y <= 0.0:
		return out

	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed

	var valid: PackedStringArray = PackedStringArray()
	var valid_w: PackedFloat32Array = PackedFloat32Array()
	for i in names.size():
		var n := names[i]
		if PropLibrary.has_prop(n):
			valid.append(n)
			valid_w.append(p_weights[i] if i < p_weights.size() else 1.0)
	if valid.is_empty():
		return out

	var total_w := 0.0
	for w in valid_w:
		total_w += maxf(0.0, w)
	if total_w <= 0.0:
		return out

	var placed: Array[Vector2] = []
	# Bounded attempts: enough retries to fill a sparse region without spinning
	# forever on one that is essentially full.
	var attempts := p_count * 24
	while out.size() < p_count and attempts > 0:
		attempts -= 1
		var pos := Vector2(
			rng.randf_range(p_region.position.x, p_region.position.x + p_region.size.x),
			rng.randf_range(p_region.position.y, p_region.position.y + p_region.size.y))

		var blocked := false
		for r in avoid:
			if r.has_point(pos):
				blocked = true
				break
		if blocked:
			continue

		if not terrain_allows(terrain, pos):
			continue

		if spacing > 0.0:
			var too_close := false
			for q in placed:
				if q.distance_to(pos) < spacing:
					too_close = true
					break
			if too_close:
				continue

		# Weighted pick.
		var roll := rng.randf() * total_w
		var pick := valid[valid.size() - 1]
		var acc := 0.0
		for i in valid.size():
			acc += maxf(0.0, valid_w[i])
			if roll <= acc:
				pick = valid[i]
				break

		var h := PropLibrary.height_for(pick)
		if jitter > 0.0:
			h *= 1.0 + rng.randf_range(-jitter, jitter)

		out.append({
			"name": pick,
			"position": pos,
			"height": h,
			"flip_h": flip and rng.randf() < 0.5,
		})
		placed.append(pos)

	return out
