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

	# Themed background — uses Panel (NOT PanelContainer) so the bg doesn't
	# auto-shrink to its content. PanelContainer is a Container that collapses
	# to its child's combined_minimum_size, which can make the menu render
	# smaller than the action menu it replaces. Panel's size is purely
	# anchor-driven, so PRESET_FULL_RECT reliably fills the menu rect.
	var bg := Panel.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", BattleUITheme.panel_style())
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Content layer — MarginContainer provides the panel's inner padding,
	# anchored FULL_RECT to self so it fills the menu independently of the bg.
	var content := MarginContainer.new()
	content.add_theme_constant_override("margin_left", 8)
	content.add_theme_constant_override("margin_right", 8)
	content.add_theme_constant_override("margin_top", 6)
	content.add_theme_constant_override("margin_bottom", 6)
	add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Main layout inside the margin container.
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	content.add_child(vbox)

	# Title row with themed back button + centered title.
	var title_row = HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(title_row)

	var title_lbl = Label.new()
	title_lbl.text = title
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if cinzel_bold: title_lbl.add_theme_font_override("font", cinzel_bold)
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", BattleUITheme.TEXT_SUBTITLE)
	title_row.add_child(title_lbl)

	var back_btn := BattleUITheme.make_button("← Back", 10)
	back_btn.custom_minimum_size = Vector2(58, 22)
	back_btn.pressed.connect(close)
	title_row.add_child(back_btn)

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
	slot.custom_minimum_size = Vector2(0, 38)

	var can_use = skill.can_use(_current_hero)
	if not can_use:
		slot.modulate.a = 0.5

	# Themed inner panel — element-tinted border so skills are scannable by
	# element at a glance, on the shared dark plum bg.
	var slot_border := ElementalSystem.get_element_color(skill.element).lerp(BattleUITheme.PANEL_BORDER, 0.5)
	var slot_style := BattleUITheme.panel_style(slot_border, BattleUITheme.SUBPANEL_BG, 1, 6)
	slot_style.content_margin_left = 6
	slot_style.content_margin_right = 6
	slot_style.content_margin_top = 4
	slot_style.content_margin_bottom = 4
	slot.add_theme_stylebox_override("panel", slot_style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	slot.add_child(vbox)

	# Row 1: name + ? button
	var top_row = HBoxContainer.new()
	vbox.add_child(top_row)

	# Skill name as a themed button with fully flat normal/hover/pressed so it
	# doesn't draw an inner border inside the slot's panel. The slot itself
	# (with its element-tinted border) is the visible "box"; hover/press just
	# paint a subtle wash so the row still feels interactive.
	var skill_btn := BattleUITheme.make_button(skill.skill_name, 11)
	skill_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var flat_normal := StyleBoxFlat.new()
	flat_normal.bg_color = Color(0, 0, 0, 0)
	flat_normal.content_margin_left = 4
	flat_normal.content_margin_right = 4
	flat_normal.content_margin_top = 2
	flat_normal.content_margin_bottom = 2
	skill_btn.add_theme_stylebox_override("normal", flat_normal)
	# Clearly visible hover wash — alpha 0.18 reads on the dark plum slot bg
	# without drawing a competing border (slot panel is the visible outline).
	var flat_hover := flat_normal.duplicate()
	flat_hover.bg_color = Color(1.0, 0.95, 1.0, 0.18)
	flat_hover.set_corner_radius_all(5)
	skill_btn.add_theme_stylebox_override("hover", flat_hover)
	var flat_pressed := flat_normal.duplicate()
	flat_pressed.bg_color = Color(1.0, 0.95, 1.0, 0.30)
	flat_pressed.set_corner_radius_all(5)
	skill_btn.add_theme_stylebox_override("pressed", flat_pressed)
	var flat_disabled := flat_normal.duplicate()
	flat_disabled.bg_color = Color(0, 0, 0, 0)
	skill_btn.add_theme_stylebox_override("disabled", flat_disabled)
	skill_btn.disabled = not can_use
	top_row.add_child(skill_btn)

	var desc_btn := BattleUITheme.make_button("?", 10)
	desc_btn.custom_minimum_size = Vector2(22, 20)
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
	elem_lbl.text = elem_name
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
		desc_panel.position = Vector2(0, -70)
		desc_panel.custom_minimum_size = Vector2(0, 60)
		# Themed description panel — matches the resonance menu's description popup.
		var desc_style := BattleUITheme.panel_style()
		desc_style.content_margin_left = 10
		desc_style.content_margin_right = 10
		desc_style.content_margin_top = 6
		desc_style.content_margin_bottom = 6
		desc_panel.add_theme_stylebox_override("panel", desc_style)
		var cinzel = load("res://fonts/Cinzel-Regular.ttf")
		var lbl = Label.new()
		lbl.name = "DescLabel"
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if cinzel: lbl.add_theme_font_override("font", cinzel)
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", BattleUITheme.TEXT_PRIMARY)
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
	slot.custom_minimum_size = Vector2(0, 38)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Faint placeholder slot — same shape as real slots but dimmer.
	var empty_style := BattleUITheme.panel_style(BattleUITheme.BUTTON_BORDER, BattleUITheme.SUBPANEL_BG, 1, 6)
	empty_style.bg_color.a = 0.45
	empty_style.border_color.a = 0.35
	slot.add_theme_stylebox_override("panel", empty_style)
	slot.modulate.a = 0.5
	var lbl = Label.new()
	lbl.text = "—"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", BattleUITheme.TEXT_SUBTITLE)
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
	return skill.get_skill_type_display()
