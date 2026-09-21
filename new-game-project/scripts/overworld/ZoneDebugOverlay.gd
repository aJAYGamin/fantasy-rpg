class_name ZoneDebugOverlay
extends Node2D

## A toggleable debug visualization of overworld zones (P7p2). OverworldScene
## creates one and flips it on/off with F3. Draws every MapZone's polygon (cyan =
## transition, green = save/other), terrain-collision polygons (red), each roamer
## territory (orange), and the area's default spawn (magenta cross) so coordinates
## can be calibrated by eye in-game.

var zones: Array = []           # Array[MapZone]
var roamer_homes: Array = []    # Array[PackedVector2Array] (territory polygons, world space)
var collision_polys: Array = [] # Array[PackedVector2Array] (world space)
var default_spawn: Vector2 = Vector2.ZERO
var has_spawn: bool = false

func refresh(z: Array, homes: Array, terrain: Array, spawn: Vector2, show_spawn: bool) -> void:
	zones = z
	roamer_homes = homes
	collision_polys = terrain
	default_spawn = spawn
	has_spawn = show_spawn
	queue_redraw()

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font

	# Terrain collision (red polygons).
	for poly in collision_polys:
		var pts: PackedVector2Array = poly
		if pts.size() < 3:
			continue
		draw_colored_polygon(pts, Color(1.0, 0.15, 0.15, 0.25))
		var n := pts.size()
		for i in n:
			draw_line(pts[i], pts[(i + 1) % n], Color(1.0, 0.2, 0.2, 0.9), 3.0)

	# Roamer territories (orange polygons).
	for r in roamer_homes:
		var tpoly: PackedVector2Array = r
		if tpoly.size() < 3:
			continue
		draw_colored_polygon(tpoly, Color(1.0, 0.6, 0.1, 0.12))
		var tn := tpoly.size()
		for i in tn:
			draw_line(tpoly[i], tpoly[(i + 1) % tn], Color(1.0, 0.6, 0.1, 0.85), 3.0)
		if font:
			draw_string(font, _centroid(tpoly), "roamer", HORIZONTAL_ALIGNMENT_CENTER, -1, 24, Color(1, 0.7, 0.25))

	# Map zones (polygon fill + outline + tag).
	for z in zones:
		if z == null or not is_instance_valid(z):
			continue
		var poly: PackedVector2Array = z.world_polygon()
		if poly.size() < 3:
			continue
		var col := Color(0.3, 0.8, 1.0) if z.is_transition() else Color(0.4, 1.0, 0.4)
		draw_colored_polygon(poly, Color(col.r, col.g, col.b, 0.15))
		var n := poly.size()
		for i in n:
			draw_line(poly[i], poly[(i + 1) % n], col, 3.0)
		if font:
			var tag: String = z.label
			if z.save_on_enter: tag += " [save]"
			if z.suppress_spawns: tag += " [no-spawn]"
			draw_string(font, _centroid(poly), tag, HORIZONTAL_ALIGNMENT_CENTER, -1, 26, col)

	# Default spawn marker (magenta cross).
	if has_spawn:
		var s := default_spawn
		var m := Color(1.0, 0.2, 1.0)
		draw_line(s - Vector2(24, 0), s + Vector2(24, 0), m, 3.0)
		draw_line(s - Vector2(0, 24), s + Vector2(0, 24), m, 3.0)
		if font:
			draw_string(font, s + Vector2(0, -28), "spawn", HORIZONTAL_ALIGNMENT_CENTER, -1, 22, m)

func _centroid(poly: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in poly:
		sum += p
	return sum / float(poly.size())
