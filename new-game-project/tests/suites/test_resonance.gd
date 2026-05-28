extends TestSuite

func suite_name() -> String:
	return "ResonanceSystem"

func _party() -> Array[Character]:
	var a = Character.new()
	a.character_name = "A"
	var b = Character.new()
	b.character_name = "B"
	return [a, b] as Array[Character]

func _system(party: Array[Character]) -> ResonanceSystem:
	var rs = ResonanceSystem.new()
	rs.setup(party)
	return rs

func test_starts_at_zero() -> void:
	var p = _party()
	var rs = _system(p)
	assert_near(rs.get_resonance(p[0]), 0.0, 0.01, "resonance starts at 0")
	assert_false(rs.is_full(p[0]), "not full at start")

func test_on_attack_adds_resonance() -> void:
	var p = _party()
	var rs = _system(p)
	rs.on_attack(p[0])
	assert_near(rs.get_resonance(p[0]), 10.0, 0.01, "attack adds 10 resonance")
	assert_near(rs.get_resonance(p[1]), 0.0, 0.01, "only attacker gains")

func test_on_damage_taken_adds_resonance() -> void:
	var p = _party()
	var rs = _system(p)
	rs.on_damage_taken(p[1])
	assert_near(rs.get_resonance(p[1]), 10.0, 0.01, "taking damage adds 10")

func test_caps_at_max_and_is_full() -> void:
	var p = _party()
	var rs = _system(p)
	for i in range(20):
		rs.on_attack(p[0])
	assert_near(rs.get_resonance(p[0]), 100.0, 0.01, "resonance caps at 100")
	assert_true(rs.is_full(p[0]), "is_full at 100")

func test_skill_resonance_uses_override() -> void:
	var p = _party()
	var rs = _system(p)
	var s = Skill.new()
	s.skill_type = Skill.SkillType.STATUS
	s.status_type = Skill.StatusType.HEAL  # heal -> 0 resonance by default
	rs.on_skill_used(p[0], s)
	assert_near(rs.get_resonance(p[0]), 0.0, 0.01, "heal skill grants no resonance")

func test_can_combine_requires_two_full() -> void:
	var p = _party()
	var rs = _system(p)
	assert_false(rs.can_combine(p), "cannot combine when nobody is full")
	for i in range(10):
		rs.on_attack(p[0])
		rs.on_attack(p[1])
	assert_true(rs.can_combine(p), "can combine when both full")

func test_setup_preserves_existing_resonance() -> void:
	# Resonance persists across battles — setup must NOT zero existing values.
	var p = _party()
	p[0].resonance_meter = 60.0
	p[1].resonance_meter = 30.0
	var rs = _system(p)  # calls setup
	assert_near(rs.get_resonance(p[0]), 60.0, 0.01, "hero 0 resonance preserved through setup")
	assert_near(rs.get_resonance(p[1]), 30.0, 0.01, "hero 1 resonance preserved through setup")

func test_spend_solo_and_combined() -> void:
	var p = _party()
	var rs = _system(p)
	for i in range(10):
		rs.on_attack(p[0])
	assert_true(rs.spend_solo_ultimate(p[0]), "spend solo when full")
	assert_near(rs.get_resonance(p[0]), 0.0, 0.01, "solo spend resets to 0")
	assert_false(rs.spend_solo_ultimate(p[0]), "cannot spend solo when empty")
