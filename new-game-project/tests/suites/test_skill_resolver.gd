extends TestSuite

## One skill resolver for heroes and enemies. Target expansion is relative to
## the user's side, so an enemy's ALL_ENEMIES is the whole party — it used to
## hit a single hero, because expansion existed only in the player's menu.

func suite_name() -> String:
	return "SkillResolver"

## Enough HP that no test here kills anyone by accident: handle_defeat reports
## quest progress to the live GameManager. Defence is zeroed explicitly so a
## probe always lands damage rather than relying on the default of 5.
##
## Enemies get their own species: Memory Echo dodge keys on species through
## GameManager.species_memory, and the default "Unknown" may already have an
## encounter count from other tests or real saves — which would make these
## tests randomly dodge.
func _unit(name: String, hero: bool) -> Character:
	var c: Character = Character.new() if hero else Enemy.new()
	if not hero:
		(c as Enemy).species = "SkillResolverTestDummy"
	c.character_name = name
	c.base_hp = 5000
	c.base_mp = 500
	c.base_attack = 20
	c.base_magic = 20
	c.base_defense = 0
	c.base_arcane = 0
	c.level = 1
	c.current_hp = c.max_hp()
	c.current_mp = c.max_mp()
	return c

func _manager(heroes: int, foes: int) -> BattleManager:
	var bm := BattleManager.new()
	var p: Array[Character] = []
	for i in heroes:
		p.append(_unit("Hero%d" % i, true))
	var e: Array[Character] = []
	for i in foes:
		e.append(_unit("Foe%d" % i, false))
	bm.party = p
	bm.enemies = e
	return bm

func _skill(target: Skill.TargetType, kind: Skill.SkillType = Skill.SkillType.DAMAGE) -> Skill:
	var s := Skill.new()
	s.skill_name = "Probe"
	s.skill_type = kind
	s.attack_type = Skill.AttackType.STRIKE
	s.target_type = target
	s.power = 1.0
	return s

func test_an_enemy_area_attack_targets_the_whole_party() -> void:
	var bm := _manager(3, 1)
	var got := bm.expand_targets(bm.enemies[0], _skill(Skill.TargetType.ALL_ENEMIES), [bm.party[0]])
	assert_eq(got.size(), 3, "every hero, not just the one the AI picked")
	bm.free()

func test_a_hero_area_attack_targets_every_enemy() -> void:
	var bm := _manager(1, 4)
	var got := bm.expand_targets(bm.party[0], _skill(Skill.TargetType.ALL_ENEMIES), [])
	assert_eq(got.size(), 4, "every enemy")
	bm.free()

func test_all_allies_is_relative_to_the_user() -> void:
	var bm := _manager(2, 3)
	var for_hero := bm.expand_targets(bm.party[0], _skill(Skill.TargetType.ALL_ALLIES), [])
	var for_enemy := bm.expand_targets(bm.enemies[0], _skill(Skill.TargetType.ALL_ALLIES), [])
	assert_eq(for_hero.size(), 2, "a hero's allies are the party")
	assert_eq(for_enemy.size(), 3, "an enemy's allies are its fellow enemies")
	assert_false(for_enemy.has(bm.party[0]), "never a hero")
	bm.free()

func test_self_targets_the_user_on_both_sides() -> void:
	# SELF used to work only for enemies.
	var bm := _manager(1, 1)
	var h := bm.expand_targets(bm.party[0], _skill(Skill.TargetType.SELF), [])
	var e := bm.expand_targets(bm.enemies[0], _skill(Skill.TargetType.SELF), [])
	assert_eq(h.size(), 1, "one target for a hero")
	assert_eq(h[0], bm.party[0], "and it is the hero")
	assert_eq(e.size(), 1, "one target for an enemy")
	assert_eq(e[0], bm.enemies[0], "and it is the enemy")
	bm.free()

func test_a_single_target_keeps_the_chosen_target() -> void:
	var bm := _manager(3, 1)
	var got := bm.expand_targets(bm.enemies[0], _skill(Skill.TargetType.SINGLE_ENEMY), [bm.party[2]])
	assert_eq(got.size(), 1, "only one target")
	assert_eq(got[0], bm.party[2], "and it is the one chosen")
	bm.free()

