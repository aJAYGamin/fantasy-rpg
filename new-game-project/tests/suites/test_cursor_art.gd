extends TestSuite

func suite_name() -> String:
	return "CursorArt"

func test_the_catalogue_lists_ten_shapes_and_twenty_colours_in_order() -> void:
	assert_eq(CursorArt.SHAPES, ["A","B","K","L","S","AB","AK","AR","AS","AV"], "shape order")
	assert_eq(CursorArt.COLOURS.size(), 20, "twenty colours")
	assert_eq(CursorArt.COLOURS[0], "amethyst", "Amethyst first")
	assert_eq(CursorArt.COLOURS[19], "lunar", "Lunar last")
	assert_eq(CursorArt.shape_name("AK"), "Brilliant Diamond", "names")
	assert_eq(CursorArt.colour_name("obsidian"), "Obsidian", "colour names")

func test_every_shape_and_colour_has_a_name_and_the_defaults_exist() -> void:
	for shape in CursorArt.SHAPES:
		assert_true(CursorArt.shape_name(shape) != "", "%s has a name" % shape)
	for colour in CursorArt.COLOURS:
		assert_true(CursorArt.colour_name(colour) != "", "%s has a name" % colour)
	assert_true(CursorArt.is_known(CursorArt.DEFAULT_SHAPE, CursorArt.DEFAULT_COLOUR), "the defaults are in the catalogue")
	assert_eq(CursorArt.shape_name("A"), "Amethyst Arrow", "the default shape's name")

func test_swatches_match_the_art_files_colour_list() -> void:
	assert_eq(CursorArt.swatch("amethyst"), Color("#8C59F2"), "Amethyst dot")
	assert_eq(CursorArt.swatch("void"), Color("#24183F"), "Void dot")
	assert_eq(CursorArt.swatch("obsidian"), Color("#1A1A1F"), "Obsidian dot")
	assert_eq(CursorArt.swatch("lunar"), Color("#E6E9F2"), "Lunar dot")
	for colour in CursorArt.COLOURS:
		var wants_ring: bool = colour == "void" or colour == "obsidian"
		assert_eq(CursorArt.swatch_ring(colour), wants_ring, "%s ring only for the two dark dots" % colour)

func test_every_shape_renders_in_every_colour() -> void:
	for shape in CursorArt.SHAPES:
		for colour in CursorArt.COLOURS:
			var img := Image.new()
			var err := img.load_svg_from_string(CursorArt.svg(shape, colour), 1.0)
			assert_eq(err, OK, "%s in %s parses" % [shape, colour])
			assert_true(img.get_used_rect().size.x > 10, "%s in %s draws something" % [shape, colour])
			assert_false(CursorArt.svg(shape, colour).contains("var("), "no CSS variables left")
			assert_false(CursorArt.svg(shape, colour).contains("{"), "%s in %s has no unfilled token" % [shape, colour])

func test_the_document_is_the_art_viewbox_grown_by_the_glow_margin() -> void:
	# A's art viewBox is "-1 -1 21 29"; every side gains GLOW_MARGIN (10).
	var doc := CursorArt.svg("A", "amethyst")
	assert_true(doc.contains('viewBox="-11.0 -11.0 41.0 49.0"'), "A's grown viewBox")
	assert_true(doc.contains('width="41.0"') and doc.contains('height="49.0"'), "width/height are the grown size")
	assert_true(CursorArt.svg("AB", "amethyst").contains('viewBox="-11.0 -11.0 43.0 51.0"'), "AB's grown viewBox")
	var img := Image.new()
	img.load_svg_from_string(doc, 2.0)
	assert_eq(img.get_size(), Vector2i(82, 98), "rasterising at 2x gives size x 2")

func test_the_shared_dark_edge_is_translucent_not_a_css_variable() -> void:
	for shape in CursorArt.SHAPES:
		assert_true(CursorArt.svg(shape, "tidal").contains('stroke="#080510" stroke-opacity="0.85"'), "%s keeps the shared edge" % shape)

