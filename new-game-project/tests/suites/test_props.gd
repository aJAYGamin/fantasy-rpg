extends TestSuite

## Overworld prop system: PropLibrary registry, PropShadow caching,
## StaticProp foot-anchoring math, and the PropScatter placement solver.

func suite_name() -> String:
	return "props"

# ---------------------------------------------------------------- PropLibrary

func test_library_lookup() -> void:
	assert_true(PropLibrary.has_prop("tree_oak"), "tree_oak is registered")
	assert_false(PropLibrary.has_prop("tree_banana"), "unknown prop is not registered")
	assert_eq(PropLibrary.path_for("tree_oak"),
		"res://assets/props/static/tree_oak.png", "path built from PROP_DIR + file")
	assert_eq(PropLibrary.path_for("nope"), "", "unknown prop yields an empty path")
	assert_eq(PropLibrary.height_for("nope"), 0.0, "unknown prop yields zero height")
	assert_eq(PropLibrary.category_for("tree_oak"), "tree", "oak is categorised as a tree")

func test_library_every_file_exists() -> void:
	# Guards against a rename in assets/ silently breaking a prop.
	for n in PropLibrary.names():
		var p := PropLibrary.path_for(n)
		assert_true(ResourceLoader.exists(p), "art exists on disk for '%s'" % n)

func test_library_heights_are_sane() -> void:
	# Heights are world units; every prop needs a positive one or StaticProp
	# would fall back to the raw 512px art and tower over the map.
	for n in PropLibrary.names():
		var h := PropLibrary.height_for(n)
		assert_true(h > 0.0 and h < 400.0, "'%s' has a sane height (%.1f)" % [n, h])

func test_library_categories() -> void:
	var trees := PropLibrary.names_in_category("tree")
	assert_true(trees.size() >= 8, "at least 8 trees registered")
	assert_true(trees.has("tree_pine"), "pine is in the tree category")
	assert_false(trees.has("bush"), "bush is not a tree")
	assert_true(PropLibrary.names_in_category("nonexistent").is_empty(),
		"unknown category returns nothing")

func test_library_has_all_seven_batches() -> void:
	# One name per generated prop; a missing entry means art landed in assets/
	# but never got registered, so it can never be placed.
	assert_eq(PropLibrary.names().size(), 70, "all seven batches registered")
	for n in ["tree_oak", "flowers_pink", "well", "forge",
			"shield", "portcullis", "pedestal"]:
		assert_true(PropLibrary.has_prop(n), "'%s' is registered" % n)

func test_library_files_are_unique() -> void:
	# Two names pointing at one file means a copy-paste slip in DEFS, and one
	# prop would silently render as another.
	var seen := {}
	for n in PropLibrary.names():
		var f := PropLibrary.path_for(n)
		assert_false(seen.has(f), "'%s' has its own art (not shared with '%s')" % [n, seen.get(f, "")])
		seen[f] = n

func test_batch_five_to_seven_categories() -> void:
	assert_eq(PropLibrary.names_in_category("dungeon").size(), 9, "dungeon set registered")
	assert_eq(PropLibrary.names_in_category("arcane").size(), 9, "arcane set registered")
	assert_eq(PropLibrary.names_in_category("furniture").size(), 7, "furniture set registered")
	assert_eq(PropLibrary.names_in_category("container").size(), 4, "container set registered")
	assert_eq(PropLibrary.names_in_category("wares").size(), 3, "shop wares registered")
	assert_eq(PropLibrary.names_in_category("decor").size(), 2, "town decor registered")
	# The signature element of the game gets its own prop.
	assert_true(PropLibrary.names_in_category("arcane").has("amethyst_cluster"),
		"amethyst cluster is arcane")

func test_light_props_registered() -> void:
	# These nine are the Sprite Motion inputs; each also drives a PointLight2D.
	var lights := PropLibrary.names_in_category("light")
	assert_eq(lights.size(), 9, "all nine fire/light props registered")
	for n in ["candle", "torch_wall", "campfire", "brazier", "lamp_post",
			"fireplace", "lantern_hanging", "forge", "cauldron"]:
		assert_true(lights.has(n), "'%s' is a light prop" % n)