func test_an_area_attack_skips_a_downed_hero() -> void:
	# REVIEW FOCUS 3.
	var bm := _manager(3, 1)
	bm.party[1].current_hp = 0
	var got := bm.expand_targets(bm.enemies[0], _skill(Skill.TargetType.ALL_ENEMIES), [])
	assert_eq(got.size(), 2, "only the living")
	assert_false(got.has(bm.party[1]), "never the downed hero")
	bm.free()

func test_all_allies_includes_a_mid_battle_summon() -> void:
	# REVIEW FOCUS 4. Boss summons are appended to `enemies` after the fight starts.
	var bm := _manager(1, 1)
	bm.enemies.append(_unit("Summoned", false))
	var got := bm.expand_targets(bm.enemies[0], _skill(Skill.TargetType.ALL_ALLIES), [])
	assert_eq(got.size(), 2, "the summon counts as an ally")
	bm.free()

# --------------------------------------------------- resolution

func _capture(bm: BattleManager) -> Array:
	var out: Array = []
	bm.action_performed.connect(func(r): out.append(r))
	return out

func test_an_enemy_area_attack_damages_every_hero() -> void:
	# The bug, end to end.
	var bm := _manager(3, 1)
	var hits := _capture(bm)
	var before: Array = bm.party.map(func(h): return h.current_hp)
	bm.enemy_use_skill(bm.enemies[0], _skill(Skill.TargetType.ALL_ENEMIES), [bm.party[0]])
	assert_eq(hits.size(), 3, "one result per hero")
	for i in 3:
		assert_true(bm.party[i].current_hp < before[i], "hero %d took damage" % i)
	bm.free()

func test_a_strike_skill_emits_skill_physical_on_both_sides() -> void:
	# "attack" routes a HERO to on_attack instead of on_skill_used, which grants
	# different resonance. Neither side may emit it for a skill.
	var bm := _manager(1, 1)
	var hits := _capture(bm)
	bm.enemy_use_skill(bm.enemies[0], _skill(Skill.TargetType.SINGLE_ENEMY), [bm.party[0]])
	bm.resolve_skill(bm.party[0], _skill(Skill.TargetType.SINGLE_ENEMY), [bm.enemies[0]])
	assert_eq(hits[0]["action"], "skill_physical", "enemy strike")
	assert_eq(hits[1]["action"], "skill_physical", "hero strike")
	bm.free()

func test_a_magic_skill_emits_skill_magic() -> void:
	var bm := _manager(1, 1)
	var hits := _capture(bm)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.attack_type = Skill.AttackType.MAGIC
	bm.resolve_skill(bm.party[0], s, [bm.enemies[0]])
	assert_eq(hits[0]["action"], "skill_magic", "magic")
	bm.free()

func test_resonance_flag_is_set_once_per_action() -> void:
	var bm := _manager(1, 4)
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], _skill(Skill.TargetType.ALL_ENEMIES), [])
	var firsts := hits.filter(func(r): return r.get("is_first_target", false))
	assert_eq(firsts.size(), 1, "an area attack grants resonance once, not per target")
	bm.free()

func test_heroes_pay_mp_and_enemies_do_not() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.mp_cost = 30
	var hero_mp := bm.party[0].current_mp
	var foe_mp := bm.enemies[0].current_mp
	bm.resolve_skill(bm.party[0], s, [bm.enemies[0]])
	bm.resolve_skill(bm.enemies[0], s, [bm.party[0]])
	assert_eq(bm.party[0].current_mp, hero_mp - 30, "the hero paid")
	assert_eq(bm.enemies[0].current_mp, foe_mp, "the enemy did not")
	bm.free()

func test_self_heals_the_hero_who_casts_it() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SELF, Skill.SkillType.STATUS)
	s.status_type = Skill.StatusType.HEAL
	bm.party[0].current_hp = 100
	bm.resolve_skill(bm.party[0], s, [])
	assert_true(bm.party[0].current_hp > 100, "SELF now works for heroes")
	bm.free()

## THE DODGE RULE (user's design): whether a skill can be dodged depends on WHO
## it lands on, not on what kind of skill it is. Anything aimed at the user's
## opponents — damage or status — can be dodged, by heroes and enemies alike.
## Anything aimed at the user or its allies always lands. (The enemy turn's old
## outer dodge covered an enemy's own SELF heal/buff too, so an enemy could
## "dodge" its own move; it no longer can.)

