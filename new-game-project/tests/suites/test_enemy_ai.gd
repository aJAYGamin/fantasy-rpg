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
