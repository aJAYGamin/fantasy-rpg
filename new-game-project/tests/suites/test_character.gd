extends TestSuite

func suite_name() -> String:
	return "Character"

func _make() -> Character:
	var c = Character.new()
	c.base_hp = 100
	c.base_mp = 50
	c.base_attack = 10
	c.base_defense = 5
	c.base_magic = 8
	c.base_arcane = 4
	c.level = 1
	c.current_hp = c.max_hp()
	c.current_mp = c.max_mp()
	return c

func test_arcane_power_scales_with_level() -> void:
	var c = _make()
	assert_eq(c.arcane_power(), 4, "Lv1 arcane_power = base_arcane")
	c.level = 5
	assert_eq(c.arcane_power(), 4 + 4, "Lv5 arcane_power adds (level-1)")

func test_take_magic_damage_subtracts_arcane() -> void:
	var c = _make()
	c.base_arcane = 4
	# Magic damage subtracts arcane_power (4 at Lv1), then applies element multiplier.
	# 30 - 4 = 26, normal multiplier → 26 damage.
	var r = c.take_magic_damage(30, ElementalSystem.Element.NORMAL)
	assert_eq(r["damage"], 26, "magic damage = 30 - arcane(4) at neutral element")

func test_max_hp_scales_with_level() -> void:
	var c = _make()
	assert_eq(c.max_hp(), 100, "Lv1 max_hp = base_hp")
	c.level = 3
	assert_eq(c.max_hp(), 130, "Lv3 max_hp = 100 + 2*15")

func test_max_mp_scales_with_level() -> void:
	var c = _make()
	c.level = 4
	assert_eq(c.max_mp(), 50 + 3 * 8, "Lv4 max_mp = 50 + 3*8")

func test_is_alive() -> void:
	var c = _make()
	assert_true(c.is_alive(), "full HP is alive")
	c.current_hp = 0
	assert_false(c.is_alive(), "0 HP is not alive")

func test_take_damage_subtracts_defense() -> void:
	var c = _make()  # defense_power = 5 at Lv1
	var r = c.take_damage(20, ElementalSystem.Element.NORMAL)
	assert_eq(r["damage"], 15, "20 dmg - 5 def = 15")
	assert_eq(c.current_hp, 85, "HP reduced by 15")

func test_take_damage_minimum_one() -> void:
	var c = _make()
	var r = c.take_damage(1, ElementalSystem.Element.NORMAL)
	assert_eq(r["damage"], 1, "damage floors at 1 even when below defense")

func test_heal_caps_at_max() -> void:
	var c = _make()
	c.current_hp = 90
	var healed = c.heal(50)
	assert_eq(healed, 10, "heal only fills to max")
	assert_eq(c.current_hp, 100, "current_hp == max_hp after overheal")

func test_use_mp() -> void:
	var c = _make()
	assert_true(c.use_mp(20), "use_mp succeeds with enough MP")
	assert_eq(c.current_mp, 30, "MP reduced")
	assert_false(c.use_mp(999), "use_mp fails without enough MP")
	assert_eq(c.current_mp, 30, "MP unchanged on failed use")

func test_status_add_remove() -> void:
	var c = _make()
	c.add_status("poison")
	assert_true(c.is_status("poison"), "poison applied")
	c.add_status("poison")
	assert_eq(c.status_effects.size(), 1, "duplicate status not stacked")
	c.remove_status("poison")
	assert_false(c.is_status("poison"), "poison removed")

func test_level_up_does_not_restore_hp_mp() -> void:
	var c = _make()
	c.current_hp = 40
	c.current_mp = 10
	c.experience = 100
	c.experience_to_next = 100
	var leveled = c.gain_experience(0)
	assert_true(leveled, "gain_experience returns true on level up")
	assert_eq(c.level, 2, "level incremented")
	assert_eq(c.current_hp, 40, "current_hp NOT restored on level up")
	assert_eq(c.current_mp, 10, "current_mp NOT restored on level up")

func test_gain_experience_multi_level() -> void:
	var c = _make()
	c.experience = 0
	c.experience_to_next = 100
	# 100 -> level 2 (carry 150 over: 250-100), threshold 150 -> level 3 ...
	c.gain_experience(300)
	assert_true(c.level >= 3, "large EXP batch yields multiple level ups (got Lv%d)" % c.level)

func test_total_experience_fresh_character() -> void:
	var c = _make()
	assert_eq(c.total_experience_earned(), 0, "fresh Lv1 character has earned 0 XP")
	c.experience = 85
	assert_eq(c.total_experience_earned(), 85, "Lv1 with 85 progress has earned 85 total")

func test_total_experience_includes_past_thresholds() -> void:
	var c = _make()
	c.level = 2
	c.experience = 85
	# Reaching Lv2 cost the first threshold (100), plus 85 toward Lv3 = 185.
	assert_eq(c.total_experience_earned(), 185, "Lv2 + 85 = 100 (past) + 85")

func test_total_experience_matches_cumulative_gain() -> void:
	# Lifetime total must equal the raw XP fed in, regardless of how many level-ups
	# it triggers (threshold truncation is recomputed identically).
	var c = _make()
	c.level = 1
	c.experience = 0
	c.experience_to_next = Character.XP_BASE
	c.gain_experience(250)
	assert_eq(c.total_experience_earned(), 250, "total earned == cumulative XP gained")
