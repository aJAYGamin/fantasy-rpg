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
# Status chip rows (mutex status + per-stat buff/debuff chips). Injected into
# the existing panel layouts on first encounter so we don't have to edit .tscn.
# Refreshed via StatusChipFactory on every _update_hero_panel / _refresh_enemy_card.
var _enemy_status_rows: Dictionary = {} # character -> HBoxContainer
var _bar_tweens: Dictionary = {}      # ProgressBar -> Tween (so we can cancel/restart on rapid updates)
const BAR_TWEEN_DURATION: float = 0.3

# Status banner display times (total visible time, including fade in/out).
# Fade-in is 0.22, fade-out is 0.30, so hold time = duration - 0.52s.
# BattleManager's skip-turn await must match BANNER_DURATION_SKIP + small buffer
# so the next turn does NOT start before the banner finishes.
const BANNER_DURATION_APPLIED: float = 1.55
const BANNER_DURATION_SKIP: float    = 1.70
const BANNER_DURATION_WAKE: float    = 1.55
var _enemy_hp_labels: Dictionary = {} # character -> Label
# Keyed by Character ref so duplicate-named enemies (e.g. two Wind Sprites)
# each have their own portrait lookup. Avoids relying on Godot's auto-rename suffixes.
var _enemy_portraits: Dictionary = {} # character -> portrait Node
var _hero_portraits: Dictionary = {}  # character -> portrait Node

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
	battle_manager.turn_ready_for_action.connect(_on_turn_ready_for_action)
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

	# Apply the shared battle UI theme to the scene-built action menu buttons
	# so they match the resonance menu / hero panels visually.
	BattleUITheme.style_button(attack_btn, 12)
	BattleUITheme.style_button(special_btn, 12)
	BattleUITheme.style_button(items_btn, 12)
	BattleUITheme.style_button(run_btn, 12)
	BattleUITheme.style_button(resonance_btn, 12)
	# Theme the outer action menu panel container too.
	var action_panel_style := BattleUITheme.panel_style()
	action_panel_style.content_margin_left = 10
	action_panel_style.content_margin_right = 10
	action_panel_style.content_margin_top = 8
	action_panel_style.content_margin_bottom = 8
	action_menu.add_theme_stylebox_override("panel", action_panel_style)
	# Title label color/font for consistency.
	if action_title:
		var f := BattleUITheme.font_bold()
		if f: action_title.add_theme_font_override("font", f)
		action_title.add_theme_color_override("font_color", BattleUITheme.TEXT_SUBTITLE)

	resonance_system.resonance_changed.connect(_on_resonance_changed)
	resonance_system.resonance_full.connect(_on_resonance_full)

	# Connect victory/defeat screens
	victory_screen.victory_closed.connect(_on_victory_closed)
	victory_screen.setup_level_up_screen(level_up_screen)

	if GameManager.in_overworld_battle:
		_start_overworld_battle()
	else:
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
		# Enemies have no MP pool — skip _max_mp caching for them.
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
	# Use the shared party inventory (the leader holds all items) so battle item
	# use and the pause-menu Items screen draw from the same store. ItemsMenu
	# filters to battle-usable items via Inventory.get_battle_items().
	_battle_inventory = party[0].inventory if not party.is_empty() else Inventory.new()
	items_menu.setup(battle_manager, _battle_inventory)
	items_menu.item_used.connect(_on_item_used)
	items_menu.menu_closed.connect(_on_attack_menu_closed)
	battle_manager.start_battle(party, enemies)

func _start_test_battle():
	await get_tree().process_frame
	await get_tree().process_frame

	# Test seed for victory-screen gold animation; only on the first battle of a session.
	if GameManager.party.is_empty():
		GameManager.gold = 50
	GameManager.ensure_default_party()

	var party: Array[Character] = []
	for c in GameManager.party:
		party.append(c)

	# 10 enemies loaded from data/enemies/*.tres
	var enemy_files = [
		"ice_golem", "fire_drake", "dark_wraith", "storm_eagle", "earth_golem",
		"sea_serpent", "wind_sprite", "light_golem", "void_shade", "frost_wyrm",
	]
	var enemies: Array[Character] = []
	for file_name in enemy_files:
		enemies.append(_load_enemy(file_name))

	start_battle(party, enemies, "fallster_plains", EnemyLayout.GRID_2COL)

