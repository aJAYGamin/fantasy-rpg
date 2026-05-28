extends TestSuite

func suite_name() -> String:
	return "Skill"

func _dmg(power: float, atk_type) -> Skill:
	var s = Skill.new()
	s.skill_type = Skill.SkillType.DAMAGE
	s.attack_type = atk_type
	s.power = power
	return s

func _status(st) -> Skill:
	var s = Skill.new()
	s.skill_type = Skill.SkillType.STATUS
	s.status_type = st
	return s

func test_is_heal_buff_debuff() -> void:
	assert_true(_status(Skill.StatusType.HEAL).is_heal(), "STATUS+HEAL -> is_heal")
	assert_false(_status(Skill.StatusType.HEAL).is_buff(), "HEAL is not buff")
	assert_true(_status(Skill.StatusType.BUFF).is_buff(), "STATUS+BUFF -> is_buff")
	assert_true(_status(Skill.StatusType.DEBUFF).is_debuff(), "STATUS+DEBUFF -> is_debuff")
	assert_false(_dmg(1.0, Skill.AttackType.STRIKE).is_heal(), "DAMAGE skill is not heal")

func test_is_physical_is_magic() -> void:
	assert_true(_dmg(1.0, Skill.AttackType.STRIKE).is_physical(), "STRIKE is physical")
	assert_true(_dmg(1.0, Skill.AttackType.RANGED).is_physical(), "RANGED is physical")
	assert_true(_dmg(1.0, Skill.AttackType.MAGIC).is_magic(), "MAGIC is magic")
	assert_false(_dmg(1.0, Skill.AttackType.MAGIC).is_physical(), "MAGIC is not physical")

func test_calculate_value_uses_correct_stat() -> void:
	var user = Character.new()
	user.base_attack = 20
	user.base_magic = 10
	user.level = 1
	user.current_hp = user.max_hp()
	var strike = _dmg(2.0, Skill.AttackType.STRIKE)
	assert_eq(strike.calculate_value(user), 40, "STRIKE scales with attack_power (20*2)")
	var magic = _dmg(2.0, Skill.AttackType.MAGIC)
	assert_eq(magic.calculate_value(user), 20, "MAGIC scales with magic_power (10*2)")

func test_calculate_value_heal_uses_magic() -> void:
	var user = Character.new()
	user.base_magic = 10
	user.level = 1
	user.current_hp = user.max_hp()
	var heal = _status(Skill.StatusType.HEAL)
	heal.power = 1.5
	assert_eq(heal.calculate_value(user), 15, "HEAL uses magic_power (10*1.5)")
	var buff = _status(Skill.StatusType.BUFF)
	buff.power = 2.0
	assert_eq(buff.calculate_value(user), 0, "BUFF skill calculate_value is 0")

func test_can_use_checks_mp_and_stun() -> void:
	var user = Character.new()
	user.base_mp = 50
	user.level = 1
	user.current_mp = 10
	var s = _dmg(1.0, Skill.AttackType.MAGIC)
	s.mp_cost = 5
	assert_true(s.can_use(user), "enough MP -> can_use")
	s.mp_cost = 20
	assert_false(s.can_use(user), "not enough MP -> cannot use")
	s.mp_cost = 5
	user.add_status("stun")
	assert_false(s.can_use(user), "stunned -> cannot use")

func test_enemies_ignore_mp_cost() -> void:
	# Enemies have no MP pool — can_use() must return true regardless of mp_cost
	# so EnemyAI can pick any skill the enemy owns.
	var foe = Enemy.new()
	foe.level = 1
	foe.current_mp = 0  # would normally block a costed skill
	var s = _dmg(1.0, Skill.AttackType.MAGIC)
	s.mp_cost = 999
	assert_true(s.can_use(foe), "Enemy with 0 MP can still use a 999-cost skill")
	# Stun still blocks enemies — MP bypass is not a status bypass.
	foe.add_status("stun")
	assert_false(s.can_use(foe), "Stunned enemy still cannot act")

func test_heroes_still_pay_mp() -> void:
	# Regression guard for the enemy-bypass change above: Characters (heroes)
	# must still be gated by MP cost.
	var hero = Character.new()
	hero.base_mp = 50
	hero.level = 1
	hero.current_mp = 5
	var s = _dmg(1.0, Skill.AttackType.MAGIC)
	s.mp_cost = 20
	assert_false(s.can_use(hero), "Hero without enough MP cannot use skill")
	hero.current_mp = 30
	assert_true(s.can_use(hero), "Hero with enough MP can use skill")

func test_resonance_gain() -> void:
	var dmg = _dmg(1.0, Skill.AttackType.STRIKE)
	assert_near(dmg.get_resonance_gain(), 10.0, 0.01, "DAMAGE default resonance = 10")
	var heal = _status(Skill.StatusType.HEAL)
	assert_near(heal.get_resonance_gain(), 0.0, 0.01, "HEAL resonance = 0")
	dmg.resonance_gain_override = 25.0
	assert_near(dmg.get_resonance_gain(), 25.0, 0.01, "override respected")

func test_skill_type_display() -> void:
	assert_eq(_dmg(1.0, Skill.AttackType.STRIKE).get_skill_type_display(), "Strike", "DAMAGE+STRIKE display")
	assert_eq(_dmg(1.0, Skill.AttackType.MAGIC).get_skill_type_display(), "Magic", "DAMAGE+MAGIC display")
	assert_eq(_status(Skill.StatusType.HEAL).get_skill_type_display(), "Heal", "STATUS+HEAL display")
	assert_eq(_status(Skill.StatusType.BUFF).get_skill_type_display(), "Buff", "STATUS+BUFF display")
	assert_eq(_status(Skill.StatusType.DEBUFF).get_skill_type_display(), "Debuff", "STATUS+DEBUFF display")
