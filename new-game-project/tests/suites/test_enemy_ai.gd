extends TestSuite

## Note: EnemyAI reads GameManager.species_memory, so these tests mutate and
## then restore that global to stay isolated.

func suite_name() -> String:
	return "EnemyAI"

func _enemy(species: String) -> Enemy:
	var e = Enemy.new()
	e.species = species
	e.character_name = species
	e.base_hp = 50
	e.level = 1
	e.current_hp = e.max_hp()
	return e

func test_dodge_chance_by_memory_tier() -> void:
	var e = _enemy("MemTestA")
	var saved = GameManager.species_memory.duplicate()

	GameManager.species_memory["MemTestA"] = 0
	assert_near(EnemyAI.get_dodge_chance(e), 0.0, 0.001, "0 encounters -> 0 dodge")

	GameManager.species_memory["MemTestA"] = 3
	assert_near(EnemyAI.get_dodge_chance(e), 0.05, 0.001, "Tier1 (3) -> 5% dodge")

	GameManager.species_memory["MemTestA"] = 7
	assert_near(EnemyAI.get_dodge_chance(e), 0.10, 0.001, "Tier2 (7) -> 10% dodge")

	GameManager.species_memory["MemTestA"] = 15
	assert_near(EnemyAI.get_dodge_chance(e), 0.15, 0.001, "Tier3 (15) -> 15% dodge")

	GameManager.species_memory = saved

func test_resonance_attack_never_dodged() -> void:
	var e = _enemy("MemTestB")
	var saved = GameManager.species_memory.duplicate()
	GameManager.species_memory["MemTestB"] = 999
	# is_resonance=true must always return false (hit)
	var dodged_any := false
	for i in range(50):
		if EnemyAI.try_dodge(e, true, true):
			dodged_any = true
	assert_false(dodged_any, "resonance attacks always hit (never dodged)")
	GameManager.species_memory = saved

func test_cannot_miss_never_dodged() -> void:
	var e = _enemy("MemTestC")
	var saved = GameManager.species_memory.duplicate()
	GameManager.species_memory["MemTestC"] = 999
	var dodged_any := false
	for i in range(50):
		if EnemyAI.try_dodge(e, false, false):  # can_miss = false
			dodged_any = true
	assert_false(dodged_any, "can_miss=false attacks always hit")
	GameManager.species_memory = saved

func test_choose_action_returns_skill_and_target() -> void:
	var e = _enemy("MemTestD")
	var skill = Skill.new()
	skill.skill_type = Skill.SkillType.DAMAGE
	skill.attack_type = Skill.AttackType.STRIKE
	skill.power = 1.0
	e.skills = [skill] as Array[Skill]

	var hero = Character.new()
	hero.character_name = "Hero"
	hero.base_hp = 100
	hero.current_hp = 100

	var decision = EnemyAI.choose_action(e, [hero] as Array[Character], [e] as Array[Character])
	assert_ne(decision.get("skill"), null, "AI returns a skill")
	assert_eq(decision.get("target"), hero, "AI targets the only alive hero")

func test_choose_action_no_alive_party() -> void:
	var e = _enemy("MemTestE")
	var dead = Character.new()
	dead.current_hp = 0
	var decision = EnemyAI.choose_action(e, [dead] as Array[Character], [e] as Array[Character])
	assert_true(decision.is_empty(), "no alive party -> empty decision")

# --- No wasted turns: a heal is a choice only when someone it reaches is hurt --

func _heal(target_type: Skill.TargetType) -> Skill:
	var s := Skill.new()
	s.skill_name = "Mend"
	s.skill_type = Skill.SkillType.STATUS
	s.status_type = Skill.StatusType.HEAL
	s.target_type = target_type
	s.power = 1.0
	return s

func _bite() -> Skill:
	var s := Skill.new()
	s.skill_name = "Bite"
	s.power = 1.0
	return s

func _hero() -> Character:
	var h := Character.new()
	h.character_name = "Hero"
	h.base_hp = 100
	h.current_hp = 100
	return h

## How many of `draws` decisions by `enemy` (fighting beside `allies`) pick
## the move named `skill_name`.
func _times_picked(enemy: Enemy, allies: Array[Character], skill_name: String, draws: int = 200) -> int:
	var n := 0
	for i in draws:
		var d := EnemyAI.choose_action(enemy, [_hero()] as Array[Character], allies)
		if d.get("skill") != null and d.get("skill").skill_name == skill_name:
			n += 1
	return n

func test_an_unhurt_enemy_never_spends_a_turn_healing_itself() -> void:
	var e := _enemy("HealTestA")
	e.skills = [_bite(), _heal(Skill.TargetType.SELF)] as Array[Skill]
	assert_eq(_times_picked(e, [e] as Array[Character], "Mend"), 0, "at full HP the self-heal is never picked")

func test_a_hurt_enemy_may_still_heal_itself() -> void:
	var e := _enemy("HealTestB")
	e.skills = [_bite(), _heal(Skill.TargetType.SELF)] as Array[Skill]
	e.current_hp = e.max_hp() / 2
	assert_true(_times_picked(e, [e] as Array[Character], "Mend") > 0, "once hurt, the self-heal is back in play")

func test_an_ally_heal_waits_until_someone_on_its_side_is_hurt() -> void:
	var e := _enemy("HealTestC")
	var ally := _enemy("HealTestC")
	e.skills = [_bite(), _heal(Skill.TargetType.SINGLE_ALLY)] as Array[Skill]
	assert_eq(_times_picked(e, [e, ally] as Array[Character], "Mend"), 0, "with every ally unhurt the heal is never picked")
	ally.current_hp = ally.max_hp() / 2
	assert_true(_times_picked(e, [e, ally] as Array[Character], "Mend") > 0, "a hurt ally brings it back")

func test_an_ally_heal_goes_to_a_hurt_ally() -> void:
	# The small ally has the least HP but is unhurt; healing it would be wasted.
	var e := _enemy("HealTestD")
	e.skills = [_heal(Skill.TargetType.SINGLE_ALLY)] as Array[Skill]
	var small := _enemy("HealTestD")
	small.base_hp = 10
	small.current_hp = small.max_hp()
	var big := _enemy("HealTestD")
	big.base_hp = 200
	big.current_hp = big.max_hp() - 1
	var d := EnemyAI.choose_action(e, [_hero()] as Array[Character], [e, small, big] as Array[Character])
	assert_eq(d.get("skill").skill_name, "Mend", "the heal is picked")
	assert_eq(d.get("target"), big, "and it goes to the ally who is actually hurt")

func test_an_enemy_with_only_a_heal_attacks_when_nobody_is_hurt() -> void:
	var e := _enemy("HealTestE")
	e.skills = [_heal(Skill.TargetType.SELF)] as Array[Skill]
	var d := EnemyAI.choose_action(e, [_hero()] as Array[Character], [e] as Array[Character])
	assert_eq(d.get("skill"), null, "no move worth using: a basic attack instead")