func test_a_self_skill_always_lands() -> void:
	var bm := _manager(1, 1)
	bm.party[0].set_meta("dodge_chance", 1.0)
	var s := _skill(Skill.TargetType.SELF, Skill.SkillType.STATUS)
	s.status_type = Skill.StatusType.HEAL
	bm.party[0].current_hp = 100
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], s, [])
	assert_true(bm.party[0].current_hp > 100, "healed despite dodge_chance 1.0")
	var dodged := hits.filter(func(r): return r.get("action", "") == "dodge")
	assert_true(dodged.is_empty(), "no dodge result for a SELF status skill")
	bm.free()

func test_a_skill_on_allies_always_lands() -> void:
	var bm := _manager(3, 1)
	for h in bm.party:
		h.set_meta("dodge_chance", 1.0)
	var s := _skill(Skill.TargetType.ALL_ALLIES, Skill.SkillType.STATUS)
	s.status_type = Skill.StatusType.BUFF
	s.status_to_apply = "defense_buff"
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], s, [])
	for h in bm.party:
		assert_true(StatusSystem.is_effectively_buffed(h, StatusSystem.STAT_DEF), "%s got the buff" % h.character_name)
	assert_true(hits.filter(func(r): return r["action"] == "dodge").is_empty(), "nobody dodges an ally's buff")
	bm.free()

func test_a_debuff_on_an_opponent_can_be_dodged() -> void:
	# The enemy's side of the rule; a hero debuffing an enemy runs the same code
	# (_opponents_of), but enemy dodge comes from Memory Echo and tops out at
	# 15%, so it cannot be pinned to "always" in a test.
	var bm := _manager(2, 1)
	bm.party[0].set_meta("dodge_chance", 1.0)
	var s := _skill(Skill.TargetType.ALL_ENEMIES, Skill.SkillType.STATUS)
	s.status_type = Skill.StatusType.DEBUFF
	s.status_to_apply = "attack_debuff"
	var hits := _capture(bm)
	bm.resolve_skill(bm.enemies[0], s, [])
	assert_false(StatusSystem.is_effectively_debuffed(bm.party[0], StatusSystem.STAT_ATK), "the dodging hero is untouched")
	assert_true(StatusSystem.is_effectively_debuffed(bm.party[1], StatusSystem.STAT_ATK), "the other hero is debuffed")
	var dodged := hits.filter(func(r): return r["action"] == "dodge")
	assert_eq(dodged.size(), 1, "one dodge")
	assert_eq(dodged[0]["target"], bm.party[0], "by the hero who can dodge")
	bm.free()

func test_dodge_is_rolled_per_target() -> void:
	var bm := _manager(3, 1)
	bm.party[1].set_meta("dodge_chance", 1.0)
	var hits := _capture(bm)
	bm.enemy_use_skill(bm.enemies[0], _skill(Skill.TargetType.ALL_ENEMIES), [bm.party[0]])
	var dodged := hits.filter(func(r): return r["action"] == "dodge")
	assert_eq(dodged.size(), 1, "exactly the hero who dodges")
	assert_eq(dodged[0]["target"], bm.party[1], "and it is that hero")
	bm.free()

func test_downed_targets_are_skipped() -> void:
	var bm := _manager(1, 1)
	bm.enemies[0].current_hp = 0
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], _skill(Skill.TargetType.SINGLE_ENEMY), [bm.enemies[0]])
	assert_true(hits.is_empty(), "no action on a downed target")
	bm.free()

func _function_body(src: String, name: String) -> String:
	var start := src.find("func %s(" % name)
	if start < 0:
		return ""
	var end := src.find("\nfunc ", start + 1)
	return src.substr(start, (end - start) if end > 0 else -1)

func test_an_enemy_skill_is_dodge_rolled_once_not_twice() -> void:
	# _execute_enemy_turn awaits real timers, so it cannot be driven from a
	# synchronous test; this pins the structure instead. Dodge is now rolled
	# inside resolve_skill, so the enemy turn must not roll it again first —
	# two rolls would make a 50% dodge land 75% of the time.
	var src := FileAccess.get_file_as_string("res://scripts/battle/BattleManager.gd")
	assert_true(_function_body(src, "resolve_skill").contains("try_dodge"), "the resolver rolls dodge")
	var turn := _function_body(src, "_execute_enemy_turn")
	var skill_branch := turn.substr(turn.find("if skill != null:"))
	skill_branch = skill_branch.substr(0, skill_branch.find("\n\telse:"))
	assert_false(skill_branch.contains("try_dodge"), "the enemy turn does not roll it again for a skill")

# --------------------------------------------------- Spec B: costs and hits

