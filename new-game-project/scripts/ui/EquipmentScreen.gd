class_name EquipmentScreen
extends Control

## EquipmentScreen — Phase P3.
## Per-hero equipment page opened from the pause menu (overworld). Three columns:
##   • Left:   portrait, name/Lv/class, affinity, and the live core stats with the
##             equipment contribution shown as a delta (e.g. ATK 18  +5).
##   • Middle: the five equip slots (1 Weapon, 1 Armor, 3 Accessory). Each slot is
##             a button that selects it; equipped slots show the piece + an Unequip
##             button.
##   • Right:  the shared unequipped pool filtered to the selected slot's type.
##             Pieces the hero can't use (class/element restriction) are greyed and
##             their Equip button disabled. Click Equip to put a piece on the hero.
##
## Equipped slots live per-hero on hero.inventory; the unequipped pool is shared on
## party[0].inventory.equipment (see Inventory). All moves go through the static
## Inventory.equip_from_pool / unequip_to_pool, which clamp the hero's vitals after
## a max-HP/MP change.
##
## Built in code and themed with BattleUITheme + HeroPalette, mirroring StatsScreen
## chrome. Opened by PauseMenu as a replace-don't-stack sub-view; Back / Esc return
## to the pause menu. ←/→ cycle heroes.

signal back_requested

# slot label, Equipment.Slot, accessory index (ignored for Weapon/Armor).
const SLOT_DEFS := [
	["Weapon", Equipment.Slot.WEAPON, 0],
	["Armor", Equipment.Slot.ARMOR, 0],
	["Accessory 1", Equipment.Slot.ACCESSORY, 0],
	["Accessory 2", Equipment.Slot.ACCESSORY, 1],
	["Accessory 3", Equipment.Slot.ACCESSORY, 2],
]

var _party: Array = []
var _selected: int = 0
var _selected_slot_def: int = 0
var _tab_buttons: Array[Button] = []
var _content_host: Control = null

# --- Pure helper (testable) ---------------------------------------------------

# Pieces in `pool` whose slot type matches `slot_type`. No scene-tree access.
static func pool_for_slot(pool: Inventory, slot_type: int) -> Array[Equipment]:
	var out: Array[Equipment] = []
	if pool == null:
		return out
	for eq in pool.equipment:
		if eq.slot == slot_type:
			out.append(eq)
	return out

# --- Lifecycle ----------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)

func setup(party: Array, start_index: int = 0) -> void:
	_party = party
	_selected = clampi(start_index, 0, max(0, _party.size() - 1))
	_build_chrome()
	_select(_selected)

func _input(event: InputEvent) -> void:
	if not visible or _party.size() <= 1:
		return
	if event.is_action_pressed("ui_left"):
		_select((_selected - 1 + _party.size()) % _party.size())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_select((_selected + 1) % _party.size())
		get_viewport().set_input_as_handled()

func _pool() -> Inventory:
	return _party[0].inventory if not _party.is_empty() else null

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

	const BASE_W := 1152.0
	const BASE_H := 648.0
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := BattleUITheme.make_panel()
	panel.custom_minimum_size = Vector2(BASE_W, BASE_H)
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

	# Header: title + Back.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root_v.add_child(header)
	var title := _label("✦  Equipment  ✦", BattleUITheme.font_bold(), 20, BattleUITheme.TEXT_ACCENT)
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

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_v.add_child(scroll)

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
	_build_content()

func _select_slot(idx_def: int) -> void:
	_selected_slot_def = clampi(idx_def, 0, SLOT_DEFS.size() - 1)
	_build_content()

func _build_content() -> void:
	if _content_host == null:
		return
	for c in _content_host.get_children():
		c.queue_free()

	var hero: Character = _party[_selected]
	var palette := HeroPalette.for_hero(hero.character_name)

	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	_content_host.add_child(columns)

	columns.add_child(_build_left_column(hero, palette))
	columns.add_child(_build_slots_column(hero))
	columns.add_child(_build_pool_column(hero))

