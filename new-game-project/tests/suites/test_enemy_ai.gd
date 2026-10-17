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

# --- No wasted turns: a buff or debuff is a choice only where it changes something

func _effect_move(name: String, kind: Skill.StatusType, target_type: Skill.TargetType,
		token: String, turns := 0) -> Skill:
	var s := Skill.new()
	s.skill_name = name
	s.skill_type = Skill.SkillType.STATUS
	s.status_type = kind
	s.target_type = target_type
	s.status_to_apply = token
	s.effect_turns = turns
	return s

## How many of `draws` decisions pick `skill_name`, with `party` as the heroes.
func _picks_against(enemy: Enemy, party: Array[Character], allies: Array[Character],
		skill_name: String, draws: int = 200) -> int:
	var n := 0
	for i in draws:
		var d := EnemyAI.choose_action(enemy, party, allies)
		if d.get("skill") != null and d.get("skill").skill_name == skill_name:
			n += 1
	return n

func test_an_enemy_never_recasts_a_buff_it_already_has() -> void:
	var e := _enemy("BuffTestA")
	e.skills = [_bite(), _effect_move("Rally", Skill.StatusType.BUFF, Skill.TargetType.SELF, "attack_buff")] as Array[Skill]
	e.apply_buff("attack")
	assert_eq(_times_picked(e, [e] as Array[Character], "Rally"), 0, "the buff is already on: never picked")
	var fresh := _enemy("BuffTestA")
	fresh.skills = e.skills
	assert_true(_times_picked(fresh, [fresh] as Array[Character], "Rally") > 0, "without it, the buff is in play")

func test_recasting_a_timed_buff_only_counts_when_it_adds_time() -> void:
	var e := _enemy("BuffTestB")
	e.skills = [_bite(), _effect_move("Rally", Skill.StatusType.BUFF, Skill.TargetType.SELF, "attack_buff", 3)] as Array[Skill]
	e.apply_buff("attack", 3)
	assert_eq(_times_picked(e, [e] as Array[Character], "Rally"), 0, "3 turns left of a 3-turn buff: nothing to add")
	e.buff_turns["attack"] = 1  # two of its turns later
	assert_true(_times_picked(e, [e] as Array[Character], "Rally") > 0, "1 turn left: recasting stretches it to 3")

func test_an_ally_buff_goes_to_an_ally_without_it() -> void:
	var e := _enemy("BuffTestC")
	e.skills = [_effect_move("Shield Up", Skill.StatusType.BUFF, Skill.TargetType.SINGLE_ALLY, "defense_buff")] as Array[Skill]
	var ally := _enemy("BuffTestC")
	e.apply_buff("defense")
	for i in 20:
		var d := EnemyAI.choose_action(e, [_hero()] as Array[Character], [e, ally] as Array[Character])
		assert_eq(d.get("target"), ally, "never the caster, who already has it")
	ally.apply_buff("defense")
	var d2 := EnemyAI.choose_action(e, [_hero()] as Array[Character], [e, ally] as Array[Character])
	assert_eq(d2.get("skill"), null, "everyone has it: a basic attack instead")

func test_an_enemy_never_casts_a_debuff_every_hero_already_has() -> void:
	var e := _enemy("DebuffTestA")
	e.skills = [_bite(), _effect_move("Sunder", Skill.StatusType.DEBUFF, Skill.TargetType.SINGLE_ENEMY, "defense_debuff")] as Array[Skill]
	var a := _hero()
	var b := _hero()
	a.apply_debuff("defense")
	b.apply_debuff("defense")
	assert_eq(_picks_against(e, [a, b] as Array[Character], [e] as Array[Character], "Sunder"), 0, "both heroes already lowered: never picked")

func test_a_debuff_goes_to_a_hero_who_lacks_it() -> void:
	var e := _enemy("DebuffTestB")
	e.skills = [_effect_move("Sunder", Skill.StatusType.DEBUFF, Skill.TargetType.SINGLE_ENEMY, "defense_debuff")] as Array[Skill]
	var a := _hero()
	var b := _hero()
	a.apply_debuff("defense")
	for i in 20:
		var d := EnemyAI.choose_action(e, [a, b] as Array[Character], [e] as Array[Character])
		assert_eq(d.get("target"), b, "only the hero it would change")

func test_a_status_move_skips_a_hero_who_cannot_take_it() -> void:
	# Mutex statuses don't stack: a paralysed hero can't also be poisoned.
	var e := _enemy("DebuffTestC")
	e.skills = [_bite(), _effect_move("Miasma", Skill.StatusType.DEBUFF, Skill.TargetType.SINGLE_ENEMY, "poison")] as Array[Skill]
	var h := _hero()
	h.add_status(StatusSystem.PARALYSIS)
	assert_eq(_picks_against(e, [h] as Array[Character], [e] as Array[Character], "Miasma"), 0, "the only hero can't take it: never picked")

func test_a_regen_buff_waits_while_regen_is_running() -> void:
	var e := _enemy("BuffTestD")
	e.skills = [_bite(), _effect_move("Renew", Skill.StatusType.BUFF, Skill.TargetType.SELF, "regenerate")] as Array[Skill]
	e.start_regen(BattleManager.REGEN_TURNS)
	assert_eq(_times_picked(e, [e] as Array[Character], "Renew"), 0, "regen already running in full: never picked")
