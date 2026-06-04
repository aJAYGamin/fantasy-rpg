class_name StatsScreen
extends Control

## StatsScreen — Phase P1.
## Per-hero info page opened from the pause menu (overworld). Shows portrait
## placeholder, bio, level/XP, HP/MP, the five battle stats, element affinity,
## the resonance meter, every learned attack/special with descriptions, and the
## hero's solo resonance (ultimate).
##
## Built entirely in code and themed with BattleUITheme + HeroPalette. Opened by
## PauseMenu as a "replace-don't-stack" sub-view: PauseMenu hides its main
## content, adds this as a child, and listens for `back_requested` (fired by the
## Back button) — Esc to back out is owned by PauseMenu. Left/Right cycle heroes.
##
## The display data is produced by the pure static build_hero_view_model() so it
## can be unit-tested without instantiating the scene tree.

signal back_requested

# stat label -> view-model key, in display order.
const STAT_ROWS := [
	["ATK", "attack"],
	["DEF", "defense"],
	["MAG", "magic"],
	["ARC", "arcane"],
	["SPD", "speed"],
]

var _party: Array = []
var _selected: int = 0
var _tab_buttons: Array[Button] = []
var _content_host: Control = null

# --- View model (pure, testable) ---------------------------------------------

# Builds the full display dictionary for a single character. Pure function — no
# scene-tree access — so tests can assert on it directly.
static func build_hero_view_model(c: Character) -> Dictionary:
	var attacks: Array = []
	var specials: Array = []
	for i in range(c.skills.size()):
		var vm := _skill_view_model(c.skills[i])
		# Hero skill convention: indices 0-3 are attacks, 4+ are specials.
		if i < 4:
			attacks.append(vm)
		else:
			specials.append(vm)

	var ult_name := "Ultimate"
	if c.has_meta("ultimate_name"):
		ult_name = str(c.get_meta("ultimate_name"))
	var ult_desc := "%s unleashes their ultimate power!" % c.character_name
	if c.has_meta("ultimate_desc"):
		ult_desc = str(c.get_meta("ultimate_desc"))
	var bio := ""
	if c.has_meta("bio"):
		bio = str(c.get_meta("bio"))

	return {
		"name": c.character_name,
		"class": c.character_class,
		"level": c.level,
		"experience": c.experience,
		"experience_to_next": c.experience_to_next,
		"exp_text": "%d / %d" % [c.experience, c.experience_to_next],
		"total_experience": c.total_experience_earned(),
		"current_hp": c.current_hp,
		"max_hp": c.max_hp(),
		"hp_text": "%d / %d" % [c.current_hp, c.max_hp()],
		"current_mp": c.current_mp,
		"max_mp": c.max_mp(),
		"mp_text": "%d / %d" % [c.current_mp, c.max_mp()],
		# Core stats are final TOTALS (base + level growth + equipment); the
		# getters already fold in equipment_bonus. The status screen shows just
		# the total — the per-piece breakdown lives on the Equipment screen.
		"attack": c.attack_power(),
		"defense": c.defense_power(),
		"magic": c.magic_power(),
		"arcane": c.arcane_power(),
		"speed": c.speed(),
		"element": c.element,
		"element_name": ElementalSystem.get_element_name(c.element),
		"secondary_element": c.secondary_element,
		"secondary_element_name": ElementalSystem.get_element_name(c.secondary_element),
		"extra_weakness": c.extra_weakness,
		"extra_resistance": c.extra_resistance,
		"resonance_meter": c.resonance_meter,
		"resonance_name": ult_name,
		"resonance_desc": ult_desc,
		"bio": bio,
		"attacks": attacks,
		"specials": specials,
	}

static func _skill_view_model(s: Skill) -> Dictionary:
	return {
		"name": s.skill_name,
		"description": s.description,
		"type_display": s.get_skill_type_display(),
		"element": s.element,
		"element_name": ElementalSystem.get_element_name(s.element),
		"element_icon": ElementalSystem.get_element_icon(s.element),
		"secondary_element": s.secondary_element,
		"mp_cost": s.mp_cost,
		"target": s.get_target_description(),
	}