# --- Left column: identity + live stats ---------------------------------------

func _build_left_column(hero: Character, palette: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(250, 0)
	col.add_theme_constant_override("separation", 8)

	var portrait_wrap := CenterContainer.new()
	col.add_child(portrait_wrap)
	portrait_wrap.add_child(_make_portrait(hero.character_name, palette))

	col.add_child(_label(hero.character_name, BattleUITheme.font_bold(), 22, palette["accent"], HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(_label("Lv %d  ·  %s" % [hero.level, hero.character_class], BattleUITheme.font_regular(), 12, palette["subtitle"], HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(_affinity_label(hero))

	col.add_child(_divider())
	col.add_child(_section_header("Stats"))

	# Each row shows the BASE stat (base + level growth, no gear) plus the
	# equipment contribution as a "+N" delta — so the effect of equipping is
	# visible. The Status screen shows the combined total instead. base = the
	# equipment-inclusive getter minus the gear bonus (overworld has no buffs, so
	# StatusSystem.compose_stat is identity and this subtraction is exact).
	var stats := VBoxContainer.new()
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_theme_constant_override("separation", 4)
	var inv := hero.inventory
	stats.add_child(_make_stat_row("HP", str(hero.max_hp() - inv.equipment_bonus("max_hp")), inv.equipment_bonus("max_hp")))
	stats.add_child(_make_stat_row("MP", str(hero.max_mp() - inv.equipment_bonus("max_mp")), inv.equipment_bonus("max_mp")))
	stats.add_child(_make_stat_row("ATK", str(hero.attack_power() - inv.equipment_bonus("attack")), inv.equipment_bonus("attack")))
	stats.add_child(_make_stat_row("DEF", str(hero.defense_power() - inv.equipment_bonus("defense")), inv.equipment_bonus("defense")))
	stats.add_child(_make_stat_row("MAG", str(hero.magic_power() - inv.equipment_bonus("magic")), inv.equipment_bonus("magic")))
	stats.add_child(_make_stat_row("ARC", str(hero.arcane_power() - inv.equipment_bonus("arcane")), inv.equipment_bonus("arcane")))
	stats.add_child(_make_stat_row("SPD", str(hero.speed() - inv.equipment_bonus("speed")), inv.equipment_bonus("speed")))
	col.add_child(stats)
	return col

func _affinity_label(hero: Character) -> Label:
	var t := ElementalSystem.get_element_name(hero.element)
	if hero.secondary_element != ElementalSystem.Element.NORMAL and hero.secondary_element != hero.element:
		t += " / " + ElementalSystem.get_element_name(hero.secondary_element)
	return _label(t, BattleUITheme.font_regular(), 11, ElementalSystem.get_element_color(hero.element), HORIZONTAL_ALIGNMENT_CENTER)

# Stat row: name (left) · value (expand, right) · equipment delta (fixed, right).
func _make_stat_row(label: String, value_text: String, delta: int) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	var name_lbl := _label(label, BattleUITheme.font_regular(), 13, BattleUITheme.TEXT_SUBTITLE)
	name_lbl.custom_minimum_size = Vector2(40, 0)
	row.add_child(name_lbl)
	var val_lbl := _label(value_text, BattleUITheme.font_bold(), 14, BattleUITheme.TEXT_PRIMARY, HORIZONTAL_ALIGNMENT_RIGHT)
	val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(val_lbl)
	var delta_text := ""
	var delta_color := BattleUITheme.TEXT_SUBTITLE
	if delta != 0:
		delta_text = "%+d" % delta
		delta_color = Color(0.55, 0.95, 0.55) if delta > 0 else Color(1.0, 0.55, 0.45)
	var delta_lbl := _label(delta_text, BattleUITheme.font_regular(), 12, delta_color, HORIZONTAL_ALIGNMENT_RIGHT)
	delta_lbl.custom_minimum_size = Vector2(46, 0)
	row.add_child(delta_lbl)
	return row

# --- Middle column: the five equip slots --------------------------------------

func _build_slots_column(hero: Character) -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(340, 0)
	col.add_theme_constant_override("separation", 8)
	col.add_child(_section_header("Equipment Slots"))
	for i in range(SLOT_DEFS.size()):
		col.add_child(_make_slot_row(hero, i))
	return col

func _make_slot_row(hero: Character, idx_def: int) -> Control:
	var d: Array = SLOT_DEFS[idx_def]
	var slot_label: String = d[0]
	var slot_type: int = d[1]
	var acc_index: int = d[2]
	var eq: Equipment = hero.inventory.get_equipped(slot_type, acc_index)
	var selected := (idx_def == _selected_slot_def)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)

	# The slot button selects this slot (drives the right-hand pool list). A child
	# VBox (mouse-ignored) supplies the multi-line content the button can't.
	# NOTE: do NOT set flat = true here — flat suppresses the `normal` stylebox, so
	# the selected/hover highlight (set below via _style_slot_button) wouldn't show.
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 52)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func(): _select_slot(idx_def))
	_style_slot_button(btn, eq, selected)
	row.add_child(btn)

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.offset_left = 10
	content.offset_right = -10
	content.offset_top = 5
	content.offset_bottom = -5
	content.add_theme_constant_override("separation", 1)
	btn.add_child(content)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 8)
	content.add_child(top)
	var type_lbl := _label(slot_label, BattleUITheme.font_regular(), 11, BattleUITheme.TEXT_SUBTITLE)
	type_lbl.custom_minimum_size = Vector2(86, 0)
	type_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(type_lbl)
	if eq != null:
		var name_lbl := _label(eq.equipment_name, BattleUITheme.font_bold(), 14, eq.rarity_color().lerp(Color.WHITE, 0.2))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(name_lbl)
	else:
		var empty_lbl := _label("— Empty —", BattleUITheme.font_regular(), 13, BattleUITheme.TEXT_SUBTITLE)
		empty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(empty_lbl)

	if eq != null:
		var meta_parts: Array[String] = []
		if eq.bonus_text() != "":
			meta_parts.append(eq.bonus_text())
		meta_parts.append(eq.rarity_name())
		var meta_lbl := _label("    ".join(meta_parts), BattleUITheme.font_regular(), 10, BattleUITheme.TEXT_SUBTITLE)
		meta_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(meta_lbl)

		var unequip := BattleUITheme.make_button("Unequip", 11)
		unequip.custom_minimum_size = Vector2(84, 0)
		unequip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		unequip.pressed.connect(func(): _on_unequip(slot_type, acc_index))
		row.add_child(unequip)

	return row

# --- Right column: equippable pool for the selected slot ----------------------

func _build_pool_column(hero: Character) -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)

	var d: Array = SLOT_DEFS[_selected_slot_def]
	var slot_label: String = d[0]
	var slot_type: int = d[1]
	col.add_child(_section_header("Available · %s" % slot_label))

	var pieces := pool_for_slot(_pool(), slot_type)
	if pieces.is_empty():
		col.add_child(_label("No spare gear for this slot.", BattleUITheme.font_regular(), 12, BattleUITheme.TEXT_SUBTITLE))
		return col

	# Highest rarity first, then alphabetical, for a stable, scannable list.
	pieces.sort_custom(func(a, b):
		if a.rarity != b.rarity:
			return a.rarity > b.rarity
		return a.equipment_name < b.equipment_name)
	for eq in pieces:
		col.add_child(_make_pool_card(hero, eq, d))
	return col

