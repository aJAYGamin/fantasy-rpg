extends Control

signal victory_closed

@onready var overlay          = $Overlay
@onready var content          = $Content
@onready var victory_label    = $Content/VictoryLabel
@onready var party_list       = $Content/PartyList
@onready var rewards_label    = $Content/RewardsLabel
@onready var continue_btn     = $Content/ContinueButton

var rewards: Dictionary = {}
var party: Array[Character] = []
var resonance_system: ResonanceSystem
var pending_exp: int = 0
var pending_gold: int = 0
var level_up_screen: Control = null
var _pending_level_up_heroes: Array[Character] = []
var _card: Control = null  # themed card wrapping Content (set in _apply_theme)

func _ready():
	hide()
	continue_btn.pressed.connect(_on_continue)
	continue_btn.visible = false
	_apply_theme()

# Wraps the centered content in a themed gold-bordered card and styles the
# title + button to match the rest of the battle UI (resonance/action menus).
func _apply_theme():
	var accent := Color(1.00, 0.84, 0.25)  # victory gold

	# Darken the overlay a touch more for contrast against the card.
	overlay.color = Color(0.02, 0.02, 0.05, 0.72)

	# Center + themed card wrapping the content.
	var center := CenterContainer.new()
	center.name = "CardCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var card := PanelContainer.new()
	card.name = "ThemedCard"
	var style := BattleUITheme.panel_style(accent, BattleUITheme.PANEL_BG, 3, 16)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	style.shadow_size = 10
	card.add_theme_stylebox_override("panel", style)
	center.add_child(card)
	_card = card

	# Reparent the existing Content VBox into the card (cached @onready refs
	# stay valid through the reparent).
	if content.get_parent() != null:
		content.get_parent().remove_child(content)
	card.add_child(content)

	# Title — gold with a drop shadow + decorative stars.
	victory_label.text = "✦  Victory  ✦"
	victory_label.add_theme_color_override("font_color", accent)
	victory_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	victory_label.add_theme_constant_override("shadow_offset_x", 2)
	victory_label.add_theme_constant_override("shadow_offset_y", 2)

	# Continue button — themed, gold-tinted, comfortable size.
	BattleUITheme.style_button(continue_btn, 15)
	continue_btn.custom_minimum_size = Vector2(240, 42)
	continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

func setup_level_up_screen(lus: Control):
	level_up_screen = lus
	level_up_screen.level_up_complete.connect(_on_level_up_complete)

func show_victory(battle_rewards: Dictionary, battle_party: Array[Character], res_system: ResonanceSystem):
	rewards = battle_rewards
	party = battle_party
	resonance_system = res_system
	pending_exp = rewards.get("exp", 0)
	pending_gold = rewards.get("gold", 0)

	await get_tree().create_timer(1.2).timeout
	show()

	overlay.modulate.a = 0.0
	var fade_target = _card if _card != null else content
	fade_target.modulate.a = 0.0
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(overlay, "modulate:a", 1.0, 0.5)
	tween.tween_property(fade_target, "modulate:a", 1.0, 0.8)
	await tween.finished

	_build_party_list()
	_build_rewards_label()

	await get_tree().create_timer(0.8).timeout
	await _animate_exp()

func _build_party_list():
	for child in party_list.get_children():
		child.queue_free()

	var cinzel = load("res://fonts/Cinzel-Regular.ttf")

	for hero in party:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		party_list.add_child(row)

		var name_lbl = Label.new()
		name_lbl.text = "%s  Lv%d" % [hero.character_name, hero.level]
		name_lbl.custom_minimum_size = Vector2(160, 0)
		if cinzel: name_lbl.add_theme_font_override("font", cinzel)
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", HeroPalette.accent_for(hero.character_name))
		row.add_child(name_lbl)

		var exp_bar = ProgressBar.new()
		exp_bar.name = "ExpBar_%s" % hero.character_name
		exp_bar.max_value = hero.experience_to_next
		exp_bar.value = hero.experience
		exp_bar.show_percentage = false
		exp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		exp_bar.custom_minimum_size = Vector2(160, 14)
		_style_exp_bar(exp_bar)
		row.add_child(exp_bar)

		var exp_lbl = Label.new()
		exp_lbl.name = "ExpLabel_%s" % hero.character_name
		exp_lbl.text = "%d / %d" % [hero.experience, hero.experience_to_next]
		exp_lbl.custom_minimum_size = Vector2(90, 0)
		if cinzel: exp_lbl.add_theme_font_override("font", cinzel)
		exp_lbl.add_theme_font_size_override("font_size", 11)
		exp_lbl.add_theme_color_override("font_color", Color(0.7, 0.6, 0.9))
		row.add_child(exp_lbl)

