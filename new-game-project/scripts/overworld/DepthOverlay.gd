@tool
class_name DepthOverlay
extends Polygon2D

## DepthOverlay — makes the player walk BEHIND map structures (P7p2).
##
## The overworld map is one flat image, so the player always drew on top of it.
## This node lifts the building's pixels and re-draws them above the player when
## the player is behind it.
##
## DEPTH (who's on top): a per-frame toggle, NOT Y-sort. Nested Y-sort with an
## offset child sprite proved too fragile (the sprite kept sorting by its crown
## instead of its foot, so the player drew in front). Instead the baked cutout sits
## at a higher z_index and is simply SHOWN only while the player is ABOVE the
## structure's foot baseline (i.e. behind it) and HIDDEN otherwise — when hidden the
## flat base map already shows the building with the player on top. Robust and
## independent of scene-tree nesting / sort order.
##
## GAME rendering: at load it BAKES a cutout image — the map's pixels inside the
## polygon copied into a transparent RGBA image (everything outside the polygon is
## transparent) — and shows it with a plain child Sprite2D. A static image blit is
## always pixel-correct, so there are no UV / triangulation / clip-buffer GPU
## artifacts (earlier textured-polygon and clip approaches smeared into vertical
## bands on some renderers). The cutout uses NEAREST filtering so the hard alpha
## edge doesn't blend into the transparent-black border and leave a grey halo.
##
## EDITOR preview (@tool): the streaky built-in translucent fill is hidden and a
## clean de-intersected wash + outline is drawn instead, so you can trace over the
## map. Author like a CollisionPolygon2D — sloppy / self-crossing traces are fine,
## they're cleaned at runtime.

@export var map_image_path: NodePath = NodePath("../../MapImage")
var _cutout: Sprite2D
# World-space Y of the structure's foot. The player is "behind" (and the cutout is
# shown over them) only while its Y is above this line.
var _foot_y: float = 0.0
# The node whose Y decides depth (the player). Set by OverworldScene after setup().
var _depth_target: Node2D = null

func _ready() -> void:
	if Engine.is_editor_hint():
		color.a = 0.0   # hide the streaky built-in fill; _draw shows a clean preview
		queue_redraw()
		return
	setup(_resolve_map())

# Finds the map sprite. The exported relative path works for an overlay that's a
# direct child of DepthOverlays, but breaks for one nested a level deeper (e.g.
# under a "Tree_Overlays" group), where "../../MapImage" points at the wrong place
# and resolves to nothing — which silently disabled every grouped tree overlay.
# Fall back to finding "MapImage" from the scene root, so overlays work at ANY
# nesting depth.
func _resolve_map() -> Sprite2D:
	var m := get_node_or_null(map_image_path) as Sprite2D
	if m != null:
		return m
	if owner != null:
		m = owner.get_node_or_null("MapImage") as Sprite2D
	return m

# OverworldScene calls this with the player so the overlay knows whose depth to
# track. Until it's set, the cutout stays hidden (player is treated as in front).
func track_depth(node: Node2D) -> void:
	_depth_target = node
	_update_depth()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		color.a = 0.0
		queue_redraw()
		return
	_update_depth()

# Show the lifted building pixels over the player only when the player is behind
# the structure (above its foot baseline); otherwise the flat map shows it, player
# on top.
func _update_depth() -> void:
	if _cutout == null or _depth_target == null:
		return
	_cutout.visible = _depth_target.global_position.y < _foot_y

func _draw() -> void:
	if not Engine.is_editor_hint() or polygon.size() < 3:
		return
	var clean := _clean_polygon(polygon)
	if clean.size() < 3:
		clean = polygon
	if Geometry2D.triangulate_polygon(clean).size() > 0:
		draw_colored_polygon(clean, Color(0.3, 0.8, 1.0, 0.28))
	var n := clean.size()
	for i in n:
		draw_line(clean[i], clean[(i + 1) % n], Color(0.3, 0.8, 1.0, 0.95), 3.0)