func _actions(hits: Array) -> Array:
	return hits.map(func(r): return r["action"])

func test_an_hp_cost_is_paid_and_reported() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.hp_cost_percent = 10.0
	var hero := bm.party[0]
	var before := hero.current_hp
	var hits := _capture(bm)
	bm.resolve_skill(hero, s, [bm.enemies[0]])
	assert_eq(hero.current_hp, before - s.hp_cost(hero), "the hero paid 10% of max HP")
	var paid := hits.filter(func(r): return r["action"] == "hp_cost")
	assert_eq(paid.size(), 1, "one hp_cost result")
	assert_false(paid[0]["is_first_target"], "the cost never takes the first-target resonance flag")
	bm.free()

func test_an_unaffordable_hp_cost_does_nothing() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.hp_cost_percent = 10.0
	var hero := bm.party[0]
	hero.current_hp = s.hp_cost(hero)   # paying would leave 0
	var foe_hp := bm.enemies[0].current_hp
	var hits := _capture(bm)
	bm.resolve_skill(hero, s, [bm.enemies[0]])
	assert_eq(hero.current_hp, s.hp_cost(hero), "never knocked out by its own cost")
	assert_eq(bm.enemies[0].current_hp, foe_hp, "and the move does not happen")
	assert_true(hits.is_empty(), "no results at all")
	bm.free()

func test_enemies_pay_hp_costs() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.hp_cost_percent = 10.0
	var foe := bm.enemies[0]
	var before := foe.current_hp
	bm.resolve_skill(foe, s, [bm.party[0]])
	assert_eq(foe.current_hp, before - s.hp_cost(foe), "enemies have HP, so they pay")
	bm.free()

func test_a_resonance_cost_equal_to_the_meter_is_spent_to_zero() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.resonance_cost = 30.0
	var hero := bm.party[0]
	hero.resonance_meter = 30.0
	var hits := _capture(bm)
	bm.resolve_skill(hero, s, [bm.enemies[0]])
	assert_eq(hero.resonance_meter, 0.0, "exactly enough is enough, and it is all spent")
	assert_true(_actions(hits).has("skill_physical"), "and the move happened")
	bm.free()

func test_two_hits_land_two_results_and_resonance_once() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.hit_count = 2
	var foe := bm.enemies[0]
	var before := foe.current_hp
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], s, [foe])
	var dmg := hits.filter(func(r): return r["action"] == "skill_physical")
	assert_eq(dmg.size(), 2, "two hits, two results")
	assert_eq(hits.filter(func(r): return r.get("is_first_target", false)).size(), 1, "skill resonance once per action")
	assert_eq(before - foe.current_hp, int(dmg[0]["value"]) + int(dmg[1]["value"]), "both hits dealt their damage")
	bm.free()

func test_took_damage_resonance_is_once_per_target() -> void:
	var bm := _manager(2, 1)
	var s := _skill(Skill.TargetType.ALL_ENEMIES)
	s.hit_count = 3
	var hits := _capture(bm)
	bm.resolve_skill(bm.enemies[0], s, [])
	for hero in bm.party:
		var firsts := hits.filter(func(r): return r["target"] == hero and r.get("is_first_hit", false))
		assert_eq(firsts.size(), 1, "%s: exactly one first hit of three" % hero.character_name)
	bm.free()

func test_a_target_killed_by_the_first_hit_takes_no_second() -> void:
	# The victim is a HERO: defeating an enemy would report quest progress.
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.hit_count = 2
	var hero := bm.party[0]
	hero.current_hp = 1
	var defeated := []
	bm.character_defeated.connect(func(c): defeated.append(c))
	var hits := _capture(bm)
	bm.resolve_skill(bm.enemies[0], s, [hero])
	assert_eq(hits.filter(func(r): return r["target"] == hero).size(), 1, "one hit, then it stops")
	assert_eq(defeated.size(), 1, "defeat handled once")
	bm.free()

func test_a_miss_is_its_own_result_and_deals_nothing() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.miss_chance = 1.0
	var foe := bm.enemies[0]
	var before := foe.current_hp
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], s, [foe])
	assert_eq(_actions(hits), ["miss"], "a miss, not a dodge")
	assert_eq(foe.current_hp, before, "and no damage")
	bm.free()