func _start_overworld_battle():
	await get_tree().process_frame
	await get_tree().process_frame

	# Party must already exist — overworld populates it before this scene runs.
	var party: Array[Character] = []
	for c in GameManager.party:
		party.append(c)

	# Enemies are already deep-copied + level-overridden + HP/MP-set by the
	# EncounterGroup, so we just consume them as-is.
	var enemies: Array[Character] = []
	for enemy in GameManager.pending_battle_enemies:
		enemies.append(enemy)

	var bg_id: String = GameManager.pending_battle_background
	if bg_id == "":
		bg_id = "fallster_plains"
	start_battle(party, enemies, bg_id, EnemyLayout.GRID_2COL)

# Loads an enemy resource and prepares it for battle.
# duplicate(true) gives each spawn its own HP/state — without it all spawns share one Resource.
func _load_enemy(file_name: String) -> Enemy:
	var enemy: Enemy = load("res://data/enemies/%s.tres" % file_name).duplicate(true)
	enemy.current_hp = enemy.max_hp()
	# Enemies don't have an MP pool — skip current_mp init.
	if enemy.inventory == null:
		enemy.inventory = Inventory.new()
	return enemy

# --- UI Setup ---
func _setup_hero_panels(party: Array[Character]):
	var panels = [hero_status_1, hero_status_2, hero_status_3]
	for i in range(panels.size()):
		if i < party.size():
			panels[i].visible = true
			# animate=false so bars show their starting values instantly at battle setup
			_update_hero_panel(panels[i], party[i], false)
		else:
			panels[i].visible = false

# Smoothly tweens a ProgressBar's value and updates its label text in lockstep.
# label_fn receives the interpolated value each frame and returns the text to display.
# Cancels any in-progress tween on the same bar so rapid updates don't fight each other.
func _animate_bar(bar: ProgressBar, label: Label, target: float, label_fn: Callable, duration: float = BAR_TWEEN_DURATION) -> void:
	if not is_instance_valid(bar):
		return
	if _bar_tweens.has(bar):
		var old = _bar_tweens[bar]
		if old != null and old.is_valid():
			old.kill()
		_bar_tweens.erase(bar)

	var start_val: float = bar.value
	if is_equal_approx(start_val, target):
		if label != null and is_instance_valid(label):
			label.text = label_fn.call(target)
		return

	var tween = create_tween().set_parallel(true)
	tween.tween_property(bar, "value", target, duration)
	if label != null and is_instance_valid(label):
		tween.tween_method(
			func(v: float):
				if is_instance_valid(label):
					label.text = label_fn.call(v),
			start_val, target, duration
		)
	_bar_tweens[bar] = tween

