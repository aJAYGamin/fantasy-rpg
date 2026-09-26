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