func test_a_miss_chance_never_applies_to_allies() -> void:
	var bm := _manager(3, 1)
	var s := _skill(Skill.TargetType.ALL_ALLIES, Skill.SkillType.STATUS)
	s.status_type = Skill.StatusType.BUFF
	s.status_to_apply = "defense_buff"
	s.miss_chance = 1.0
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], s, [])
	assert_false(_actions(hits).has("miss"), "moves on your own side always land")
	for h in bm.party:
		assert_true(StatusSystem.is_effectively_buffed(h, "defense"), "%s buffed" % h.character_name)
	bm.free()

func test_pierce_reaches_the_target() -> void:
	var bm := _manager(1, 1)
	var foe := bm.enemies[0]
	foe.base_defense = 10
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], s, [foe])
	s.pierce = 1.0
	bm.resolve_skill(bm.party[0], s, [foe])
	assert_eq(int(hits[0]["value"]), 10, "20 ATK - 10 DEF")
	assert_eq(int(hits[1]["value"]), 20, "pierce 1.0 ignores the DEF")
	bm.free()

func test_the_element_override_reaches_the_target() -> void:
	var bm := _manager(1, 1)
	var foe := bm.enemies[0]
	foe.element = ElementalSystem.Element.WATER
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.element = ElementalSystem.Element.WATER
	s.override_element = ElementalSystem.Element.WATER
	s.override_super = true
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], s, [foe])
	assert_eq(hits[0]["multiplier"], 2.0, "water made super-effective against water")
	assert_eq(int(hits[0]["value"]), 40, "20 x 2")
	bm.free()

func test_a_target_afflicted_bonus() -> void:
	var bm := _manager(1, 2)
	var s := _skill(Skill.TargetType.ALL_ENEMIES)
	s.bonus_condition = Skill.BonusCondition.TARGET_AFFLICTED
	s.bonus_multiplier = 1.5
	bm.enemies[1].add_status(StatusSystem.POISON)
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], s, [])
	assert_eq(int(hits[0]["value"]), 20, "a clean enemy takes the plain 20")
	assert_eq(int(hits[1]["value"]), 30, "a poisoned one takes 20 x 1.5")
	bm.free()

func test_a_low_hp_user_bonus() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.bonus_condition = Skill.BonusCondition.USER_HP_LOW
	s.bonus_multiplier = 1.75
	var hero := bm.party[0]
	hero.current_hp = int(hero.max_hp() * 0.2)
	var hits := _capture(bm)
	bm.resolve_skill(hero, s, [bm.enemies[0]])
	assert_eq(int(hits[0]["value"]), 35, "20 x 1.75 below 30% HP")
	bm.free()

func test_scaling_is_measured_before_costs_are_paid() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.hp_cost_percent = 50.0
	s.scale_with = Skill.ScaleWith.HP
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], s, [bm.enemies[0]])
	var dmg := hits.filter(func(r): return r["action"] == "skill_physical")
	assert_eq(int(dmg[0]["value"]), 30, "full HP when the move began: 20 x 1.5, not weakened by its own cost")
	bm.free()

func test_a_status_rider_is_on_the_target_before_its_results_reach_the_ui() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.hit_count = 3
	s.status_to_apply = "attack_debuff"
	s.status_chance = 1.0
	var foe := bm.enemies[0]
	var seen := []
	bm.action_performed.connect(func(_r): seen.append(StatusSystem.is_effectively_debuffed(foe, "attack")))
	bm.resolve_skill(bm.party[0], s, [foe])
	assert_eq(seen, [true, true, true], "rolled after the hits, applied before they are shown")
	bm.free()

func test_a_status_rider_rolls_once_per_target_not_per_hit() -> void:
	# Per hit, three 25% rolls would land ~58% of the time; once per target, 25%.
	seed(20261004)
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.hit_count = 3
	s.status_to_apply = "attack_debuff"
	s.status_chance = 0.25
	var foe := bm.enemies[0]
	var landed := 0
	for i in 400:
		foe.debuffs.clear()
		foe.current_hp = foe.max_hp()
		bm.resolve_skill(bm.party[0], s, [foe])
		if StatusSystem.is_effectively_debuffed(foe, "attack"):
			landed += 1
	assert_true(landed < 160, "about 100 of 400, far below the ~232 a per-hit roll gives (got %d)" % landed)
	assert_true(landed > 50, "and the rider still lands (got %d)" % landed)
	bm.free()

