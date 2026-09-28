extends TestSuite

## Every rounded progress bar must stay inside its own rounded outline.
##
## ProgressBar draws the fill `round(ratio * (width - min_width)) + min_width`
## wide, and skips it when that rounds to zero. A fill style with rounded
## corners but NO minimum width was drawn 1-2px wide for a near-empty bar
## (a couple of XP right after a level-up) — too narrow to round, so it showed
## as a square-cornered line poking out past the bar's curved ends. A fill
## whose minimum width is at least its two corner radii is either not drawn at
## all or drawn as a properly rounded pill.

func suite_name() -> String:
	return "MeterBars"

func _assert_fill_can_round(bar: ProgressBar, label: String) -> void:
	var fill := bar.get_theme_stylebox("fill") as StyleBoxFlat
	assert_true(fill != null, "%s has a rounded fill" % label)
	if fill == null:
		return
	var ends := fill.corner_radius_top_left + fill.corner_radius_top_right
	assert_true(fill.get_minimum_size().x >= ends,
			"%s: fill is never narrower than its rounded ends (min %d, needs %d)" % [label, int(fill.get_minimum_size().x), ends])

func test_the_shared_meter_style_can_always_round_its_ends() -> void:
	var bar := ProgressBar.new()
	BattleUITheme.style_meter_bar(bar, Color(0.85, 0.78, 0.45))
	_assert_fill_can_round(bar, "BattleUITheme meter")
	bar.free()

func test_the_stats_screen_bars_can_always_round_their_ends() -> void:
	var screen := StatsScreen.new()
	var row := screen._make_meter_row("XP", 1.0, 150.0, Color(0.85, 0.78, 0.45), "1 / 150")
	var bar: ProgressBar = null
	for c in row.get_children():
		if c is ProgressBar:
			bar = c
	assert_true(bar != null, "the meter row has a bar")
	if bar != null:
		_assert_fill_can_round(bar, "Stats screen XP/resonance")
	row.free()
	screen.free()

func test_the_victory_exp_bar_can_always_round_its_ends() -> void:
	var screen = load("res://scripts/battle/VictoryScreen.gd").new()  # no class_name
	var bar := ProgressBar.new()
	screen._style_exp_bar(bar)
	_assert_fill_can_round(bar, "Victory EXP")
	bar.free()
	screen.free()
