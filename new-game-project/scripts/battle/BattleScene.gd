extends Node2D

## BattleScene.gd — The Amethyst Requiem

@onready var background       = $Background
@onready var party_positions  = $CharactersLayer/PartyPositions
@onready var enemy_positions  = $CharactersLayer/EnemyPositions
@onready var enemy_info_row   = $BattleUI/UIRoot/EnemyInfoRow
@onready var party_status_bar = $BattleUI/UIRoot/PartyStatusBar
@onready var hero_status_1    = $BattleUI/UIRoot/PartyStatusBar/HeroStatus1
@onready var hero_status_2    = $BattleUI/UIRoot/PartyStatusBar/HeroStatus2
@onready var hero_status_3    = $BattleUI/UIRoot/PartyStatusBar/HeroStatus3
@onready var action_menu      = $BattleUI/UIRoot/ActionMenu
@onready var action_title     = $BattleUI/UIRoot/ActionMenu/ActionLayout/ActionTitle
@onready var attack_btn       = $BattleUI/UIRoot/ActionMenu/ActionLayout/ActionGrid/AttackButton
@onready var special_btn      = $BattleUI/UIRoot/ActionMenu/ActionLayout/ActionGrid/SpecialButton
@onready var items_btn        = $BattleUI/UIRoot/ActionMenu/ActionLayout/ActionGrid/ItemsButton
@onready var run_btn          = $BattleUI/UIRoot/ActionMenu/ActionLayout/ActionGrid/RunButton
@onready var resonance_btn       = $BattleUI/UIRoot/ActionMenu/ActionLayout/ResonanceButton
@onready var turn_order_indicator = $BattleUI/UIRoot/TurnOrderIndicator
@onready var attack_menu          = $BattleUI/UIRoot/AttackMenu
@onready var resonance_menu       = $BattleUI/UIRoot/ResonanceMenu
@onready var items_menu           = $BattleUI/UIRoot/ItemsMenu
@onready var victory_screen   = $BattleUI/UIRoot/VictoryScreen
@onready var defeat_screen    = $BattleUI/UIRoot/DefeatScreen
@onready var level_up_screen  = $BattleUI/UIRoot/LevelUpScreen

# --- Systems ---
var battle_manager: BattleManager
var resonance_system: ResonanceSystem

# Enemy portrait layout options
enum EnemyLayout {
	ROW,        # All in one horizontal row
	GRID_2COL,  # 2 columns grid
	GRID_3COL,  # 3 columns grid
	DIAGONAL,   # Slight diagonal stagger
}

# --- State ---
var current_actor: Character = null
var _enemy_layout: EnemyLayout = EnemyLayout.GRID_2COL
var _max_hp: Dictionary = {}   # character -> max hp at battle start
var _max_mp: Dictionary = {}   # character -> max mp at battle start
var _enemy_hp_bars: Dictionary = {}   # character -> ProgressBar
var _enemy_hp_labels: Dictionary = {} # character -> Label

# --- Backgrounds per area ---
const BACKGROUNDS = {
	"fallster_plains": "res://assets/backgrounds/FallsterPlains.png",
	"ruins":           "res://assets/backgrounds/bg_ruins.png",
	"forest":          "res://assets/backgrounds/bg_forest.png",
	"city":            "res://assets/backgrounds/bg_city.png",
}

func _ready():
	battle_manager = BattleManager.new()
	add_child(battle_manager)
	resonance_system = ResonanceSystem.new()
	add_child(resonance_system)

	battle_manager.battle_started.connect(_on_battle_started)
	battle_manager.turn_started.connect(_on_turn_started)
	battle_manager.action_performed.connect(_on_action_performed)
	battle_manager.character_defeated.connect(_on_character_defeated)
	battle_manager.battle_ended.connect(_on_battle_ended)
	battle_manager.enemy_move_preview.connect(_on_enemy_move_preview)
	battle_manager.status_effect_triggered.connect(_on_status_triggered)

	attack_btn.pressed.connect(_on_attack_pressed)
	special_btn.pressed.connect(_on_special_pressed)
	items_btn.pressed.connect(_on_items_pressed)
	run_btn.pressed.connect(_on_run_pressed)
	resonance_btn.pressed.connect(_on_resonance_pressed)

	resonance_system.resonance_changed.connect(_on_resonance_changed)
	resonance_system.resonance_full.connect(_on_resonance_full)

	# Connect victory/defeat screens
	victory_screen.victory_closed.connect(_on_victory_closed)
	victory_screen.setup_level_up_screen(level_up_screen)

	_start_test_battle()

func set_background(area: String):
	if BACKGROUNDS.has(area):
		var texture = load(BACKGROUNDS[area])
		if texture:
			background.texture = texture

func start_battle(party: Array[Character], enemies: Array[Character], area: String = "fallster_plains", enemy_layout: EnemyLayout = EnemyLayout.GRID_2COL):
	_enemy_layout = enemy_layout
	set_background(area)
	resonance_system.setup(party)
	# Store max values at battle start so bars don't change mid-battle
	for c in party:
		_max_hp[c] = c.max_hp()
		_max_mp[c] = c.max_mp()
	for e in enemies:
		_max_hp[e] = e.max_hp()
		_max_mp[e] = e.max_mp()
	_setup_hero_panels(party)
	_setup_enemy_cards(enemies)
	turn_order_indicator.setup(party, enemies)
	_setup_portraits(party, enemies)
	attack_menu.setup(battle_manager, resonance_system)
	attack_menu.move_selected.connect(_on_move_selected)
	attack_menu.menu_closed.connect(_on_attack_menu_closed)
	resonance_menu.setup(battle_manager, resonance_system)
	resonance_menu.resonance_action_selected.connect(_on_resonance_action)
	resonance_menu.menu_closed.connect(_on_attack_menu_closed)
	_test_items = _create_test_items()
	items_menu.setup(battle_manager, null)
	items_menu.set_items(_test_items)
	items_menu.item_used.connect(_on_item_used)
	items_menu.menu_closed.connect(_on_attack_menu_closed)
	battle_manager.start_battle(party, enemies)