func test_an_enemy_never_picks_an_hp_cost_it_cannot_pay() -> void:
	var bm := _manager(1, 1)
	var foe := bm.enemies[0]
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.hp_cost_percent = 50.0
	foe.skills = [s] as Array[Skill]
	foe.current_hp = s.hp_cost(foe)
	var decision := EnemyAI.choose_action(foe, bm.party, bm.enemies)
	assert_eq(decision.get("skill"), null, "it falls back to its basic attack")
	bm.free()

func test_skill_resonance_rides_on_the_first_hit_that_lands() -> void:
	# The first target dodges; the action still grants its resonance, once,
	# on the second target's landed hit.
	var bm := _manager(2, 1)
	bm.party[0].set_meta("dodge_chance", 1.0)
	var s := _skill(Skill.TargetType.ALL_ENEMIES)
	var hits := _capture(bm)
	bm.resolve_skill(bm.enemies[0], s, [])
	var firsts := hits.filter(func(r): return r.get("is_first_target", false))
	assert_eq(firsts.size(), 1, "still once per action")
	assert_eq(firsts[0]["target"], bm.party[1], "on the hit that landed")
	assert_eq(firsts[0]["action"], "skill_physical", "never on the dodge")
	bm.free()

# --------------------------------------------------- Spec B: after-effects

func test_a_heal_applies_its_attached_effect() -> void:
	# Restoring Breeze: heal, then regenerate.
	var bm := _manager(2, 1)
	var s := _skill(Skill.TargetType.SINGLE_ALLY, Skill.SkillType.STATUS)
	s.status_type = Skill.StatusType.HEAL
	s.status_to_apply = StatusSystem.REGENERATE
	var ally := bm.party[1]
	ally.current_hp = 100
	bm.resolve_skill(bm.party[0], s, [ally])
	assert_true(ally.current_hp > 100, "healed")
	assert_eq(ally.regen_turns, BattleManager.REGEN_TURNS, "and regenerating")
	bm.free()

func test_a_heals_regen_scales_with_the_casters_mag() -> void:
	# Ruling 11: the attached regen is HEAL_REGEN_POWER x the caster's MAG per
	# turn, not the default max_hp / 8 (which healed ~4x the move's old total).
	var bm := _manager(2, 1)
	var s := _skill(Skill.TargetType.SINGLE_ALLY, Skill.SkillType.STATUS)
	s.status_type = Skill.StatusType.HEAL
	s.status_to_apply = StatusSystem.REGENERATE
	var caster := bm.party[0]
	var ally := bm.party[1]
	ally.current_hp = 100
	bm.resolve_skill(caster, s, [ally])
	var expected := maxi(1, int(caster.magic_power() * BattleManager.HEAL_REGEN_POWER))
	assert_eq(ally.regen_amount, expected, "regen heals a share of the caster's MAG each turn")
	assert_eq(ally.regen_turns, BattleManager.REGEN_TURNS, "for the usual number of turns")
	assert_true(ally.regen_amount < maxi(1, ally.max_hp() / 8), "far below the old max_hp / 8")
	bm.free()

func test_restoring_breeze_keeps_about_its_old_total() -> void:
	# It healed 1.2 x MAG when its regen token was ignored; the honest version
	# is 0.5 x MAG now plus REGEN_TURNS ticks of the regen.
	var bm := _manager(2, 1)
	var breeze: Skill = load("res://data/skills/restoring_breeze.tres")
	var caster := bm.party[0]
	var ally := bm.party[1]
	ally.current_hp = 100
	var hits := _capture(bm)
	bm.resolve_skill(caster, breeze, [ally])
	var mag := float(caster.magic_power())
	var total := float(hits[0]["value"]) + float(BattleManager.REGEN_TURNS * ally.regen_amount)
	assert_in_range(total, mag * 1.2 * 0.85, mag * 1.2 * 1.15, "within 15% of the old 1.2 x MAG")
	bm.free()

func test_a_buffs_regen_keeps_the_default_amount() -> void:
	# Iron Will: a BUFF-type regenerate is still a share of the target's max HP.
	var bm := _manager(2, 1)
	var s := _skill(Skill.TargetType.ALL_ALLIES, Skill.SkillType.STATUS)
	s.status_type = Skill.StatusType.BUFF
	s.status_to_apply = StatusSystem.REGENERATE
	bm.resolve_skill(bm.party[0], s, [])
	for h in bm.party:
		assert_eq(h.regen_amount, maxi(1, h.max_hp() / 8), "%s regenerates max_hp / 8" % h.character_name)
		assert_eq(h.regen_turns, BattleManager.REGEN_TURNS, "%s for the usual turns" % h.character_name)
	bm.free()