func _update_hero_panel(panel: PanelContainer, hero: Character, animate: bool = true):
	var layout = panel.get_node("HeroLayout")
	var name_lbl: Label = layout.get_node("HeroNameLabel")
	name_lbl.text = "  %s · Lv%d" % [hero.character_name, hero.level]

	# --- Hero-themed panel chrome ---
	# Tint the panel border / bg with the hero's accent so each party slot is
	# visually distinct (Aria blue, Kael red, Lyra green). The HP/MP/Resonance
	# bars keep their semantic colors so readability isn't sacrificed — the
	# tint is only on the chrome and the name.
	var palette: Dictionary = HeroPalette.for_hero(hero.character_name)
	# Tinted panel chrome — rebuilt every refresh so tweaks (margins, border)
	# always reflect current code. (The `themed` meta was previously used to
	# avoid rebuilding but it meant later style tweaks didn't apply.)
	var styled := StyleBoxFlat.new()
	styled.bg_color = palette["panel_bg"]
	styled.border_color = palette["accent"]
	styled.set_border_width_all(2)
	styled.set_corner_radius_all(10)
	styled.shadow_color = Color(0, 0, 0, 0.5)
	styled.shadow_size = 4
	# Generous top padding so the hero name doesn't kiss the border + room at
	# the bottom for the status chip row that the layout grows into.
	styled.content_margin_left = 10
	styled.content_margin_right = 10
	styled.content_margin_top = 10
	styled.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", styled)
	# Name label always gets the accent color + drop shadow for legibility.
	name_lbl.add_theme_color_override("font_color", palette["accent"])
	name_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	name_lbl.add_theme_constant_override("shadow_offset_x", 1)
	name_lbl.add_theme_constant_override("shadow_offset_y", 1)

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
	var hp_label_fn := func(v: float) -> String: return "%d/%d" % [int(v), hero.max_hp()]
	if animate:
		_animate_bar(hp_bar, hp_val, hero.current_hp, hp_label_fn)
	else:
		hp_bar.value = hero.current_hp
		hp_val.text = hp_label_fn.call(hero.current_hp)

	# HP color based on percentage (instant — modulate isn't worth tweening)
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
	var mp_label_fn := func(v: float) -> String: return "%d/%d" % [int(v), hero.max_mp()]
	if animate:
		_animate_bar(mp_bar, mp_val, hero.current_mp, mp_label_fn)
	else:
		mp_bar.value = hero.current_mp
		mp_val.text = mp_label_fn.call(hero.current_mp)

	var mp_color = Color(0.3, 0.65, 1.0)        # Light blue
	mp_bar.modulate = mp_color
	mp_lbl.add_theme_color_override("font_color", mp_color)
	mp_val.add_theme_color_override("font_color", mp_color)

	# --- Resonance ---
	var res_pct = resonance_system.get_resonance_percent(hero) * 100
	res_bar.max_value = 100
	var res_label_fn := func(v: float) -> String:
		if v >= 100.0:
			return "FULL ✦"
		return "%d%%" % int(v)
	if animate:
		_animate_bar(res_bar, res_val, res_pct, res_label_fn)
	else:
		res_bar.value = res_pct
		res_val.text = res_label_fn.call(res_pct)

	var res_color = Color(0.72, 0.55, 1.0)      # Light purple
	res_bar.modulate = res_color
	res_lbl.add_theme_color_override("font_color", res_color)
	if resonance_system.is_full(hero):
		res_val.add_theme_color_override("font_color", Color(0.88, 0.69, 1.0))
	else:
		res_val.add_theme_color_override("font_color", res_color)

	# --- Status / Buff / Debuff chip row (beneath ResonanceRow) ---
	# Lazily inject the row the first time we see this panel — keeps scene files
	# untouched and means new heroes added later get the row for free.
	var status_row: HBoxContainer = layout.get_node_or_null("StatusRow")
	if status_row == null:
		status_row = HBoxContainer.new()
		status_row.name = "StatusRow"
		status_row.add_theme_constant_override("separation", 4)
		status_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		layout.add_child(status_row)
	StatusChipFactory.populate_row(status_row, hero)

func _setup_enemy_cards(enemies: Array[Character]):
	for child in enemy_info_row.get_children():
		child.queue_free()

	# Cards are fixed-width and centered. 10 enemies fill the row; fewer cluster in the middle.
	# Bosses/key enemies will later flag as "is_boss" to use SIZE_EXPAND_FILL instead.
	enemy_info_row.alignment = BoxContainer.ALIGNMENT_CENTER

	var count = mini(enemies.size(), 10)
	for i in range(count):
		var card = _create_enemy_card(enemies[i])
		enemy_info_row.add_child(card)

func _create_enemy_card(enemy: Character) -> PanelContainer:
	var card = PanelContainer.new()
	# Fixed width — cards no longer stretch when there are few enemies.
	# 10 cards × 124 + 9 × 2 spacing = 1258, fits comfortably in the 1280-wide viewport.
	card.custom_minimum_size = Vector2(124, 70)
	# Themed chrome — border colored by the enemy's RARITY (common=grey,
	# uncommon=green, rare=blue, epic=purple, mythic=red, legendary=gold,
	# celestial=white) so the player can read an enemy's tier at a glance.
	# Dark plum bg matches the action/resonance menus.
	var enemy_border: Color = enemy.get_rarity_color() if enemy is Enemy else BattleUITheme.PANEL_BORDER
	card.add_theme_stylebox_override("panel",
			BattleUITheme.panel_style(enemy_border, BattleUITheme.PANEL_BG, 2, 8))

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
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

	# Name label — includes level indicator (matches hero panel format)
	var name_lbl = Label.new()
	name_lbl.text = "%s · Lv%d" % [enemy.character_name, enemy.level]
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

	# Status chip row beneath the HP label. Built empty and shown only when
	# the enemy actually has effects (StatusChipFactory auto-hides if none).
	var status_row = HBoxContainer.new()
	status_row.name = "StatusRow"
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_row.add_theme_constant_override("separation", 3)
	status_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(status_row)
	_enemy_status_rows[enemy] = status_row
	StatusChipFactory.populate_row(status_row, enemy)

	return card

