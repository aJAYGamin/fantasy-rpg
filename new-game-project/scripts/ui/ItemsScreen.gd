class_name ItemsScreen
extends Control

## ItemsScreen — Phase P2.
## Full-screen inventory page opened from the pause menu (overworld). Lists the
## party's shared items (GameManager.party[0].inventory) under four tabs:
## Items (misc/general), Healing Items, Battle Items, and Key Items.
##
## Healing consumables can be USED from here on a chosen hero (single-ally items
## pop a target picker; all-ally items apply to the whole party). Battle items are
## combat-only and Key items are never used, so those tabs are display-only.
##
## Built in code and themed with BattleUITheme, mirroring StatsScreen's chrome
## (CenterContainer + explicitly-sized PanelContainer that fills the base-res
## canvas). Opened by PauseMenu as a replace-don't-stack sub-view; Back / Esc
## return to the pause menu. ←/→ cycle tabs.
##
## The categorization + use-eligibility logic lives in pure static helpers so the
## test suite can assert on them without a scene tree.

signal back_requested

# Tab label -> ItemCategory, in display order.
const TAB_DEFS := [
	["Items", Item.ItemCategory.GENERAL],
	["Healing Items", Item.ItemCategory.HEALING],
	["Battle Items", Item.ItemCategory.BATTLE],
	["Key Items", Item.ItemCategory.KEY],
]

var _inventory: Inventory = null
var _party: Array = []
var _selected_tab: int = 0
var _tab_buttons: Array[Button] = []
var _content_host: Control = null
# Target picker is two nodes added directly to this screen (a full-rect dim that
# blocks clicks + a CenterContainer holding the panel) rather than a wrapped
# overlay Control: a plain Control wrapper doesn't reliably get a size here, which
# collapses the CenterContainer and pins the panel to the top-left.
var _picker: Control = null
var _picker_dim: Control = null

# --- Pure helpers (testable) --------------------------------------------------

# Buckets an inventory's items (quantity > 0) by their derived ItemCategory.
# Returns a Dictionary keyed by Item.ItemCategory with an Array of Items each.
static func categorize(inventory: Inventory) -> Dictionary:
	var buckets := {
		Item.ItemCategory.GENERAL: [],
		Item.ItemCategory.HEALING: [],
		Item.ItemCategory.BATTLE: [],
		Item.ItemCategory.KEY: [],
	}
	if inventory == null:
		return buckets
	for item in inventory.items:
		if item.quantity > 0:
			buckets[item.get_category()].append(item)
	return buckets

# True if the item can be used from the overworld AND at least one party member
# is a valid target for it (otherwise the Use button stays disabled).
static func can_field_use(item: Item, party: Array) -> bool:
	if item == null or item.quantity <= 0 or not item.is_field_usable():
		return false
	for hero in party:
		if can_target_hero(item, hero):
			return true
	return false

# True if applying this (field-usable) item to a specific hero would do something.
static func can_target_hero(item: Item, hero: Character) -> bool:
	if hero == null:
		return false
	match item.item_type:
		Item.ItemType.HP_RESTORE:
			return hero.is_alive() and hero.current_hp < hero.max_hp()
		Item.ItemType.MP_RESTORE:
			return hero.is_alive() and hero.current_mp < hero.max_mp()
		Item.ItemType.ANTIDOTE:
			return hero.has_status("poison") or hero.has_status("burn")
		Item.ItemType.REVIVAL:
			return not hero.is_alive()
	return false

static func item_color(item: Item) -> Color:
	match item.item_type:
		Item.ItemType.HP_RESTORE:   return Color(0.20, 0.90, 0.40)
		Item.ItemType.MP_RESTORE:   return Color(0.30, 0.65, 1.00)
		Item.ItemType.REVIVAL:      return Color(1.00, 0.85, 0.20)
		Item.ItemType.BUFF:         return Color(0.85, 0.60, 1.00)
		Item.ItemType.ANTIDOTE:     return Color(0.40, 0.90, 0.70)
		Item.ItemType.DAMAGE:       return Color(0.95, 0.35, 0.15)
		Item.ItemType.DEBUFF:       return Color(0.80, 0.30, 0.50)
		Item.ItemType.DODGE_BUFF:   return Color(0.70, 0.80, 0.95)
		Item.ItemType.KEY:          return Color(0.95, 0.80, 0.45)
	return Color(0.72, 0.70, 0.78)  # GENERAL / misc