func test_a_heals_regen_never_weakens_a_stronger_running_regen() -> void:
	var bm := _manager(2, 1)
	var ally := bm.party[1]
	ally.current_hp = 100
	ally.start_regen(BattleManager.REGEN_TURNS)
	var strong := ally.regen_amount
	var s := _skill(Skill.TargetType.SINGLE_ALLY, Skill.SkillType.STATUS)
	s.status_type = Skill.StatusType.HEAL
	s.status_to_apply = StatusSystem.REGENERATE
	bm.resolve_skill(bm.party[0], s, [ally])
	assert_eq(ally.regen_amount, strong, "the larger running regen is kept")
	bm.free()

func test_a_target_buff_lands_only_on_targets_hit() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.target_buff = "attack"
	var foe := bm.enemies[0]
	bm.resolve_skill(bm.party[0], s, [foe])
	assert_true(StatusSystem.is_effectively_buffed(foe, "attack"), "the struck enemy is enraged")
	bm.free()

func test_a_move_that_misses_everyone_has_no_after_effects() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.miss_chance = 1.0
	s.target_buff = "attack"
	s.status_to_apply = "defense_debuff"
	s.status_chance = 1.0
	s.recoil_percent = 50.0
	var hero := bm.party[0]
	var foe := bm.enemies[0]
	var hp := hero.current_hp
	var hits := _capture(bm)
	bm.resolve_skill(hero, s, [foe])
	assert_false(StatusSystem.is_effectively_buffed(foe, "attack"), "no buff")
	assert_false(StatusSystem.is_effectively_debuffed(foe, "defense"), "no rider")
	assert_eq(hero.current_hp, hp, "no recoil")
	assert_false(_actions(hits).has("recoil"), "no recoil result")
	bm.free()

func test_the_ally_heal_heals_the_users_whole_side() -> void:
	var bm := _manager(3, 2)
	for h in bm.party:
		h.current_hp -= 100
	var s := _skill(Skill.TargetType.ALL_ENEMIES)
	s.ally_heal_power = 1.0
	var foe_hp := bm.enemies.map(func(e): return e.current_hp)
	bm.resolve_skill(bm.party[0], s, [])
	for h in bm.party:
		assert_eq(h.current_hp, h.max_hp() - 100 + 20, "%s healed by MAG 20 x 1.0" % h.character_name)
	for i in bm.enemies.size():
		assert_true(bm.enemies[i].current_hp < foe_hp[i], "enemies are damaged, never healed")
	bm.free()

func test_the_ally_heal_reports_only_allies_it_actually_healed() -> void:
	# A full-HP ally gets no "0 Healed" popup (Gale Requiem is a level-1 special,
	# so a healthy party would otherwise see one per hero every cast).
	var bm := _manager(3, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.ally_heal_power = 1.0
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], s, [bm.enemies[0]])
	assert_eq(_actions(hits), ["skill_physical"], "the hit only: nobody needed healing")
	bm.free()

func test_the_ally_heal_skips_the_healthy_but_reports_the_hurt() -> void:
	var bm := _manager(3, 1)
	bm.party[1].current_hp -= 100
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.ally_heal_power = 1.0
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], s, [bm.enemies[0]])
	var heals := hits.filter(func(r): return r["action"] == "heal")
	assert_eq(heals.size(), 1, "one heal result")
	assert_eq(heals[0]["target"], bm.party[1], "for the hurt ally")
	assert_eq(int(heals[0]["value"]), 20, "worth what it healed")
	bm.free()

func test_an_enemys_ally_heal_heals_enemies() -> void:
	var bm := _manager(1, 2)
	for e in bm.enemies:
		e.current_hp -= 100
	var hero_hp := bm.party[0].max_hp() - 50
	bm.party[0].current_hp = hero_hp
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.ally_heal_power = 1.0
	bm.resolve_skill(bm.enemies[0], s, [bm.party[0]])
	for e in bm.enemies:
		assert_eq(e.current_hp, e.max_hp() - 80, "%s healed by 20" % e.character_name)
	assert_true(bm.party[0].current_hp < hero_hp, "the hero was hit, not healed")
	bm.free()

