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
@onready var resonance_btn    = $BattleUI/UIRoot/ActionMenu/ActionLayout/ResonanceButton

# --- Systems ---
var battle_manager: BattleManager
var resonance_system: ResonanceSystem

# --- State ---
var current_actor: Character = null

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

	_start_test_battle()

func set_background(area: String):
	if BACKGROUNDS.has(area):
		var texture = load(BACKGROUNDS[area])
		if texture:
			background.texture = texture

func start_battle(party: Array[Character], enemies: Array[Character], area: String = "fallster_plains"):
	set_background(area)
	resonance_system.setup(party)
	_setup_hero_panels(party)
	_setup_enemy_cards(enemies)
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

	var hero2 = Character.new()
	hero2.character_name = "Kael"
	hero2.character_class = "Warrior"
	hero2.element = ElementalSystem.Element.FIRE
	hero2.base_hp = 280
	hero2.base_mp = 60
	hero2.base_attack = 20

	var enemy1 = Character.new()
	enemy1.character_name = "Shadow Wraith"
	enemy1.element = ElementalSystem.Element.DARK
	enemy1.base_hp = 150
	enemy1.base_attack = 12

	var party: Array[Character] = [hero1, hero2]
	var enemies: Array[Character] = [enemy1]
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

	var hp_bar  = layout.get_node("HPRow/HPBar")
	var hp_val  = layout.get_node("HPRow/HPValue")
	var mp_bar  = layout.get_node("MPRow/MPBar")
	var mp_val  = layout.get_node("MPRow/MPValue")
	var res_bar = layout.get_node("ResonanceRow/ResonanceBar")
	var res_val = layout.get_node("ResonanceRow/ResValue")

	hp_bar.max_value = hero.max_hp()
	hp_bar.value = hero.current_hp
	hp_val.text = "%d/%d" % [hero.current_hp, hero.max_hp()]

	mp_bar.max_value = hero.max_mp()
	mp_bar.value = hero.current_mp
	mp_val.text = "%d/%d" % [hero.current_mp, hero.max_mp()]

	var res_pct = resonance_system.get_resonance_percent(hero) * 100
	res_bar.max_value = 100
	res_bar.value = res_pct
	if resonance_system.is_full(hero):
		res_val.text = "FULL ✦"
		res_val.modulate = Color(0.88, 0.69, 1.0)
	else:
		res_val.text = "%d%%" % int(res_pct)
		res_val.modulate = Color(0.78, 0.62, 0.88)

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
	gem.custom_minimum_size = Vector2(24, 24)
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
	var hp_bar = ProgressBar.new()
	hp_bar.max_value = enemy.max_hp()
	hp_bar.value = enemy.current_hp
	hp_bar.custom_minimum_size = Vector2(0, 8)
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar.show_percentage = false
	vbox.add_child(hp_bar)

	# HP label
	var hp_lbl = Label.new()
	hp_lbl.text = "%d/%d" % [enemy.current_hp, enemy.max_hp()]
	hp_lbl.add_theme_font_size_override("font_size", 9)
	hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if cinzel:
		hp_lbl.add_theme_font_override("font", cinzel)
	vbox.add_child(hp_lbl)

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

func _on_action_performed(result: Dictionary):
	_refresh_all_panels()
	if result.has("multiplier") and result["multiplier"] != 1.0:
		print(result.get("effectiveness", ""))
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

func _on_battle_ended(player_won: bool, rewards: Dictionary):
	_toggle_action_menu(false)
	if player_won:
		GameManager.award_rewards(rewards)
		print("Victory!")
		for enemy in battle_manager.enemies:
			if enemy is Enemy:
				GameManager.record_battle_against(enemy.species)
	else:
		print("Defeated...")

func _on_status_triggered(character: Character, result: Dictionary):
	print("%s: %s %d" % [character.character_name, result["type"], result["value"]])
	_refresh_all_panels()

# --- Action Buttons ---
func _on_attack_pressed():
	if current_actor == null:
		return
	var alive_enemies = battle_manager.get_alive_enemies()
	if alive_enemies.is_empty():
		return
	battle_manager.player_attack(current_actor, alive_enemies[0])

func _on_special_pressed():
	print("Special menu — coming soon!")

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