static func effect_text(item: Item) -> String:
	match item.item_type:
		Item.ItemType.HP_RESTORE:  return "+%d HP" % item.effect_value
		Item.ItemType.MP_RESTORE:  return "+%d MP" % item.effect_value
		Item.ItemType.REVIVAL:     return "Revive (%d%%)" % item.effect_value
		Item.ItemType.ANTIDOTE:    return "Cure status"
		Item.ItemType.BUFF:        return "+%s" % item.effect_stat
		Item.ItemType.DAMAGE:      return "-%d HP" % item.effect_value
		Item.ItemType.DEBUFF:      return item.effect_stat
		Item.ItemType.DODGE_BUFF:  return "%d%% dodge" % item.effect_value
	return ""

# --- Lifecycle ----------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)

func setup(party: Array, start_tab: int = 0) -> void:
	_party = party
	_inventory = party[0].inventory if not party.is_empty() else null
	_selected_tab = clampi(start_tab, 0, TAB_DEFS.size() - 1)
	_build_chrome()
	_select_tab(_selected_tab)
	# The central focus guard maintains controller focus on the item list / picker;
	# category tabs are tagged no-focus (cycled with L1/R1).
	for tb in _tab_buttons:
		BattleUITheme.mark_no_focus(tb)
	GameManager.register_focus_scope(self)

func _exit_tree() -> void:
	GameManager.unregister_focus_scope(self)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	# While the target picker is open, Cancel/B closes it (and is consumed so the
	# pause menu doesn't back out the whole screen).
	if _picker != null:
		if event.is_action_pressed("ui_cancel"):
			_close_target_picker()
			get_viewport().set_input_as_handled()
		return
	# L1 / R1 (shoulder buttons) cycle category tabs on controller. Keyboard+mouse
	# users switch tabs by clicking them with the mouse.
	if FocusUtil.is_prev_category(event):
		_select_tab((_selected_tab - 1 + TAB_DEFS.size()) % TAB_DEFS.size())
		get_viewport().set_input_as_handled()
	elif FocusUtil.is_next_category(event):
		_select_tab((_selected_tab + 1) % TAB_DEFS.size())
		get_viewport().set_input_as_handled()

# --- Chrome (built once) ------------------------------------------------------

