class_name ShopScreen
extends Control

## ShopScreen — a buy/sell shop opened by a Shopkeeper NPC (not the pause menu).
## Two tabs: Buy (the shop's stock, with prices) and Sell (the party's sellable
## items + unequipped gear, at half price). Pauses the game while open; Back / Esc /
## B closes it. Themed with BattleUITheme.

signal closed

const TAB_BUY := 0
const TAB_SELL := 1
const TAB_NAMES := ["Buy", "Sell"]

var _shop_id: String = ""
var _selected_tab: int = 0
var _tab_buttons: Array[Button] = []
var _content_host: VBoxContainer = null
var _gold_label: Label = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)

func setup(shop_id: String) -> void:
	_shop_id = shop_id
	get_tree().paused = true     # freeze the world while shopping
	_build_chrome()
	_select_tab(0)
	for tb in _tab_buttons:
		BattleUITheme.mark_no_focus(tb)
	GameManager.register_focus_scope(self)

func _exit_tree() -> void:
	GameManager.unregister_focus_scope(self)
	if get_tree() != null:
		get_tree().paused = false

func _close() -> void:
	closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
	elif FocusUtil.is_prev_category(event):
		_select_tab((_selected_tab - 1 + TAB_NAMES.size()) % TAB_NAMES.size())
		get_viewport().set_input_as_handled()
	elif FocusUtil.is_next_category(event):
		_select_tab((_selected_tab + 1) % TAB_NAMES.size())
		get_viewport().set_input_as_handled()

# --- Chrome -------------------------------------------------------------------

func _build_chrome() -> void:
	for c in get_children():
		c.queue_free()
	_tab_buttons.clear()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	const BASE_W := 1100.0
	const BASE_H := 620.0
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := BattleUITheme.make_panel()
	panel.custom_minimum_size = Vector2(BASE_W, BASE_H)
	var pstyle := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if pstyle:
		pstyle.set_corner_radius_all(0)
		pstyle.content_margin_left = 28
		pstyle.content_margin_right = 28
		pstyle.content_margin_top = 16
		pstyle.content_margin_bottom = 16
	center.add_child(panel)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 10)
	panel.add_child(root_v)

	# Header: shop name + gold + Back.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root_v.add_child(header)
	var title := _label("✦  %s  ✦" % ShopFactory.shop_name(_shop_id), BattleUITheme.font_bold(), 20, BattleUITheme.TEXT_ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_gold_label = _label("", BattleUITheme.font_bold(), 15, Color(0.97, 0.83, 0.35))
	header.add_child(_gold_label)
	var back_btn := BattleUITheme.make_button("← Leave", 12)
	back_btn.custom_minimum_size = Vector2(96, 30)
	back_btn.pressed.connect(_close)
	header.add_child(back_btn)

	# Tabs.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	root_v.add_child(tabs)
	for i in range(TAB_NAMES.size()):
		var tab := _make_tab(TAB_NAMES[i], i)
		_tab_buttons.append(tab)
		tabs.add_child(tab)

	root_v.add_child(_divider())

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	root_v.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 16)
	scroll.add_child(margin)

	_content_host = VBoxContainer.new()
	_content_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_host.add_theme_constant_override("separation", 6)
	margin.add_child(_content_host)

func _refresh_gold() -> void:
	if _gold_label:
		_gold_label.text = "Gold: %d" % GameManager.gold

# --- Tabs / content -----------------------------------------------------------

func _select_tab(index: int) -> void:
	_selected_tab = clampi(index, 0, TAB_NAMES.size() - 1)
	for i in range(_tab_buttons.size()):
		_style_tab(_tab_buttons[i], i == _selected_tab)
	_build_content()

func _build_content() -> void:
	if _content_host == null:
		return
	for c in _content_host.get_children():
		c.queue_free()
	_refresh_gold()
	if _selected_tab == TAB_BUY:
		_build_buy()
	else:
		_build_sell()