# --- Battle Signals ---
func _on_battle_started(_party, _enemies):
	_toggle_action_menu(false)

func _on_turn_started(character: Character):
	# Fires the moment a new turn begins, BEFORE stun/sleep/paralysis is
	# resolved. We use it for: turn-order highlight, target-selection cleanup,
	# and force-hiding the action menu so it can't flash visible while a
	# skip-turn banner plays. The menu re-appears via _on_turn_ready_for_action
	# only if the actor actually gets to act.
	current_actor = character

	_pending_action = ""
	_clear_target_buttons()
	var action_layout = action_menu.get_node_or_null("ActionLayout")
	if action_layout:
		var back_btn = action_layout.get_node_or_null("TargetBackBtn")
		if back_btn:
			back_btn.queue_free()
		for child in action_layout.get_children():
			child.visible = true

	# Always hide the menu at turn start — _on_turn_ready_for_action will show
	# it again iff the actor is a player and not skipping.
	action_menu.visible = false

	# General refresh at turn boundary so any inter-turn state (HP drain
	# animations finishing, etc.) is visible. The sleep-wake chip clear is
	# handled separately: BattleManager fires status_effect_triggered with
	# type="woke_up" right after resolve_turn_skip, and _on_status_triggered
	# refreshes there — at which point Character has already lost the Sleep
	# status, so the chip disappears together with the wake banner.
	_refresh_all_panels()
	if battle_manager.enemies.has(character):
		_refresh_enemy_card(character)

	_update_resonance_button()
	turn_order_indicator.set_active(character)

func _on_turn_ready_for_action(character: Character):
	# Fires AFTER skip/wake banners finish, only when the actor will actually
	# act this turn. Safe point to reveal the action menu for the player.
	var is_player = battle_manager.party.has(character)
	if is_player:
		action_title.text = "— %s's Turn —" % character.character_name
		action_menu.visible = not _battle_over
	else:
		action_menu.visible = false

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
		# Card may have been freed by an enemy-card rebuild during the yield (e.g. an enemy
		# died on the previous turn and the 0.4s delayed rebuild fired). Bail out cleanly.
		if not is_instance_valid(card) or not is_instance_valid(panel):
			if is_instance_valid(panel):
				panel.queue_free()
			return
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

	var hp_label_fn := func(v: float) -> String: return "%d/%d" % [int(v), enemy_max_hp]
	_animate_bar(hp_bar, hp_lbl, enemy.current_hp, hp_label_fn)

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
		hp_lbl.add_theme_color_override("font_color", hp_color)

	# Refresh status chips — buff/debuff/poison/etc may have changed this turn.
	var status_row = _enemy_status_rows.get(enemy)
	if status_row != null and is_instance_valid(status_row):
		StatusChipFactory.populate_row(status_row, enemy)

