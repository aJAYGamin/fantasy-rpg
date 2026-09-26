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
