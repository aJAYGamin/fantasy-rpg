class_name PartyFactory
extends RefCounted

## PartyFactory — builds the default starting party.
## Heroes live in GameManager.party once created; this is only called for a fresh game.

static func create_default_party() -> Array[Character]:
	var party: Array[Character] = [_create_aria(), _create_kael(), _create_lyra()]
	# TEST SEED: stock the shared party inventory (the leader, party[0], holds all
	# items) so the pause-menu Items screen and the battle item menu have content
	# from a fresh game. Replace with real starting-loot balancing for actual play.
	_seed_starter_items(party[0].inventory)
	_seed_starter_equipment(party)
	return party

static func _create_aria() -> Character:
	var hero = Character.new()
	hero.character_name = "Aria"
	hero.character_class = "Mage"
	hero.element = ElementalSystem.Element.WATER
	hero.base_hp = 200
	hero.base_mp = 120
	hero.base_attack = 8
	hero.base_defense = 6
	hero.base_magic = 18
	hero.base_arcane = 14   # high magic resistance — Aria is the magic specialist
	hero.base_speed = 12
	hero.experience = 85
	hero.experience_to_next = 100
	hero.current_hp = hero.max_hp()
	hero.current_mp = hero.max_mp()
	hero.set_meta("ultimate_name", "Tidal Requiem")
	hero.set_meta("ultimate_desc", "Aria calls forth a crushing tide, drowning all enemies in pure aquatic fury.")
	hero.set_meta("bio", "A prodigy of the tidal arts, Aria channels the ocean's calm and its fury in equal measure. She joined the journey to learn why the old water-shrines have fallen silent.")

	# Attacks (indices 0–3)
	var slash = _make_skill("Aqua Slash", "A swift slash trailing arcing water.",
		Skill.SkillType.DAMAGE, Skill.AttackType.STRIKE, ElementalSystem.Element.WATER,
		1.2, 0, Skill.TargetType.SINGLE_ENEMY)

	var frost = _make_skill("Frost Bolt", "A bolt of ice that slows the target.",
		Skill.SkillType.DAMAGE, Skill.AttackType.MAGIC, ElementalSystem.Element.ICE,
		1.5, 12, Skill.TargetType.SINGLE_ENEMY)

	var tide_pulse = _make_skill("Tide Pulse", "A wave of crashing water hitting all enemies.",
		Skill.SkillType.DAMAGE, Skill.AttackType.MAGIC, ElementalSystem.Element.WATER,
		1.0, 18, Skill.TargetType.ALL_ENEMIES)

	var heal_spell = _make_status_skill("Mend", "Restores HP to a single ally.",
		Skill.StatusType.HEAL, ElementalSystem.Element.LIGHT,
		1.8, 15, Skill.TargetType.SINGLE_ALLY)

	# Specials (indices 4–7)
	var requiem = _make_skill("Tidal Requiem", "Aria's ultimate — a torrent of pure aquatic energy.",
		Skill.SkillType.DAMAGE, Skill.AttackType.MAGIC, ElementalSystem.Element.WATER,
		3.5, 40, Skill.TargetType.ALL_ENEMIES)

	var hydro_pierce = _make_skill("Hydro Pierce", "Pierces through defenses with a high-pressure water spike.",
		Skill.SkillType.DAMAGE, Skill.AttackType.MAGIC, ElementalSystem.Element.WATER,
		2.5, 25, Skill.TargetType.SINGLE_ENEMY)

	# "Shields" -> DEF buff. Target ALL_ALLIES so the whole party gets a chip.
	var aria_barrier = _make_status_skill("Tidal Barrier", "Shields all allies with a swirling tide.",
		Skill.StatusType.BUFF, ElementalSystem.Element.WATER,
		1.0, 20, Skill.TargetType.ALL_ALLIES, "defense_buff")

	var mass_heal = _make_status_skill("Grand Mend", "Restores HP to all allies.",
		Skill.StatusType.HEAL, ElementalSystem.Element.LIGHT,
		1.5, 30, Skill.TargetType.ALL_ALLIES)

	hero.skills = [slash, frost, tide_pulse, heal_spell, requiem, hydro_pierce, aria_barrier, mass_heal] as Array[Skill]
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
	hero.base_arcane = 5    # low magic resistance — Kael is a physical bruiser
	hero.base_speed = 8
	hero.experience = 85
	hero.experience_to_next = 100
	hero.current_hp = hero.max_hp()
	hero.current_mp = hero.max_mp()
	hero.set_meta("ultimate_name", "Phoenix Inferno")
	hero.set_meta("ultimate_desc", "Kael becomes one with the phoenix, raining fire on all enemies.")
	hero.set_meta("bio", "A hot-blooded warrior whose blade burns as fiercely as his temper. Kael fights to shield those who cannot fight for themselves, carrying the ember of a home long lost.")

	var flame_strike = _make_skill("Flame Strike", "A powerful strike wreathed in fire.",
		Skill.SkillType.DAMAGE, Skill.AttackType.STRIKE, ElementalSystem.Element.FIRE,
		1.4, 0, Skill.TargetType.SINGLE_ENEMY)

	var shield_bash = _make_skill("Shield Bash", "Stuns the enemy with a powerful bash.",
		Skill.SkillType.DAMAGE, Skill.AttackType.STRIKE, ElementalSystem.Element.NORMAL,
		1.0, 8, Skill.TargetType.SINGLE_ENEMY, "stun", 0.5)

	# "Fighting spirit" -> ATK buff.
	var war_cry = _make_status_skill("War Cry", "Boosts the party's fighting spirit.",
		Skill.StatusType.BUFF, ElementalSystem.Element.SOUND,
		1.0, 10, Skill.TargetType.ALL_ALLIES, "attack_buff")

	var inferno = _make_skill("Inferno", "Engulfs all enemies in roaring flames.",
		Skill.SkillType.DAMAGE, Skill.AttackType.MAGIC, ElementalSystem.Element.FIRE,
		1.2, 20, Skill.TargetType.ALL_ENEMIES)

	var phoenix = _make_skill("Phoenix Fury", "Kael's ultimate — unleashes the fury of a phoenix.",
		Skill.SkillType.DAMAGE, Skill.AttackType.MAGIC, ElementalSystem.Element.FIRE,
		4.0, 45, Skill.TargetType.ALL_ENEMIES)

	var molten = _make_skill("Molten Blade", "A blade heated to molten temperatures.",
		Skill.SkillType.DAMAGE, Skill.AttackType.STRIKE, ElementalSystem.Element.FIRE,
		2.8, 28, Skill.TargetType.SINGLE_ENEMY)

	# Heals the party over a few turns (transient regen effect, not a status chip).
	var iron_will = _make_status_skill("Iron Will", "Regenerates HP each turn for the party.",
		Skill.StatusType.BUFF, ElementalSystem.Element.NORMAL,
		1.0, 22, Skill.TargetType.ALL_ALLIES, "regenerate")

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
	hero.base_arcane = 12   # solid magic resistance — Lyra is a healer/support
	hero.base_speed = 14
	hero.experience = 85
	hero.experience_to_next = 100
	hero.current_hp = hero.max_hp()
	hero.current_mp = hero.max_mp()
	hero.set_meta("ultimate_name", "Gale Requiem")
	hero.set_meta("ultimate_desc", "Lyra calls upon the winds to heal all allies and damage all enemies.")
	hero.set_meta("bio", "A gentle healer who hears the whispers of the wind. Lyra mends wounds and spirits alike, searching for the lost melody said to soothe the coming Requiem.")

	var wind_slash = _make_skill("Wind Slash", "A sharp gust of wind that cuts through enemies.",
		Skill.SkillType.DAMAGE, Skill.AttackType.STRIKE, ElementalSystem.Element.WIND,
		1.1, 0, Skill.TargetType.SINGLE_ENEMY)

	var mend = _make_status_skill("Mend", "Restores HP to a single ally.",
		Skill.StatusType.HEAL, ElementalSystem.Element.WIND,
		1.8, 12, Skill.TargetType.SINGLE_ALLY)

	var gust = _make_skill("Gust", "Blows wind at all enemies dealing light damage.",
		Skill.SkillType.DAMAGE, Skill.AttackType.MAGIC, ElementalSystem.Element.WIND,
		0.9, 10, Skill.TargetType.ALL_ENEMIES)

	# Description literally says "boosting their defense" -> DEF buff on a single ally.
	var barrier = _make_status_skill("Wind Barrier", "Surrounds an ally with wind, boosting their defense.",
		Skill.StatusType.BUFF, ElementalSystem.Element.WIND,
		1.0, 8, Skill.TargetType.SINGLE_ALLY, "defense_buff")

	var gale = _make_skill("Gale Requiem", "Lyra's ultimate — heals all allies and damages all enemies with wild winds.",
		Skill.SkillType.DAMAGE, Skill.AttackType.MAGIC, ElementalSystem.Element.WIND,
		3.0, 40, Skill.TargetType.ALL_ENEMIES)

	var cyclone = _make_skill("Cyclone", "A massive cyclone that strikes all enemies twice.",
		Skill.SkillType.DAMAGE, Skill.AttackType.MAGIC, ElementalSystem.Element.WIND,
		2.2, 28, Skill.TargetType.ALL_ENEMIES)

	var grand_mend = _make_status_skill("Grand Mend", "Restores HP to all allies.",
		Skill.StatusType.HEAL, ElementalSystem.Element.WIND,
		1.5, 30, Skill.TargetType.ALL_ALLIES)

	# Description says "speed and attack" — single-token system can apply one. SPD
	# is the closer fit for "Tailwind". (User: ask me if you'd rather have ATK,
	# or split this into two skills, one for each buff.)
	var tailwind = _make_status_skill("Tailwind", "Boosts the speed of all allies.",
		Skill.StatusType.BUFF, ElementalSystem.Element.WIND,
		1.0, 22, Skill.TargetType.ALL_ALLIES, "speed_buff")

	hero.skills = [wind_slash, mend, gust, barrier, gale, cyclone, grand_mend, tailwind] as Array[Skill]
	return hero

