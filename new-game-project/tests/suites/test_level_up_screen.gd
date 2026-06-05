extends TestSuite

## LevelUpScreen stat-diff display: the per-level growth is always shown as a
## positive delta even when stat-reducing equipment makes the equipment-inclusive
## total lower than the raw base+growth (the old "+-2" bug), and the +/- text is
## sign-safe.

const LevelUpScreenScript := preload("res://scripts/battle/LevelUpScreen.gd")

func suite_name() -> String:
	return "LevelUpScreen"

func _screen() -> Node:
	return LevelUpScreenScript.new()

func _kael_with_slow_armor() -> Character:
	# A bruiser with low speed wearing armor that reduces SPD — the exact shape
	# that produced "+-2" before the fix.
	var c := Character.new()
	c.character_name = "Kael"
	c.base_speed = 8
	c.level = 2
	var armor := Equipment.new()
	armor.equipment_name = "Heavy Plate"
	armor.slot = Equipment.Slot.ARMOR
	armor.stat_bonuses = {"speed": -2}
	c.inventory.equipped_armor = armor
	return c

func test_level_growth_diff_is_positive_with_slow_armor() -> void:
	var s := _screen()
	var c := _kael_with_slow_armor()
	var old_stats: Dictionary = s._get_old_stats(c)
	var new_stats: Dictionary = s._get_new_stats(c)
	var spd_diff: int = new_stats["SPD"] - old_stats["SPD"]
	assert_eq(spd_diff, 1, "SPD level-growth diff is +1 regardless of slowing armor")
	# New value reflects the real current stat (equipment included).
	assert_eq(new_stats["SPD"], c.speed(), "new SPD equals the live getter (equipment-inclusive)")
	s.free()

func test_all_stat_diffs_match_level_growth() -> void:
	var s := _screen()
	var c := _kael_with_slow_armor()
	var old_stats: Dictionary = s._get_old_stats(c)
	var new_stats: Dictionary = s._get_new_stats(c)
	for stat in ["HP", "MP", "ATK", "DEF", "MAG", "ARC", "SPD"]:
		var diff: int = new_stats[stat] - old_stats[stat]
		assert_eq(diff, s.LEVEL_GROWTH[stat], "%s diff equals its per-level growth" % stat)
	s.free()

func test_format_diff_is_sign_safe() -> void:
	var s := _screen()
	assert_eq(s._format_diff(3), "+3", "positive shows +N")
	assert_eq(s._format_diff(0), "0", "zero shows 0 (no plus)")
	assert_eq(s._format_diff(-2), "-2", "negative shows -N, never +-N")
	s.free()