func _on_action_performed(result: Dictionary):
	_refresh_all_panels()
	# Refresh enemy card if an enemy was the target (took damage / got debuffed)
	if result.has("target"):
		var target = result["target"]
		if battle_manager.enemies.has(target):
			_refresh_enemy_card(target)
	# Also refresh the actor's card if the actor is an enemy that buffed itself
	# or an ally — heroes are covered by _refresh_all_panels above.
	if result.has("actor"):
		var actor = result["actor"]
		if actor != null and battle_manager.enemies.has(actor):
			_refresh_enemy_card(actor)

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
	# Resonance hooks — ONLY grant on first target so AoE doesn't compound
	if result.get("is_first_target", false) and result.has("actor") and battle_manager.party.has(result["actor"]):
		var actor: Character = result["actor"]
		var skill_ref: Skill = result.get("skill")
		match result.get("action", ""):
			"attack":
				resonance_system.on_attack(actor)
			"skill_magic", "skill_physical", "status":
				resonance_system.on_skill_used(actor, skill_ref)
	# Taking damage builds resonance for heroes on receiving end (once per hit)
	if result.has("target") and battle_manager.party.has(result["target"]):
		if result.get("action") in ["attack", "skill_magic", "skill_physical"]:
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
	# Queue a rebuild instead of rebuilding immediately.
	# Waits for the HP-drain tween to finish so the bar doesn't snap to 0 visually.
	# Multiple enemies dying in one turn (AoE) all collapse into one rebuild via the queue flag.
	if _card_rebuild_queued:
		return
	_card_rebuild_queued = true
	await get_tree().create_timer(BAR_TWEEN_DURATION + 0.1).timeout
	_rebuild_enemy_cards()
	_card_rebuild_queued = false

func _rebuild_enemy_cards():
	var alive_enemies = battle_manager.get_alive_enemies()
	for card in enemy_info_row.get_children():
		card.queue_free()
	if alive_enemies.is_empty():
		return
	# Match _setup_enemy_cards: fixed-width cards, centered. No SIZE_EXPAND_FILL.
	enemy_info_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for e in alive_enemies:
		var card = _create_enemy_card(e)
		enemy_info_row.add_child(card)

func _on_battle_ended(player_won: bool, rewards: Dictionary):
	_battle_over = true
	_toggle_action_menu(false)
	# Clear ALL temporary battle effects from the party — mutex statuses
	# (poison/scorched/frostbite/stun/sleep/paralysis), buffs, debuffs, sleep
	# counter. Without this they'd leak into the next encounter or overworld.
	# Enemies are destroyed at battle end so they don't need cleanup.
	for hero in battle_manager.party:
		hero.clear_battle_effects()
	# Hide menus immediately (no animations on these), but let HP/MP/Resonance bars
	# finish their tween so the killing blow's drain is visible to the player.
	attack_menu.visible = false
	action_menu.visible = false
	resonance_menu.visible = false
	items_menu.visible = false
	await get_tree().create_timer(BAR_TWEEN_DURATION + 0.1).timeout
	enemy_info_row.visible = false
	party_status_bar.visible = false
	turn_order_indicator.visible = false
	if player_won:
		GameManager.award_rewards(rewards)
		for enemy in battle_manager.enemies:
			if enemy is Enemy:
				GameManager.record_battle_against(enemy.species)
		victory_screen.show_victory(rewards, battle_manager.party, resonance_system)
	else:
		defeat_screen.show_defeat()

func _on_victory_closed():
	if GameManager.in_overworld_battle:
		_return_to_overworld()
	else:
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

# Returns the player to the overworld scene at their pre-encounter position.
# OverworldScene._ready handles the position restore and clears in_overworld_battle.
func _return_to_overworld():
	var path: String = GameManager.pending_overworld_scene_path
	if path == "":
		path = "res://scenes/OverworldScene.tscn"
	get_tree().change_scene_to_file(path)

func _on_status_triggered(character: Character, result: Dictionary):
	var event_type: String = result.get("type", "")
	print("%s: %s %d" % [character.character_name, event_type, int(result.get("value", 0))])
	_refresh_all_panels()
	# Status events fire on enemies too (poison tick, sleep skip, etc.) — refresh
	# that enemy's card so chips and HP bar stay in sync.
	if character != null and battle_manager.enemies.has(character):
		_refresh_enemy_card(character)

	# Banner routing — three event shapes:
	#   applied=true  -> "[Name] was Poisoned!" / "fell Asleep!" / etc.
	#   skipped=true  -> "[Name] reoriented themself" (stun) / "is Asleep!" (sleep)
	#   type=woke_up  -> "[Name] woke up!"
	var nm: String = character.character_name
	if event_type == "woke_up":
		_show_status_banner(
			StatusSystem.woke_phrase(nm),
			Color(1.00, 0.95, 0.55),  # warm wake-up yellow
			BANNER_DURATION_WAKE
		)
	elif result.get("skipped", false):
		# Defensive: force-hide the action menu the moment a skip banner fires
		# (stun / sleep / paralysis). _on_turn_started already hides it at turn
		# boundary, but this guards against any race where the menu was set
		# visible elsewhere between turn_started and resolve_turn_skip.
		action_menu.visible = false
		var skip_color: Color = StatusSystem.STATUS_COLORS.get(event_type, Color(0.8, 0.8, 0.9))
		_show_status_banner(
			StatusSystem.skipped_phrase(nm, event_type),
			skip_color,
			BANNER_DURATION_SKIP
		)
	elif result.get("applied", false):
		var apply_color: Color = StatusSystem.STATUS_COLORS.get(event_type, Color(0.8, 0.8, 0.9))
		_show_status_banner(
			StatusSystem.applied_phrase(nm, event_type),
			apply_color,
			BANNER_DURATION_APPLIED
		)