func _build_rewards_label():
	var cinzel = load("res://fonts/Cinzel-Regular.ttf")
	# Items + equipment drops (gold is handled separately with animation).
	var items = rewards.get("items", [])
	var equipment = rewards.get("equipment", [])

	var lines: Array[String] = []
	if not items.is_empty():
		lines.append("Items:")
		for item in items:
			lines.append("%s  x%d" % [item.item_name, item.quantity])
	if not equipment.is_empty():
		lines.append("Equipment:")
		# Aggregate identical pieces by name for a compact list.
		var counts := {}
		var order: Array[String] = []
		for eq in equipment:
			if not counts.has(eq.equipment_name):
				counts[eq.equipment_name] = {"count": 0, "rarity": eq.rarity_name()}
				order.append(eq.equipment_name)
			counts[eq.equipment_name]["count"] += 1
		for eq_name in order:
			var c: int = counts[eq_name]["count"]
			var rar: String = counts[eq_name]["rarity"]
			if c > 1:
				lines.append("%s  x%d  (%s)" % [eq_name, c, rar])
			else:
				lines.append("%s  (%s)" % [eq_name, rar])
	if lines.is_empty():
		lines.append("No items dropped")

	rewards_label.text = "\n".join(lines)
	if cinzel: rewards_label.add_theme_font_override("font", cinzel)
	rewards_label.add_theme_font_size_override("font_size", 13)
	rewards_label.add_theme_color_override("font_color", Color(0.78, 0.7, 0.95))
	await get_tree().create_timer(1.0).timeout
	await _animate_gold(cinzel)

func _animate_gold(cinzel):
	var start_gold = GameManager.gold - pending_gold
	var end_gold = GameManager.gold
	# Use the cached `content` ref, not $Content — the node was reparented into
	# the themed card in _apply_theme, so the $Content path no longer resolves.
	var content_vbox = content

	# Add gold label
	var gold_title = Label.new()
	gold_title.text = "Gold"
	if cinzel: gold_title.add_theme_font_override("font", cinzel)
	gold_title.add_theme_font_size_override("font_size", 13)
	gold_title.add_theme_color_override("font_color", Color(0.78, 0.7, 0.95))
	content_vbox.add_child(gold_title)
	content_vbox.move_child(gold_title, rewards_label.get_index())

	# Add gold row with value + increment
	var gold_row = HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 10)
	content_vbox.add_child(gold_row)
	content_vbox.move_child(gold_row, gold_title.get_index() + 1)

	var gold_val = Label.new()
	gold_val.text = str(start_gold)
	if cinzel: gold_val.add_theme_font_override("font", cinzel)
	gold_val.add_theme_font_size_override("font_size", 16)
	gold_val.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	gold_row.add_child(gold_val)

	var gold_inc = Label.new()
	gold_inc.text = "+%d" % pending_gold
	gold_inc.modulate.a = 0.0
	if cinzel: gold_inc.add_theme_font_override("font", cinzel)
	gold_inc.add_theme_font_size_override("font_size", 13)
	gold_inc.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	gold_row.add_child(gold_inc)

	# Short delay then fade in increment
	await get_tree().create_timer(0.6).timeout
	var inc_fade_in = create_tween()
	inc_fade_in.tween_property(gold_inc, "modulate:a", 1.0, 0.3)
	await inc_fade_in.finished

	# Count up
	var tween = create_tween()
	tween.tween_method(
		func(val: float): gold_val.text = str(int(val)),
		float(start_gold), float(end_gold), 1.2
	)
	await tween.finished

	# Fade out increment
	var fade = create_tween()
	fade.tween_property(gold_inc, "modulate:a", 0.0, 0.4)
	await fade.finished
	gold_inc.queue_free()

