extends TestSuite

## DepthOverlay (P7p2): walk-behind-buildings depth. The overlay bakes a cutout
## IMAGE of the map inside its polygon (transparent outside) and shows it with a
## plain Sprite2D — robust against GPU UV/clip artifacts. Tests cover the bake,
## the map-transform/scale handling (the bug that smeared it when the map sprite
## was scaled), baseline re-anchor, self-intersection cleanup, and the guards.

const OverworldSceneScript := preload("res://scripts/overworld/OverworldScene.gd")

func suite_name() -> String:
	return "DepthOverlay"

func _fake_map(pos: Vector2, sz: int, scl: Vector2) -> Sprite2D:
	var map := Sprite2D.new()
	map.centered = false
	map.position = pos
	map.scale = scl
	var img := Image.create(sz, sz, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.6, 0.3))
	map.texture = ImageTexture.create_from_image(img)
	return map

func _overlay(poly: PackedVector2Array, pos := Vector2.ZERO) -> DepthOverlay:
	var ov := DepthOverlay.new()
	ov.position = pos
	ov.polygon = poly
	return ov

func _cutout_of(ov: DepthOverlay) -> Sprite2D:
	for c in ov.get_children():
		if c is Sprite2D:
			return c
	return null

func _square(x: float, y: float, s: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x, y), Vector2(x + s, y), Vector2(x + s, y + s), Vector2(x, y + s)])

func test_bakes_clipped_cutout() -> void:
	var map := _fake_map(Vector2.ZERO, 512, Vector2.ONE)
	var ov := _overlay(_square(100, 100, 200))
	ov.setup(map)
	assert_true(ov.visible, "overlay visible after bake")
	var sp := _cutout_of(ov)
	assert_ne(sp, null, "a child Sprite2D holds the baked cutout")
	if sp != null:
		assert_ne(sp.texture, null, "cutout has a baked texture")
		assert_near(sp.global_position.x, 100.0, 2.0, "cutout placed at the region's world x")
		assert_near(sp.global_position.y, 100.0, 2.0, "cutout placed at the region's world y")
	ov.free()
	map.free()

func test_handles_scaled_map() -> void:
	# The actual bug: the MapImage is scaled, so world units != texture pixels.
	# Polygon world (200,200)-(400,400) over a 512² texture scaled x2 -> texture
	# region (100,100)-(200,200), well within bounds.
	var map := _fake_map(Vector2.ZERO, 512, Vector2(2, 2))
	var ov := _overlay(_square(200, 200, 200))
	ov.setup(map)
	assert_true(ov.visible, "scaled-map overlay still bakes (no off-texture sampling)")
	var sp := _cutout_of(ov)
	assert_ne(sp, null, "cutout created for scaled map")
	if sp != null:
		assert_near(sp.scale.x, 2.0, 0.01, "cutout drawn at the map's scale")
		assert_near(sp.global_position.x, 200.0, 3.0, "cutout placed at world x via map transform")
		assert_near(sp.global_position.y, 200.0, 3.0, "cutout placed at world y via map transform")
	ov.free()
	map.free()

func test_records_foot_baseline() -> void:
	var map := _fake_map(Vector2.ZERO, 512, Vector2.ONE)
	var ov := _overlay(PackedVector2Array([Vector2(100, 100), Vector2(300, 100), Vector2(200, 300)]))
	ov.setup(map)
	assert_near(ov._foot_y, 300.0, 2.0, "foot baseline (max Y) recorded as the depth threshold")
	ov.free()
	map.free()

func test_depth_toggle_shows_cutout_only_when_behind() -> void:
	var map := _fake_map(Vector2.ZERO, 512, Vector2.ONE)
	var ov := _overlay(_square(100, 100, 200))   # foot at y=300
	ov.setup(map)
	var sp := _cutout_of(ov)
	assert_ne(sp, null, "cutout exists")
	# No depth target yet -> treated as in front -> hidden.
	assert_false(sp.visible, "cutout hidden until a depth target is tracked")
	var target := Node2D.new()
	# Player above the foot (behind the structure) -> cutout shown over them.
	target.global_position = Vector2(150, 250)
	ov.track_depth(target)
	assert_true(sp.visible, "cutout shown while the player is above the foot (behind)")
	assert_eq(sp.z_index, 1, "cutout sits above the player when shown")
	assert_false(sp.z_as_relative, "cutout z_index is absolute")
	# Player below the foot (in front) -> hidden, base map shows the structure.
	target.global_position = Vector2(150, 360)
	ov._update_depth()
	assert_false(sp.visible, "cutout hidden once the player passes the foot (in front)")
	target.free()
	ov.free()
	map.free()