func _start_test_battle():
	await get_tree().process_frame
	await get_tree().process_frame
	var hero1 = Character.new()
	hero1.character_name = "Aria"
	hero1.character_class = "Mage"
	hero1.element = ElementalSystem.Element.ARCANE
	hero1.base_hp = 200
	hero1.base_mp = 120
	hero1.base_attack = 8    # Mages have low but non-zero physical attack
	hero1.base_defense = 6
	hero1.base_magic = 18
	hero1.base_speed = 12
	hero1.experience = 85
	hero1.experience_to_next = 100
	hero1.current_hp = hero1.max_hp()
	hero1.current_mp = hero1.max_mp()
	hero1.set_meta("ultimate_name", "Void Requiem")
	hero1.set_meta("ultimate_desc", "Aria tears open the void, unleashing pure amethyst energy on all enemies.")

	# Aria's attacks (index 0-3)
	var slash = Skill.new()
	slash.skill_name = "Arcane Slash"
	slash.description = "A swift slash imbued with arcane energy."
	slash.skill_type = Skill.SkillType.PHYSICAL
	slash.element = ElementalSystem.Element.ARCANE
	slash.power = 1.2
	slash.mp_cost = 0
	slash.target_type = Skill.TargetType.SINGLE_ENEMY

	var frost = Skill.new()
	frost.skill_name = "Frost Bolt"
	frost.description = "A bolt of ice that slows the target."
	frost.skill_type = Skill.SkillType.MAGIC
	frost.element = ElementalSystem.Element.ICE
	frost.power = 1.5
	frost.mp_cost = 12
	frost.target_type = Skill.TargetType.SINGLE_ENEMY

	var dark_pulse = Skill.new()
	dark_pulse.skill_name = "Dark Pulse"
	dark_pulse.description = "A wave of dark energy hitting all enemies."
	dark_pulse.skill_type = Skill.SkillType.MAGIC
	dark_pulse.element = ElementalSystem.Element.DARK
	dark_pulse.power = 1.0
	dark_pulse.mp_cost = 18
	dark_pulse.target_type = Skill.TargetType.ALL_ENEMIES

	var heal_spell = Skill.new()
	heal_spell.skill_name = "Mend"
	heal_spell.description = "Restores HP to a single ally."
	heal_spell.skill_type = Skill.SkillType.HEAL
	heal_spell.element = ElementalSystem.Element.LIGHT
	heal_spell.power = 1.8
	heal_spell.mp_cost = 15
	heal_spell.target_type = Skill.TargetType.SINGLE_ALLY

	# Aria's specials (index 4-7)
	var requiem = Skill.new()
	requiem.skill_name = "Amethyst Requiem"
	requiem.description = "Aria's ultimate — a burst of pure amethyst energy."
	requiem.skill_type = Skill.SkillType.MAGIC
	requiem.element = ElementalSystem.Element.ARCANE
	requiem.power = 3.5
	requiem.mp_cost = 40
	requiem.target_type = Skill.TargetType.ALL_ENEMIES

	var void_strike = Skill.new()
	void_strike.skill_name = "Void Strike"
	void_strike.description = "Strikes through defenses with void energy."
	void_strike.skill_type = Skill.SkillType.MAGIC
	void_strike.element = ElementalSystem.Element.DARK
	void_strike.power = 2.5
	void_strike.mp_cost = 25
	void_strike.target_type = Skill.TargetType.SINGLE_ENEMY

	var aria_barrier = Skill.new()
	aria_barrier.skill_name = "Arcane Barrier"
	aria_barrier.description = "Shields all allies with an arcane field."
	aria_barrier.skill_type = Skill.SkillType.BUFF
	aria_barrier.element = ElementalSystem.Element.ARCANE
	aria_barrier.power = 1.0
	aria_barrier.mp_cost = 20
	aria_barrier.target_type = Skill.TargetType.ALL_ALLIES

	var mass_heal = Skill.new()
	mass_heal.skill_name = "Grand Mend"
	mass_heal.description = "Restores HP to all allies."
	mass_heal.skill_type = Skill.SkillType.HEAL
	mass_heal.element = ElementalSystem.Element.LIGHT
	mass_heal.power = 1.5
	mass_heal.mp_cost = 30
	mass_heal.target_type = Skill.TargetType.ALL_ALLIES

	var h1_skills: Array[Skill] = [slash, frost, dark_pulse, heal_spell, requiem, void_strike, aria_barrier, mass_heal]
	hero1.skills = h1_skills

	var hero2 = Character.new()
	hero2.character_name = "Kael"
	hero2.character_class = "Warrior"
	hero2.element = ElementalSystem.Element.FIRE
	hero2.base_hp = 280
	hero2.base_mp = 60
	hero2.base_attack = 20
	hero2.base_defense = 14
	hero2.base_magic = 6     # Warriors have low but non-zero magic
	hero2.base_speed = 8
	hero2.experience = 0
	hero2.experience_to_next = 100
	hero2.current_hp = hero2.max_hp()
	hero2.current_mp = hero2.max_mp()
	hero2.set_meta("ultimate_name", "Phoenix Inferno")
	hero2.set_meta("ultimate_desc", "Kael becomes one with the phoenix, raining fire on all enemies.")

	# Kael's attacks (index 0-3)
	var flame_strike = Skill.new()
	flame_strike.skill_name = "Flame Strike"
	flame_strike.description = "A powerful strike wreathed in fire."
	flame_strike.skill_type = Skill.SkillType.PHYSICAL
	flame_strike.element = ElementalSystem.Element.FIRE
	flame_strike.power = 1.4
	flame_strike.mp_cost = 0
	flame_strike.target_type = Skill.TargetType.SINGLE_ENEMY

	var shield_bash = Skill.new()
	shield_bash.skill_name = "Shield Bash"
	shield_bash.description = "Stuns the enemy with a powerful bash."
	shield_bash.skill_type = Skill.SkillType.PHYSICAL
	shield_bash.element = ElementalSystem.Element.NONE
	shield_bash.power = 1.0
	shield_bash.mp_cost = 8
	shield_bash.status_to_apply = "stun"
	shield_bash.status_chance = 0.5
	shield_bash.target_type = Skill.TargetType.SINGLE_ENEMY

	var war_cry = Skill.new()
	war_cry.skill_name = "War Cry"
	war_cry.description = "Boosts the party's fighting spirit."
	war_cry.skill_type = Skill.SkillType.BUFF
	war_cry.element = ElementalSystem.Element.NONE
	war_cry.power = 1.0
	war_cry.mp_cost = 10
	war_cry.target_type = Skill.TargetType.ALL_ALLIES

	var inferno = Skill.new()
	inferno.skill_name = "Inferno"
	inferno.description = "Engulfs all enemies in roaring flames."
	inferno.skill_type = Skill.SkillType.MAGIC
	inferno.element = ElementalSystem.Element.FIRE
	inferno.power = 1.2
	inferno.mp_cost = 20
	inferno.target_type = Skill.TargetType.ALL_ENEMIES

	# Kael's specials (index 4-7)
	var phoenix = Skill.new()
	phoenix.skill_name = "Phoenix Fury"
	phoenix.description = "Kael's ultimate — unleashes the fury of a phoenix."
	phoenix.skill_type = Skill.SkillType.MAGIC
	phoenix.element = ElementalSystem.Element.FIRE
	phoenix.power = 4.0
	phoenix.mp_cost = 45
	phoenix.target_type = Skill.TargetType.ALL_ENEMIES

	var molten = Skill.new()
	molten.skill_name = "Molten Blade"
	molten.description = "A blade heated to molten temperatures."
	molten.skill_type = Skill.SkillType.PHYSICAL
	molten.element = ElementalSystem.Element.FIRE
	molten.power = 2.8
	molten.mp_cost = 28
	molten.target_type = Skill.TargetType.SINGLE_ENEMY

	var iron_will = Skill.new()
	iron_will.skill_name = "Iron Will"
	iron_will.description = "Regenerates HP each turn for the party."
	iron_will.skill_type = Skill.SkillType.BUFF
	iron_will.element = ElementalSystem.Element.NONE
	iron_will.power = 1.0
	iron_will.mp_cost = 22
	iron_will.target_type = Skill.TargetType.ALL_ALLIES

	var flame_wall = Skill.new()
	flame_wall.skill_name = "Flame Wall"
	flame_wall.description = "Creates a wall of fire that poisons enemies."
	flame_wall.skill_type = Skill.SkillType.MAGIC
	flame_wall.element = ElementalSystem.Element.FIRE
	flame_wall.power = 1.8
	flame_wall.mp_cost = 32
	flame_wall.status_to_apply = "burn"
	flame_wall.status_chance = 0.7
	flame_wall.target_type = Skill.TargetType.ALL_ENEMIES

	var h2_skills: Array[Skill] = [flame_strike, shield_bash, war_cry, inferno, phoenix, molten, iron_will, flame_wall]
	hero2.skills = h2_skills

	# Ice Golem — weak to Fire (Kael will do 2x damage)
	var enemy1 = Character.new()
	enemy1.character_name = "Ice Golem"
	enemy1.element = ElementalSystem.Element.ICE
	enemy1.base_hp = 60
	enemy1.base_attack = 8
	enemy1.base_defense = 6
	enemy1.base_magic = 10
	enemy1.base_speed = 7
	enemy1.current_hp = enemy1.max_hp()

	# Ice Golem skills
	var ice_shard = Skill.new()
	ice_shard.skill_name = "Ice Shard"
	ice_shard.skill_type = Skill.SkillType.MAGIC
	ice_shard.element = ElementalSystem.Element.ICE
	ice_shard.power = 1.2
	ice_shard.mp_cost = 0
	ice_shard.target_type = Skill.TargetType.SINGLE_ENEMY

	var blizzard = Skill.new()
	blizzard.skill_name = "Blizzard"
	blizzard.skill_type = Skill.SkillType.MAGIC
	blizzard.element = ElementalSystem.Element.ICE
	blizzard.power = 1.8
	blizzard.mp_cost = 15
	blizzard.target_type = Skill.TargetType.ALL_ENEMIES

	var frost_armor = Skill.new()
	frost_armor.skill_name = "Frost Armor"
	frost_armor.skill_type = Skill.SkillType.BUFF
	frost_armor.element = ElementalSystem.Element.ICE
	frost_armor.power = 1.0
	frost_armor.mp_cost = 10
	frost_armor.target_type = Skill.TargetType.SELF

	var e1_skills: Array[Skill] = [ice_shard, blizzard, frost_armor]
	enemy1.skills = e1_skills

	# Fire Drake — resists Fire (Kael does 0.5x), weak to Ice
	var enemy2 = Character.new()
	enemy2.character_name = "Fire Drake"
	enemy2.element = ElementalSystem.Element.FIRE
	enemy2.base_hp = 50
	enemy2.base_attack = 10
	enemy2.base_defense = 5
	enemy2.base_magic = 12
	enemy2.base_speed = 9
	enemy2.current_hp = enemy2.max_hp()

	# Fire Drake skills
	var flame_breath = Skill.new()
	flame_breath.skill_name = "Flame Breath"
	flame_breath.skill_type = Skill.SkillType.MAGIC
	flame_breath.element = ElementalSystem.Element.FIRE
	flame_breath.power = 1.4
	flame_breath.mp_cost = 0
	flame_breath.target_type = Skill.TargetType.SINGLE_ENEMY

	var inferno_roar = Skill.new()
	inferno_roar.skill_name = "Inferno Roar"
	inferno_roar.skill_type = Skill.SkillType.MAGIC
	inferno_roar.element = ElementalSystem.Element.FIRE
	inferno_roar.power = 2.0
	inferno_roar.mp_cost = 20
	inferno_roar.target_type = Skill.TargetType.ALL_ENEMIES

	var ember_bite = Skill.new()
	ember_bite.skill_name = "Ember Bite"
	ember_bite.skill_type = Skill.SkillType.PHYSICAL
	ember_bite.element = ElementalSystem.Element.FIRE
	ember_bite.power = 1.0
	ember_bite.mp_cost = 0
	ember_bite.status_to_apply = "burn"
	ember_bite.status_chance = 0.4
	ember_bite.target_type = Skill.TargetType.SINGLE_ENEMY

	var dragon_regen = Skill.new()
	dragon_regen.skill_name = "Dragon Regen"
	dragon_regen.description = "The Fire Drake regenerates its scales."
	dragon_regen.skill_type = Skill.SkillType.HEAL
	dragon_regen.element = ElementalSystem.Element.FIRE
	dragon_regen.power = 1.5
	dragon_regen.mp_cost = 10
	dragon_regen.target_type = Skill.TargetType.SELF

	var e2_skills: Array[Skill] = [flame_breath, inferno_roar, ember_bite, dragon_regen]
	enemy2.skills = e2_skills

	# Start with 50 gold to verify gold addition on victory screen
	GameManager.gold = 50

	# Hero 3: Lyra (Wind healer)
	var hero3 = Character.new()
	hero3.character_name = "Lyra"
	hero3.character_class = "Healer"
	hero3.element = ElementalSystem.Element.WIND
	hero3.base_hp = 220
	hero3.base_mp = 100
	hero3.base_attack = 7
	hero3.base_defense = 8
	hero3.base_magic = 16
	hero3.base_speed = 14
	hero3.experience = 0
	hero3.experience_to_next = 100
	hero3.current_hp = hero3.max_hp()
	hero3.current_mp = hero3.max_mp()
	hero3.set_meta("ultimate_name", "Gale Requiem")
	hero3.set_meta("ultimate_desc", "Lyra calls upon the winds to heal all allies and damage all enemies.")

	# Lyra's attacks (index 0-3)
	var lyra_wind_slash = Skill.new()
	lyra_wind_slash.skill_name = "Wind Slash"
	lyra_wind_slash.description = "A sharp gust of wind that cuts through enemies."
	lyra_wind_slash.skill_type = Skill.SkillType.PHYSICAL
	lyra_wind_slash.element = ElementalSystem.Element.WIND
	lyra_wind_slash.power = 1.1
	lyra_wind_slash.mp_cost = 0
	lyra_wind_slash.target_type = Skill.TargetType.SINGLE_ENEMY

	var lyra_mend = Skill.new()
	lyra_mend.skill_name = "Mend"
	lyra_mend.description = "Restores HP to a single ally."
	lyra_mend.skill_type = Skill.SkillType.HEAL
	lyra_mend.element = ElementalSystem.Element.WIND
	lyra_mend.power = 1.8
	lyra_mend.mp_cost = 12
	lyra_mend.target_type = Skill.TargetType.SINGLE_ALLY

	var lyra_gust = Skill.new()
	lyra_gust.skill_name = "Gust"
	lyra_gust.description = "Blows wind at all enemies dealing light damage."
	lyra_gust.skill_type = Skill.SkillType.MAGIC
	lyra_gust.element = ElementalSystem.Element.WIND
	lyra_gust.power = 0.9
	lyra_gust.mp_cost = 10
	lyra_gust.target_type = Skill.TargetType.ALL_ENEMIES

	var lyra_barrier = Skill.new()
	lyra_barrier.skill_name = "Wind Barrier"
	lyra_barrier.description = "Surrounds an ally with wind, boosting their defense."
	lyra_barrier.skill_type = Skill.SkillType.BUFF
	lyra_barrier.element = ElementalSystem.Element.WIND
	lyra_barrier.power = 1.0
	lyra_barrier.mp_cost = 8
	lyra_barrier.target_type = Skill.TargetType.SINGLE_ALLY

	# Lyra's specials (index 4-7)
	var lyra_gale = Skill.new()
	lyra_gale.skill_name = "Gale Requiem"
	lyra_gale.description = "Lyra's ultimate — heals all allies and damages all enemies with wild winds."
	lyra_gale.skill_type = Skill.SkillType.MAGIC
	lyra_gale.element = ElementalSystem.Element.WIND
	lyra_gale.power = 3.0
	lyra_gale.mp_cost = 40
	lyra_gale.target_type = Skill.TargetType.ALL_ENEMIES

	var lyra_cyclone = Skill.new()
	lyra_cyclone.skill_name = "Cyclone"
	lyra_cyclone.description = "A massive cyclone that strikes all enemies twice."
	lyra_cyclone.skill_type = Skill.SkillType.MAGIC
	lyra_cyclone.element = ElementalSystem.Element.WIND
	lyra_cyclone.power = 2.2
	lyra_cyclone.mp_cost = 28
	lyra_cyclone.target_type = Skill.TargetType.ALL_ENEMIES

	var lyra_grand_mend = Skill.new()
	lyra_grand_mend.skill_name = "Grand Mend"
	lyra_grand_mend.description = "Restores HP to all allies."
	lyra_grand_mend.skill_type = Skill.SkillType.HEAL
	lyra_grand_mend.element = ElementalSystem.Element.WIND
	lyra_grand_mend.power = 1.5
	lyra_grand_mend.mp_cost = 30
	lyra_grand_mend.target_type = Skill.TargetType.ALL_ALLIES

	var lyra_tailwind = Skill.new()
	lyra_tailwind.skill_name = "Tailwind"
	lyra_tailwind.description = "Boosts the speed and attack of all allies."
	lyra_tailwind.skill_type = Skill.SkillType.BUFF
	lyra_tailwind.element = ElementalSystem.Element.WIND
	lyra_tailwind.power = 1.0
	lyra_tailwind.mp_cost = 22
	lyra_tailwind.target_type = Skill.TargetType.ALL_ALLIES

	var h3_skills: Array[Skill] = [lyra_wind_slash, lyra_mend, lyra_gust, lyra_barrier, lyra_gale, lyra_cyclone, lyra_grand_mend, lyra_tailwind]
	hero3.skills = h3_skills

	# 10 enemies of varying types
	var enemy_defs = [
		{"name": "Ice Golem",    "element": ElementalSystem.Element.ICE,        "hp": 60,  "atk": 8,  "mag": 10},
		{"name": "Fire Drake",   "element": ElementalSystem.Element.FIRE,       "hp": 50,  "atk": 10, "mag": 12},
		{"name": "Dark Wraith",  "element": ElementalSystem.Element.DARK,       "hp": 45,  "atk": 12, "mag": 8},
		{"name": "Storm Eagle",  "element": ElementalSystem.Element.LIGHTNING,  "hp": 40,  "atk": 9,  "mag": 14},
		{"name": "Earth Golem",  "element": ElementalSystem.Element.EARTH,      "hp": 80,  "atk": 7,  "mag": 6},
		{"name": "Sea Serpent",  "element": ElementalSystem.Element.WATER,      "hp": 55,  "atk": 11, "mag": 10},
		{"name": "Wind Sprite",  "element": ElementalSystem.Element.WIND,       "hp": 35,  "atk": 8,  "mag": 15},
		{"name": "Light Golem",  "element": ElementalSystem.Element.LIGHT,      "hp": 65,  "atk": 9,  "mag": 11},
		{"name": "Void Shade",   "element": ElementalSystem.Element.ARCANE,     "hp": 42,  "atk": 13, "mag": 13},
		{"name": "Frost Wyrm",   "element": ElementalSystem.Element.ICE,        "hp": 70,  "atk": 10, "mag": 9},
	]
	var enemies: Array[Character] = []
	for def in enemy_defs:
		var e = Character.new()
		e.character_name = def["name"]
		e.element = def["element"]
		e.base_hp = def["hp"]
		e.base_attack = def["atk"]
		e.base_defense = 5
		e.base_magic = def["mag"]
		e.base_speed = randi_range(6, 12)
		e.current_hp = e.max_hp()
		e.skills = _generate_enemy_skills(e)
		enemies.append(e)

	# Start with 50 gold to verify gold addition on victory screen
	GameManager.gold = 50

	var party: Array[Character] = [hero1, hero2, hero3]
	start_battle(party, enemies, "fallster_plains", EnemyLayout.GRID_2COL)