func test_the_hotspot_is_the_tip() -> void:
	assert_eq(CursorArt.hotspot("A"), Vector2(12.5, 12.5), "A's tip, inside the glow margin")
	assert_eq(CursorArt.hotspot("AB"), Vector2(13.5, 13.5), "AB's tip")
	# The tip pixel is opaque and the pixel up-left of it is clear.
	var img := CursorArt.image("A", "amethyst", 1.0)
	assert_true(img.get_pixelv(Vector2i(CursorArt.hotspot("A")) + Vector2i(1, 1)).a > 0.5, "drawn at the tip")
	assert_true(img.get_pixelv(Vector2i(CursorArt.hotspot("A")) - Vector2i(4, 4)).a < 0.1, "clear beyond it")

func test_every_shapes_hotspot_sits_on_the_drawn_tip() -> void:
	# Every symbol's tip is (1.5, 1.5) — (2.5, 2.5) for AB — so the hotspot is that
	# plus the padding the viewBox (min -1) and the glow margin add on the left/top.
	for shape in CursorArt.SHAPES:
		var tip := Vector2(2.5, 2.5) if shape == "AB" else Vector2(1.5, 1.5)
		assert_eq(CursorArt.hotspot(shape), tip + Vector2(1, 1) + Vector2(CursorArt.GLOW_MARGIN, CursorArt.GLOW_MARGIN), "%s hotspot" % shape)
		var img := Image.new()
		img.load_svg_from_string(CursorArt.svg(shape, "amethyst"), 1.0)
		var spot := Vector2i(CursorArt.hotspot(shape))
		assert_true(img.get_pixelv(spot + Vector2i(1, 1)).a > 0.5, "%s is drawn at its tip" % shape)
		assert_true(img.get_pixelv(spot - Vector2i(4, 4)).a < 0.1, "%s is clear up-left of its tip" % shape)

func test_ak_and_ar_use_the_deeper_cut_except_void_obsidian_lunar() -> void:
	assert_true(CursorArt.svg("AK", "amethyst").contains("#B48CFF"), "Amethyst AK centre is s2")
	assert_true(CursorArt.svg("AK", "void").contains("#6B55A0"), "Void AK keeps its s0 centre")
	assert_true(CursorArt.svg("AR", "venom").contains('stroke-width="3.8"'), "deeper AR has the heavier edge")
	assert_true(CursorArt.svg("AR", "lunar").contains('stroke-width="3"'), "Lunar AR keeps the original edge")
	assert_false(CursorArt.svg("AR", "lunar").contains('stroke-width="3.8"'), "Lunar AR is not the heavy edge")
	assert_true(CursorArt.svg("AR", "obsidian").contains('stroke-width="3"'), "Obsidian AR keeps the original edge")
	assert_true(CursorArt.svg("AK", "obsidian").contains("#8C8C99"), "Obsidian AK keeps its s0 centre")

func test_gradient_shapes_carry_their_own_literal_stops() -> void:
	# A fills with the day gradient (s2 -> s6 for Amethyst); AS with the night one.
	var arrow := CursorArt.svg("A", "amethyst")
	assert_true(arrow.contains("<linearGradient") and arrow.contains("#B48CFF") and arrow.contains("#4B2A99"), "A has its gradient stops")
	var starlit := CursorArt.svg("AS", "amethyst")
	assert_true(starlit.contains("<clipPath"), "AS keeps its clipPath")
	for stop in ["#6A3BC9", "#3A2860", "#140C24"]:
		assert_true(starlit.contains(stop), "AS night stop %s" % stop)
	# The gradients are literal per colour, not derived: Lunar's day gradient ends on s5.
	assert_true(CursorArt.svg("A", "lunar").contains("#9CA5BF"), "Lunar's literal gradient end")
	assert_true(CursorArt.svg("A", "obsidian").contains("#0A0A0D"), "Obsidian's literal gradient end")