# --- Starter inventory (test seed) ---
# Item definitions live in ItemFactory; this just lists starting quantities so
# seeds and enemy drops share one source of truth. Replace with real
# starting-loot balancing for actual play.
static func _seed_starter_items(inv: Inventory) -> void:
	var starter_quantities := {
		"Health Potion": 5,
		"Mana Potion": 3,
		"Elixir": 1,
		"Phoenix Down": 2,
		"Antidote": 3,
		"Fire Bomb": 3,
		"Smoke Veil": 2,
		"Monster Fang": 4,
		"Worn Pendant": 1,
		"Amethyst Shard": 1,
		"Silent Shrine Key": 1,
	}
	for item_name in starter_quantities:
		var item := ItemFactory.create(item_name, starter_quantities[item_name])
		if item != null:
			inv.add_item(item)

# --- Starter equipment (test seed) ---
# Equip a class/element-appropriate weapon, armor, and accessory on each hero,
# and leave a few spare pieces in the shared pool (party[0]) so the Equipment
# screen has things to swap. Definitions live in EquipmentFactory.
static func _seed_starter_equipment(party: Array[Character]) -> void:
	var pool := party[0].inventory
	# hero -> [weapon, armor, accessory]
	var loadouts := [
		["Apprentice Staff", "Mage Robe", "Sage Pendant"],     # Aria  (Mage / Water)
		["Iron Greatsword", "Knight's Plate", "Power Ring"],   # Kael  (Warrior / Fire)
		["Cedar Wand", "Healer's Garb", "Swift Boots"],        # Lyra  (Healer / Wind)
	]
	for i in range(min(party.size(), loadouts.size())):
		for name in loadouts[i]:
			_equip_new(party[i], pool, name)
	# Spare gear, left unequipped in the shared pool.
	for name in ["Worn Shortsword", "Leather Vest", "Guardian Charm",
			"Vitality Brooch", "Tidecaller Rod", "Galewind Cloak"]:
		var e := EquipmentFactory.create(name)
		if e != null:
			pool.add_equipment(e)
	# Top heroes off so they start at full including the gear's max-HP/MP bonuses.
	for hero in party:
		hero.current_hp = hero.max_hp()
		hero.current_mp = hero.max_mp()

# Creates a fresh piece into the shared pool, then equips it onto `hero`.
static func _equip_new(hero: Character, pool: Inventory, name: String) -> void:
	var e := EquipmentFactory.create(name)
	if e == null:
		return
	pool.add_equipment(e)
	Inventory.equip_from_pool(hero, pool, e)

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
		target: Skill.TargetType, status_to_apply: String = "") -> Skill:
	var s = Skill.new()
	s.skill_name = name
	s.description = desc
	s.skill_type = Skill.SkillType.STATUS
	s.status_type = status_type
	s.element = element
	s.power = power
	s.mp_cost = mp_cost
	s.target_type = target
	# Token can be a stat-buff ("attack_buff"), stat-debuff ("magic_debuff"),
	# or a legacy named status ("regenerate"). Empty -> regenerate by default.
	s.status_to_apply = status_to_apply
	return s