func _make_pool_card(hero: Character, eq: Equipment, slot_def: Array) -> Control:
	var can := eq.can_equip(hero)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var border := eq.rarity_color().lerp(BattleUITheme.PANEL_BORDER, 0.5)
	var style := BattleUITheme.panel_style(border, BattleUITheme.SUBPANEL_BG, 1, 6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", style)
	if not can:
		card.modulate = Color(1, 1, 1, 0.45)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	card.add_child(v)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var name_lbl := _label(eq.equipment_name, BattleUITheme.font_bold(), 14, eq.rarity_color().lerp(Color.WHITE, 0.2))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)
	row.add_child(_label(eq.rarity_name(), BattleUITheme.font_regular(), 10, eq.rarity_color()))
	var equip_btn := BattleUITheme.make_button("Equip", 11)
	equip_btn.custom_minimum_size = Vector2(74, 26)
	equip_btn.disabled = not can
	equip_btn.pressed.connect(func(): _on_equip(eq, slot_def))
	row.add_child(equip_btn)

	if eq.bonus_text() != "":
		v.add_child(_label(eq.bonus_text(), BattleUITheme.font_regular(), 11, BattleUITheme.TEXT_PRIMARY))
	var restr := eq.restriction_text()
	if restr != "":
		var rcolor := Color(0.55, 0.95, 0.55) if can else Color(1.0, 0.55, 0.45)
		v.add_child(_label("Requires: %s" % restr, BattleUITheme.font_regular(), 10, rcolor))
	if eq.description != "":
		var desc := _label(eq.description, BattleUITheme.font_regular(), 10, BattleUITheme.TEXT_SUBTITLE)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(desc)
	return card