func _make_skill(skill_name: String, desc: String, type: Skill.SkillType,
	elem: ElementalSystem.Element, power: float, mp: int,
	target: Skill.TargetType, status: String = "", chance: float = 0.0) -> Skill:
	var s = Skill.new()
	s.skill_name = skill_name
	s.description = desc
	s.skill_type = type
	s.element = elem
	s.power = power
	s.mp_cost = mp
	s.target_type = target
	s.status_to_apply = status
	s.status_chance = chance
	return s

func _get_enemy_unique_skills(enemy_name: String, elem: ElementalSystem.Element) -> Array[Skill]:
	var S = Skill.SkillType
	var T = Skill.TargetType
	var E = ElementalSystem.Element
	var skills: Array[Skill] = []
	match enemy_name:
		"Ice Golem":
			skills = [
				_make_skill("Glacial Fist",   "A frozen punch that chills to the bone.",          S.PHYSICAL, E.ICE,       1.1, 0,  T.SINGLE_ENEMY),
				_make_skill("Frost Breath",   "Exhales a cone of freezing air.",                  S.MAGIC,    E.ICE,       1.4, 10, T.SINGLE_ENEMY, "freeze", 0.35),
				_make_skill("Blizzard",       "Summons a blizzard hitting all heroes.",            S.MAGIC,    E.ICE,       1.0, 18, T.ALL_ENEMIES),
				_make_skill("Ice Armor",      "Encases itself in ice, restoring some HP.",         S.HEAL,     E.ICE,       1.2, 12, T.SELF),
			]
		"Fire Drake":
			skills = [
				_make_skill("Flame Bite",     "A savage bite that burns on contact.",             S.PHYSICAL, E.FIRE,      1.1, 0,  T.SINGLE_ENEMY, "burn", 0.4),
				_make_skill("Inferno Breath", "A torrent of fire from its maw.",                  S.MAGIC,    E.FIRE,      1.5, 12, T.SINGLE_ENEMY),
				_make_skill("Dragon Roar",    "A terrifying roar that scorches all heroes.",       S.MAGIC,    E.FIRE,      1.0, 20, T.ALL_ENEMIES),
				_make_skill("Fire Scales",    "Channels fire energy to regenerate HP.",            S.HEAL,     E.FIRE,      1.2, 12, T.SELF),
			]
		"Dark Wraith":
			skills = [
				_make_skill("Shadow Claw",    "A claw strike infused with dark energy.",          S.PHYSICAL, E.DARK,      1.2, 0,  T.SINGLE_ENEMY),
				_make_skill("Soul Drain",     "Drains the life force of a hero.",                 S.MAGIC,    E.DARK,      1.4, 10, T.SINGLE_ENEMY, "poison", 0.5),
				_make_skill("Dark Pulse",     "A wave of dark energy that corrupts all heroes.",  S.MAGIC,    E.DARK,      1.0, 18, T.ALL_ENEMIES),
				_make_skill("Void Shroud",    "Wraps itself in darkness, healing its wounds.",    S.HEAL,     E.DARK,      1.1, 10, T.SELF),
			]
		"Storm Eagle":
			skills = [
				_make_skill("Talon Strike",   "A lightning-fast talon attack.",                   S.PHYSICAL, E.LIGHTNING, 1.2, 0,  T.SINGLE_ENEMY),
				_make_skill("Thunder Beak",   "Strikes with a beak charged with lightning.",      S.MAGIC,    E.LIGHTNING, 1.4, 10, T.SINGLE_ENEMY, "stun", 0.3),
				_make_skill("Storm Dive",     "Dives through the party trailing lightning.",       S.MAGIC,    E.LIGHTNING, 1.0, 18, T.ALL_ENEMIES),
				_make_skill("Wind Ride",      "Rides an updraft to recover HP.",                  S.HEAL,     E.LIGHTNING, 1.0, 10, T.SELF),
			]
		"Earth Golem":
			skills = [
				_make_skill("Boulder Smash",  "Slams a massive fist into one hero.",              S.PHYSICAL, E.EARTH,     1.3, 0,  T.SINGLE_ENEMY),
				_make_skill("Stone Spike",    "Drives a spike of rock into a hero.",              S.MAGIC,    E.EARTH,     1.3, 10, T.SINGLE_ENEMY),
				_make_skill("Earthquake",     "Shakes the ground beneath all heroes.",            S.MAGIC,    E.EARTH,     1.0, 20, T.ALL_ENEMIES),
				_make_skill("Earth Mend",     "Draws energy from the earth to heal.",             S.HEAL,     E.EARTH,     1.4, 14, T.SELF),
			]
		"Sea Serpent":
			skills = [
				_make_skill("Coil Crush",     "Wraps around and crushes a hero.",                 S.PHYSICAL, E.WATER,     1.2, 0,  T.SINGLE_ENEMY),
				_make_skill("Tidal Wave",     "Crashes water over one hero.",                     S.MAGIC,    E.WATER,     1.4, 10, T.SINGLE_ENEMY),
				_make_skill("Whirlpool",      "Creates a whirlpool that pulls all heroes in.",    S.MAGIC,    E.WATER,     1.0, 18, T.ALL_ENEMIES),
				_make_skill("Sea Foam",       "Uses ocean energy to restore HP.",                 S.HEAL,     E.WATER,     1.2, 12, T.SELF),
			]
		"Wind Sprite":
			skills = [
				_make_skill("Gust Slash",     "A razor-sharp wind that cuts deep.",               S.PHYSICAL, E.WIND,      1.1, 0,  T.SINGLE_ENEMY),
				_make_skill("Cyclone Dart",   "Launches a spinning dart of wind.",                S.MAGIC,    E.WIND,      1.3, 8,  T.SINGLE_ENEMY),
				_make_skill("Tempest",        "Unleashes a tempest on all heroes.",               S.MAGIC,    E.WIND,      0.9, 15, T.ALL_ENEMIES),
				_make_skill("Zephyr Veil",    "Rides the wind to recover HP.",                    S.HEAL,     E.WIND,      1.0, 8,  T.SELF),
			]
		"Light Golem":
			skills = [
				_make_skill("Radiant Punch",  "A punch that burns with holy light.",              S.PHYSICAL, E.LIGHT,     1.1, 0,  T.SINGLE_ENEMY),
				_make_skill("Holy Beam",      "Fires a concentrated beam of light.",              S.MAGIC,    E.LIGHT,     1.5, 12, T.SINGLE_ENEMY),
				_make_skill("Sacred Flash",   "A blinding flash that hits all heroes.",           S.MAGIC,    E.LIGHT,     1.0, 20, T.ALL_ENEMIES),
				_make_skill("Mending Light",  "Heals wounds using radiant energy.",               S.HEAL,     E.LIGHT,     1.3, 12, T.SELF),
			]
		"Void Shade":
			skills = [
				_make_skill("Null Strike",    "A strike from the void that drains energy.",       S.PHYSICAL, E.ARCANE,    1.2, 0,  T.SINGLE_ENEMY, "poison", 0.35),
				_make_skill("Arcane Bolt",    "A bolt of pure arcane energy.",                    S.MAGIC,    E.ARCANE,    1.4, 10, T.SINGLE_ENEMY),
				_make_skill("Void Burst",     "An explosion of void energy hitting all heroes.",  S.MAGIC,    E.ARCANE,    1.1, 20, T.ALL_ENEMIES),
				_make_skill("Void Mend",      "Absorbs void energy to restore HP.",               S.HEAL,     E.ARCANE,    1.1, 10, T.SELF),
			]
		"Frost Wyrm":
			skills = [
				_make_skill("Frozen Bite",    "A bite so cold it freezes solid.",                 S.PHYSICAL, E.ICE,       1.2, 0,  T.SINGLE_ENEMY, "freeze", 0.4),
				_make_skill("Ice Lance",      "Hurls a lance of pure ice.",                       S.MAGIC,    E.ICE,       1.5, 12, T.SINGLE_ENEMY),
				_make_skill("Frozen Gale",    "Breathes a freezing gale over all heroes.",        S.MAGIC,    E.ICE,       1.1, 20, T.ALL_ENEMIES),
				_make_skill("Wyrm Regen",     "Scales shimmer as HP is slowly restored.",         S.HEAL,     E.ICE,       1.3, 14, T.SELF),
			]
		_:
			# Fallback generic skills
			skills = _generate_enemy_skills(Character.new())
	return skills