func _animate_exp():
	var exp_share = int(pending_exp / max(1, party.size()))
	var leveled_heroes: Array[Character] = []

	for hero in party:
		var exp_bar = _find_node_by_name("ExpBar_%s" % hero.character_name)
		var exp_lbl = _find_node_by_name("ExpLabel_%s" % hero.character_name)
		if exp_bar == null:
			continue

		var start_exp = hero.experience
		var target = min(start_exp + exp_share, hero.experience_to_next)
		var duration = 1.2

		var tween = create_tween()
		tween.tween_method(
			func(val: float):
				exp_bar.value = val
				if exp_lbl:
					exp_lbl.text = "%d / %d" % [int(val), hero.experience_to_next],
			float(start_exp), float(target), duration
		)
		await tween.finished

		# Apply EXP and check for level up
		var leveled = hero.gain_experience(exp_share)
		if leveled:
			leveled_heroes.append(hero)

	# Show continue button — level up shown when player presses it
	continue_btn.visible = true
	# Central focus guard keeps controller focus on Continue while shown.
	GameManager.register_focus_scope(self)
	if not leveled_heroes.is_empty() and level_up_screen != null:
		continue_btn.text = "Level Up! (Press to Continue)"
		continue_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		# Store leveled heroes for when button is pressed
		_pending_level_up_heroes = leveled_heroes
	else:
		_pending_level_up_heroes = []

func _on_level_up_complete():
	# Return to victory screen after level ups
	show()
	# Rebuild party list with updated levels and EXP
	_build_party_list()
	# Animate EXP bars from 0 to current value for leveled up heroes
	await get_tree().create_timer(0.3).timeout
	for hero in party:
		var exp_bar = _find_node_by_name("ExpBar_%s" % hero.character_name)
		var exp_lbl = _find_node_by_name("ExpLabel_%s" % hero.character_name)
		if exp_bar == null:
			continue
		# Start from 0 and animate to current EXP
		exp_bar.max_value = hero.experience_to_next
		exp_bar.value = 0
		if exp_lbl:
			exp_lbl.text = "0 / %d" % hero.experience_to_next
		var tween = create_tween()
		tween.tween_method(
			func(val: float):
				exp_bar.value = val
				if exp_lbl:
					exp_lbl.text = "%d / %d" % [int(val), hero.experience_to_next],
			0.0, float(hero.experience), 1.0
		)
	continue_btn.visible = true
	continue_btn.text = "Continue"
	continue_btn.remove_theme_color_override("font_color")
	# Re-register: the scope was unregistered when we left for the level-up screen,
	# so the focus guard needs it back to put controller focus on Continue.
	GameManager.register_focus_scope(self)

func _on_continue():
	GameManager.unregister_focus_scope(self)
	if not _pending_level_up_heroes.is_empty():
		hide()
		level_up_screen.show_level_ups(_pending_level_up_heroes)
		_pending_level_up_heroes = []
	else:
		emit_signal("victory_closed")
		hide()

# Matches the resonance meter styling used by the pause-menu Stats screen
# (StatsScreen._make_meter_row): amethyst fill on a dark, button-bordered track.
func _style_exp_bar(bar: ProgressBar) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.04, 0.09, 0.9)
	bg.set_corner_radius_all(4)
	bg.border_color = BattleUITheme.BUTTON_BORDER
	bg.set_border_width_all(1)
	bar.add_theme_stylebox_override("background", bg)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(0.62, 0.40, 0.95)
	fg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fg)

func _find_node_by_name(node_name: String) -> Node:
	return _search_children(party_list, node_name)

func _search_children(parent: Node, node_name: String) -> Node:
	for child in parent.get_children():
		if child.name == node_name:
			return child
		var found = _search_children(child, node_name)
		if found:
			return found
	return null