func test_cleans_self_intersecting() -> void:
	var map := _fake_map(Vector2.ZERO, 512, Vector2.ONE)
	# Bow-tie self-intersection.
	var ov := _overlay(PackedVector2Array([Vector2(100, 100), Vector2(300, 300), Vector2(300, 100), Vector2(100, 300)]))
	ov.setup(map)
	assert_true(ov.visible, "self-intersecting overlay still bakes a cutout")
	assert_ne(_cutout_of(ov), null, "cutout produced")
	ov.free()
	map.free()

func test_guards_hide_overlay() -> void:
	var ov := _overlay(_square(10, 10, 50))
	ov.setup(null)
	assert_false(ov.visible, "no map -> hidden")
	var blank := DepthOverlay.new()   # no polygon
	var map := _fake_map(Vector2.ZERO, 128, Vector2.ONE)
	blank.setup(map)
	assert_false(blank.visible, "no polygon -> hidden")
	ov.free()
	blank.free()
	map.free()

func test_offmap_polygon_hidden() -> void:
	# Polygon entirely outside the texture -> empty region -> hidden, not a crash.
	var map := _fake_map(Vector2.ZERO, 128, Vector2.ONE)
	var ov := _overlay(_square(900, 900, 100))
	ov.setup(map)
	assert_false(ov.visible, "polygon off the texture -> hidden")
	ov.free()
	map.free()

func test_ysort_skips_overlay_leaves() -> void:
	# The grouping containers must be Y-sorted, but each DepthOverlay leaf must NOT
	# be — a Y-sorted leaf flattens its cutout sprite into the scene sort by the
	# sprite's crown Y instead of the foot baseline, which drew the player in front
	# of trees.
	var scene: Node2D = OverworldSceneScript.new()
	var group := Node2D.new()         # DepthOverlays
	var subgroup := Node2D.new()      # Tree_Overlays
	var leaf := DepthOverlay.new()
	var sprite := Sprite2D.new()      # stand-in for the baked cutout child
	leaf.add_child(sprite)
	subgroup.add_child(leaf)
	group.add_child(subgroup)
	var town_leaf := DepthOverlay.new()
	group.add_child(town_leaf)

	scene._enable_ysort_recursive(group)

	assert_true(group.y_sort_enabled, "the DepthOverlays container is Y-sorted")
	assert_true(subgroup.y_sort_enabled, "a nested overlay group is Y-sorted")
	assert_false(leaf.y_sort_enabled, "a DepthOverlay leaf sorts as one unit at its foot, not Y-sorted")
	assert_false(town_leaf.y_sort_enabled, "a direct DepthOverlay leaf is not Y-sorted")
	assert_false(sprite.y_sort_enabled, "the leaf's cutout sprite is left out of Y-sort")

	group.free()
	scene.free()

func test_resolve_map_when_nested_under_group() -> void:
	# A tree overlay nested under a group can't reach the map via the relative
	# "../../MapImage" path; it must fall back to the scene root (the bug that
	# silently disabled every grouped tree overlay).
	var root := Node2D.new()
	var map := _fake_map(Vector2.ZERO, 256, Vector2.ONE)
	map.name = "MapImage"
	root.add_child(map)
	var depth := Node2D.new()
	depth.name = "DepthOverlays"
	root.add_child(depth)
	var group := Node2D.new()
	group.name = "Tree_Overlays"
	depth.add_child(group)
	var ov := _overlay(_square(50, 50, 100))
	group.add_child(ov)
	var ov2 := _overlay(_square(50, 50, 100))   # direct child, like the building overlays
	depth.add_child(ov2)
	for n in [map, depth, group, ov, ov2]:
		n.owner = root
	assert_eq(ov._resolve_map(), map, "nested overlay resolves MapImage from the scene root")
	assert_eq(ov2._resolve_map(), map, "direct-child overlay resolves MapImage via the relative path")
	root.free()

func test_plains_scene_depthoverlays_group() -> void:
	var scene: Node = (load("res://scenes/OverworldScene.tscn") as PackedScene).instantiate()
	var holder: Node = scene.get_node_or_null("DepthOverlays")
	assert_ne(holder, null, "plains scene has a DepthOverlays node")
	if holder != null:
		assert_true(holder.y_sort_enabled, "DepthOverlays participates in Y-sort")
	scene.free()

# The auto-save badge must render ABOVE the transition fade and outlive it.
func test_save_indicator_outlives_transition_fade() -> void:
	assert_true(OverworldSceneScript.SAVE_INDICATOR_LAYER > OverworldSceneScript.FADE_LAYER,
		"save indicator CanvasLayer sits above the fade layer")
	assert_true(SaveIndicator.HOLD_TIME >= OverworldSceneScript.FADE_TIME + 2.0,
		"saved badge holds for the fade plus at least 2 seconds")
