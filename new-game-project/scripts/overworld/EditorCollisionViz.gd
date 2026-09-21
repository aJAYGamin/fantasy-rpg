@tool
class_name EditorCollisionViz
extends Node2D

## EDITOR-ONLY authoring aid (P7p2). Draws bright, thick outlines for every
## CollisionPolygon2D and rectangle CollisionShape2D in the open scene, so
## collision borders stay clearly visible while you trace/adjust other shapes
## over the busy map art. The stock editor gizmo is a faint semi-transparent
## wash that's hard to read against the map; this overdraws it boldly.
##
## Usage: add one of these nodes anywhere in the scene (Create Node ->
## EditorCollisionViz). Toggle it on/off with its EYE icon in the Scene dock.
## Tune the colors / width / fill in the Inspector. Color-coded by purpose:
##   • StaticBody2D collision (terrain walls/river/etc.) -> collision_color (red)
##   • Area2D shapes (MapZone entrances, RoamerTerritory) -> area_color (cyan)
##
## It draws ONLY in the editor (guarded by Engine.is_editor_hint) and is a
## completely inert, invisible empty node in the running game.

@export var width: float = 5.0
@export var collision_color: Color = Color(1.0, 0.15, 0.15, 0.95)   # terrain collision
@export var area_color: Color = Color(0.1, 0.9, 1.0, 0.95)          # zones / territories
@export var fill_alpha: float = 0.10
## Flip this in the Inspector if a redraw ever looks stale.
@export var redraw_now: bool = false:
	set(_v):
		queue_redraw()

func _process(_delta: float) -> void:
	# Keep the outlines synced as you drag points (editor only).
	if Engine.is_editor_hint():
		queue_redraw()

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var root: Node = get_tree().edited_scene_root if get_tree() else null
	if root == null:
		return
	_walk(root)

func _walk(node: Node) -> void:
	if node is CollisionPolygon2D:
		_draw_poly(node as CollisionPolygon2D)
	elif node is CollisionShape2D and (node as CollisionShape2D).shape is RectangleShape2D:
		_draw_rect(node as CollisionShape2D)
	for c in node.get_children():
		_walk(c)

func _color_for(n: Node2D) -> Color:
	return area_color if n.get_parent() is Area2D else collision_color

func _draw_poly(cp: CollisionPolygon2D) -> void:
	if cp.polygon.size() < 2:
		return
	var pts := PackedVector2Array()
	for v in cp.polygon:
		pts.append(to_local(cp.global_transform * v))
	var col := _color_for(cp)
	# Fill only convex/simple polygons — many hand-traced collision shapes are
	# self-intersecting (fine for collision, but draw_colored_polygon can't
	# triangulate them). Outlines always draw, which is what matters for editing.
	if pts.size() >= 3 and fill_alpha > 0.0 and Geometry2D.triangulate_polygon(pts).size() > 0:
		draw_colored_polygon(pts, Color(col.r, col.g, col.b, fill_alpha))
	var n := pts.size()
	for i in n:
		draw_line(pts[i], pts[(i + 1) % n], col, width)

func _draw_rect(cs: CollisionShape2D) -> void:
	var sz := (cs.shape as RectangleShape2D).size * 0.5
	var corners := PackedVector2Array([
		Vector2(-sz.x, -sz.y), Vector2(sz.x, -sz.y), Vector2(sz.x, sz.y), Vector2(-sz.x, sz.y)])
	var pts := PackedVector2Array()
	for v in corners:
		pts.append(to_local(cs.global_transform * v))
	for i in 4:
		draw_line(pts[i], pts[(i + 1) % 4], collision_color, width)