# --- Equip / unequip actions --------------------------------------------------

func _on_equip(eq: Equipment, slot_def: Array) -> void:
	var hero: Character = _party[_selected]
	var acc_index: int = slot_def[2]
	Inventory.equip_from_pool(hero, _pool(), eq, acc_index)
	_build_content()

func _on_unequip(slot_type: int, acc_index: int) -> void:
	var hero: Character = _party[_selected]
	Inventory.unequip_to_pool(hero, _pool(), slot_type, acc_index)
	_build_content()

# --- Primitives ---------------------------------------------------------------

func _make_portrait(hero_name: String, palette: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(120, 120)
	var style := BattleUITheme.panel_style(palette["accent"], palette["panel_bg"], 2, 12)
	p.add_theme_stylebox_override("panel", style)
	var letter := Label.new()
	letter.text = hero_name.substr(0, 1) if hero_name != "" else "?"
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var f := BattleUITheme.font_bold()
	if f: letter.add_theme_font_override("font", f)
	letter.add_theme_font_size_override("font_size", 58)
	letter.add_theme_color_override("font_color", palette["accent"])
	p.add_child(letter)
	return p

func _style_slot_button(b: Button, eq: Equipment, selected: bool) -> void:
	var accent: Color = eq.rarity_color() if eq != null else BattleUITheme.BUTTON_BORDER
	var border: Color = BattleUITheme.TEXT_ACCENT if selected else accent.lerp(BattleUITheme.PANEL_BORDER, 0.5)
	# Selected slots get a brighter accent-tinted fill so it's obvious which slot
	# the right-hand pool is targeting; idle slots use the plain subpanel bg.
	var bg: Color = BattleUITheme.TEXT_ACCENT.lerp(BattleUITheme.SUBPANEL_BG, 0.78) if selected else BattleUITheme.SUBPANEL_BG
	var normal := BattleUITheme.panel_style(border, bg, 2 if selected else 1, 6)
	b.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.border_color = BattleUITheme.TEXT_ACCENT
	hover.set_border_width_all(2)
	if not selected:
		hover.bg_color = BattleUITheme.TEXT_ACCENT.lerp(BattleUITheme.SUBPANEL_BG, 0.88)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

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
	return _label(text.to_upper(), BattleUITheme.font_bold(), 12, BattleUITheme.TEXT_SUBTITLE)

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