# Shows a large centered banner with a status-colored border for `duration`
# seconds, then fades out. Safe to call repeatedly — any in-progress banner is
# replaced. Banner sits above the battle UI on its own CanvasLayer so it
# doesn't get clipped by panels or the camera.
func _show_status_banner(text: String, color: Color, duration: float):
	# Lazily build the banner layer + nodes on first use.
	var layer: CanvasLayer = get_node_or_null("StatusBannerLayer")
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "StatusBannerLayer"
		layer.layer = 50  # above everything else in BattleUI
		add_child(layer)

	# Centered Control filling the viewport so its child can use anchor presets.
	var root: Control = layer.get_node_or_null("BannerRoot")
	if root == null:
		root = Control.new()
		root.name = "BannerRoot"
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(root)

	# Kill any previous banner so we never have two stacked.
	for child in root.get_children():
		child.queue_free()

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.modulate.a = 0.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.10, 0.92)
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 4
	panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	# Cinzel for visual consistency with the rest of the battle UI.
	if ResourceLoader.exists("res://fonts/Cinzel-Bold.ttf"):
		label.add_theme_font_override("font", load("res://fonts/Cinzel-Bold.ttf"))
	# Drop shadow for legibility over any background.
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	panel.add_child(label)

	root.add_child(panel)
	# Re-center after layout pass (size depends on label).
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	panel.position = (root.size - panel.size) * 0.5
	# Drift upward slightly while fading — gives it some life.
	var start_y := panel.position.y + 10
	panel.position.y = start_y

	# Fade-in (0.22) -> hold (duration - 0.52) -> fade-out (0.30) + drift up.
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.22)
	tw.tween_property(panel, "position:y", start_y - 10, 0.22)
	await tw.finished
	if not is_instance_valid(panel):
		return
	await get_tree().create_timer(max(0.0, duration - 0.52)).timeout
	if not is_instance_valid(panel):
		return
	var out := create_tween().set_parallel(true)
	out.tween_property(panel, "modulate:a", 0.0, 0.30)
	out.tween_property(panel, "position:y", start_y - 24, 0.30)
	await out.finished
	if is_instance_valid(panel):
		panel.queue_free()

# --- Target Selection ---
var _pending_action: String = ""
var _pending_skill: Skill = null
var _pending_item: Item = null
var _battle_over: bool = false
# Shared party inventory used for in-battle item use (set in start_battle).
var _battle_inventory: Inventory = null

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
		# Remove item from the shared inventory if depleted.
		if item.quantity <= 0 and _battle_inventory != null:
			_battle_inventory.items.erase(item)
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

# Hero colors keyed by uppercased element name (lookup is `get_element_name(...).to_upper()`).
const HERO_COLORS = {
	"FIRE":      Color(0.90, 0.30, 0.15),
	"WATER":     Color(0.20, 0.50, 0.90),
	"NATURE":    Color(0.40, 0.85, 0.40),
	"ICE":       Color(0.40, 0.75, 1.00),
	"LIGHTNING": Color(0.95, 0.85, 0.10),
	"EARTH":     Color(0.50, 0.35, 0.15),
	"WIND":      Color(0.50, 0.90, 0.40),
	"SOUND":     Color(0.95, 0.85, 0.45),
	"PSYCHIC":   Color(0.90, 0.40, 0.85),
	"SPIRIT":    Color(0.78, 0.78, 1.00),
	"DRAGON":    Color(0.85, 0.50, 0.20),
	"METAL":     Color(0.70, 0.72, 0.78),
	"LIGHT":     Color(1.00, 0.95, 0.60),
	"DARK":      Color(0.40, 0.20, 0.60),
	"NORMAL":    Color(0.50, 0.50, 0.55),
}

