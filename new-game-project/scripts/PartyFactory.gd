class_name PartyFactory
extends RefCounted

## PartyFactory — builds the default starting party.
## Heroes live in GameManager.party once created; this is only called for a fresh game.

## When each pool skill is learned, and which battle menu it belongs to, indexed
## by its position in Character.skills.
##
## `skills` is a POOL (up to Character.MAX_SKILLS) — heroes learn more moves than
## they can carry, and only Character.EQUIP_SLOTS of each category are usable at
## once. Each hero currently defines 18: eight attacks and ten specials, so
## there is a real choice to make at an NPC or campfire rather than a forced
## loadout.
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
	3,   # 12 attack   (Spec B: Brine Surge / Bloodfire Edge / Opportune Gust)
	9,   # 13 special  (Spec B: Mana Surge / Last Stand / Resonant Gale)
	14,  # 14 special  (Spec B: Abyssal Tithe / Provoking Blow / Tempest Gamble)
	6,   # 15 attack   (Spec C: Undertow / Sunforge Strike / Gathering Squall)
	11,  # 16 special  (Spec C: Deluge / Searing Brand / Windrunner's Blessing)
	16,  # 17 special  (Spec C: Tsunami / Eruption / Dawnsong)
]

## Which menu each pool slot feeds. Parallel to SKILL_UNLOCK_LEVELS. With eight
## attacks and ten specials against four slots each, the player always has
## something to swap.
const SKILL_CATEGORIES: Array[int] = [
	Skill.SkillCategory.ATTACK,  Skill.SkillCategory.ATTACK,
	Skill.SkillCategory.ATTACK,  Skill.SkillCategory.ATTACK,
	Skill.SkillCategory.SPECIAL, Skill.SkillCategory.SPECIAL,
	Skill.SkillCategory.SPECIAL, Skill.SkillCategory.SPECIAL,
	Skill.SkillCategory.ATTACK,  Skill.SkillCategory.ATTACK,
	Skill.SkillCategory.SPECIAL, Skill.SkillCategory.SPECIAL,
	Skill.SkillCategory.ATTACK,  Skill.SkillCategory.SPECIAL,
	Skill.SkillCategory.SPECIAL,
	Skill.SkillCategory.ATTACK,  Skill.SkillCategory.SPECIAL,   # Spec C: slots 16-18
	Skill.SkillCategory.SPECIAL,
]

# Play-testing toggle, OFF for normal play. Flipping it to true collapses every
# unlock level to 1, so a fresh party knows its whole 18-move pool and the
# trainer/campfire loadout screens have something to swap between immediately.
# While it is on the curve in SKILL_UNLOCK_LEVELS never runs and level-ups teach
# nothing, so it must stay false in a shipped build.
const TEST_UNLOCK_ALL_SKILLS := false

const MOVES := "res://data/skills/"

## Each hero's pool, in slot order. The order is load-bearing:
## SKILL_UNLOCK_LEVELS, SKILL_CATEGORIES and the equipped loadout are positional.
const POOLS := {
	"Aria": [
		"aqua_slash.tres", "frost_bolt.tres", "tide_pulse.tres", "mend.tres",
		"tidal_requiem.tres", "hydro_pierce.tres", "tidal_barrier.tres", "grand_mend.tres",
		"riptide_lash.tres", "glacial_shard.tres", "abyssal_veil.tres", "maelstrom.tres",
		"brine_surge.tres", "mana_surge.tres", "abyssal_tithe.tres",
		"undertow.tres", "deluge.tres", "tsunami.tres",
	],
	"Kael": [
		"flame_strike.tres", "shield_bash.tres", "war_cry.tres", "inferno.tres",
		"phoenix_fury.tres", "molten_blade.tres", "iron_will.tres", "flame_wall.tres",
		"cinder_cleave.tres", "guard_crush.tres", "ember_ward.tres", "scorched_earth.tres",
		"bloodfire_edge.tres", "last_stand.tres", "provoking_blow.tres",
		"sunforge_strike.tres", "searing_brand.tres", "eruption.tres",
	],
	"Lyra": [
		"wind_slash.tres", "mend.tres", "gust.tres", "wind_barrier.tres",
		"gale_requiem.tres", "cyclone.tres", "grand_mend.tres", "tailwind.tres",
		"zephyr_cut.tres", "feather_volley.tres", "restoring_breeze.tres", "sanctuary.tres",
		"opportune_gust.tres", "resonant_gale.tres", "tempest_gamble.tres",
		"gathering_squall.tres", "windrunners_blessing.tres", "dawnsong.tres",
	],
}

## A hero's whole pool as their own copies, in slot order.
static func _pool(hero_name: String) -> Array[Skill]:
	var out: Array[Skill] = []
	for f in POOLS[hero_name]:
		out.append(_move(f))
	return out

## Stamps the curve and category for pool slot `slot` onto a hero's copy.
static func _stamp_slot(skill: Skill, slot: int) -> void:
	if slot < SKILL_UNLOCK_LEVELS.size():
		skill.unlock_level = 1 if TEST_UNLOCK_ALL_SKILLS else SKILL_UNLOCK_LEVELS[slot]
	elif TEST_UNLOCK_ALL_SKILLS:
		skill.unlock_level = 1
	if slot < SKILL_CATEGORIES.size():
		skill.category = SKILL_CATEGORIES[slot]

## Appends, at the end of the pool, a copy of every move in this hero's factory
## pool that `hero` lacks — matched by file, or by name for a move saved before
## moves had files — stamped with that move's OWN slot's unlock level and
## category. A save keeps a pool exactly as written, so without this a save
## from before a pool grew would never gain the new moves. Returns how many
## were added; an unknown hero is left alone.
static func top_up_pool(hero: Character) -> int:
	if not POOLS.has(hero.character_name):
		return 0
	var have_paths := {}
	var have_names := {}
	for s in hero.skills:
		if s == null:
			continue
		if s.source_path != "":
			have_paths[s.source_path] = true
		have_names[s.skill_name] = true
	var files: Array = POOLS[hero.character_name]
	var added := 0
	for slot in files.size():
		var path: String = MOVES + files[slot]
		var template: Skill = load(path)
		if have_paths.has(path) or have_names.has(template.skill_name):
			continue
		if hero.skills.size() >= Character.MAX_SKILLS:
			break
		var copy := _move(files[slot])
		_stamp_slot(copy, slot)
		hero.skills.append(copy)
		added += 1
	return added

## After a save loads: give every hero the moves added to their pool since it
## was written, then fill any EMPTY loadout slots (the player's choices stay).
static func top_up_party(party: Array) -> void:
	for hero in party:
		if top_up_pool(hero) > 0:
			hero.auto_equip_unslotted()

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
		if hero.skills[i] != null:
			_stamp_slot(hero.skills[i], i)

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

	hero.skills = _pool("Aria")
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

	hero.skills = _pool("Kael")
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

	hero.skills = _pool("Lyra")
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

