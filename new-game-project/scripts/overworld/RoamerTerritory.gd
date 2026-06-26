class_name RoamerTerritory
extends Area2D

## RoamerTerritory — a drawable roaming-enemy territory (P7p2). Add one under the
## overworld's RoamerTerritories node, give it a CollisionPolygon2D child, and draw
## any shape over the map; one roamer spawns inside it and wanders/chases only
## within that polygon. Set `group` to pin a specific encounter (e.g. a boss);
## leave it null for a weighted pick from the area's encounter_groups. A non-null
## group must also be listed in the area's encounter_groups (weight 0 is fine) so
## the roamer can be persisted across battles.
##
## The polygon is editor-only data — this Area2D does no physics (layers zeroed,
## monitoring off), so it never blocks or detects anything in-game.

@export var group: EncounterGroup = null

func _ready() -> void:
	# Inert: the polygon is read by OverworldScene, not the physics engine.
	monitoring = false
	monitorable = false
	collision_layer = 0
	collision_mask = 0

# World-space polygon points from the first CollisionPolygon2D child.
func world_polygon() -> PackedVector2Array:
	for c in get_children():
		if c is CollisionPolygon2D:
			var cp := c as CollisionPolygon2D
			var xf := cp.global_transform
			var out := PackedVector2Array()
			for p in cp.polygon:
				out.append(xf * p)
			return out
	return PackedVector2Array()

static func centroid(poly: PackedVector2Array) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for p in poly:
		sum += p
	return sum / float(poly.size())

static func bounding_rect(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r
