extends TestSuite

## Every scrolling list in the pause-menu screens wears the amethyst theme. The
## Loadout, Items, Equipment, Stats, Shop and Quest screens each built a bare
## ScrollContainer, so their scrollbars were Godot's default grey — against the
## project's rule that no default-themed control ships. They now come from
## BattleUITheme.make_scroll(), whose bar is the theme's purple.

func suite_name() -> String:
	return "Scrollbars"

func _grabber_color(sb: ScrollBar) -> Color:
	var g := sb.get_theme_stylebox("grabber") as StyleBoxFlat
	return g.bg_color if g != null else Color.BLACK

func test_the_shared_scrollbar_is_the_theme_purple() -> void:
	var sb := VScrollBar.new()
	BattleUITheme.style_scrollbar(sb)
	assert_eq(_grabber_color(sb), BattleUITheme.PANEL_BORDER, "the grabber is the amethyst border colour")
	assert_true(sb.get_theme_stylebox("scroll") is StyleBoxFlat, "and the track is themed, not the default")
	sb.free()

func test_a_themed_scroll_list_scrolls_down_only_with_a_purple_bar() -> void:
	var scroll := BattleUITheme.make_scroll()
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "lists scroll vertically only")
	assert_eq(_grabber_color(scroll.get_v_scroll_bar()), BattleUITheme.PANEL_BORDER, "with the purple bar")
	scroll.free()

func test_no_pause_screen_builds_a_default_grey_scrollbar() -> void:
	# A bare ScrollContainer.new() in a screen is how the grey bars got in.
	var dir := "res://scripts/ui/"
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".gd") or f == "BattleUITheme.gd":
			continue
		var src := FileAccess.get_file_as_string(dir + f)
		assert_false(src.contains("ScrollContainer.new()"), "%s builds its lists with BattleUITheme.make_scroll()" % f)