# --- Lifecycle ----------------------------------------------------------------

func _ready() -> void:
	# Process while the tree is paused so input/animations work inside the
	# (paused) overworld pause menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)

func setup(party: Array, start_index: int = 0) -> void:
	_party = party
	_selected = clampi(start_index, 0, max(0, _party.size() - 1))
	_build_chrome()
	_select(_selected)
	# The central focus guard keeps controller focus inside this screen; hero tabs
	# are tagged no-focus (cycled with L1/R1) so the controller skips them.
	for tb in _tab_buttons:
		BattleUITheme.mark_no_focus(tb)
	GameManager.register_focus_scope(self)

func _exit_tree() -> void:
	GameManager.unregister_focus_scope(self)

func _input(event: InputEvent) -> void:
	if not visible or _party.size() <= 1:
		return
	# L1 / R1 cycle heroes (the category for this screen).
	if FocusUtil.is_prev_category(event):
		_select((_selected - 1 + _party.size()) % _party.size())
		get_viewport().set_input_as_handled()
	elif FocusUtil.is_next_category(event):
		_select((_selected + 1) % _party.size())
		get_viewport().set_input_as_handled()

# --- Chrome (built once) ------------------------------------------------------

func _build_chrome() -> void:
	for c in get_children():
		c.queue_free()
	_tab_buttons.clear()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# Panel covers the entire screen. This reuses the proven CenterContainer +
	# explicitly-sized PanelContainer structure (a bare full-rect PanelContainer
	# collapses to its content — see CLAUDE.md). In this project's canvas_items
	# stretch mode the UI space is always the base resolution, so sizing to it
	# exactly fills the screen at any window size.
	const BASE_W := 1152.0
	const BASE_H := 648.0
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := BattleUITheme.make_panel()
	panel.custom_minimum_size = Vector2(BASE_W, BASE_H)
	# Square corners (full-screen rectangle, no rounding) + compact margins so all
	# sections fit on screen without scrolling.
	var pstyle := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if pstyle:
		pstyle.set_corner_radius_all(0)
		pstyle.content_margin_left = 22
		pstyle.content_margin_right = 22
		pstyle.content_margin_top = 12
		pstyle.content_margin_bottom = 12
	center.add_child(panel)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 8)
	panel.add_child(root_v)

	# Header: title + Back button.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root_v.add_child(header)

	var title := _label("✦  Character  ✦", BattleUITheme.font_bold(), 20, BattleUITheme.TEXT_ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var back_btn := BattleUITheme.make_button("← Back", 12)
	back_btn.custom_minimum_size = Vector2(90, 30)
	back_btn.pressed.connect(func(): back_requested.emit())
	header.add_child(back_btn)

	# Hero tabs.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	root_v.add_child(tabs)
	for i in range(_party.size()):
		var hero: Character = _party[i]
		var tab := _make_tab(hero.character_name, i)
		_tab_buttons.append(tab)
		tabs.add_child(tab)

	root_v.add_child(_divider())

	# Scrollable content area — rebuilt per selected hero. Fills the rest of the
	# panel vertically so the screen uses the full window height.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_v.add_child(scroll)

	# Reserve a right gutter so the vertical scrollbar never crowds the
	# right-aligned stat numbers.
	var scroll_margin := MarginContainer.new()
	scroll_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_margin.add_theme_constant_override("margin_right", 16)
	scroll.add_child(scroll_margin)

	_content_host = VBoxContainer.new()
	_content_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_margin.add_child(_content_host)

# --- Selection ----------------------------------------------------------------

func _select(index: int) -> void:
	if _party.is_empty():
		return
	_selected = clampi(index, 0, _party.size() - 1)
	for i in range(_tab_buttons.size()):
		_style_tab(_tab_buttons[i], _party[i].character_name, i == _selected)
	_build_content(_party[_selected])

func _build_content(hero: Character) -> void:
	if _content_host == null:
		return
	for c in _content_host.get_children():
		c.queue_free()

	var vm := build_hero_view_model(hero)
	var palette := HeroPalette.for_hero(hero.character_name)

	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	_content_host.add_child(columns)

	# Three columns so the wide screen stays filled: identity/XP/affinity/resonance
	# on the left, bio stacked on top of the vertical core stats in the middle, and
	# the skill cards on the right.
	columns.add_child(_build_left_column(vm, palette))
	columns.add_child(_build_middle_column(vm, palette))
	columns.add_child(_build_right_column(vm, palette))

func _build_left_column(vm: Dictionary, palette: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(270, 0)
	col.add_theme_constant_override("separation", 10)

	# Portrait placeholder (hero-accent letter tile).
	var portrait_wrap := CenterContainer.new()
	col.add_child(portrait_wrap)
	portrait_wrap.add_child(_make_portrait(vm["name"], palette))

	# Name + Lv / class.
	var name_lbl := _label(vm["name"], BattleUITheme.font_bold(), 24, palette["accent"], HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(name_lbl)
	var sub_lbl := _label("Lv %d  ·  %s" % [vm["level"], vm["class"]], BattleUITheme.font_regular(), 13, palette["subtitle"], HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(sub_lbl)

	# XP bar + lifetime XP earned (under the bar).
	col.add_child(_make_meter_row("XP", vm["experience"], vm["experience_to_next"], Color(0.85, 0.78, 0.45), vm["exp_text"]))
	var total_xp := _label("Total XP earned:  %d" % int(vm["total_experience"]), BattleUITheme.font_regular(), 11, BattleUITheme.TEXT_SUBTITLE, HORIZONTAL_ALIGNMENT_RIGHT)
	total_xp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(total_xp)

	col.add_child(_divider())

	# Element affinity.
	col.add_child(_section_header("Affinity"))
	col.add_child(_make_affinity_block(vm))

	col.add_child(_divider())

	# Resonance.
	col.add_child(_section_header("Resonance"))
	col.add_child(_make_meter_row("", vm["resonance_meter"], 100.0, Color(0.62, 0.40, 0.95), "%d%%" % int(round(vm["resonance_meter"]))))
	var res_name := _label("✦ %s" % vm["resonance_name"], BattleUITheme.font_bold(), 14, palette["accent"])
	col.add_child(res_name)
	var res_desc := _label(vm["resonance_desc"], BattleUITheme.font_regular(), 11, BattleUITheme.TEXT_SUBTITLE)
	res_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	res_desc.custom_minimum_size = Vector2(254, 0)
	col.add_child(res_desc)

	return col

# Middle column: each hero's biography sits directly on top of their core stats,
# which are listed vertically (one stat per row) rather than side-by-side.
func _build_middle_column(vm: Dictionary, _palette: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(240, 0)
	col.add_theme_constant_override("separation", 8)

	if str(vm["bio"]) != "":
		col.add_child(_section_header("Bio"))
		var bio_lbl := _label(vm["bio"], BattleUITheme.font_regular(), 11, BattleUITheme.TEXT_PRIMARY)
		bio_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bio_lbl.custom_minimum_size = Vector2(224, 0)
		col.add_child(bio_lbl)
		col.add_child(_divider())

	col.add_child(_section_header("Core Stats"))
	var stats_col := VBoxContainer.new()
	stats_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_col.add_theme_constant_override("separation", 4)
	stats_col.add_child(_make_stat_row("HP", vm["hp_text"], Color(0.55, 0.95, 0.55)))
	stats_col.add_child(_make_stat_row("MP", vm["mp_text"], Color(0.50, 0.70, 1.0)))
	for pair in STAT_ROWS:
		stats_col.add_child(_make_stat_row(pair[0], str(vm[pair[1]]), BattleUITheme.TEXT_PRIMARY))
	col.add_child(stats_col)

	return col

func _build_right_column(vm: Dictionary, _palette: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)

	# Attacks / Specials — two cards per row to fill the horizontal space.
	col.add_child(_section_header("Attacks"))
	col.add_child(_build_skill_grid(vm["attacks"]))
	col.add_child(_section_header("Specials"))
	col.add_child(_build_skill_grid(vm["specials"]))

	return col

# Lays skill cards out two-per-row. Returns a "None learned." label when empty.
func _build_skill_grid(skills: Array) -> Control:
	if skills.is_empty():
		return _label("None learned.", BattleUITheme.font_regular(), 11, BattleUITheme.TEXT_SUBTITLE)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	for s in skills:
		grid.add_child(_make_skill_card(s))
	return grid

# --- Builders -----------------------------------------------------------------

func _make_portrait(hero_name: String, palette: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(130, 130)
	var style := BattleUITheme.panel_style(palette["accent"], palette["panel_bg"], 2, 12)
	p.add_theme_stylebox_override("panel", style)
	var letter := Label.new()
	letter.text = hero_name.substr(0, 1) if hero_name != "" else "?"
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var f := BattleUITheme.font_bold()
	if f: letter.add_theme_font_override("font", f)
	letter.add_theme_font_size_override("font_size", 64)
	letter.add_theme_color_override("font_color", palette["accent"])
	p.add_child(letter)
	return p

func _make_affinity_block(vm: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)

	var primary := HBoxContainer.new()
	primary.add_theme_constant_override("separation", 6)
	primary.add_child(_element_chip(vm["element"]))
	if vm["secondary_element"] != ElementalSystem.Element.NORMAL \
			and vm["secondary_element"] != vm["element"]:
		primary.add_child(_element_chip(vm["secondary_element"]))
	v.add_child(primary)

	if vm["extra_weakness"] != ElementalSystem.Element.NORMAL:
		v.add_child(_label("Weak to %s %s" % [
			ElementalSystem.get_element_icon(vm["extra_weakness"]),
			ElementalSystem.get_element_name(vm["extra_weakness"]),
		], BattleUITheme.font_regular(), 11, Color(1.0, 0.55, 0.45)))
	if vm["extra_resistance"] != ElementalSystem.Element.NORMAL:
		v.add_child(_label("Resists %s %s" % [
			ElementalSystem.get_element_icon(vm["extra_resistance"]),
			ElementalSystem.get_element_name(vm["extra_resistance"]),
		], BattleUITheme.font_regular(), 11, Color(0.55, 0.85, 0.55)))
	return v

func _element_chip(element: int) -> Control:
	var color := ElementalSystem.get_element_color(element)
	var chip := PanelContainer.new()
	var style := BattleUITheme.panel_style(color, color.lerp(Color(0.04, 0.03, 0.07), 0.82), 1, 8)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", style)
	var lbl := _label("%s %s" % [
		ElementalSystem.get_element_icon(element),
		ElementalSystem.get_element_name(element),
	], BattleUITheme.font_bold(), 12, color.lerp(Color.WHITE, 0.3))
	chip.add_child(lbl)
	return chip

func _make_stat_row(stat: String, value_text: String, value_color: Color) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	var name_lbl := _label(stat, BattleUITheme.font_regular(), 13, BattleUITheme.TEXT_SUBTITLE)
	name_lbl.custom_minimum_size = Vector2(46, 0)
	row.add_child(name_lbl)
	var val_lbl := _label(value_text, BattleUITheme.font_bold(), 14, value_color, HORIZONTAL_ALIGNMENT_RIGHT)
	val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(val_lbl)
	return row

# A labeled progress meter: "<label>  <value_text>" with a themed fill bar.
func _make_meter_row(label: String, value: float, max_value: float, fill: Color, value_text: String) -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)

	var caption := HBoxContainer.new()
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if label != "":
		var l := _label(label, BattleUITheme.font_regular(), 11, BattleUITheme.TEXT_SUBTITLE)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.add_child(l)
	var val := _label(value_text, BattleUITheme.font_bold(), 11, BattleUITheme.TEXT_PRIMARY, HORIZONTAL_ALIGNMENT_RIGHT)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.add_child(val)
	v.add_child(caption)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = max(1.0, max_value)
	bar.value = clampf(value, 0.0, bar.max_value)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.04, 0.09, 0.9)
	bg.set_corner_radius_all(4)
	bg.border_color = BattleUITheme.BUTTON_BORDER
	bg.set_border_width_all(1)
	bar.add_theme_stylebox_override("background", bg)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fg)
	v.add_child(bar)
	return v

func _make_skill_card(s: Dictionary) -> Control:
	var elem_color := ElementalSystem.get_element_color(s["element"])
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(236, 0)
	var style := BattleUITheme.panel_style(BattleUITheme.BUTTON_BORDER, BattleUITheme.SUBPANEL_BG, 1, 8)
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	style.content_margin_left = 10
	style.content_margin_right = 10
	card.add_theme_stylebox_override("panel", style)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)

	var top := HBoxContainer.new()
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_theme_constant_override("separation", 6)
	var name_lbl := _label(s["name"], BattleUITheme.font_bold(), 13, elem_color.lerp(Color.WHITE, 0.25))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_lbl)
	if int(s["mp_cost"]) > 0:
		top.add_child(_label("MP %d" % int(s["mp_cost"]), BattleUITheme.font_bold(), 12, Color(0.50, 0.70, 1.0), HORIZONTAL_ALIGNMENT_RIGHT))
	v.add_child(top)

	var meta_parts: Array = [s["type_display"]]
	# Always surface the element — Normal-typed moves show "◇ Normal" too.
	meta_parts.append("%s %s" % [s["element_icon"], s["element_name"]])
	meta_parts.append(s["target"])
	var meta_lbl := _label("  ·  ".join(meta_parts), BattleUITheme.font_regular(), 10, BattleUITheme.TEXT_SUBTITLE)
	v.add_child(meta_lbl)

	if str(s["description"]) != "":
		var desc := _label(s["description"], BattleUITheme.font_regular(), 11, BattleUITheme.TEXT_PRIMARY)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# No fixed min width — wrap to whatever width the grid cell gives the card.
		desc.custom_minimum_size = Vector2(0, 0)
		v.add_child(desc)
	return card

func _make_tab(hero_name: String, index: int) -> Button:
	var b := Button.new()
	b.text = hero_name
	b.custom_minimum_size = Vector2(110, 32)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func(): _select(index))
	_style_tab(b, hero_name, false)
	return b