func _setup_portraits(party: Array[Character], enemies: Array[Character]):
	# Clear existing portraits
	for child in party_positions.get_children():
		child.queue_free()
	for child in enemy_positions.get_children():
		child.queue_free()
	_enemy_portraits.clear()
	_hero_portraits.clear()

	var cinzel = load("res://fonts/Cinzel-Regular.ttf")
	var screen = get_viewport().get_visible_rect().size

	# Portrait size — smaller than before to keep the diagonal stack from
	# overlapping the (now-taller) hero info bar. Real character sprites will
	# slot in here later; the placeholder rect just needs enough room for the
	# letter initial.
	var pw = 32.0
	var ph = 40.0

	# Tighter VBox stacking so the bottom hero clears the info panel.
	party_positions.add_theme_constant_override("separation", 0)

	# --- Hero portraits ---
	# VBoxContainer at x:50, y:320 — portraits stack vertically with diagonal offset.
	# Each Control wrapper has just enough height for its portrait + name label
	# so the whole stack fits above the PartyStatusBar (top at scene y=508).
	for i in range(party.size()):
		var hero = party[i]
		var wrapper = Control.new()
		wrapper.custom_minimum_size = Vector2(pw + i * 30, ph + 12)
		party_positions.add_child(wrapper)

		var portrait = _create_portrait(hero, cinzel, false)
		portrait.name = "HeroPortrait_%s" % hero.character_name
		# Each successive hero shifts right to create front-to-back diagonal
		# Hero 1 (i=0): leftmost/back, last hero: rightmost/front
		portrait.position = Vector2((party.size() - 1 - i) * 30, 0)
		wrapper.add_child(portrait)
		_hero_portraits[hero] = portrait

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
		_enemy_portraits[enemy] = portrait

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
	vbox.add_theme_constant_override("separation", 2)

	# Themed portrait placeholder — a PanelContainer with a rounded
	# accent-tinted border, so portraits match the rest of the battle UI
	# instead of looking like flat colored rects. Slimmer than before so the
	# diagonal stack fits comfortably above the (now-taller) hero info bar.
	var portrait_panel := PanelContainer.new()
	portrait_panel.custom_minimum_size = Vector2(32, 40)
	var elem_key = ElementalSystem.get_element_name(character.element).to_upper()
	var fill: Color = HERO_COLORS.get(elem_key, Color(0.5, 0.5, 0.55))
	# Heroes use HeroPalette accent for the border (matches their info panel);
	# enemies use the element color so distinct enemy types are scannable.
	var border_color: Color
	if is_enemy:
		fill = fill.darkened(0.15)
		border_color = ElementalSystem.get_element_color(character.element).lerp(BattleUITheme.PANEL_BORDER, 0.40)
	else:
		border_color = HeroPalette.accent_for(character.character_name)
	var portrait_style := BattleUITheme.panel_style(border_color, fill, 2, 6)
	portrait_style.content_margin_left = 0
	portrait_style.content_margin_right = 0
	portrait_style.content_margin_top = 0
	portrait_style.content_margin_bottom = 0
	portrait_style.shadow_size = 3
	portrait_panel.add_theme_stylebox_override("panel", portrait_style)
	vbox.add_child(portrait_panel)

	# First letter initial centered on portrait
	var initial_lbl = Label.new()
	initial_lbl.text = character.character_name.substr(0, 1).to_upper()
	initial_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cinzel: initial_lbl.add_theme_font_override("font", cinzel)
	initial_lbl.add_theme_font_size_override("font_size", 16)
	initial_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.30))
	portrait_panel.add_child(initial_lbl)

	# Name label underneath (compact font so the wrapper height stays tight)
	var name_lbl = Label.new()
	name_lbl.text = character.character_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if cinzel: name_lbl.add_theme_font_override("font", cinzel)
	name_lbl.add_theme_font_size_override("font_size", 7)
	name_lbl.add_theme_color_override("font_color", Color(0.88, 0.78, 1.0))
	vbox.add_child(name_lbl)

	return vbox

