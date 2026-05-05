class_name PartyFactory
extends RefCounted

## PartyFactory — builds the default starting party.
## Heroes live in GameManager.party once created; this is only called for a fresh game.

static func create_default_party() -> Array[Character]:
	return [_create_aria(), _create_kael(), _create_lyra()]

static func _create_aria() -> Character:
	var hero = Character.new()
	hero.character_name = "Aria"
	hero.character_class = "Mage"
	hero.element = ElementalSystem.Element.ARCANE
	hero.base_hp = 200
	hero.base_mp = 120
	hero.base_attack = 8
	hero.base_defense = 6
	hero.base_magic = 18
	hero.base_speed = 12
	hero.experience = 85
	hero.experience_to_next = 100
	hero.current_hp = hero.max_hp()
	hero.current_mp = hero.max_mp()
	hero.set_meta("ultimate_name", "Void Requiem")
	hero.set_meta("ultimate_desc", "Aria tears open the void, unleashing pure amethyst energy on all enemies.")

	var slash = _make_skill("Arcane Slash", "A swift slash imbued with arcane energy.",
		Skill.SkillType.DAMAGE, Skill.AttackType.STRIKE, ElementalSystem.Element.ARCANE,
		1.2, 0, Skill.TargetType.SINGLE_ENEMY)

	var frost = _make_skill("Frost Bolt", "A bolt of ice that slows the target.",
		Skill.SkillType.DAMAGE, Skill.AttackType.MAGIC, ElementalSystem.Element.ICE,
		1.5, 12, Skill.TargetType.SINGLE_ENEMY)

	var dark_pulse = _make_skill("Dark Pulse", "A wave of dark energy hitting all enemies.",
		Skill.SkillType.DAMAGE, Skill.AttackType.MAGIC, ElementalSystem.Element.DARK,
		1.0, 18, Skill.TargetType.ALL_ENEMIES)

	var heal_spell = _make_status_skill("Mend", "Restores HP to a single ally.",
		Skill.StatusType.HEAL, ElementalSystem.Element.LIGHT,
		1.8, 15, Skill.TargetType.SINGLE_ALLY)

	var requiem = _make_skill("Amethyst Requiem", "Aria's ultimate — a burst of pure amethyst energy.",
		Skill.SkillType.DAMAGE, Skill.AttackType.MAGIC, ElementalSystem.Element.ARCANE,
		3.5, 40, Skill.TargetType.ALL_ENEMIES)

	var void_strike = _make_skill("Void Strike", "Strikes through defenses with void energy.",
		Skill.SkillType.DAMAGE, Skill.AttackType.MAGIC, ElementalSystem.Element.DARK,
		2.5, 25, Skill.TargetType.SINGLE_ENEMY)

	var aria_barrier = _make_status_skill("Arcane Barrier", "Shields all allies with an arcane field.",
		Skill.StatusType.BUFF, ElementalSystem.Element.ARCANE,
		1.0, 20, Skill.TargetType.ALL_ALLIES)

	var mass_heal = _make_status_skill("Grand Mend", "Restores HP to all allies.",
		Skill.StatusType.HEAL, ElementalSystem.Element.LIGHT,
		1.5, 30, Skill.TargetType.ALL_ALLIES)

	hero.skills = [slash, frost, dark_pulse, heal_spell, requiem, void_strike, aria_barrier, mass_heal] as Array[Skill]
	return hero

static func _create_kael() -> Character:
	var hero = Character.new()
	hero.character_name = "Kael"
	hero.character_class = "Warrior"
	hero.element = ElementalSystem.Element.FIRE
	hero.base_hp = 280
	hero.base_mp = 60
	hero.base_attack = 20
	hero.base_defense = 14
	hero.base_magic = 6
	hero.base_speed = 8
	hero.experience = 0
	hero.experience_to_next = 100
	hero.current_hp = hero.max_hp()
	hero.current_mp = hero.max_mp()
	hero.set_meta("ultimate_name", "Phoenix Inferno")
	hero.set_meta("ultimate_desc", "Kael becomes one with the phoenix, raining fire on all enemies.")

	var flame_strike = _make_skill("Flame Strike", "A powerful strike wreathed in fire.",
		Skill.SkillType.DAMAGE, Skill.AttackType.STRIKE, ElementalSystem.Element.FIRE,
		1.4, 0, Skill.TargetType.SINGLE_ENEMY)

	var shield_bash = _make_skill("Shield Bash", "Stuns the enemy with a powerful bash.",
		Skill.SkillType.DAMAGE, Skill.AttackType.STRIKE, ElementalSystem.Element.NONE,
		1.0, 8, Skill.TargetType.SINGLE_ENEMY, "stun", 0.5)

	var war_cry = _make_status_skill("War Cry", "Boosts the party's fighting spirit.",
		Skill.StatusType.BUFF, ElementalSystem.Element.NONE,
		1.0, 10, Skill.TargetType.ALL_ALLIES)

	var inferno = _make_skill("Inferno", "Engulfs all enemies in roaring flames.",
		Skill.SkillType.DAMAGE, Skill.AttackType.MAGIC, ElementalSystem.Element.FIRE,
		1.2, 20, Skill.TargetType.ALL_ENEMIES)

	var phoenix = _make_skill("Phoenix Fury", "Kael's ultimate — unleashes the fury of a phoenix.",
		Skill.SkillType.DAMAGE, Skill.AttackType.MAGIC, ElementalSystem.Element.FIRE,
		4.0, 45, Skill.TargetType.ALL_ENEMIES)

	var molten = _make_skill("Molten Blade", "A blade heated to molten temperatures.",
		Skill.SkillType.DAMAGE, Skill.AttackType.STRIKE, ElementalSystem.Element.FIRE,
		2.8, 28, Skill.TargetType.SINGLE_ENEMY)

	var iron_will = _make_status_skill("Iron Will", "Regenerates HP each turn for the party.",
		Skill.StatusType.BUFF, ElementalSystem.Element.NONE,
		1.0, 22, Skill.TargetType.ALL_ALLIES)

	var flame_wall = _make_skill("Flame Wall", "Creates a wall of fire that poisons enemies.",
		Skill.SkillType.DAMAGE, Skill.AttackType.MAGIC, ElementalSystem.Element.FIRE,
		1.8, 32, Skill.TargetType.ALL_ENEMIES, "burn", 0.7)

	hero.skills = [flame_strike, shield_bash, war_cry, inferno, phoenix, molten, iron_will, flame_wall] as Array[Skill]
	return hero