func test_structure_and_rock_categories() -> void:
	assert_true(PropLibrary.names_in_category("rock").has("rock_boulders"), "boulders are rock")
	assert_true(PropLibrary.names_in_category("structure").has("well"), "well is a structure")
	assert_true(PropLibrary.names_in_category("debris").has("stump"), "stump is debris")
	assert_true(PropLibrary.height_for("rock_small") < PropLibrary.height_for("rock_boulders"),
		"a single rock is smaller than a boulder cluster")

func test_trees_are_taller_than_ground_cover() -> void:
	# The art arrives all ~430px regardless of subject, so the library is the
	# only thing preventing daisies rendering as tall as oaks.
	var min_tree := 9999.0
	for n in PropLibrary.names_in_category("tree"):
		if n == "tree_sapling":
			continue   # deliberately small
		min_tree = minf(min_tree, PropLibrary.height_for(n))
	for n in PropLibrary.names_in_category("flower"):
		assert_true(PropLibrary.height_for(n) < min_tree,
			"'%s' is shorter than every full-grown tree" % n)

# ---------------------------------------------------------------- PropShadow

func test_shadow_texture_is_cached_and_soft() -> void:
	PropShadow.clear_cache()
	var a := PropShadow.texture()
	assert_true(a != null, "shadow texture builds")
	assert_eq(a.get_width(), PropShadow.TEX_SIZE, "shadow is TEX_SIZE wide")
	var b := PropShadow.texture()
	assert_true(a == b, "second call returns the cached instance, not a rebuild")

	var img := a.get_image()
	var c := int(PropShadow.TEX_SIZE / 2)
	assert_true(img.get_pixel(c, c).a > 0.9, "centre is opaque")
	assert_true(img.get_pixel(0, 0).a < 0.05, "corner is transparent")
	assert_true(img.get_pixel(c, int(c * 0.5)).a < img.get_pixel(c, c).a,
		"alpha falls off from the centre outward")

# ---------------------------------------------------------------- StaticProp

func test_static_prop_anchors_at_its_foot() -> void:
	# The art is 512x512; the prop must end up library-height and standing ON
	# the node origin, because that origin is what the scene's y-sort compares
	# against the player to decide walk-in-front vs walk-behind.
	var tex := Vector2(512, 512)
	var lay := StaticProp.layout(tex, "tree_oak")
	var h := PropLibrary.height_for("tree_oak")
	assert_near(lay["height"], h, 0.01, "scaled to the library height")
	assert_near(lay["scale"], h / 512.0, 0.0001, "scale derived from texture height")
	# offset.y + rendered height == 0 means the bottom edge rests on the origin.
	assert_near(lay["offset"].y + lay["height"], 0.0, 0.01, "bottom edge rests on the foot")
	assert_near(lay["offset"].x + lay["width"] * 0.5, 0.0, 0.01, "horizontally centred on the foot")

func test_static_prop_height_override() -> void:
	var lay := StaticProp.layout(Vector2(512, 512), "tree_oak", 60.0)
	assert_near(lay["height"], 60.0, 0.01, "override wins over the library default")
	assert_near(lay["width"], 60.0, 0.01, "square art stays square after scaling")

func test_static_prop_layout_handles_unknown_name() -> void:
	# A typo in a scene must not produce a zero-scale or divide-by-zero prop.
	var lay := StaticProp.layout(Vector2(512, 512), "tree_banana")
	assert_near(lay["height"], 512.0, 0.01, "unknown prop falls back to native size")
	assert_near(lay["scale"], 1.0, 0.0001, "fallback scale is 1:1")
	var degenerate := StaticProp.layout(Vector2(0, 0), "tree_oak")
	assert_eq(degenerate["scale"], 0.0, "zero-sized texture yields zero scale, not a crash")

func test_static_prop_non_square_art() -> void:
	# Trimmed/rectangular art must keep its aspect ratio.
	var lay := StaticProp.layout(Vector2(256, 512), "tree_oak")
	var h := PropLibrary.height_for("tree_oak")
	assert_near(lay["width"], h * 0.5, 0.01, "aspect ratio preserved")

func test_static_prop_shadow_is_a_flat_ellipse() -> void:
	var sz := StaticProp.shadow_size(100.0, 0.72, 0.30)
	assert_near(sz.x, 72.0, 0.01, "shadow width is the configured fraction")
	assert_near(sz.y, 21.6, 0.01, "shadow height is flattened from its width")
	assert_true(sz.y < sz.x, "shadow reads as ground contact, not a ball")

# ---------------------------------------------------------------- PropScatter