# --- UI Setup ---
func _setup_hero_panels(party: Array[Character]):
	var panels = [hero_status_1, hero_status_2, hero_status_3]
	for i in range(panels.size()):
		if i < party.size():
			panels[i].visible = true
			_update_hero_panel(panels[i], party[i])
		else:
			panels[i].visible = false

func _update_hero_panel(panel: PanelContainer, hero: Character):
	var layout = panel.get_node("HeroLayout")
	layout.get_node("HeroNameLabel").text = "  %s · Lv%d" % [hero.character_name, hero.level]

	var hp_bar   = layout.get_node("HPRow/HPBar")
	var hp_lbl   = layout.get_node("HPRow/HPLabel")
	var hp_val   = layout.get_node("HPRow/HPValue")
	var mp_bar   = layout.get_node("MPRow/MPBar")
	var mp_lbl   = layout.get_node("MPRow/MPLabel")
	var mp_val   = layout.get_node("MPRow/MPValue")
	var res_bar  = layout.get_node("ResonanceRow/ResonanceBar")
	var res_lbl  = layout.get_node("ResonanceRow/ResLabel")
	var res_val  = layout.get_node("ResonanceRow/ResValue")

	# --- HP ---
	hp_bar.max_value = hero.max_hp()
	hp_bar.value = hero.current_hp
	hp_val.text = "%d/%d" % [hero.current_hp, hero.max_hp()]

	# HP color based on percentage
	var hp_pct = float(hero.current_hp) / float(hero.max_hp())
	var hp_color: Color
	if hp_pct >= 0.5:
		hp_color = Color(0.2, 0.85, 0.3)       # Green
	elif hp_pct >= 0.3:
		hp_color = Color(0.95, 0.85, 0.1)       # Yellow
	elif hp_pct >= 0.15:
		hp_color = Color(1.0, 0.5, 0.1)         # Orange
	else:
		hp_color = Color(0.9, 0.15, 0.15)       # Red

	hp_bar.modulate = hp_color
	hp_lbl.add_theme_color_override("font_color", hp_color)
	hp_val.add_theme_color_override("font_color", hp_color)

	# --- MP ---
	mp_bar.max_value = hero.max_mp()
	mp_bar.value = hero.current_mp
	mp_val.text = "%d/%d" % [hero.current_mp, hero.max_mp()]

	var mp_color = Color(0.3, 0.65, 1.0)        # Light blue
	mp_bar.modulate = mp_color
	mp_lbl.add_theme_color_override("font_color", mp_color)
	mp_val.add_theme_color_override("font_color", mp_color)

	# --- Resonance ---
	var res_pct = resonance_system.get_resonance_percent(hero) * 100
	res_bar.max_value = 100
	res_bar.value = res_pct

	var res_color = Color(0.72, 0.55, 1.0)      # Light purple
	res_bar.modulate = res_color
	res_lbl.add_theme_color_override("font_color", res_color)

	if resonance_system.is_full(hero):
		res_val.text = "FULL ✦"
		res_val.add_theme_color_override("font_color", Color(0.88, 0.69, 1.0))
	else:
		res_val.text = "%d%%" % int(res_pct)
		res_val.add_theme_color_override("font_color", res_color)