func _remove_portrait(character: Character):
	# Look up by Character ref so duplicate-named enemies each find their own portrait.
	var portrait: Node = null
	if _enemy_portraits.has(character):
		portrait = _enemy_portraits[character]
		_enemy_portraits.erase(character)
	elif _hero_portraits.has(character):
		portrait = _hero_portraits[character]
		_hero_portraits.erase(character)
	if portrait == null or not is_instance_valid(portrait):
		return
	var tween = create_tween()
	tween.tween_property(portrait, "modulate:a", 0.0, 0.4)
	await tween.finished
	if is_instance_valid(portrait):
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
		if item.quantity <= 0 and _battle_inventory != null:
			_battle_inventory.items.erase(item)
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
	# Running bypasses the battle_ended signal, so we have to clear temporary
	# battle effects (statuses, buffs, debuffs, sleep counter) explicitly here
	# — otherwise a hero who ran with Poison still has Poison in the next fight.
	for hero in battle_manager.party:
		hero.clear_battle_effects()
	if GameManager.in_overworld_battle:
		_return_to_overworld()
	else:
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
	resonance_skill.mp_cost = 0
	resonance_skill.resonance_gain_override = 0.0  # Don't give resonance for ultimates
	resonance_skill.skill_type = Skill.SkillType.DAMAGE
	resonance_skill.attack_type = Skill.AttackType.MAGIC
	resonance_skill.target_type = Skill.TargetType.ALL_ENEMIES

	if action_type == "solo":
		resonance_skill.skill_name = "%s Ultimate" % heroes[0].character_name
		resonance_skill.power = 3.5
		# Solo ultimate uses the hero's own element pair.
		resonance_skill.element = heroes[0].element
		resonance_skill.secondary_element = heroes[0].secondary_element
		battle_manager.player_use_skill(heroes[0], resonance_skill, typed_targets)
	elif action_type == "triple":
		resonance_skill.skill_name = "Amethyst Requiem"
		resonance_skill.power = 8.0
		# Triple resonance is pure Amethyst — universally super-effective via the chart.
		resonance_skill.element = ElementalSystem.Element.AMETHYST
		resonance_skill.secondary_element = ElementalSystem.Element.NORMAL
		battle_manager.player_use_skill(heroes[0], resonance_skill, typed_targets)
	else:
		# Combined (duo) resonance — element pair depends on which two heroes.
		var info = _combined_resonance_info(heroes)
		resonance_skill.skill_name = info["name"]
		resonance_skill.element = info["element"]
		resonance_skill.secondary_element = info["secondary"]
		resonance_skill.power = 5.0
		battle_manager.player_use_skill(heroes[0], resonance_skill, typed_targets)

	_refresh_all_panels()

# Resolves the duo-resonance attack name + element pair for a 2-hero combination.
# Elements are derived from the heroes' own primary elements (works for any
# future heroes added). The flavorful name is looked up by the sorted
# hero-name key in ResonanceMenu.COMBINED_ATTACK_NAMES.
func _combined_resonance_info(heroes: Array) -> Dictionary:
	var E = ElementalSystem.Element
	var names: Array = []
	for h in heroes:
		names.append(h.character_name)
	names.sort()
	var key: String = "+".join(names)
	var attack_name: String = "Combined Resonance"
	if resonance_menu != null and resonance_menu.COMBINED_ATTACK_NAMES.has(key):
		attack_name = resonance_menu.COMBINED_ATTACK_NAMES[key]
	# Elements = each hero's primary. Order of attacker elements doesn't change
	# damage under the multiply-all formula, so heroes[0]/heroes[1] is fine.
	var primary: int = heroes[0].element if heroes.size() > 0 else E.NORMAL
	var secondary: int = heroes[1].element if heroes.size() > 1 else E.NORMAL
	return {"name": attack_name, "element": primary, "secondary": secondary}

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
	resonance_btn.text = "✦ Resonance — READY" if is_full else "✦ Resonance"
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