static func _create_lyra() -> Character:
	var hero = Character.new()
	hero.character_name = "Lyra"
	hero.character_class = "Healer"
	hero.element = ElementalSystem.Element.WIND
	hero.base_hp = 220
	hero.base_mp = 100
	hero.base_attack = 7
	hero.base_defense = 8
	hero.base_magic = 16
	hero.base_speed = 14
	hero.experience = 0
	hero.experience_to_next = 100
	hero.current_hp = hero.max_hp()
	hero.current_mp = hero.max_mp()
	hero.set_meta("ultimate_name", "Gale Requiem")
	hero.set_meta("ultimate_desc", "Lyra calls upon the winds to heal all allies and damage all enemies.")

	var wind_slash = _make_skill("Wind Slash", "A sharp gust of wind that cuts through enemies.",
		Skill.SkillType.DAMAGE, Skill.AttackType.STRIKE, ElementalSystem.Element.WIND,
		1.1, 0, Skill.TargetType.SINGLE_ENEMY)

	var mend = _make_status_skill("Mend", "Restores HP to a single ally.",
		Skill.StatusType.HEAL, ElementalSystem.Element.WIND,
		1.8, 12, Skill.TargetType.SINGLE_ALLY)

	var gust = _make_skill("Gust", "Blows wind at all enemies dealing light damage.",
		Skill.SkillType.DAMAGE, Skill.AttackType.MAGIC, ElementalSystem.Element.WIND,
		0.9, 10, Skill.TargetType.ALL_ENEMIES)

	var barrier = _make_status_skill("Wind Barrier", "Surrounds an ally with wind, boosting their defense.",
		Skill.StatusType.BUFF, ElementalSystem.Element.WIND,
		1.0, 8, Skill.TargetType.SINGLE_ALLY)

	var gale = _make_skill("Gale Requiem", "Lyra's ultimate — heals all allies and damages all enemies with wild winds.",
		Skill.SkillType.DAMAGE, Skill.AttackType.MAGIC, ElementalSystem.Element.WIND,
		3.0, 40, Skill.TargetType.ALL_ENEMIES)

	var cyclone = _make_skill("Cyclone", "A massive cyclone that strikes all enemies twice.",
		Skill.SkillType.DAMAGE, Skill.AttackType.MAGIC, ElementalSystem.Element.WIND,
		2.2, 28, Skill.TargetType.ALL_ENEMIES)

	var grand_mend = _make_status_skill("Grand Mend", "Restores HP to all allies.",
		Skill.StatusType.HEAL, ElementalSystem.Element.WIND,
		1.5, 30, Skill.TargetType.ALL_ALLIES)

	var tailwind = _make_status_skill("Tailwind", "Boosts the speed and attack of all allies.",
		Skill.StatusType.BUFF, ElementalSystem.Element.WIND,
		1.0, 22, Skill.TargetType.ALL_ALLIES)

	hero.skills = [wind_slash, mend, gust, barrier, gale, cyclone, grand_mend, tailwind] as Array[Skill]
	return hero

# --- Skill construction helpers ---
static func _make_skill(name: String, desc: String, skill_type: Skill.SkillType,
		attack_type: Skill.AttackType, element: ElementalSystem.Element,
		power: float, mp_cost: int, target: Skill.TargetType,
		status: String = "", chance: float = 0.0) -> Skill:
	var s = Skill.new()
	s.skill_name = name
	s.description = desc
	s.skill_type = skill_type
	s.attack_type = attack_type
	s.element = element
	s.power = power
	s.mp_cost = mp_cost
	s.target_type = target
	s.status_to_apply = status
	s.status_chance = chance
	return s

static func _make_status_skill(name: String, desc: String, status_type: Skill.StatusType,
		element: ElementalSystem.Element, power: float, mp_cost: int,
		target: Skill.TargetType) -> Skill:
	var s = Skill.new()
	s.skill_name = name
	s.description = desc
	s.skill_type = Skill.SkillType.STATUS
	s.status_type = status_type
	s.element = element
	s.power = power
	s.mp_cost = mp_cost
	s.target_type = target
	return s