func setup(map: Sprite2D) -> void:
	if map == null or map.texture == null or polygon.size() < 3:
		visible = false
		return
	var src := map.texture.get_image()
	if src == null:
		visible = false
		return

	# World-space polygon, self-intersections resolved.
	var world := PackedVector2Array()
	for v in polygon:
		world.append(to_global(v))
	world = _clean_polygon(world)
	if world.size() < 3:
		visible = false
		return

	# Convert the polygon to the map's TEXTURE-pixel space via the map's own
	# transform (map.to_local) — this accounts for the MapImage being scaled, so 1
	# world unit may be several texture pixels (or a fraction). Sampling in raw
	# world units here was the bug that smeared the cutout into vertical bands.
	var texpoly := PackedVector2Array()
	for w in world:
		texpoly.append(map.to_local(w))
	var tbb := Rect2(texpoly[0], Vector2.ZERO)
	for p in texpoly:
		tbb = tbb.expand(p)
	var tex_rect := Rect2i(
		int(floor(tbb.position.x)), int(floor(tbb.position.y)),
		int(ceil(tbb.size.x)) + 1, int(ceil(tbb.size.y)) + 1)
	tex_rect = tex_rect.intersection(Rect2i(0, 0, src.get_width(), src.get_height()))
	if tex_rect.size.x <= 0 or tex_rect.size.y <= 0:
		visible = false
		return

	# Bake the cutout in texture space: copy inside-polygon pixels into a transparent
	# image, span by span (scanline) — fast and exact.
	var region := src.get_region(tex_rect)
	region.convert(Image.FORMAT_RGBA8)
	var w := region.get_width()
	var h := region.get_height()
	var cut := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rp := PackedVector2Array()
	for p in texpoly:
		rp.append(p - Vector2(tex_rect.position))
	for y in h:
		for span in _row_spans(rp, float(y) + 0.5, w):
			var sw: int = span.y - span.x
			if sw > 0:
				cut.blit_rect(region, Rect2i(span.x, y, sw, 1), Vector2i(span.x, y))

	# World bbox -> foot baseline (max Y) = the depth threshold for this structure.
	var wbb := Rect2(world[0], Vector2.ZERO)
	for ww in world:
		wbb = wbb.expand(ww)
	_foot_y = wbb.end.y

	visible = true
	transform = Transform2D.IDENTITY
	global_position = Vector2.ZERO
	color.a = 0.0                              # hide the Polygon2D's own fill in-game

	if _cutout == null or not is_instance_valid(_cutout):
		_cutout = Sprite2D.new()
		add_child(_cutout)
	_cutout.centered = false
	_cutout.texture = ImageTexture.create_from_image(cut)
	# NEAREST: the cutout has a hard alpha edge. With linear filtering the GPU blends
	# the opaque edge texels against the transparent-black border, which paints a
	# grey halo tracing the polygon. Nearest samples one texel, so no halo — and the
	# cutout pixels line up 1:1 with the map underneath, so it stays seamless.
	_cutout.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Sit above the player (z 0) / map (z -1) so that, WHEN SHOWN, the lifted pixels
	# cover the player; visibility (not sort order) is what gates the depth effect.
	_cutout.z_as_relative = false
	_cutout.z_index = 1
	# Draw the lifted texture region at the map's scale/position so it overlays the
	# map exactly.
	_cutout.scale = map.global_scale
	_cutout.global_position = map.to_global(Vector2(tex_rect.position))
	# Start hidden; _update_depth() reveals it once a depth target is tracked and the
	# player is actually behind the structure.
	_cutout.visible = false
	_update_depth()

# Even-odd scanline spans (x ranges inside the polygon) for one pixel row.
func _row_spans(poly: PackedVector2Array, yf: float, width: int) -> Array:
	var xs: Array[float] = []
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		if (a.y <= yf and b.y > yf) or (b.y <= yf and a.y > yf):
			xs.append(a.x + (yf - a.y) / (b.y - a.y) * (b.x - a.x))
	xs.sort()
	var spans: Array = []
	var i := 0
	while i + 1 < xs.size():
		var x0 := clampi(int(floor(xs[i])), 0, width)
		var x1 := clampi(int(ceil(xs[i + 1])), 0, width)
		if x1 > x0:
			spans.append(Vector2i(x0, x1))
		i += 2
	return spans

# Largest simple polygon covering a (possibly self-intersecting) one.
func _clean_polygon(pts: PackedVector2Array) -> PackedVector2Array:
	var pieces := Geometry2D.merge_polygons(pts, pts)
	var best := PackedVector2Array()
	var best_area := -1.0
	for p in pieces:
		var a := absf(_signed_area(p))
		if a > best_area:
			best_area = a
			best = p
	return best if best.size() >= 3 else pts

func _signed_area(p: PackedVector2Array) -> float:
	var s := 0.0
	var n := p.size()
	for i in n:
		var a := p[i]
		var b := p[(i + 1) % n]
		s += a.x * b.y - b.x * a.y
	return s * 0.5