func _setup_enemy_cards(enemies: Array[Character]):
	for child in enemy_info_row.get_children():
		child.queue_free()

	enemy_info_row.alignment = BoxContainer.ALIGNMENT_BEGIN

	var screen_w = get_viewport().get_visible_rect().size.x
	var count = mini(enemies.size(), 10)
	# Leave 16px margin on each side and 2px spacing between cards
	var margin = 32
	var spacing = 2 * (count - 1)
	var card_width = max(60.0, (screen_w - margin - spacing) / count)

	for i in range(count):
		var card = _create_enemy_card(enemies[i])
		card.custom_minimum_size = Vector2(card_width, 0)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		enemy_info_row.add_child(card)

func _create_enemy_card(enemy: Character) -> PanelContainer:
	var card = PanelContainer.new()
	# Scale card width based on enemy count — fewer enemies = wider cards
	var enemy_count = mini(battle_manager.enemies.size(), 10)
	var card_width = clamp(1280.0 / enemy_count - 8, 80, 260)
	card.custom_minimum_size = Vector2(card_width, 70)

	var vbox = VBoxContainer.new()
	card.add_child(vbox)

	# Load Cinzel font for enemy cards
	var cinzel = load("res://fonts/Cinzel-Regular.ttf")

	# Name row with rarity gem
	var name_row = HBoxContainer.new()
	vbox.add_child(name_row)

	# Rarity gem icon
	var gem = TextureRect.new()
	gem.custom_minimum_size = Vector2(16, 16)
	gem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var icon_path = _get_rarity_icon_path(enemy)
	var icon_texture = load(icon_path)
	if icon_texture:
		gem.texture = icon_texture
	name_row.add_child(gem)

	# Name label
	var name_lbl = Label.new()
	name_lbl.text = enemy.character_name
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if cinzel:
		name_lbl.add_theme_font_override("font", cinzel)
	name_row.add_child(name_lbl)

	# Invisible spacer to balance gem on left — keeps name centered
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(16, 16)
	spacer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	name_row.add_child(spacer)

	# HP bar
	var enemy_max_hp = _max_hp.get(enemy, enemy.max_hp())
	var hp_bar = ProgressBar.new()
	hp_bar.max_value = enemy_max_hp
	hp_bar.value = enemy.current_hp
	hp_bar.custom_minimum_size = Vector2(0, 8)
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar.show_percentage = false
	vbox.add_child(hp_bar)

	# Store bar reference for live updates
	_enemy_hp_bars[enemy] = hp_bar

	# HP color based on percentage
	var hp_pct = float(enemy.current_hp) / float(enemy_max_hp)
	var hp_color: Color
	if hp_pct >= 0.5:
		hp_color = Color(0.2, 0.85, 0.3)
	elif hp_pct >= 0.3:
		hp_color = Color(0.95, 0.85, 0.1)
	elif hp_pct >= 0.15:
		hp_color = Color(1.0, 0.5, 0.1)
	else:
		hp_color = Color(0.9, 0.15, 0.15)
	hp_bar.modulate = hp_color

	# HP label
	var hp_lbl = Label.new()
	hp_lbl.text = "%d/%d" % [enemy.current_hp, enemy_max_hp]
	hp_lbl.add_theme_font_size_override("font_size", 9)
	hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_lbl.add_theme_color_override("font_color", hp_color)
	if cinzel:
		hp_lbl.add_theme_font_override("font", cinzel)
	vbox.add_child(hp_lbl)

	# Store label reference for live updates
	_enemy_hp_labels[enemy] = hp_lbl

	return card

# --- Battle Signals ---
func _on_battle_started(_party, _enemies):
	_toggle_action_menu(false)

func _on_turn_started(character: Character):
	current_actor = character
	var is_player = battle_manager.party.has(character)

	# Always clean up target selection state on any new turn
	_pending_action = ""
	_clear_target_buttons()
	var action_layout = action_menu.get_node_or_null("ActionLayout")
	if action_layout:
		var back_btn = action_layout.get_node_or_null("TargetBackBtn")
		if back_btn:
			back_btn.queue_free()
		for child in action_layout.get_children():
			child.visible = true

	if is_player:
		action_title.text = "— %s's Turn —" % character.character_name
		action_menu.visible = not _battle_over
	else:
		action_menu.visible = false

	_update_resonance_button()
	turn_order_indicator.set_active(character)

func _on_enemy_move_preview(enemy: Character, move_name: String):
	# Remove any existing preview panel
	var existing = $BattleUI/UIRoot.get_node_or_null("MovePreviewPanel")
	if existing:
		existing.queue_free()

	if move_name == "":
		return

	# Find the enemy card's screen position
	var alive_enemies = battle_manager.get_alive_enemies()
	for i in range(enemy_info_row.get_child_count()):
		var card = enemy_info_row.get_child(i)
		if i >= alive_enemies.size() or alive_enemies[i] != enemy:
			continue

		var cinzel = load("res://fonts/Cinzel-Regular.ttf")

		# Create panel as a child of UIRoot so it doesn't interfere with cards
		var panel = PanelContainer.new()
		panel.name = "MovePreviewPanel"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.05, 0.05, 0.08, 0.92)
		style.border_color = Color(0.4, 0.35, 0.5, 1.0)
		style.set_border_width_all(1)
		style.set_corner_radius_all(3)
		panel.add_theme_stylebox_override("panel", style)

		var lbl = Label.new()
		lbl.text = move_name
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if cinzel: lbl.add_theme_font_override("font", cinzel)
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		panel.add_child(lbl)

		# Position below the card using its global position
		$BattleUI/UIRoot.add_child(panel)
		await get_tree().process_frame
		var card_pos = card.global_position
		var ui_pos = $BattleUI/UIRoot.global_position
		panel.position = Vector2(
			card_pos.x - ui_pos.x,
			card_pos.y - ui_pos.y + card.size.y + 4
		)
		panel.custom_minimum_size = Vector2(card.size.x, 0)
		break

func _refresh_enemy_card(enemy: Character):
	if not _enemy_hp_bars.has(enemy):
		return
	var hp_bar = _enemy_hp_bars[enemy]
	var hp_lbl = _enemy_hp_labels.get(enemy)
	if not is_instance_valid(hp_bar):
		return
	var enemy_max_hp = _max_hp.get(enemy, enemy.max_hp())
	hp_bar.value = enemy.current_hp
	var hp_pct = float(enemy.current_hp) / float(enemy_max_hp)
	var hp_color: Color
	if hp_pct >= 0.5:
		hp_color = Color(0.2, 0.85, 0.3)
	elif hp_pct >= 0.3:
		hp_color = Color(0.95, 0.85, 0.1)
	elif hp_pct >= 0.15:
		hp_color = Color(1.0, 0.5, 0.1)
	else:
		hp_color = Color(0.9, 0.15, 0.15)
	hp_bar.modulate = hp_color
	if hp_lbl and is_instance_valid(hp_lbl):
		hp_lbl.text = "%d/%d" % [enemy.current_hp, enemy_max_hp]
		hp_lbl.add_theme_color_override("font_color", hp_color)