func _build_buy() -> void:
	var any := false
	for name in ShopFactory.item_names(_shop_id):
		var it := ItemFactory.create(String(name))
		if it != null and it.price > 0:
			any = true
			_content_host.add_child(_buy_row(it.item_name, it.description, it.price, GameManager.can_afford(it.price),
				func(): if GameManager.buy_item(it.item_name): call_deferred("_build_content")))
	for name in ShopFactory.equipment_names(_shop_id):
		var eq := EquipmentFactory.create(String(name))
		if eq != null and eq.price > 0:
			any = true
			_content_host.add_child(_buy_row(eq.equipment_name, eq.bonus_text() if eq.has_method("bonus_text") else eq.description, eq.price,
				GameManager.can_afford(eq.price),
				func(): if GameManager.buy_equipment(eq.equipment_name): call_deferred("_build_content")))
	if not any:
		_content_host.add_child(_muted("This shop has nothing to sell right now."))

func _build_sell() -> void:
	var inv: Inventory = GameManager.party[0].inventory if not GameManager.party.is_empty() else null
	if inv == null:
		_content_host.add_child(_muted("Nothing to sell."))
		return
	var any := false
	for it in inv.items:
		if it.quantity > 0 and it.sell_price() > 0:
			any = true
			var item := it
			_content_host.add_child(_sell_row("%s  x%d" % [item.item_name, item.quantity], item.sell_price(),
				func(): if GameManager.sell_item(item) > 0: call_deferred("_build_content")))
	for eq in inv.equipment:
		if eq.sell_price() > 0:
			any = true
			var piece := eq
			_content_host.add_child(_sell_row(piece.equipment_name, piece.sell_price(),
				func(): if GameManager.sell_equipment(piece) > 0: call_deferred("_build_content")))
	if not any:
		_content_host.add_child(_muted("You have nothing worth selling."))

# --- Rows ---------------------------------------------------------------------

func _buy_row(name_text: String, sub: String, price: int, affordable: bool, on_buy: Callable) -> Control:
	var slot := _row_panel()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	slot.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 1)
	row.add_child(col)
	col.add_child(_label(name_text, BattleUITheme.font_bold(), 15, BattleUITheme.TEXT_PRIMARY))
	if sub != "":
		var d := _label(sub, BattleUITheme.font_regular(), 11, BattleUITheme.TEXT_SUBTITLE)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(d)
	row.add_child(_label("%d G" % price, BattleUITheme.font_bold(), 14, Color(0.97, 0.83, 0.35)))
	var btn := BattleUITheme.make_button("Buy", 12)
	btn.custom_minimum_size = Vector2(76, 30)
	btn.disabled = not affordable
	btn.pressed.connect(on_buy)
	row.add_child(btn)
	return slot

func _sell_row(name_text: String, sell_price: int, on_sell: Callable) -> Control:
	var slot := _row_panel()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	slot.add_child(row)
	row.add_child(_label(name_text, BattleUITheme.font_bold(), 15, BattleUITheme.TEXT_PRIMARY))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_label("+%d G" % sell_price, BattleUITheme.font_bold(), 14, Color(0.55, 0.85, 0.55)))
	var btn := BattleUITheme.make_button("Sell", 12)
	btn.custom_minimum_size = Vector2(76, 30)
	btn.pressed.connect(on_sell)
	row.add_child(btn)
	return slot

func _row_panel() -> PanelContainer:
	var slot := PanelContainer.new()
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := BattleUITheme.panel_style(BattleUITheme.PANEL_BORDER, BattleUITheme.SUBPANEL_BG, 1, 6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	slot.add_theme_stylebox_override("panel", style)
	return slot

# --- Primitives ---------------------------------------------------------------

func _make_tab(text: String, index: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 32)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	BattleUITheme.mark_no_focus(b)
	b.pressed.connect(func(): _select_tab(index))
	_style_tab(b, false)
	return b

func _style_tab(b: Button, active: bool) -> void:
	var accent := BattleUITheme.PANEL_BORDER
	var f := BattleUITheme.font_bold()
	if f:
		b.add_theme_font_override("font", f)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", BattleUITheme.TEXT_ACCENT if active else BattleUITheme.TEXT_SUBTITLE)
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

func _muted(text: String) -> Control:
	return _label("   " + text, BattleUITheme.font_regular(), 13, BattleUITheme.TEXT_SUBTITLE, HORIZONTAL_ALIGNMENT_CENTER)

func _divider() -> Control:
	var line := ColorRect.new()
	line.color = Color(0.40, 0.30, 0.55, 0.6)
	line.custom_minimum_size = Vector2(0, 1)
	return line

func _label(text: String, font: Font, size: int, color: Color, h_align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = h_align
	if font:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