func _build_chrome() -> void:
	for c in get_children():
		c.queue_free()
	_tab_buttons.clear()
	_picker = null
	_picker_dim = null

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
		pstyle.content_margin_left = 24
		pstyle.content_margin_right = 24
		pstyle.content_margin_top = 14
		pstyle.content_margin_bottom = 14
	center.add_child(panel)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 8)
	panel.add_child(root_v)

	# Header: title + Back.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root_v.add_child(header)
	var title := _label("✦  Items  ✦", BattleUITheme.font_bold(), 20, BattleUITheme.TEXT_ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back_btn := BattleUITheme.make_button("← Back", 12)
	back_btn.custom_minimum_size = Vector2(90, 30)
	back_btn.pressed.connect(func(): back_requested.emit())
	header.add_child(back_btn)

	# Category tabs.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	root_v.add_child(tabs)
	for i in range(TAB_DEFS.size()):
		var tab := _make_tab(TAB_DEFS[i][0], i)
		_tab_buttons.append(tab)
		tabs.add_child(tab)

	root_v.add_child(_divider())

	# Scrollable item list — rebuilt per tab.
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
	_content_host.add_theme_constant_override("separation", 6)
	scroll_margin.add_child(_content_host)

# --- Tab selection ------------------------------------------------------------

func _select_tab(index: int) -> void:
	_selected_tab = clampi(index, 0, TAB_DEFS.size() - 1)
	for i in range(_tab_buttons.size()):
		_style_tab(_tab_buttons[i], i == _selected_tab)
	_build_content()
	# New item buttons appeared — the central focus guard re-grabs focus next frame.

func _build_content() -> void:
	if _content_host == null:
		return
	for c in _content_host.get_children():
		c.queue_free()

	var category: int = TAB_DEFS[_selected_tab][1]
	var items: Array = categorize(_inventory)[category]
	if items.is_empty():
		var empty := _label("No items in this category.", BattleUITheme.font_regular(), 14, BattleUITheme.TEXT_SUBTITLE, HORIZONTAL_ALIGNMENT_CENTER)
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_content_host.add_child(empty)
		return
	for item in items:
		_content_host.add_child(_make_item_slot(item))

# --- Item slot ----------------------------------------------------------------

func _make_item_slot(item: Item) -> Control:
	var slot := PanelContainer.new()
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var border := item_color(item).lerp(BattleUITheme.PANEL_BORDER, 0.5)
	var style := BattleUITheme.panel_style(border, BattleUITheme.SUBPANEL_BG, 1, 6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	slot.add_theme_stylebox_override("panel", style)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	slot.add_child(v)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)

	var name_lbl := _label(item.item_name, BattleUITheme.font_bold(), 15, item_color(item))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	var eff := effect_text(item)
	if eff != "":
		row.add_child(_label(eff, BattleUITheme.font_regular(), 12, BattleUITheme.TEXT_SUBTITLE))

	row.add_child(_label("x%d" % item.quantity, BattleUITheme.font_bold(), 13, BattleUITheme.TEXT_PRIMARY))

	var desc := _label(item.description, BattleUITheme.font_regular(), 11, BattleUITheme.TEXT_PRIMARY)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.visible = false

	var desc_btn := BattleUITheme.make_button("?", 11)
	desc_btn.custom_minimum_size = Vector2(28, 28)
	# Controller skips the "?" so vertical navigation lands on the Use button.
	BattleUITheme.mark_no_focus(desc_btn)
	desc_btn.pressed.connect(func(): desc.visible = not desc.visible)
	row.add_child(desc_btn)

	# Right-most slot action: Use for field-usable healing items; an inert hint
	# for battle items (combat-only). Key/general items get nothing.
	if item.is_field_usable():
		var use_btn := BattleUITheme.make_button("Use", 12)
		use_btn.custom_minimum_size = Vector2(72, 28)
		use_btn.disabled = not can_field_use(item, _party)
		use_btn.pressed.connect(func(): _on_use_pressed(item))
		row.add_child(use_btn)
	elif item.get_category() == Item.ItemCategory.BATTLE:
		var hint := _label("Battle only", BattleUITheme.font_regular(), 10, BattleUITheme.TEXT_SUBTITLE)
		hint.custom_minimum_size = Vector2(72, 0)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(hint)

	v.add_child(desc)
	return slot

# --- Use flow -----------------------------------------------------------------

func _on_use_pressed(item: Item) -> void:
	if item.target_type == Item.TargetType.ALL_ALLIES:
		var targets: Array = []
		for hero in _party:
			if hero.is_alive():
				targets.append(hero)
		_apply_field_item(item, targets)
	else:
		_open_target_picker(item)

func _apply_field_item(item: Item, targets: Array) -> void:
	for t in targets:
		item.use(t)
	item.quantity -= 1
	if item.quantity <= 0 and _inventory != null:
		_inventory.items.erase(item)
	_build_content()

func _open_target_picker(item: Item) -> void:
	_close_target_picker()
	# This screen's own rect can be (0,0): the chrome only looks full-screen
	# because its panel's large min-size forces its CenterContainer to fill. A
	# small picker panel would otherwise collapse to the top-left. So we pin the
	# dim and the CenterContainer to the viewport size explicitly — they then fill
	# the screen (dimming everything behind, like the pause menu) and center the
	# panel regardless of this control's own size.
	var screen_size := get_viewport_rect().size

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.custom_minimum_size = screen_size
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_picker_dim = dim
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.custom_minimum_size = screen_size
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	_picker = center
	add_child(center)

	var panel := BattleUITheme.make_panel()
	panel.custom_minimum_size = Vector2(460, 0)
	var pstyle := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if pstyle:
		pstyle.content_margin_left = 22
		pstyle.content_margin_right = 22
		pstyle.content_margin_top = 16
		pstyle.content_margin_bottom = 16
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	# Title tinted with the item's color so it reads as "using <this item>".
	v.add_child(_label("Use %s on…" % item.item_name, BattleUITheme.font_bold(), 17, item_color(item), HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_divider())

	for hero in _party:
		v.add_child(_make_target_button(item, hero))

	var cancel := BattleUITheme.make_button("Cancel", 12)
	cancel.custom_minimum_size = Vector2(0, 32)
	cancel.pressed.connect(_close_target_picker)
	v.add_child(cancel)
	# Register the picker on top so the focus guard tracks it; closing it pops back
	# to the item list scope.
	GameManager.register_focus_scope(_picker)

# A target row themed in the hero's own palette color, with HP/MP shown as
# distinct colored columns. A plain Button can only tint its whole label one
# color, so the name/HP/MP live in a mouse-ignored child HBox.
func _make_target_button(item: Item, hero: Character) -> Button:
	var palette := HeroPalette.for_hero(hero.character_name)
	var accent: Color = palette["accent"]
	var valid := can_target_hero(item, hero)

	var b := Button.new()
	b.custom_minimum_size = Vector2(416, 46)
	b.disabled = not valid
	if not valid:
		b.modulate = Color(1, 1, 1, 0.45)
	_style_target_button(b, accent)
	if valid:
		b.pressed.connect(func():
			_apply_field_item(item, [hero])
			_close_target_picker())

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.offset_left = 14
	row.offset_right = -14
	row.add_theme_constant_override("separation", 12)
	b.add_child(row)

	var name_lbl := _label(hero.character_name, BattleUITheme.font_bold(), 15, accent)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_lbl)

	if hero.is_alive():
		var hp_lbl := _label("HP %d/%d" % [hero.current_hp, hero.max_hp()], BattleUITheme.font_regular(), 12, Color(0.55, 0.95, 0.55))
		hp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hp_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(hp_lbl)
		var mp_lbl := _label("MP %d/%d" % [hero.current_mp, hero.max_mp()], BattleUITheme.font_regular(), 12, Color(0.50, 0.70, 1.0))
		mp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mp_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(mp_lbl)
	else:
		var ko := _label("KO", BattleUITheme.font_bold(), 12, Color(1.0, 0.45, 0.45))
		ko.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ko.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ko)

	return b

