extends TestSuite

## Spec B's move options on Skill: every one defaults to "off", and the pure
## maths behind costs, scaling and conditions. The resolver that uses them is
## tested in test_skill_resolver.gd.

func suite_name() -> String:
	return "SkillOptions"

func _hero(hp := 100, mp := 50) -> Character:
	var c := Character.new()
	c.character_name = "OptionsHero"
	c.base_hp = hp
	c.base_mp = mp
	c.level = 1
	c.current_hp = c.max_hp()
	c.current_mp = c.max_mp()
	return c

func _enemy(hp := 100) -> Enemy:
	var e := Enemy.new()
	e.character_name = "OptionsFoe"
	e.base_hp = hp
	e.level = 1
	e.current_hp = e.max_hp()
	return e

func test_every_option_defaults_to_off() -> void:
	var s := Skill.new()
	assert_eq(s.hp_cost_percent, 0.0, "no HP cost")
	assert_eq(s.resonance_cost, 0.0, "no resonance cost")
	assert_eq(s.hit_count, 1, "one hit")
	assert_eq(s.pierce, 0.0, "no pierce")
	assert_eq(s.ally_heal_power, 0.0, "no ally heal")
	assert_eq(int(s.bonus_condition), int(Skill.BonusCondition.NONE), "no condition")
	assert_eq(int(s.override_element), int(ElementalSystem.Element.NORMAL), "no element override")
	assert_eq(int(s.scale_with), int(Skill.ScaleWith.NONE), "no scaling")
	assert_eq(s.self_debuff, "", "no self-debuff")
	assert_eq(s.recoil_percent, 0.0, "no recoil")
	assert_eq(s.miss_chance, 0.0, "no miss chance")
	assert_eq(s.target_buff, "", "no target buff")

func test_hp_cost_is_a_rounded_up_share_of_max_hp() -> void:
	var s := Skill.new()
	s.hp_cost_percent = 12.5
	assert_eq(s.hp_cost(_hero(100)), 13, "12.5% of 100 rounds up to 13")
	s.hp_cost_percent = 0.0
	assert_eq(s.hp_cost(_hero(100)), 0, "no cost, no HP")

func test_an_hp_cost_can_never_knock_the_user_out() -> void:
	var s := Skill.new()
	s.hp_cost_percent = 12.0
	var h := _hero(100)
	h.current_hp = 12
	assert_false(s.can_use(h), "paying 12 would leave 0 HP: greyed out")
	h.current_hp = 13
	assert_true(s.can_use(h), "13 HP leaves 1 after paying: usable")

func test_enemies_pay_hp_but_ignore_mp_and_resonance() -> void:
	var s := Skill.new()
	s.mp_cost = 99
	s.resonance_cost = 99.0
	var e := _enemy(100)
	assert_true(s.can_use(e), "an enemy has no MP or resonance pool to pay from")
	s.hp_cost_percent = 50.0
	e.current_hp = 50
	assert_false(s.can_use(e), "but it does have HP, and may not KO itself")

func test_a_resonance_cost_needs_that_much_meter() -> void:
	var s := Skill.new()
	s.resonance_cost = 30.0
	var h := _hero()
	h.resonance_meter = 29.0
	assert_false(s.can_use(h), "29 is not enough for 30")
	h.resonance_meter = 30.0
	assert_true(s.can_use(h), "exactly 30 is enough")

func test_a_resonance_cost_move_builds_no_resonance() -> void:
	var s := Skill.new()
	assert_eq(s.get_resonance_gain(), 10.0, "an ordinary damage move builds 10")
	s.resonance_cost = 30.0
	assert_eq(s.get_resonance_gain(), 0.0, "spending resonance never refunds itself")
	s.resonance_gain_override = 25.0
	assert_eq(s.get_resonance_gain(), 0.0, "not even with an override")

func test_scaling_runs_from_min_to_max_on_the_users_own_pool() -> void:
	var s := Skill.new()
	var h := _hero(100, 50)
	assert_eq(s.scale_factor(h), 1.0, "no scaling is 1x")
	s.scale_with = Skill.ScaleWith.HP
	assert_true(is_equal_approx(s.scale_factor(h), Skill.SCALE_MAX), "full HP, more is stronger: max")
	h.current_hp = 50
	assert_true(is_equal_approx(s.scale_factor(h), lerpf(Skill.SCALE_MIN, Skill.SCALE_MAX, 0.5)), "half HP: halfway")
	s.scale_more_is_stronger = false
	h.current_hp = 100
	assert_true(is_equal_approx(s.scale_factor(h), Skill.SCALE_MIN), "full HP, less is stronger: min")
	s.scale_with = Skill.ScaleWith.RESONANCE
	s.scale_more_is_stronger = true
	h.resonance_meter = 100.0
	assert_true(is_equal_approx(s.scale_factor(h), Skill.SCALE_MAX), "a full meter: max")
	s.scale_with = Skill.ScaleWith.MP
	h.current_mp = 0
	assert_true(is_equal_approx(s.scale_factor(h), Skill.SCALE_MIN), "empty MP: min")

func test_scaling_on_a_pool_an_enemy_lacks_is_neutral() -> void:
	var s := Skill.new()
	var e := _enemy()
	s.scale_with = Skill.ScaleWith.MP
	assert_eq(s.scale_factor(e), 1.0, "enemies have no MP pool")
	s.scale_with = Skill.ScaleWith.RESONANCE
	assert_eq(s.scale_factor(e), 1.0, "or resonance meter")

