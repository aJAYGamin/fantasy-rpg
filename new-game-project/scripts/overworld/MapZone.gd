class_name MapZone
extends Area2D

## MapZone — a drawable overworld zone (P7p2). Add it as a child of an overworld
## scene, give it a CollisionPolygon2D child, and draw the polygon over a map
## feature (a town, the mountain gate, a castle entrance, a river crossing…). The
## zone fires when the PLAYER walks into it. Capabilities are independent flags so a
## single zone can do several things (a town both auto-saves AND is an entrance):
##
##  - save_on_enter   : auto-save the game on entry (towns / sanctuaries)
##  - suppress_spawns : roaming enemies won't spawn inside this zone
##  - target_scene≠"" : a TRANSITION — fade out and load target_scene at target_spawn
##  - return_to_origin: a transition that sends the player back to wherever they last
##                      entered from (used by shared interiors like the town placeholder
##                      so one interior can serve several towns and exit to the right one)
##
## Irregular shapes: use a CollisionPolygon2D and click the outline; OverworldScene
## detects entry via Area2D body_entered, so any polygon works (not just rectangles).

@export var label: String = ""
@export var save_on_enter: bool = false
@export var suppress_spawns: bool = false
@export_file("*.tscn") var target_scene: String = ""
@export var target_spawn: Vector2 = Vector2.ZERO
@export var return_to_origin: bool = false

func is_transition() -> bool:
	return return_to_origin or target_scene != ""

# World-space polygon points from the first CollisionPolygon2D child (for the debug
# overlay + point tests). Returns empty if there's no polygon child.
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

# True if a world-space point is inside this zone's polygon.
func contains_point(world_p: Vector2) -> bool:
	var poly := world_polygon()
	if poly.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(world_p, poly)