func _on_action_performed(result: Dictionary):
	_refresh_all_panels()
	# Refresh enemy card if enemy took damage
	if result.has("target"):
		var target = result["target"]
		if battle_manager.enemies.has(target):
			_refresh_enemy_card(target)

	# Spawn damage/heal/dodge numbers
	if result.has("target"):
		var target = result["target"]
		var spawn_pos = _get_character_screen_pos(target)
		match result.get("action", ""):
			"attack", "skill_physical", "skill_magic":
				var multiplier = result.get("multiplier", 1.0)
				var dmg_value = result.get("value", 0)
				if dmg_value is Dictionary:
					dmg_value = dmg_value.get("damage", 0)
				_spawn_damage_number(int(dmg_value), spawn_pos, multiplier)
			"heal":
				_spawn_heal_number(result.get("value", 0), spawn_pos)
			"dodge":
				_spawn_dodge_text(spawn_pos)
	if result.has("actor") and battle_manager.party.has(result["actor"]):
		match result.get("action", ""):
			"attack":
				resonance_system.on_attack(result["actor"])
			"skill_magic", "skill_physical":
				resonance_system.on_skill_used(result["actor"])
			"heal":
				resonance_system.on_heal(result["actor"])
	if result.has("target") and battle_manager.party.has(result["target"]):
		if result.get("action") == "attack":
			resonance_system.on_damage_taken(result["target"])

func _on_character_defeated(character: Character):
	print("%s was defeated!" % character.character_name)
	_refresh_all_panels()
	turn_order_indicator.remove_character(character)
	_remove_portrait(character)
	# Remove enemy card if an enemy was defeated
	if battle_manager.enemies.has(character):
		_remove_enemy_card(character)

var _card_rebuild_queued: bool = false

func _remove_enemy_card(_enemy: Character):
	# Queue a rebuild instead of rebuilding immediately
	# This handles multiple enemies dying in one turn
	if _card_rebuild_queued:
		return
	_card_rebuild_queued = true
	await get_tree().process_frame
	await get_tree().process_frame
	_rebuild_enemy_cards()
	_card_rebuild_queued = false

func _rebuild_enemy_cards():
	var alive_enemies = battle_manager.get_alive_enemies()
	for card in enemy_info_row.get_children():
		card.queue_free()
	if alive_enemies.is_empty():
		return
	var screen_w = get_viewport().get_visible_rect().size.x
	var count = alive_enemies.size()
	var margin = 32
	var spacing = 2 * (count - 1)
	var card_width = max(60.0, (screen_w - margin - spacing) / count)
	enemy_info_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for e in alive_enemies:
		var card = _create_enemy_card(e)
		card.custom_minimum_size = Vector2(card_width, 0)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		enemy_info_row.add_child(card)

func _on_battle_ended(player_won: bool, rewards: Dictionary):
	_battle_over = true
	_toggle_action_menu(false)
	# Hide battle UI elements immediately
	enemy_info_row.visible = false
	party_status_bar.visible = false
	turn_order_indicator.visible = false
	attack_menu.visible = false
	action_menu.visible = false
	resonance_menu.visible = false
	items_menu.visible = false
	if player_won:
		GameManager.award_rewards(rewards)
		for enemy in battle_manager.enemies:
			if enemy is Enemy:
				GameManager.record_battle_against(enemy.species)
		victory_screen.show_victory(rewards, battle_manager.party, resonance_system)
	else:
		defeat_screen.show_defeat()

func _on_victory_closed():
	# Return to game — for now go back to main menu until world map is built
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_status_triggered(character: Character, result: Dictionary):
	print("%s: %s %d" % [character.character_name, result["type"], result["value"]])
	_refresh_all_panels()

# --- Target Selection ---
var _pending_action: String = ""
var _pending_skill: Skill = null
var _pending_item: Item = null
var _battle_over: bool = false
var _test_items: Array[Item] = []

func _input(event):
	if _battle_over:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_BACKSPACE:
		if _pending_action != "":
			_cancel_target_selection()

func _enter_target_selection(action: String):
	_pending_action = action
	action_title.text = "— Choose Target —"
	_set_target_selection_ui(true)
	if action == "item_ally":
		_show_ally_target_buttons()
	else:
		_show_target_buttons()

func _show_ally_target_buttons():
	var alive_party = battle_manager.get_alive_party()
	# Highlight hero panels to show they are selectable
	for i in range(party_status_bar.get_child_count()):
		var panel = party_status_bar.get_child(i)
		if i < alive_party.size():
			panel.modulate = Color(1.2, 1.2, 0.6)
			var btn = Button.new()
			btn.name = "AllyTargetBtn_%d" % i
			btn.flat = true
			btn.set_anchors_preset(Control.PRESET_FULL_RECT)
			btn.modulate = Color(1, 1, 1, 0.01)
			panel.add_child(btn)
			btn.pressed.connect(_on_target_selected.bind(alive_party[i]))

func _clear_ally_target_buttons():
	for panel in party_status_bar.get_children():
		panel.modulate = Color(1, 1, 1)
		for child in panel.get_children():
			if child.name.begins_with("AllyTargetBtn_"):
				child.queue_free()

func _set_target_selection_ui(selecting: bool):
	var action_layout = action_menu.get_node_or_null("ActionLayout")
	if action_layout == null:
		return
	# Show/hide all children except title and back button
	for child in action_layout.get_children():
		if child.name == "ActionTitle":
			child.visible = true
		elif child.name == "TargetBackBtn":
			child.visible = selecting
		else:
			child.visible = not selecting
	# Create back button if entering selection
	if selecting and action_layout.get_node_or_null("TargetBackBtn") == null:
		var cinzel = load("res://fonts/Cinzel-Regular.ttf")
		var back_btn = Button.new()
		back_btn.name = "TargetBackBtn"
		back_btn.text = "← Back"
		back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		back_btn.custom_minimum_size = Vector2(0, 30)
		if cinzel: back_btn.add_theme_font_override("font", cinzel)
		back_btn.add_theme_font_size_override("font_size", 13)
		back_btn.pressed.connect(func(): _cancel_target_selection())
		action_layout.add_child(back_btn)
	# Only show if it's a player's turn and battle isn't over
	if current_actor != null and battle_manager.party.has(current_actor) and not _battle_over:
		action_menu.visible = true

func _cancel_target_selection():
	_clear_target_buttons()
	_pending_action = ""
	_pending_skill = null
	action_title.text = "— %s's Turn —" % current_actor.character_name
	_set_target_selection_ui(false)
	# Remove back button
	var action_layout = action_menu.get_node_or_null("ActionLayout")
	if action_layout:
		var back_btn = action_layout.get_node_or_null("TargetBackBtn")
		if back_btn:
			back_btn.queue_free()

func _show_target_buttons():
	var alive_enemies = battle_manager.get_alive_enemies()
	for i in range(enemy_info_row.get_child_count()):
		var card = enemy_info_row.get_child(i)
		if i < alive_enemies.size():
			card.modulate = Color(1.2, 1.2, 0.6)
			var btn = Button.new()
			btn.name = "TargetBtn_%d" % i
			btn.flat = true
			btn.set_anchors_preset(Control.PRESET_FULL_RECT)
			btn.modulate = Color(1, 1, 1, 0.01)
			card.add_child(btn)
			btn.pressed.connect(_on_target_selected.bind(alive_enemies[i]))

func _on_target_selected(target: Character):
	_clear_target_buttons()
	_pending_action = ""
	# Clean up UI
	var action_layout = action_menu.get_node_or_null("ActionLayout")
	if action_layout:
		var back_btn = action_layout.get_node_or_null("TargetBackBtn")
		if back_btn:
			back_btn.queue_free()
	_set_target_selection_ui(false)

	if _pending_skill != null:
		var typed: Array[Character] = [target]
		battle_manager.player_use_skill(current_actor, _pending_skill, typed)
		_pending_skill = null
	elif _pending_item != null:
		var item = _pending_item
		_pending_item = null
		# Decrement quantity
		item.quantity -= 1
		# Use item directly — do NOT go through player_attack or player_use_skill
		var result = item.use(target)
		result["target"] = target
		_handle_item_result(result)
		_refresh_all_panels()
		# Remove item from list if depleted
		if item.quantity <= 0:
			_test_items.erase(item)
		if not _battle_over:
			battle_manager.end_player_turn()
	else:
		battle_manager.player_attack(current_actor, target)

func _clear_target_buttons():
	for card in enemy_info_row.get_children():
		card.modulate = Color(1, 1, 1)
		for child in card.get_children():
			if child.name.begins_with("TargetBtn_"):
				child.queue_free()
	_clear_ally_target_buttons()

# --- Action Buttons ---
func _on_attack_pressed():
	if current_actor == null:
		return
	if current_actor.skills.is_empty():
		var alive_enemies = battle_manager.get_alive_enemies()
		if alive_enemies.size() == 1:
			action_menu.visible = false
			battle_manager.player_attack(current_actor, alive_enemies[0])
		else:
			_enter_target_selection("attack")
		return
	action_menu.visible = false
	attack_menu.show_attacks(current_actor)

func _on_special_pressed():
	if current_actor == null:
		return
	action_menu.visible = false
	attack_menu.show_specials(current_actor)

func _on_move_selected(skill: Skill, targets: Array):
	if targets.is_empty():
		_pending_skill = skill
		_enter_target_selection("skill")
	else:
		var typed_targets: Array[Character] = []
		for t in targets:
			typed_targets.append(t)
		battle_manager.player_use_skill(current_actor, skill, typed_targets)