func _style_target_button(b: Button, accent: Color) -> void:
	var normal := BattleUITheme.panel_style(accent, accent.lerp(BattleUITheme.SUBPANEL_BG, 0.84), 1, 6)
	b.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = accent.lerp(BattleUITheme.SUBPANEL_BG, 0.62)
	hover.set_border_width_all(2)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	var disabled := normal.duplicate()
	disabled.bg_color = BattleUITheme.SUBPANEL_BG
	b.add_theme_stylebox_override("disabled", disabled)
	# Controller focus reuses the hover look — highlight only the targeted hero,
	# no extra border box.
	b.add_theme_stylebox_override("focus", hover)

func _close_target_picker() -> void:
	if _picker != null and is_instance_valid(_picker):
		GameManager.unregister_focus_scope(_picker)
		_picker.queue_free()
	_picker = null
	if _picker_dim != null and is_instance_valid(_picker_dim):
		_picker_dim.queue_free()
	_picker_dim = null

# --- Tab + primitives ---------------------------------------------------------

func _make_tab(text: String, index: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 32)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Tabs are cycled with L1/R1, never controller-focusable.
	BattleUITheme.mark_no_focus(b)
	b.pressed.connect(func(): _select_tab(index))
	_style_tab(b, false)
	return b

func _style_tab(b: Button, active: bool) -> void:
	var accent := BattleUITheme.PANEL_BORDER
	var f := BattleUITheme.font_bold()
	if f: b.add_theme_font_override("font", f)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", BattleUITheme.TEXT_ACCENT if active else BattleUITheme.TEXT_SUBTITLE)
	b.add_theme_color_override("font_hover_color", BattleUITheme.TEXT_ACCENT)
	b.add_theme_color_override("font_pressed_color", BattleUITheme.TEXT_ACCENT)

	var normal := StyleBoxFlat.new()
	normal.bg_color = accent.lerp(Color(0.04, 0.03, 0.07), 0.55 if active else 0.86)
	normal.border_color = accent if active else BattleUITheme.BUTTON_BORDER
	normal.set_border_width_all(2 if active else 1)
	normal.border_width_bottom = 0 if active else 1
	normal.set_corner_radius_all(6)
	normal.corner_radius_bottom_left = 0
	normal.corner_radius_bottom_right = 0
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5
	b.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = accent.lerp(Color(0.04, 0.03, 0.07), 0.5)
	hover.border_color = accent
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)

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