func _style_tab(b: Button, hero_name: String, active: bool) -> void:
	var palette := HeroPalette.for_hero(hero_name)
	var f := BattleUITheme.font_bold()
	if f: b.add_theme_font_override("font", f)
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", palette["accent"] if active else palette["subtitle"])
	b.add_theme_color_override("font_hover_color", palette["accent"].lerp(Color.WHITE, 0.3))
	b.add_theme_color_override("font_pressed_color", palette["accent"])

	var normal := StyleBoxFlat.new()
	normal.bg_color = palette["accent"].lerp(Color(0.04, 0.03, 0.07), 0.55 if active else 0.86)
	normal.border_color = palette["accent"] if active else palette["border"]
	normal.set_border_width_all(2 if active else 1)
	# Active tab "lifts" into the content by dropping its bottom border.
	normal.border_width_bottom = 0 if active else 1
	normal.set_corner_radius_all(6)
	normal.corner_radius_bottom_left = 0
	normal.corner_radius_bottom_right = 0
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5
	b.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = palette["accent"].lerp(Color(0.04, 0.03, 0.07), 0.5)
	hover.border_color = palette["accent"]
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)

func _section_header(text: String) -> Label:
	var l := _label(text.to_upper(), BattleUITheme.font_bold(), 12, BattleUITheme.TEXT_SUBTITLE)
	return l

func _divider() -> Control:
	var line := ColorRect.new()
	line.color = Color(0.40, 0.30, 0.55, 0.6)
	line.custom_minimum_size = Vector2(0, 1)
	return line

func _label(text: String, font: Font, size: int, color: Color, h_align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = h_align
	if font: l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