func test_glow_colours() -> void:
	assert_eq(CursorArt.glow_colours("amethyst"), [Color("#B48CFF"), Color("#7E4FE0")], "s2 then s4")
	assert_eq(CursorArt.glow_colours("obsidian"), [Color("#D9D9E6"), Color("#8C8C99")], "rim glow")
	assert_eq(CursorArt.glow_colours("void"), [Color("#B48CFF"), Color("#8C59F2")], "Void glows in its rim colour")
	assert_eq(CursorArt.glow_colours("lunar"), [Color("#FFFFFF"), Color("#B9C0D4")], "Lunar glow")

func test_textures_are_cached_and_unknown_ids_are_refused() -> void:
	assert_true(CursorArt.texture("B", "tidal") == CursorArt.texture("B", "tidal"), "asking again for the same style gives the same texture")
	assert_false(CursorArt.texture("B", "tidal") == CursorArt.texture("B", "frost"), "a different colour is a different texture")
	assert_false(CursorArt.is_known("Z", "tidal"), "unknown shape")
	assert_false(CursorArt.is_known("A", "teal"), "unknown colour")
	assert_true(CursorArt.is_known("AV", "lunar"), "a real pair")
	assert_eq(CursorArt.svg("Z", "tidal"), "", "no document for an unknown shape")
	assert_eq(CursorArt.svg("A", "teal"), "", "no document for an unknown colour")
	assert_true(CursorArt.texture("Z", "tidal") == null, "no texture for an unknown shape")
	assert_true(CursorArt.image("Z", "tidal") == null, "and no image")

## A weak reference to a style's cursor texture, so nothing in the test keeps it alive.
func _weak_texture(shape: String, colour: String) -> WeakRef:
	return weakref(CursorArt.texture(shape, colour))

func test_only_the_style_in_use_stays_cached() -> void:
	# Stepping through the Mouse page's styles used to leave every one cached at 4x. A shape
	# other than the player's, so the live cursor isn't holding these textures itself.
	var shape := "L" if GameManager.settings.cursor_shape != "L" else "S"
	var first := _weak_texture(shape, "grove")
	assert_true(first.get_ref() != null, "the style asked for last is kept")
	_weak_texture(shape, "frost")
	assert_true(first.get_ref() == null, "and let go once another style is asked for")
	GameManager.virtual_cursor.refresh_style()   # leave the player's own style cached

func test_textures_are_rendered_at_the_art_size_times_scale() -> void:
	var one := CursorArt.image("A", "amethyst", 1.0)
	assert_eq(one.get_size(), Vector2i(41, 49), "1x is the grown viewBox size")
	var big := CursorArt.texture("A", "amethyst")
	assert_eq(Vector2i(big.get_width(), big.get_height()), Vector2i(164, 196), "default is RENDER_SCALE (4x)")
	assert_eq(CursorArt.RENDER_SCALE, 4.0, "rasterised at 4x")

func test_the_icon_is_the_cursors_art_without_its_glow_margin_with_mipmaps() -> void:
	var icon := CursorArt.icon("A", "amethyst")
	assert_true(icon != null, "an icon for a real style")
	assert_true(CursorArt.icon("Z", "amethyst") == null, "none for an unknown shape")
	if icon == null:
		return
	var view: Rect2 = CursorArt.SHAPE_DATA["A"]["view"]
	var size := Vector2i(view.size * CursorArt.RENDER_SCALE)
	assert_eq(Vector2i(icon.get_width(), icon.get_height()), size, "the art's own size at 4x, no glow margin (84 x 116)")
	var img := icon.get_image()
	assert_true(img.has_mipmaps(), "with mipmaps, so it shrinks into the Mouse page's small slot cleanly")
	var base := img.duplicate() as Image
	base.clear_mipmaps()
	var margin := int(CursorArt.GLOW_MARGIN * CursorArt.RENDER_SCALE)
	var drawn := CursorArt.image("A", "amethyst").get_region(Rect2i(Vector2i(margin, margin), size))
	assert_true(base.get_data() == drawn.get_data(), "and exactly the art the cursor draws")