func _names() -> PackedStringArray:
	return PackedStringArray(["tree_oak", "tree_pine", "bush"])

func test_scatter_is_deterministic() -> void:
	var r := Rect2(0, 0, 1000, 800)
	var a := PropScatter.compute_placements(r, _names(), PackedFloat32Array(), 12, 7, 0.1, true, [], 0.0)
	var b := PropScatter.compute_placements(r, _names(), PackedFloat32Array(), 12, 7, 0.1, true, [], 0.0)
	assert_eq(a.size(), b.size(), "same seed yields the same count")
	for i in a.size():
		assert_eq(a[i]["position"], b[i]["position"], "placement %d is reproducible" % i)
		assert_eq(a[i]["name"], b[i]["name"], "prop choice %d is reproducible" % i)

	var c := PropScatter.compute_placements(r, _names(), PackedFloat32Array(), 12, 8, 0.1, true, [], 0.0)
	var same := true
	for i in mini(a.size(), c.size()):
		if a[i]["position"] != c[i]["position"]:
			same = false
			break
	assert_false(same, "a different seed rerolls the arrangement")

func test_scatter_stays_inside_region() -> void:
	var r := Rect2(100, 50, 400, 300)
	for pl in PropScatter.compute_placements(r, _names(), PackedFloat32Array(), 30, 3, 0.0, false, [], 0.0):
		var p: Vector2 = pl["position"]
		assert_true(p.x >= r.position.x and p.x <= r.position.x + r.size.x, "x inside region")
		assert_true(p.y >= r.position.y and p.y <= r.position.y + r.size.y, "y inside region")

func test_scatter_respects_keep_out() -> void:
	var r := Rect2(0, 0, 600, 600)
	var river: Array[Rect2] = [Rect2(200, 0, 200, 600)]
	var placements := PropScatter.compute_placements(r, _names(), PackedFloat32Array(), 40, 11, 0.0, false, river, 0.0)
	assert_true(placements.size() > 0, "still places props outside the keep-out")
	for pl in placements:
		assert_false(river[0].has_point(pl["position"]), "no prop stands in the river")

func test_scatter_honours_min_spacing() -> void:
	var r := Rect2(0, 0, 500, 500)
	var spacing := 60.0
	var placements := PropScatter.compute_placements(r, _names(), PackedFloat32Array(), 15, 5, 0.0, false, [], spacing)
	for i in placements.size():
		for j in range(i + 1, placements.size()):
			var d: float = (placements[i]["position"] as Vector2).distance_to(placements[j]["position"])
			assert_true(d >= spacing - 0.01, "props %d and %d are at least min_spacing apart" % [i, j])

func test_scatter_weights_bias_selection() -> void:
	var r := Rect2(0, 0, 2000, 2000)
	# Oak weighted 20x against two zero-weight props: everything should be oak.
	var names := PackedStringArray(["tree_oak", "tree_pine", "bush"])
	var w := PackedFloat32Array([20.0, 0.0, 0.0])
	var placements := PropScatter.compute_placements(r, names, w, 25, 2, 0.0, false, [], 0.0)
	assert_true(placements.size() > 0, "placed something")
	for pl in placements:
		assert_eq(pl["name"], "tree_oak", "zero-weight props are never chosen")

func test_scatter_applies_scale_jitter() -> void:
	var r := Rect2(0, 0, 1200, 1200)
	var base := PropLibrary.height_for("tree_oak")
	var names := PackedStringArray(["tree_oak"])
	var placements := PropScatter.compute_placements(r, names, PackedFloat32Array(), 20, 4, 0.2, false, [], 0.0)
	var varied := false
	for pl in placements:
		var h: float = pl["height"]
		assert_true(h >= base * 0.79 and h <= base * 1.21, "height stays within the jitter band")
		if absf(h - base) > 0.01:
			varied = true
	assert_true(varied, "jitter actually varies the sizes")

	var none := PropScatter.compute_placements(r, names, PackedFloat32Array(), 6, 4, 0.0, false, [], 0.0)
	for pl in none:
		assert_near(pl["height"], base, 0.01, "zero jitter uses the library height exactly")

