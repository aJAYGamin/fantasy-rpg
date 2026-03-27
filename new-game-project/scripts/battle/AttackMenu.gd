extends Control

## AttackMenu.gd
## Replaces the action menu when Attack or Special is pressed
## Shows 4 moves in a 2x2 grid with name, element, type, and ? description toggle

signal move_selected(skill: Skill, targets: Array)
signal menu_closed

const ATTACK_TYPE_COLORS = {
	"Strike":    Color(0.9, 0.6, 0.2),
	"Magic":     Color(0.6, 0.3, 1.0),
	"Ranged":    Color(0.2, 0.8, 0.5),
	"Status":    Color(0.8, 0.3, 0.5),
	"Resonance": Color(0.85, 0.5, 1.0),
}

var _current_hero: Character = null
var _skills: Array[Skill] = []
var _is_attack_menu: bool = true  # true = attacks, false = specials
var _description_visible: Dictionary = {}  # skill_name -> bool
var _battle_manager: BattleManager = null
var _resonance_system: ResonanceSystem = null

func _ready():
	hide()

func _input(event):
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_BACKSPACE:
		close()

func setup(battle_mgr: BattleManager, res_system: ResonanceSystem):
	_battle_manager = battle_mgr
	_resonance_system = res_system

func show_attacks(hero: Character):
	_current_hero = hero
	_is_attack_menu = true
	# First 4 skills are attacks (index 0-3)
	_skills = []
	for i in range(min(4, hero.skills.size())):
		_skills.append(hero.skills[i])
	_build_menu("— Choose Attack —")
	show()

func show_specials(hero: Character):
	_current_hero = hero
	_is_attack_menu = false
	# Next 4 skills are specials (index 4-7)
	_skills = []
	for i in range(4, min(8, hero.skills.size())):
		_skills.append(hero.skills[i])
	_build_menu("— Choose Special —")
	show()

func close():
	hide()
	emit_signal("menu_closed")

func _build_menu(title: String):
	for child in get_children():
		child.queue_free()
	_description_visible.clear()

	var cinzel = load("res://fonts/Cinzel-Regular.ttf")
	var cinzel_bold = load("res://fonts/Cinzel-Bold.ttf")

	# Dark background
	var bg = ColorRect.new()
	bg.color = Color(0.04, 0.02, 0.10, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Main layout
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# Title row with back button
	var title_row = HBoxContainer.new()
	vbox.add_child(title_row)

	var back_btn = Button.new()
	back_btn.text = "← Back"
	back_btn.custom_minimum_size = Vector2(70, 24)
	if cinzel: back_btn.add_theme_font_override("font", cinzel)
	back_btn.add_theme_font_size_override("font_size", 10)
	back_btn.pressed.connect(close)
	title_row.add_child(back_btn)

	var title_lbl = Label.new()
	title_lbl.text = title
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if cinzel: title_lbl.add_theme_font_override("font", cinzel)
	title_lbl.add_theme_font_size_override("font_size", 11)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 1.0))
	title_row.add_child(title_lbl)

	# 2x2 grid
	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(grid)

	for i in range(4):
		var skill_slot: Control
		if i < _skills.size():
			skill_slot = _create_skill_slot(_skills[i], cinzel, cinzel_bold)
		else:
			skill_slot = _create_empty_slot(cinzel)
		grid.add_child(skill_slot)