func test_target_afflicted_condition() -> void:
	var s := Skill.new()
	s.bonus_condition = Skill.BonusCondition.TARGET_AFFLICTED
	s.bonus_multiplier = 1.5
	var t := _hero()
	assert_eq(s.condition_multiplier(1.0, t), 1.0, "a clean target gets no bonus")
	t.add_status(StatusSystem.POISON)
	assert_eq(s.condition_multiplier(1.0, t), 1.5, "a poisoned target does")
	var d := _hero()
	d.apply_debuff("defense")
	assert_eq(s.condition_multiplier(1.0, d), 1.5, "so does a debuffed one")

func test_user_hp_low_condition_is_strictly_below_thirty_percent() -> void:
	var s := Skill.new()
	s.bonus_condition = Skill.BonusCondition.USER_HP_LOW
	s.bonus_multiplier = 1.75
	assert_eq(s.condition_multiplier(0.29, _hero()), 1.75, "below 30%")
	assert_eq(s.condition_multiplier(0.30, _hero()), 1.0, "exactly 30% is not low")

func test_override_multiplier_is_effective_or_super_effective() -> void:
	var s := Skill.new()
	assert_eq(s.override_multiplier(), 1.0, "effective by default")
	s.override_super = true
	assert_eq(s.override_multiplier(), ElementalSystem.WEAKNESS_MULTIPLIER, "super-effective")

# --------------------------------------------------- costs and tags in menus

func test_cost_parts_list_every_cost() -> void:
	var s := Skill.new()
	assert_true(s.cost_parts().is_empty(), "a free move has no costs")
	assert_eq(s.cost_text(), "", "and no cost text")
	s.mp_cost = 12
	s.hp_cost_percent = 15.0
	s.resonance_cost = 30.0
	var parts := s.cost_parts()
	assert_eq(parts.map(func(p): return p["kind"]), ["mp", "hp", "resonance"], "in MP, HP, resonance order")
	assert_eq(s.cost_text(), "12 MP · 15% HP · 30 ✦", "joined for single-label menus")

func test_effect_tags_describe_the_options() -> void:
	var s := Skill.new()
	s.attack_type = Skill.AttackType.MAGIC
	assert_true(s.effect_tags().is_empty(), "a plain move has no tags")
	s.hit_count = 2
	s.pierce = 1.0
	assert_eq(s.effect_tags(), ["2 hits", "Ignores ARC"] as Array[String], "hits and pierce")
	s.hit_count = 1
	s.pierce = 0.5
	s.attack_type = Skill.AttackType.STRIKE
	assert_eq(s.effect_tags(), ["Ignores 50% DEF"] as Array[String], "partial physical pierce")

func test_effect_tags_cover_riders_and_heal_effects() -> void:
	var s := Skill.new()
	s.status_to_apply = "speed_debuff"
	s.status_chance = 0.4
	assert_eq(s.effect_tags(), ["40% chance: Lowers SPD"] as Array[String], "a damage rider")
	var h := Skill.new()
	h.skill_type = Skill.SkillType.STATUS
	h.status_type = Skill.StatusType.HEAL
	h.status_to_apply = StatusSystem.REGENERATE
	assert_eq(h.effect_tags(), ["Regenerates"] as Array[String], "a heal's attached effect")

func test_effect_tags_cover_conditions_override_and_scaling() -> void:
	var s := Skill.new()
	s.bonus_condition = Skill.BonusCondition.TARGET_AFFLICTED
	assert_eq(s.effect_tags(), ["×1.5 vs afflicted"] as Array[String], "afflicted bonus")
	s.bonus_condition = Skill.BonusCondition.USER_HP_LOW
	s.bonus_multiplier = 1.75
	assert_eq(s.effect_tags(), ["×1.75 below 30% HP"] as Array[String], "low-HP bonus")
	s.bonus_condition = Skill.BonusCondition.NONE
	s.override_element = ElementalSystem.Element.WATER
	s.override_super = true
	assert_eq(s.effect_tags(), ["Super-effective vs Water"] as Array[String], "element override")
	s.override_element = ElementalSystem.Element.NORMAL
	s.scale_with = Skill.ScaleWith.MP
	assert_eq(s.effect_tags(), ["Stronger with more MP"] as Array[String], "scaling")
	s.scale_more_is_stronger = false
	s.scale_with = Skill.ScaleWith.HP
	assert_eq(s.effect_tags(), ["Stronger with less HP"] as Array[String], "inverse scaling")

func test_effect_tags_cover_trade_offs_and_ally_heal() -> void:
	var s := Skill.new()
	s.ally_heal_power = 1.0
	s.recoil_percent = 25.0
	s.miss_chance = 0.3
	s.self_debuff = "defense"
	s.target_buff = "attack"
	assert_eq(s.effect_tags(), ["Heals allies", "25% recoil", "30% miss chance",
			"Lowers your DEF", "Raises target's ATK"] as Array[String], "every trade-off")
	assert_eq(s.effect_text(), "Heals allies · 25% recoil · 30% miss chance · Lowers your DEF · Raises target's ATK", "joined")

func test_each_cost_kind_has_its_own_colour() -> void:
	var mp := BattleUITheme.cost_color("mp")
	var hp := BattleUITheme.cost_color("hp")
	var res := BattleUITheme.cost_color("resonance")
	assert_ne(mp, hp, "MP and HP differ")
	assert_ne(hp, res, "HP and resonance differ")
	assert_ne(mp, res, "MP and resonance differ")