func test_scatter_rejects_bad_input() -> void:
	var r := Rect2(0, 0, 500, 500)
	assert_eq(PropScatter.compute_placements(r, PackedStringArray(), PackedFloat32Array(), 10, 1, 0.0, false, [], 0.0).size(),
		0, "no names yields no placements")
	assert_eq(PropScatter.compute_placements(r, _names(), PackedFloat32Array(), 0, 1, 0.0, false, [], 0.0).size(),
		0, "zero count yields no placements")
	assert_eq(PropScatter.compute_placements(Rect2(0, 0, 0, 0), _names(), PackedFloat32Array(), 10, 1, 0.0, false, [], 0.0).size(),
		0, "empty region yields no placements")
	# Unknown names are filtered, not fatal.
	var mixed := PackedStringArray(["tree_banana", "tree_oak"])
	var placements := PropScatter.compute_placements(r, mixed, PackedFloat32Array(), 8, 1, 0.0, false, [], 0.0)
	assert_true(placements.size() > 0, "valid names still place")
	for pl in placements:
		assert_eq(pl["name"], "tree_oak", "unknown names are skipped")

func test_scatter_full_region_terminates() -> void:
	# Impossible spacing must bail out rather than spin forever.
	var placements := PropScatter.compute_placements(
		Rect2(0, 0, 100, 100), _names(), PackedFloat32Array(), 50, 9, 0.0, false, [], 500.0)
	assert_true(placements.size() <= 1, "over-constrained scatter places at most one prop")

# ------------------------------------------------- PropScatter: terrain rules

func test_classify_terrain() -> void:
	assert_eq(PropScatter.classify_terrain(Color(0.15, 0.45, 0.85)), "water", "blue reads as water")
	assert_eq(PropScatter.classify_terrain(Color(0.35, 0.65, 0.25)), "grass", "green reads as grass")
	assert_eq(PropScatter.classify_terrain(Color(0.85, 0.75, 0.45)), "road", "tan reads as road")

func _fake_terrain() -> Dictionary:
	# Left half water, right half grass — 1:1 world-to-texture mapping.
	var img := Image.create(100, 100, false, Image.FORMAT_RGBA8)
	for y in 100:
		for x in 100:
			img.set_pixel(x, y, Color(0.15, 0.45, 0.85) if x < 50 else Color(0.35, 0.65, 0.25))
	return {
		"image": img,
		"offset": Vector2.ZERO,
		"scale": Vector2.ONE,
		"avoid_water": true,
		"avoid_roads": true,
	}

func test_terrain_allows() -> void:
	var rules := _fake_terrain()
	assert_false(PropScatter.terrain_allows(rules, Vector2(10, 50)), "water is rejected")
	assert_true(PropScatter.terrain_allows(rules, Vector2(75, 50)), "grass is accepted")
	assert_false(PropScatter.terrain_allows(rules, Vector2(-5, 50)), "off-map is rejected")
	assert_false(PropScatter.terrain_allows(rules, Vector2(500, 50)), "beyond the map is rejected")
	assert_true(PropScatter.terrain_allows({}, Vector2(10, 50)),
		"no rules means no terrain filtering")

func test_terrain_offset_and_scale() -> void:
	var rules := _fake_terrain()
	rules["offset"] = Vector2(1000, 500)
	rules["scale"] = Vector2(2.0, 2.0)
	# World (1020,600) -> texture (10,50), which is water.
	assert_false(PropScatter.terrain_allows(rules, Vector2(1020, 600)), "offset+scale map to water")
	# World (1150,600) -> texture (75,50), which is grass.
	assert_true(PropScatter.terrain_allows(rules, Vector2(1150, 600)), "offset+scale map to grass")

func test_scatter_keeps_props_out_of_water() -> void:
	var rules := _fake_terrain()
	var names := PackedStringArray(["tree_oak"])
	var placements := PropScatter.compute_placements(
		Rect2(0, 0, 100, 100), names, PackedFloat32Array(), 30, 21, 0.0, false, [], 0.0, rules)
	assert_true(placements.size() > 0, "still plants on the grassy half")
	for pl in placements:
		assert_true((pl["position"] as Vector2).x >= 50.0, "every prop is on the grass side")

func test_scatter_builds_nodes() -> void:
	var r := Rect2(0, 0, 600, 400)
	var props := PropScatter.build_props(r, _names(), PackedFloat32Array(), 5, 6, 0.0, false, [], 0.0)
	assert_eq(props.size(), 5, "one node per placement")
	for p in props:
		assert_true(p is StaticProp, "produces StaticProp nodes")
		p.queue_free()