func _on_attack_menu_closed():
	if not _battle_over and current_actor != null and battle_manager.party.has(current_actor):
		action_menu.visible = true

# Hero colors by element
const HERO_COLORS = {
	"FIRE":      Color(0.9, 0.3, 0.15),
	"ICE":       Color(0.4, 0.75, 1.0),
	"LIGHTNING": Color(0.95, 0.85, 0.1),
	"WATER":     Color(0.2, 0.5, 0.9),
	"EARTH":     Color(0.5, 0.35, 0.15),
	"WIND":      Color(0.5, 0.9, 0.4),
	"LIGHT":     Color(1.0, 0.95, 0.6),
	"DARK":      Color(0.4, 0.2, 0.6),
	"ARCANE":    Color(0.65, 0.3, 0.9),
	"NONE":      Color(0.5, 0.5, 0.55),
}

func _setup_portraits(party: Array[Character], enemies: Array[Character]):
	# Clear existing portraits
	for child in party_positions.get_children():
		child.queue_free()
	for child in enemy_positions.get_children():
		child.queue_free()

	var cinzel = load("res://fonts/Cinzel-Regular.ttf")
	var screen = get_viewport().get_visible_rect().size

	# Portrait size
	var pw = 32.0
	var ph = 48.0

	# --- Hero portraits ---
	# VBoxContainer at x:50, y:200 — portraits stack vertically with diagonal offset
	# We use a Control wrapper per hero and offset it horizontally for the diagonal
	for i in range(party.size()):
		var hero = party[i]
		var wrapper = Control.new()
		wrapper.custom_minimum_size = Vector2(pw + i * 30, ph + 20)
		party_positions.add_child(wrapper)

		var portrait = _create_portrait(hero, cinzel, false)
		portrait.name = "HeroPortrait_%s" % hero.character_name
		# Each successive hero shifts right to create front-to-back diagonal
		# Hero 1 (i=0): leftmost/back, last hero: rightmost/front
		portrait.position = Vector2((party.size() - 1 - i) * 30, 0)
		wrapper.add_child(portrait)

	# --- Enemy portraits ---
	var enemy_grid = Control.new()
	enemy_grid.name = "EnemyGrid"
	enemy_positions.add_child(enemy_grid)

	var count = enemies.size()
	for i in range(count):
		var enemy = enemies[i]
		var portrait = _create_portrait(enemy, cinzel, true)
		portrait.name = "EnemyPortrait_%s" % enemy.character_name
		portrait.position = _get_enemy_portrait_pos(i, count)
		enemy_grid.add_child(portrait)

func _get_enemy_portrait_pos(index: int, total: int) -> Vector2:
	var cell_w = 52.0
	var cell_h = 65.0
	match _enemy_layout:
		EnemyLayout.ROW:
			return Vector2(index * cell_w, 0)
		EnemyLayout.GRID_2COL:
			return Vector2((index % 2) * cell_w, (index / 2) * cell_h)
		EnemyLayout.GRID_3COL:
			return Vector2((index % 3) * cell_w, (index / 3) * cell_h)
		EnemyLayout.DIAGONAL:
			return Vector2(index * 20.0, index * 30.0)
	return Vector2(index * cell_w, 0)

func _create_portrait(character: Character, cinzel, is_enemy: bool) -> VBoxContainer:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	# Colored rectangle
	var rect = ColorRect.new()
	rect.custom_minimum_size = Vector2(32, 48)
	var elem_key = ElementalSystem.get_element_name(character.element).to_upper()
	rect.color = HERO_COLORS.get(elem_key, Color(0.5, 0.5, 0.55))
	# Add slight dark overlay for enemies
	if is_enemy:
		rect.color = rect.color.darkened(0.15)
	vbox.add_child(rect)

	# First letter initial centered on portrait
	var initial_lbl = Label.new()
	initial_lbl.text = character.character_name.substr(0, 1).to_upper()
	initial_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	initial_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cinzel: initial_lbl.add_theme_font_override("font", cinzel)
	initial_lbl.add_theme_font_size_override("font_size", 18)
	initial_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.25))
	rect.add_child(initial_lbl)

	# Name label underneath
	var name_lbl = Label.new()
	name_lbl.text = character.character_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if cinzel: name_lbl.add_theme_font_override("font", cinzel)
	name_lbl.add_theme_font_size_override("font_size", 8)
	name_lbl.add_theme_color_override("font_color", Color(0.88, 0.78, 1.0))
	vbox.add_child(name_lbl)

	return vbox

func _remove_portrait(character: Character):
	# Check hero portraits in party_positions
	var hero_portrait = _find_portrait_in(party_positions, "HeroPortrait_%s" % character.character_name)
	# Check enemy portraits inside EnemyGrid
	var enemy_grid = enemy_positions.get_node_or_null("EnemyGrid")
	var enemy_portrait = _find_portrait_in(enemy_grid, "EnemyPortrait_%s" % character.character_name) if enemy_grid else null
	var portrait = hero_portrait if hero_portrait != null else enemy_portrait
	if portrait == null:
		return
	var tween = create_tween()
	tween.tween_property(portrait, "modulate:a", 0.0, 0.4)
	await tween.finished
	portrait.queue_free()

func _find_portrait_in(container: Node, portrait_name: String) -> Node:
	if container == null:
		return null
	for child in container.get_children():
		if child.name == portrait_name:
			return child
		# Check wrappers
		var found = child.get_node_or_null(portrait_name)
		if found:
			return found
	return null

func _generate_enemy_skills(enemy: Character) -> Array[Skill]:
	var skills: Array[Skill] = []
	var elem = enemy.element
	var elem_name = ElementalSystem.get_element_name(elem)

	# Basic attack — always free, single target
	var basic = Skill.new()
	basic.skill_name = "%s Strike" % elem_name
	basic.description = "A basic elemental strike."
	basic.skill_type = Skill.SkillType.PHYSICAL
	basic.element = elem
	basic.power = 1.0
	basic.mp_cost = 0
	basic.target_type = Skill.TargetType.SINGLE_ENEMY
	skills.append(basic)

	# Magic attack — costs MP, single target
	var magic = Skill.new()
	magic.skill_name = "%s Bolt" % elem_name
	magic.description = "A focused burst of elemental energy."
	magic.skill_type = Skill.SkillType.MAGIC
	magic.element = elem
	magic.power = 1.4
	magic.mp_cost = 10
	magic.target_type = Skill.TargetType.SINGLE_ENEMY
	skills.append(magic)

	# AoE attack — costs more MP, hits all heroes
	var aoe = Skill.new()
	aoe.skill_name = "%s Wave" % elem_name
	aoe.description = "A wave of elemental energy hitting all heroes."
	aoe.skill_type = Skill.SkillType.MAGIC
	aoe.element = elem
	aoe.power = 1.0
	aoe.mp_cost = 18
	aoe.target_type = Skill.TargetType.ALL_ENEMIES
	skills.append(aoe)

	# Self heal — available to tougher enemies
	if enemy.base_hp >= 60:
		var heal = Skill.new()
		heal.skill_name = "%s Mend" % elem_name
		heal.description = "Channels elemental energy to restore HP."
		heal.skill_type = Skill.SkillType.HEAL
		heal.element = elem
		heal.power = 1.2
		heal.mp_cost = 12
		heal.target_type = Skill.TargetType.SELF
		skills.append(heal)

	# Status attack — chance to apply a status effect
	var status = Skill.new()
	status.skill_name = "%s Curse" % elem_name
	status.description = "Inflicts a status condition on one hero."
	status.skill_type = Skill.SkillType.MAGIC
	status.element = elem
	status.power = 0.8
	status.mp_cost = 8
	status.target_type = Skill.TargetType.SINGLE_ENEMY
	# Assign status based on element
	match elem:
		ElementalSystem.Element.FIRE:
			status.status_to_apply = "burn"
			status.status_chance = 0.5
		ElementalSystem.Element.ICE:
			status.status_to_apply = "freeze"
			status.status_chance = 0.4
		ElementalSystem.Element.LIGHTNING:
			status.status_to_apply = "stun"
			status.status_chance = 0.35
		ElementalSystem.Element.DARK:
			status.status_to_apply = "poison"
			status.status_chance = 0.5
		_:
			status.status_to_apply = "poison"
			status.status_chance = 0.3
	skills.append(status)

	return skills