func _create_skill_slot(skill: Skill, cinzel, cinzel_bold) -> PanelContainer:
	var slot = PanelContainer.new()
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot.custom_minimum_size = Vector2(0, 36)

	var can_use = skill.can_use(_current_hero)
	if not can_use:
		slot.modulate.a = 0.5

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	slot.add_child(vbox)

	# Row 1: name + ? button
	var top_row = HBoxContainer.new()
	vbox.add_child(top_row)

	var skill_btn = Button.new()
	skill_btn.text = skill.skill_name
	skill_btn.flat = true
	skill_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if cinzel_bold: skill_btn.add_theme_font_override("font", cinzel_bold)
	skill_btn.add_theme_font_size_override("font_size", 11)
	skill_btn.add_theme_color_override("font_color", Color(0.95, 0.88, 1.0))
	skill_btn.disabled = not can_use
	top_row.add_child(skill_btn)

	var desc_btn = Button.new()
	desc_btn.text = "?"
	desc_btn.custom_minimum_size = Vector2(18, 18)
	desc_btn.flat = true
	if cinzel: desc_btn.add_theme_font_override("font", cinzel)
	desc_btn.add_theme_font_size_override("font_size", 10)
	desc_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
	top_row.add_child(desc_btn)

	# Row 2: use GridContainer with 3 equal columns so all slots align perfectly
	var info_grid = GridContainer.new()
	info_grid.columns = 3
	info_grid.add_theme_constant_override("h_separation", 0)
	info_grid.add_theme_constant_override("v_separation", 0)
	vbox.add_child(info_grid)

	# Column 1: Element
	var elem_name = ElementalSystem.get_element_name(skill.element)
	var elem_lbl = Label.new()
	elem_lbl.text = elem_name if elem_name != "None" else "—"
	elem_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	elem_lbl.clip_text = true
	if cinzel: elem_lbl.add_theme_font_override("font", cinzel)
	elem_lbl.add_theme_font_size_override("font_size", 9)
	elem_lbl.add_theme_color_override("font_color", ElementalSystem.get_element_color(skill.element))
	info_grid.add_child(elem_lbl)

	# Column 2: Attack type
	var attack_type = _get_attack_type(skill)
	var type_lbl = Label.new()
	type_lbl.text = attack_type
	type_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if cinzel: type_lbl.add_theme_font_override("font", cinzel)
	type_lbl.add_theme_font_size_override("font_size", 9)
	type_lbl.add_theme_color_override("font_color", ATTACK_TYPE_COLORS.get(attack_type, Color(0.7, 0.7, 0.7)))
	info_grid.add_child(type_lbl)

	# Column 3: MP cost
	var mp_lbl = Label.new()
	mp_lbl.text = "%d MP" % skill.mp_cost if skill.mp_cost > 0 else ""
	mp_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if cinzel: mp_lbl.add_theme_font_override("font", cinzel)
	mp_lbl.add_theme_font_size_override("font_size", 9)
	mp_lbl.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
	info_grid.add_child(mp_lbl)

	# Connect ? button — shows description above the menu via parent
	desc_btn.pressed.connect(func():
		_show_description_above(skill)
	)

	# Connect skill button
	skill_btn.pressed.connect(func():
		if not can_use:
			return
		_on_skill_selected(skill)
	)

	return slot

func _show_description_above(skill: Skill):
	# Find or create description panel above the menu
	var desc_panel = get_node_or_null("DescriptionPanel")
	if desc_panel == null:
		desc_panel = PanelContainer.new()
		desc_panel.name = "DescriptionPanel"
		desc_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
		# Position above the menu
		desc_panel.position = Vector2(0, -70)
		desc_panel.custom_minimum_size = Vector2(0, 60)
		var cinzel = load("res://fonts/Cinzel-Regular.ttf")
		var lbl = Label.new()
		lbl.name = "DescLabel"
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if cinzel: lbl.add_theme_font_override("font", cinzel)
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(0.88, 0.82, 1.0))
		desc_panel.add_child(lbl)
		add_child(desc_panel)

	var lbl = desc_panel.get_node("DescLabel")
	var new_text = "%s — %s" % [skill.skill_name, skill.description if skill.description != "" else "No description."]
	# Toggle off if same skill clicked again
	if desc_panel.visible and lbl.text == new_text:
		desc_panel.visible = false
	else:
		lbl.text = new_text
		desc_panel.visible = true

func _create_empty_slot(cinzel) -> PanelContainer:
	var slot = PanelContainer.new()
	slot.custom_minimum_size = Vector2(0, 36)
	slot.modulate.a = 0.3
	var lbl = Label.new()
	lbl.text = "—"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if cinzel: lbl.add_theme_font_override("font", cinzel)
	slot.add_child(lbl)
	return slot

func _on_skill_selected(skill: Skill):
	var alive_enemies = _battle_manager.get_alive_enemies()
	var alive_party = _battle_manager.get_alive_party()

	match skill.target_type:
		Skill.TargetType.SINGLE_ENEMY:
			if alive_enemies.size() == 1:
				var t: Array = [alive_enemies[0]]
				emit_signal("move_selected", skill, t)
				close()
			else:
				var t: Array = []
				emit_signal("move_selected", skill, t)
				close()
		Skill.TargetType.ALL_ENEMIES:
			var t: Array = []
			for e in alive_enemies: t.append(e)
			emit_signal("move_selected", skill, t)
			close()
		Skill.TargetType.SINGLE_ALLY:
			var t: Array = [alive_party[0]]
			emit_signal("move_selected", skill, t)
			close()
		Skill.TargetType.ALL_ALLIES:
			var t: Array = []
			for a in alive_party: t.append(a)
			emit_signal("move_selected", skill, t)
			close()
		Skill.TargetType.SELF:
			var t: Array = [_current_hero]
			emit_signal("move_selected", skill, t)
			close()

func _get_attack_type(skill: Skill) -> String:
	match skill.skill_type:
		Skill.SkillType.PHYSICAL: return "Strike"
		Skill.SkillType.MAGIC:    return "Magic"
		Skill.SkillType.HEAL:     return "Magic"
		Skill.SkillType.BUFF:     return "Status"
		Skill.SkillType.DEBUFF:   return "Status"
	return "Strike"
