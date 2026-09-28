class_name PartyFactory
extends RefCounted

## PartyFactory — builds the default starting party.
## Heroes live in GameManager.party once created; this is only called for a fresh game.

## When each pool skill is learned, and which battle menu it belongs to, indexed
## by its position in Character.skills.
##
## `skills` is a POOL (up to Character.MAX_SKILLS) — heroes learn more moves than
## they can carry, and only Character.EQUIP_SLOTS of each category are usable at
## once. Each hero currently defines 12: six attacks and six specials, so there
## is a real choice to make at an NPC or campfire rather than a forced loadout.
##
## Heroes open with three usable moves (two attacks, one special) and the first
## level-up always teaches something — an empty first level-up makes the system
## look broken. Shared by all three heroes so the pacing is easy to balance.
const SKILL_UNLOCK_LEVELS: Array[int] = [
	1,   #  0 attack  — starting
	1,   #  1 attack  — starting
	2,   #  2 attack
	7,   #  3 attack
	1,   #  4 special — starting
	4,   #  5 special
	10,  #  6 special
	15,  #  7 special
	5,   #  8 attack   (pool-only until swapped in)
	12,  #  9 attack
	8,   # 10 special
	18,  # 11 special
]

## Which menu each pool slot feeds. Parallel to SKILL_UNLOCK_LEVELS. With six of
## each against four slots, the player always has something to swap.
const SKILL_CATEGORIES: Array[int] = [
	Skill.SkillCategory.ATTACK,  Skill.SkillCategory.ATTACK,
	Skill.SkillCategory.ATTACK,  Skill.SkillCategory.ATTACK,
	Skill.SkillCategory.SPECIAL, Skill.SkillCategory.SPECIAL,
	Skill.SkillCategory.SPECIAL, Skill.SkillCategory.SPECIAL,
	Skill.SkillCategory.ATTACK,  Skill.SkillCategory.ATTACK,
	Skill.SkillCategory.SPECIAL, Skill.SkillCategory.SPECIAL,
]

# Play-testing toggle, OFF for normal play. Flipping it to true collapses every
# unlock level to 1, so a fresh party knows its whole 12-move pool and the
# trainer/campfire loadout screens have something to swap between immediately.
# While it is on the curve in SKILL_UNLOCK_LEVELS never runs and level-ups teach
# nothing, so it must stay false in a shipped build.
const TEST_UNLOCK_ALL_SKILLS := false

const MOVES := "res://data/skills/"

## A hero's own copy of a library move. The file is the single definition of
## what the move does; the copy belongs to this hero, so stamping its unlock
## level and category — which differ per hero — can never leak into the file
## or into another hero who shares the move.
static func _move(file: String) -> Skill:
	var path := MOVES + file
	var template: Skill = load(path)
	var copy: Skill = template.duplicate(true)
	copy.source_path = path
	return copy

## Stamps the curve and category onto a hero's pool. Slots beyond the tables keep
## their Skill defaults (level 1, ATTACK) rather than becoming unreachable.
static func _apply_skill_tables(hero: Character) -> void:
	for i in hero.skills.size():
		if hero.skills[i] == null:
			continue
		if i < SKILL_UNLOCK_LEVELS.size():
			hero.skills[i].unlock_level = 1 if TEST_UNLOCK_ALL_SKILLS else SKILL_UNLOCK_LEVELS[i]
		elif TEST_UNLOCK_ALL_SKILLS:
			hero.skills[i].unlock_level = 1
		if i < SKILL_CATEGORIES.size():
			hero.skills[i].category = SKILL_CATEGORIES[i]

static func create_default_party() -> Array[Character]:
	var party: Array[Character] = [_create_aria(), _create_kael(), _create_lyra()]
	for hero in party:
		_apply_skill_tables(hero)
		# Fill the four attack and four special slots from what they know at
		# level 1, so a fresh party can fight without visiting a menu first.
		hero.auto_equip_unslotted()
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

	hero.skills = [
		_move("aqua_slash.tres"), _move("frost_bolt.tres"), _move("tide_pulse.tres"), _move("mend.tres"),
		_move("tidal_requiem.tres"), _move("hydro_pierce.tres"), _move("tidal_barrier.tres"), _move("grand_mend.tres"),
		_move("riptide_lash.tres"), _move("glacial_shard.tres"), _move("abyssal_veil.tres"), _move("maelstrom.tres"),
	] as Array[Skill]
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

	hero.skills = [
		_move("flame_strike.tres"), _move("shield_bash.tres"), _move("war_cry.tres"), _move("inferno.tres"),
		_move("phoenix_fury.tres"), _move("molten_blade.tres"), _move("iron_will.tres"), _move("flame_wall.tres"),
		_move("cinder_cleave.tres"), _move("guard_crush.tres"), _move("ember_ward.tres"), _move("scorched_earth.tres"),
	] as Array[Skill]
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

	hero.skills = [
		_move("wind_slash.tres"), _move("mend.tres"), _move("gust.tres"), _move("wind_barrier.tres"),
		_move("gale_requiem.tres"), _move("cyclone.tres"), _move("grand_mend.tres"), _move("tailwind.tres"),
		_move("zephyr_cut.tres"), _move("feather_volley.tres"), _move("restoring_breeze.tres"), _move("sanctuary.tres"),
	] as Array[Skill]
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