func _create_test_items() -> Array[Item]:
	var items: Array[Item] = []

	var potion = Item.new()
	potion.item_name = "Health Potion"
	potion.description = "Restores 50 HP to one ally."
	potion.item_type = Item.ItemType.HP_RESTORE
	potion.effect_value = 50
	potion.quantity = 3
	potion.target_type = Item.TargetType.SINGLE_ALLY
	items.append(potion)

	var mp_potion = Item.new()
	mp_potion.item_name = "Mana Potion"
	mp_potion.description = "Restores 30 MP to one ally."
	mp_potion.item_type = Item.ItemType.MP_RESTORE
	mp_potion.effect_value = 30
	mp_potion.quantity = 2
	mp_potion.target_type = Item.TargetType.SINGLE_ALLY
	items.append(mp_potion)

	var elixir = Item.new()
	elixir.item_name = "Elixir"
	elixir.description = "Restores 100 HP to all allies."
	elixir.item_type = Item.ItemType.HP_RESTORE
	elixir.effect_value = 100
	elixir.quantity = 1
	elixir.target_type = Item.TargetType.ALL_ALLIES
	items.append(elixir)

	var revive = Item.new()
	revive.item_name = "Phoenix Down"
	revive.description = "Revives a defeated ally with 50% HP."
	revive.item_type = Item.ItemType.REVIVAL
	revive.effect_value = 50
	revive.quantity = 1
	revive.target_type = Item.TargetType.SINGLE_ALLY
	items.append(revive)

	var antidote = Item.new()
	antidote.item_name = "Antidote"
	antidote.description = "Cures poison and burn from one ally."
	antidote.item_type = Item.ItemType.ANTIDOTE
	antidote.effect_value = 0
	antidote.quantity = 2
	antidote.target_type = Item.TargetType.SINGLE_ALLY
	items.append(antidote)

	var bomb = Item.new()
	bomb.item_name = "Fire Bomb"
	bomb.description = "Deals 40 fire damage to all enemies."
	bomb.item_type = Item.ItemType.DAMAGE
	bomb.effect_value = 40
	bomb.quantity = 2
	bomb.target_type = Item.TargetType.ALL_ENEMIES
	items.append(bomb)

	var smoke = Item.new()
	smoke.item_name = "Smoke Veil"
	smoke.description = "Grants a 20% chance to dodge attacks to one ally."
	smoke.item_type = Item.ItemType.DODGE_BUFF
	smoke.effect_value = 20
	smoke.quantity = 2
	smoke.target_type = Item.TargetType.SINGLE_ALLY
	items.append(smoke)

	return items

func _on_items_pressed():
	if current_actor == null:
		return
	action_menu.visible = false
	items_menu.show_menu(current_actor)

func _on_item_used(item: Item, targets: Array):
	if targets.is_empty():
		_pending_skill = null
		_pending_item = item
		# Choose correct target pool based on item type
		if item.target_type == Item.TargetType.SINGLE_ENEMY:
			_enter_target_selection("item_enemy")
		else:
			_enter_target_selection("item_ally")
	else:
		action_menu.visible = false
		item.quantity -= 1
		if item.quantity <= 0:
			_test_items.erase(item)
		for t in targets:
			var result = item.use(t)
			result["target"] = t
			_handle_item_result(result)
		_refresh_all_panels()
		if not _battle_over:
			battle_manager.end_player_turn()

func _handle_item_result(result: Dictionary):
	if not result.has("target"):
		return
	var target = result["target"]
	var pos = _get_character_screen_pos(target)
	match result.get("action", ""):
		"heal", "mp_restore", "revival":
			_spawn_heal_number(result.get("value", 0), pos)
		"attack":
			var mult = result.get("multiplier", 1.0)
			_spawn_damage_number(result.get("value", 0), pos, mult)
	if battle_manager.enemies.has(target):
		_refresh_enemy_card(target)
		if not target.is_alive():
			battle_manager.handle_defeat(target)
			if battle_manager.check_battle_end():
				return

func _on_run_pressed():
	action_menu.visible = false
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_resonance_pressed():
	if current_actor == null:
		return
	if resonance_system.is_full(current_actor):
		action_menu.visible = false
		resonance_menu.show_menu(current_actor)

func _on_resonance_action(action_type: String, heroes: Array, targets: Array):
	action_menu.visible = false
	var typed_targets: Array[Character] = []
	for t in targets:
		typed_targets.append(t)

	# Calculate resonance damage based on type
	var total_magic = 0
	for h in heroes:
		total_magic += h.magic_power()

	var resonance_skill = Skill.new()
	resonance_skill.element = ElementalSystem.Element.ARCANE
	resonance_skill.mp_cost = 0

	if action_type == "solo":
		resonance_skill.skill_name = "%s Ultimate" % heroes[0].character_name
		resonance_skill.skill_type = Skill.SkillType.MAGIC
		resonance_skill.power = 3.5
		resonance_skill.target_type = Skill.TargetType.ALL_ENEMIES
		battle_manager.player_use_skill(heroes[0], resonance_skill, typed_targets)
	elif action_type == "triple":
		resonance_skill.skill_name = "Amethyst Requiem"
		resonance_skill.skill_type = Skill.SkillType.MAGIC
		resonance_skill.power = 8.0
		resonance_skill.target_type = Skill.TargetType.ALL_ENEMIES
		battle_manager.player_use_skill(heroes[0], resonance_skill, typed_targets)
	else:
		resonance_skill.skill_name = "Combined Resonance"
		resonance_skill.skill_type = Skill.SkillType.MAGIC
		resonance_skill.power = 5.0
		resonance_skill.target_type = Skill.TargetType.ALL_ENEMIES
		battle_manager.player_use_skill(heroes[0], resonance_skill, typed_targets)

	_refresh_all_panels()

# --- Resonance Callbacks ---
func _on_resonance_changed(character: Character, _value: float):
	_refresh_hero_panel_for(character)
	_update_resonance_button()

func _on_resonance_full(character: Character):
	print("%s Resonance FULL!" % character.character_name)
	_update_resonance_button()

func _update_resonance_button():
	if current_actor == null:
		return
	var is_full = resonance_system.is_full(current_actor)
	resonance_btn.disabled = not is_full
	resonance_btn.text = "💜 Resonance — READY" if is_full else "💜 Resonance"
	resonance_btn.modulate = Color(1.0, 0.9, 1.0) if is_full else Color(0.6, 0.5, 0.7)

# --- Helpers ---
func _toggle_action_menu(is_shown: bool):
	if _battle_over:
		action_menu.visible = false
		return
	action_menu.visible = is_shown

func _refresh_all_panels():
	var panels = [hero_status_1, hero_status_2, hero_status_3]
	var party = battle_manager.party
	for i in range(mini(panels.size(), party.size())):
		if panels[i].visible:
			_update_hero_panel(panels[i], party[i])

func _refresh_hero_panel_for(character: Character):
	var panels = [hero_status_1, hero_status_2, hero_status_3]
	var party = battle_manager.party
	for i in range(mini(panels.size(), party.size())):
		if party[i] == character and panels[i].visible:
			_update_hero_panel(panels[i], party[i])

func _get_character_screen_pos(character: Character) -> Vector2:
	# Returns an approximate screen position for the character
	# This will be updated when sprites are added
	var party = battle_manager.party
	var enemies = battle_manager.enemies
	var screen_w = get_viewport().get_visible_rect().size.x
	var screen_h = get_viewport().get_visible_rect().size.y

	if party.has(character):
		var idx = party.find(character)
		var x = screen_w * 0.3 + idx * 80
		return Vector2(x, screen_h * 0.55)
	elif enemies.has(character):
		var idx = enemies.find(character)
		var count = enemies.size()
		var x = screen_w * 0.5 + (idx - count / 2.0) * (screen_w * 0.3 / count) + 60
		return Vector2(x, screen_h * 0.35)
	return Vector2(screen_w * 0.5, screen_h * 0.5)

func _spawn_dodge_text(pos: Vector2):
	var label = Label.new()
	add_child(label)
	label.set_script(load("res://scripts/battle/DamageNumber.gd"))
	label.position = pos + Vector2(randf_range(-20, 20), 0)
	label.call("setup_dodge")

func _spawn_damage_number(amount: int, pos: Vector2, multiplier: float = 1.0):
	var label = Label.new()
	add_child(label)
	label.set_script(load("res://scripts/battle/DamageNumber.gd"))
	label.position = pos + Vector2(randf_range(-20, 20), 0)
	label.call("setup", amount, multiplier)

func _spawn_heal_number(amount: int, pos: Vector2):
	var label = Label.new()
	add_child(label)
	label.set_script(load("res://scripts/battle/DamageNumber.gd"))
	label.position = pos + Vector2(randf_range(-20, 20), 0)
	label.call("setup_heal", amount)

func _get_rarity_icon_path(enemy: Character) -> String:
	if not enemy is Enemy:
		return "res://assets/icons/CommonGemIcon.png"
	match enemy.rarity:
		Rarity.Tier.COMMON:    return "res://assets/icons/CommonGemIcon.png"
		Rarity.Tier.UNCOMMON:  return "res://assets/icons/UncommonGemIcon.png"
		Rarity.Tier.RARE:      return "res://assets/icons/RareGemIcon.png"
		Rarity.Tier.EPIC:      return "res://assets/icons/EpicGemIcon.png"
		Rarity.Tier.MYTHIC:    return "res://assets/icons/MythicGemIcon.png"
		Rarity.Tier.LEGENDARY: return "res://assets/icons/LegendaryGemIcon.png"
		Rarity.Tier.CELESTIAL: return "res://assets/icons/CelestialGemIcon.png"
	return "res://assets/icons/CommonGemIcon.png"
