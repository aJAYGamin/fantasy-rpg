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
@onready var victory_screen   = $BattleUI/UIRoot/VictoryScreen
@onready var defeat_screen    = $BattleUI/UIRoot/DefeatScreen
@onready var level_up_screen  = $BattleUI/UIRoot/LevelUpScreen

# --- Systems ---
var battle_manager: BattleManager
var resonance_system: ResonanceSystem

# --- State ---
var current_actor: Character = null
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

func start_battle(party: Array[Character], enemies: Array[Character], area: String = "fallster_plains"):
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
	attack_menu.setup(battle_manager, resonance_system)
	attack_menu.move_selected.connect(_on_move_selected)
	attack_menu.menu_closed.connect(_on_attack_menu_closed)
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
	hero1.base_magic = 18
	hero1.experience = 85
	hero1.experience_to_next = 100
	hero1.current_hp = hero1.max_hp()
	hero1.current_mp = hero1.max_mp()

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

	var barrier = Skill.new()
	barrier.skill_name = "Arcane Barrier"
	barrier.description = "Shields all allies with an arcane field."
	barrier.skill_type = Skill.SkillType.BUFF
	barrier.element = ElementalSystem.Element.ARCANE
	barrier.power = 1.0
	barrier.mp_cost = 20
	barrier.target_type = Skill.TargetType.ALL_ALLIES

	var mass_heal = Skill.new()
	mass_heal.skill_name = "Grand Mend"
	mass_heal.description = "Restores HP to all allies."
	mass_heal.skill_type = Skill.SkillType.HEAL
	mass_heal.element = ElementalSystem.Element.LIGHT
	mass_heal.power = 1.5
	mass_heal.mp_cost = 30
	mass_heal.target_type = Skill.TargetType.ALL_ALLIES

	var h1_skills: Array[Skill] = [slash, frost, dark_pulse, heal_spell, requiem, void_strike, barrier, mass_heal]
	hero1.skills = h1_skills

	var hero2 = Character.new()
	hero2.character_name = "Kael"
	hero2.character_class = "Warrior"
	hero2.element = ElementalSystem.Element.FIRE
	hero2.base_hp = 280
	hero2.base_mp = 60
	hero2.base_attack = 20
	hero2.experience = 0
	hero2.experience_to_next = 100
	hero2.current_hp = hero2.max_hp()
	hero2.current_mp = hero2.max_mp()

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
	enemy1.current_hp = enemy1.max_hp()

	# Fire Drake — resists Fire (Kael does 0.5x), weak to Ice
	var enemy2 = Character.new()
	enemy2.character_name = "Fire Drake"
	enemy2.element = ElementalSystem.Element.FIRE
	enemy2.base_hp = 50
	enemy2.base_attack = 10
	enemy2.current_hp = enemy2.max_hp()

	# Start with 50 gold to verify gold addition on victory screen
	GameManager.gold = 50

	var party: Array[Character] = [hero1, hero2]
	var enemies: Array[Character] = [enemy1, enemy2]
	start_battle(party, enemies, "fallster_plains")

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

	# Always center enemies regardless of count (up to 10)
	# Use a CenterContainer wrapper so HBoxContainer centers naturally
	enemy_info_row.alignment = BoxContainer.ALIGNMENT_CENTER

	var count = mini(enemies.size(), 10)
	for i in range(count):
		var card = _create_enemy_card(enemies[i])
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
	action_title.text = "— %s's Turn —" % character.character_name
	var is_player = battle_manager.party.has(character)
	_toggle_action_menu(is_player)
	_update_resonance_button()
	turn_order_indicator.set_active(character)

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

	# Spawn damage/heal numbers
	if result.has("value") and result.has("target"):
		var target = result["target"]
		var spawn_pos = _get_character_screen_pos(target)
		match result.get("action", ""):
			"attack", "skill_physical", "skill_magic":
				var multiplier = result.get("multiplier", 1.0)
				var dmg_value = result["value"]
				if dmg_value is Dictionary:
					dmg_value = dmg_value.get("damage", 0)
				_spawn_damage_number(int(dmg_value), spawn_pos, multiplier)
			"heal":
				_spawn_heal_number(result["value"], spawn_pos)
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
	# Remove enemy card if an enemy was defeated
	if battle_manager.enemies.has(character):
		_remove_enemy_card(character)

func _remove_enemy_card(enemy: Character):
	var alive_enemies = battle_manager.get_alive_enemies()
	# Rebuild enemy cards showing only alive enemies
	for card in enemy_info_row.get_children():
		card.queue_free()
	await get_tree().process_frame
	for e in alive_enemies:
		if e != enemy:
			var card = _create_enemy_card(e)
			enemy_info_row.add_child(card)

func _on_battle_ended(player_won: bool, rewards: Dictionary):
	_toggle_action_menu(false)
	# Hide battle UI elements
	enemy_info_row.visible = false
	party_status_bar.visible = false
	turn_order_indicator.visible = false
	attack_menu.visible = false
	action_menu.visible = false
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

func _enter_target_selection(action: String):
	_pending_action = action
	action_title.text = "— Choose Target —"
	# Clear and rebuild enemy info row with clickable buttons
	for child in enemy_info_row.get_children():
		child.mouse_filter = Control.MOUSE_FILTER_STOP
	_show_target_buttons()

func _show_target_buttons():
	# Add a clickable overlay button on top of each enemy card
	var alive_enemies = battle_manager.get_alive_enemies()
	for i in range(enemy_info_row.get_child_count()):
		var card = enemy_info_row.get_child(i)
		if i < alive_enemies.size():
			var enemy = alive_enemies[i]
			# Add a transparent button over the card
			var btn = Button.new()
			btn.name = "TargetBtn_%d" % i
			btn.flat = true
			btn.set_anchors_preset(Control.PRESET_FULL_RECT)
			btn.modulate = Color(1, 1, 1, 0.01)
			card.add_child(btn)
			btn.pressed.connect(_on_target_selected.bind(enemy))

func _on_target_selected(target: Character):
	# Remove target buttons
	_clear_target_buttons()
	action_title.text = "— %s's Turn —" % current_actor.character_name
	match _pending_action:
		"attack":
			battle_manager.player_attack(current_actor, target)
		"skill":
			if _pending_skill != null:
				battle_manager.player_use_skill(current_actor, _pending_skill, [target])
				_pending_skill = null
	_pending_action = ""

func _clear_target_buttons():
	for card in enemy_info_row.get_children():
		for child in card.get_children():
			if child.name.begins_with("TargetBtn_"):
				child.queue_free()

# --- Action Buttons ---
func _on_attack_pressed():
	if current_actor == null:
		return
	if current_actor.skills.is_empty():
		# No skills — fallback to basic attack
		var alive_enemies = battle_manager.get_alive_enemies()
		if alive_enemies.size() == 1:
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
	action_menu.visible = true

func _on_items_pressed():
	print("Items menu — coming soon!")

func _on_run_pressed():
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_resonance_pressed():
	if current_actor == null:
		return
	if resonance_system.is_full(current_actor):
		resonance_system.spend_solo_ultimate(current_actor)
		print("%s unleashes their Ultimate!" % current_actor.character_name)
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