func test_recoil_is_a_share_of_the_damage_dealt() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.recoil_percent = 25.0
	var hero := bm.party[0]
	var hp := hero.current_hp
	var hits := _capture(bm)
	bm.resolve_skill(hero, s, [bm.enemies[0]])
	assert_eq(hero.current_hp, hp - 5, "25% of the 20 dealt")
	var r := hits.filter(func(x): return x["action"] == "recoil")
	assert_eq(r.size(), 1, "one recoil result")
	assert_eq(int(r[0]["value"]), 5, "worth 5")
	bm.free()

func test_recoil_never_knocks_the_user_out() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.recoil_percent = 25.0
	var hero := bm.party[0]
	hero.current_hp = 3
	bm.resolve_skill(hero, s, [bm.enemies[0]])
	assert_eq(hero.current_hp, 1, "recoil of 5 stops at 1 HP")
	bm.free()

func test_recoil_counts_only_hp_actually_lost() -> void:
	# The enemy hits a HERO with 8 HP for 20: only 8 was dealt. (A hero is the
	# victim so no quest progress is reported.)
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.recoil_percent = 25.0
	var foe := bm.enemies[0]
	var hp := foe.current_hp
	bm.party[0].current_hp = 8
	bm.resolve_skill(foe, s, [bm.party[0]])
	assert_eq(foe.current_hp, hp - 2, "25% of 8, not of 20")
	bm.free()

func test_a_self_debuff_lands_on_the_user_after_the_hits() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.self_debuff = "defense"
	var hero := bm.party[0]
	var hits := _capture(bm)
	bm.resolve_skill(hero, s, [bm.enemies[0]])
	assert_true(StatusSystem.is_effectively_debuffed(hero, "defense"), "the user's DEF is lowered")
	assert_eq(_actions(hits), ["skill_physical", "self_debuff"], "after the hit")
	bm.free()

func test_after_effects_run_heal_then_recoil_then_self_debuff() -> void:
	var bm := _manager(2, 1)
	# Both heroes need healing, or the heal reports nothing.
	for h in bm.party:
		h.current_hp -= 100
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.ally_heal_power = 1.0
	s.recoil_percent = 25.0
	s.self_debuff = "speed"
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], s, [bm.enemies[0]])
	assert_eq(_actions(hits), ["skill_physical", "heal", "heal", "recoil", "self_debuff"], "the spec's order")
	bm.free()

func test_an_unknown_stat_name_changes_nothing() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.self_debuff = "burn"
	s.target_buff = "burn"
	var hero := bm.party[0]
	var hits := _capture(bm)
	bm.resolve_skill(hero, s, [bm.enemies[0]])
	assert_false(_actions(hits).has("self_debuff"), "no self-debuff result")
	assert_true(hero.debuffs.is_empty(), "no debuff invented")
	assert_true(bm.enemies[0].buffs.is_empty(), "no buff invented")
	bm.free()

# --------------------------------------------------- Spec B: battle feedback

func test_took_damage_resonance_follows_the_first_hit_flag() -> void:
	assert_true(BattleScene.grants_damage_resonance({"action": "skill_physical", "is_first_hit": true}), "first landed hit")
	assert_false(BattleScene.grants_damage_resonance({"action": "skill_physical", "is_first_hit": false}), "a later hit")
	assert_true(BattleScene.grants_damage_resonance({"action": "attack"}), "a basic attack carries no flag and counts")
	assert_false(BattleScene.grants_damage_resonance({"action": "recoil", "is_first_hit": false}), "recoil is self-inflicted")
	assert_false(BattleScene.grants_damage_resonance({"action": "hp_cost", "is_first_hit": false}), "so is an HP cost")
	assert_false(BattleScene.grants_damage_resonance({"action": "miss", "is_first_hit": false}), "a miss deals nothing")

# --------------------------------------------------- Spec B: honest skills in battle

func test_the_real_cyclone_strikes_every_enemy_twice() -> void:
	var bm := _manager(1, 2)
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], load("res://data/skills/cyclone.tres"), [])
	for foe in bm.enemies:
		var on_foe := hits.filter(func(r): return r["target"] == foe and r["action"] == "skill_magic")
		assert_eq(on_foe.size(), 2, "%s hit twice" % foe.character_name)
	bm.free()

func test_the_real_gale_requiem_heals_the_party() -> void:
	var bm := _manager(2, 1)
	bm.party[1].current_hp -= 100
	var hp := bm.party[1].current_hp
	bm.resolve_skill(bm.party[0], load("res://data/skills/gale_requiem.tres"), [])
	assert_true(bm.party[1].current_hp > hp, "the ally was healed")
	bm.free()
