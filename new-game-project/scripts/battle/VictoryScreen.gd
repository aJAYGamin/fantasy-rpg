extends Control

## VictoryScreen.gd
## Attach to a Control node inside BattleUI/UIRoot
## Set Anchor Preset to Full Rect, initially hidden

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
var level_up_queue: Array[Character] = []

func _ready():
	hide()
	continue_btn.pressed.connect(_on_continue)

func show_victory(battle_rewards: Dictionary, battle_party: Array[Character], res_system: ResonanceSystem):
	rewards = battle_rewards
	party = battle_party
	resonance_system = res_system
	pending_exp = rewards.get("exp", 0)
	pending_gold = rewards.get("gold", 0)

	# Small delay before showing
	await get_tree().create_timer(1.2).timeout
	show()

	# Fade in overlay
	overlay.modulate.a = 0.0
	content.modulate.a = 0.0
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(overlay, "modulate:a", 1.0, 0.5)
	tween.tween_property(content, "modulate:a", 1.0, 0.8)
	await tween.finished

	# Build party entries
	_build_party_list()

	# Show gold and items
	_build_rewards_label()

	# Wait then animate EXP
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

		# Hero name + level
		var name_lbl = Label.new()
		name_lbl.text = "%s  Lv%d" % [hero.character_name, hero.level]
		name_lbl.custom_minimum_size = Vector2(160, 0)
		if cinzel: name_lbl.add_theme_font_override("font", cinzel)
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color(0.88, 0.78, 1.0))
		row.add_child(name_lbl)

		# EXP bar background
		var exp_bar_bg = PanelContainer.new()
		exp_bar_bg.custom_minimum_size = Vector2(160, 14)
		exp_bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(exp_bar_bg)

		var exp_bar = ProgressBar.new()
		exp_bar.name = "ExpBar_%s" % hero.character_name
		exp_bar.max_value = hero.experience_to_next
		exp_bar.value = hero.experience
		exp_bar.show_percentage = false
		exp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		exp_bar_bg.add_child(exp_bar)

		# EXP label
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
	var text = "Gold:  %d" % pending_gold
	var items = rewards.get("items", [])
	if not items.is_empty():
		text += "\n\nItems:"
		for item in items:
			text += "\n  %s" % item.item_name
	rewards_label.text = text
	if cinzel: rewards_label.add_theme_font_override("font", cinzel)

func _animate_exp():
	var exp_share = int(pending_exp / max(1, party.size()))

	for hero in party:
		var exp_bar = _find_node_by_name("ExpBar_%s" % hero.character_name)
		var exp_lbl = _find_node_by_name("ExpLabel_%s" % hero.character_name)
		if exp_bar == null:
			continue

		var start_exp = hero.experience
		var end_exp = start_exp + exp_share
		var duration = 1.2

		var tween = create_tween()
		tween.tween_method(
			func(val: float):
				exp_bar.value = val
				if exp_lbl:
					exp_lbl.text = "%d / %d" % [int(val), hero.experience_to_next],
			float(start_exp), float(min(end_exp, hero.experience_to_next)), duration
		)
		await tween.finished

		# Check for level up
		var leveled = hero.gain_experience(exp_share)
		if leveled:
			level_up_queue.append(hero)

	# Show level up screens if any
	for hero in level_up_queue:
		await _show_level_up(hero)

func _show_level_up(hero: Character):
	var cinzel = load("res://fonts/Cinzel-Regular.ttf")
	var popup = PanelContainer.new()
	popup.custom_minimum_size = Vector2(300, 120)
	add_child(popup)

	# Center it
	popup.set_anchors_preset(Control.PRESET_CENTER)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	popup.add_child(vbox)

	var lbl1 = Label.new()
	lbl1.text = hero.character_name
	lbl1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if cinzel: lbl1.add_theme_font_override("font", cinzel)
	lbl1.add_theme_font_size_override("font_size", 16)
	lbl1.add_theme_color_override("font_color", Color(0.88, 0.78, 1.0))
	vbox.add_child(lbl1)

	var lbl2 = Label.new()
	lbl2.text = "Level Up!  Lv %d" % hero.level
	lbl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if cinzel: lbl2.add_theme_font_override("font", cinzel)
	lbl2.add_theme_font_size_override("font_size", 20)
	lbl2.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	vbox.add_child(lbl2)

	# Animate popup in then out
	popup.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(popup, "modulate:a", 1.0, 0.3)
	await get_tree().create_timer(1.8).timeout
	tween = create_tween()
	tween.tween_property(popup, "modulate:a", 0.0, 0.3)
	await tween.finished
	popup.queue_free()

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

func _on_continue():
	emit_signal("victory_closed")
	hide()
