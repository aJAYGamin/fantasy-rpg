extends Control

## ItemsMenu.gd
## Scrollable vertical list of items with name, quantity, effect, and ? description

signal item_used(item: Item, targets: Array)
signal menu_closed

var _current_hero: Character = null
var _battle_manager: BattleManager = null
var _inventory: Inventory = null
var _pending_item: Item = null
var _persistent_items: Array[Item] = []

func _ready():
	hide()

func _input(event):
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_BACKSPACE:
		close()

func setup(battle_mgr: BattleManager, inventory: Inventory):
	_battle_manager = battle_mgr
	_inventory = inventory

func set_items(items: Array[Item]):
	_persistent_items = items

func show_menu(hero: Character):
	_current_hero = hero
	_pending_item = null
	_build_menu()
	show()

func close():
	hide()
	emit_signal("menu_closed")

func _build_menu():
	for child in get_children():
		child.queue_free()

	var cinzel = load("res://fonts/Cinzel-Regular.ttf")
	var cinzel_bold = load("res://fonts/Cinzel-Bold.ttf")

	# Themed background — uses Panel (NOT PanelContainer) so the bg doesn't
	# auto-shrink to its content. PanelContainer is a Container whose
	# combined_minimum_size is driven by its child's min size; with sparse
	# content (title + a couple of items) the Container collapses, making the
	# items menu render smaller than the action menu it replaces. Panel is a
	# plain Control with a stylebox — its size is purely anchor-driven, so
	# PRESET_FULL_RECT reliably fills the menu rect.
	var bg := Panel.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", BattleUITheme.panel_style())
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Content layer — MarginContainer for the panel's inner padding, anchored
	# FULL_RECT to self so it fills the menu independently of the bg.
	var content := MarginContainer.new()
	content.add_theme_constant_override("margin_left", 8)
	content.add_theme_constant_override("margin_right", 8)
	content.add_theme_constant_override("margin_top", 6)
	content.add_theme_constant_override("margin_bottom", 6)
	add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Outer VBox holding title row + scrollable item list.
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	content.add_child(outer)

	# Title row — centered title with themed back chip
	var title_row = HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(title_row)

	var title_lbl = Label.new()
	title_lbl.text = "✦  Items  ✦"
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

	# Scrollable item list
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	# Theme the vertical scrollbar to match the amethyst aesthetic.
	_style_scrollbar(scroll.get_v_scroll_bar())

	# MarginContainer reserves space on the right so item slots stop short of
	# the scrollbar instead of running underneath it.
	var list_margin := MarginContainer.new()
	list_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_margin.add_theme_constant_override("margin_right", 6)
	scroll.add_child(list_margin)

	var item_list = VBoxContainer.new()
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.add_theme_constant_override("separation", 3)
	list_margin.add_child(item_list)

	# Get items from inventory
	var items: Array[Item]
	if not _persistent_items.is_empty():
		items = _persistent_items
	elif _inventory != null:
		items = _inventory.get_battle_items()
	else:
		items = _get_test_items()

	if items.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "No items available."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if cinzel: empty_lbl.add_theme_font_override("font", cinzel)
		empty_lbl.add_theme_font_size_override("font_size", 11)
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		item_list.add_child(empty_lbl)
		return

	for item in items:
		var slot = _create_item_slot(item, cinzel, cinzel_bold)
		item_list.add_child(slot)

func _create_item_slot(item: Item, cinzel, cinzel_bold) -> PanelContainer:
	var slot = PanelContainer.new()
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Themed slot panel — item-type-tinted border on the shared subpanel bg.
	var slot_border := _get_item_color(item).lerp(BattleUITheme.PANEL_BORDER, 0.55)
	var slot_style := BattleUITheme.panel_style(slot_border, BattleUITheme.SUBPANEL_BG, 1, 6)
	slot_style.content_margin_left = 6
	slot_style.content_margin_right = 6
	slot_style.content_margin_top = 3
	slot_style.content_margin_bottom = 3
	slot.add_theme_stylebox_override("panel", slot_style)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	slot.add_child(hbox)

	# Use button — themed; transparent normal/hover/pressed so the only border
	# visible is the slot panel's. Hover/press paint a subtle inner tint so the
	# slot itself looks like it's lighting up without drawing a second box.
	var use_btn := BattleUITheme.make_button("", 10)
	use_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	use_btn.custom_minimum_size = Vector2(0, 24)
	var flat_normal := StyleBoxFlat.new()
	flat_normal.bg_color = Color(0, 0, 0, 0)
	flat_normal.content_margin_left = 6
	flat_normal.content_margin_right = 6
	flat_normal.content_margin_top = 3
	flat_normal.content_margin_bottom = 3
	use_btn.add_theme_stylebox_override("normal", flat_normal)
	# Clearly visible hover wash so the row "lights up" — alpha 0.18 reads well
	# on the dark plum slot bg without drawing a competing border.
	var flat_hover := flat_normal.duplicate()
	flat_hover.bg_color = Color(1.0, 0.95, 1.0, 0.18)
	flat_hover.set_corner_radius_all(5)
	use_btn.add_theme_stylebox_override("hover", flat_hover)
	var flat_pressed := flat_normal.duplicate()
	flat_pressed.bg_color = Color(1.0, 0.95, 1.0, 0.30)
	flat_pressed.set_corner_radius_all(5)
	use_btn.add_theme_stylebox_override("pressed", flat_pressed)
	var flat_disabled := flat_normal.duplicate()
	flat_disabled.bg_color = Color(0, 0, 0, 0)
	use_btn.add_theme_stylebox_override("disabled", flat_disabled)

	var btn_inner = HBoxContainer.new()
	btn_inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn_inner.add_theme_constant_override("separation", 6)
	btn_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	use_btn.add_child(btn_inner)

	# Item name — item-type colored for quick scanning.
	var name_lbl = Label.new()
	name_lbl.text = item.item_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cinzel_bold: name_lbl.add_theme_font_override("font", cinzel_bold)
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", _get_item_color(item))
	btn_inner.add_child(name_lbl)

	# Quantity
	var qty_lbl = Label.new()
	qty_lbl.text = "x%d" % item.quantity
	qty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cinzel: qty_lbl.add_theme_font_override("font", cinzel)
	qty_lbl.add_theme_font_size_override("font_size", 9)
	qty_lbl.add_theme_color_override("font_color", BattleUITheme.TEXT_SUBTITLE)
	btn_inner.add_child(qty_lbl)

	var unusable = item.quantity <= 0 or not _can_use_item(item)
	use_btn.disabled = unusable
	if unusable:
		# Dim the WHOLE slot, not just the use button, so disabled state is
		# obvious at a glance — was easy to miss before because the slot panel
		# stayed at full opacity while only the inner button faded.
		slot.modulate.a = 0.45

	use_btn.pressed.connect(func(): _on_item_selected(item))
	hbox.add_child(use_btn)

	# ? description button — themed mini-button
	var desc_btn := BattleUITheme.make_button("?", 10)
	desc_btn.custom_minimum_size = Vector2(22, 24)
	desc_btn.pressed.connect(func(): _toggle_description(item))
	hbox.add_child(desc_btn)

	return slot

func _on_item_selected(item: Item):
	_pending_item = item
	match item.target_type:
		Item.TargetType.SINGLE_ALLY:
			# Target selection from party
			hide()
			emit_signal("item_used", item, [])
		Item.TargetType.SINGLE_ENEMY:
			# Target selection from enemies
			hide()
			emit_signal("item_used", item, [])
		Item.TargetType.ALL_ALLIES:
			var targets = Array(_battle_manager.get_alive_party())
			emit_signal("item_used", item, targets)
			close()
		Item.TargetType.ALL_ENEMIES:
			var targets = Array(_battle_manager.get_alive_enemies())
			emit_signal("item_used", item, targets)
			close()
		Item.TargetType.ALL:
			var targets = Array(_battle_manager.get_alive_party()) + Array(_battle_manager.get_alive_enemies())
			emit_signal("item_used", item, targets)
			close()

func _can_use_item(item: Item) -> bool:
	var party = _battle_manager.get_alive_party()
	match item.item_type:
		Item.ItemType.HP_RESTORE:
			# Only usable if at least one ally is not at full HP
			for hero in party:
				if hero.current_hp < hero.max_hp():
					return true
			return false
		Item.ItemType.MP_RESTORE:
			# Only usable if at least one ally is not at full MP
			for hero in party:
				if hero.current_mp < hero.max_mp():
					return true
			return false
		Item.ItemType.ANTIDOTE:
			# Only usable if at least one ally has a status condition
			for hero in party:
				if hero.has_status("poison") or hero.has_status("burn"):
					return true
			return false
		Item.ItemType.REVIVAL:
			# Only usable if at least one ally is defeated
			for hero in _battle_manager.party:
				if not hero.is_alive():
					return true
			return false
	return true

func _toggle_description(item: Item):
	var desc_panel = get_node_or_null("DescPanel")
	if desc_panel == null:
		var cinzel = load("res://fonts/Cinzel-Regular.ttf")
		desc_panel = PanelContainer.new()
		desc_panel.name = "DescPanel"
		desc_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
		desc_panel.position = Vector2(0, -55)
		desc_panel.custom_minimum_size = Vector2(0, 45)
		# Themed description panel.
		var desc_style := BattleUITheme.panel_style()
		desc_style.content_margin_left = 10
		desc_style.content_margin_right = 10
		desc_style.content_margin_top = 6
		desc_style.content_margin_bottom = 6
		desc_panel.add_theme_stylebox_override("panel", desc_style)
		var lbl = Label.new()
		lbl.name = "DescLbl"
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if cinzel: lbl.add_theme_font_override("font", cinzel)
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", BattleUITheme.TEXT_PRIMARY)
		desc_panel.add_child(lbl)
		add_child(desc_panel)

	var lbl = desc_panel.get_node("DescLbl")
	var new_text = "%s — %s" % [item.item_name, item.description]
	if desc_panel.visible and lbl.text == new_text:
		desc_panel.visible = false
	else:
		lbl.text = new_text
		desc_panel.visible = true

func _get_item_color(item: Item) -> Color:
	match item.item_type:
		Item.ItemType.HP_RESTORE:   return Color(0.2, 0.9, 0.4)
		Item.ItemType.MP_RESTORE:   return Color(0.3, 0.65, 1.0)
		Item.ItemType.REVIVAL:      return Color(1.0, 0.85, 0.2)
		Item.ItemType.BUFF:         return Color(0.85, 0.6, 1.0)
		Item.ItemType.ANTIDOTE:     return Color(0.4, 0.9, 0.7)
		Item.ItemType.DAMAGE:       return Color(0.95, 0.35, 0.15)
		Item.ItemType.DEBUFF:       return Color(0.8, 0.3, 0.5)
	return Color.WHITE

func _get_effect_text(item: Item) -> String:
	match item.item_type:
		Item.ItemType.HP_RESTORE:  return "+%d HP" % item.effect_value
		Item.ItemType.MP_RESTORE:  return "+%d MP" % item.effect_value
		Item.ItemType.REVIVAL:     return "Revive"
		Item.ItemType.BUFF:        return "+%d %s" % [item.effect_value, item.effect_stat]
		Item.ItemType.ANTIDOTE:    return "Cure"
		Item.ItemType.DAMAGE:      return "-%d HP" % item.effect_value
		Item.ItemType.DEBUFF:      return item.effect_stat
	return ""

func _get_test_items() -> Array:
	# Test items when no inventory is connected
	var items = []

	var potion = Item.new()
	potion.item_name = "Health Potion"
	potion.description = "Restores 50 HP to one ally."
	potion.item_type = Item.ItemType.HP_RESTORE
	potion.effect_value = 50
	potion.quantity = 3
	potion.target_type = Item.TargetType.SINGLE_ALLY
	items.append(potion)

	var mp_potion = Item.new()
	mp_potion.item_name = "Mana Potion"
	mp_potion.description = "Restores 30 MP to one ally."
	mp_potion.item_type = Item.ItemType.MP_RESTORE
	mp_potion.effect_value = 30
	mp_potion.quantity = 2
	mp_potion.target_type = Item.TargetType.SINGLE_ALLY
	items.append(mp_potion)

	var elixir = Item.new()
	elixir.item_name = "Elixir"
	elixir.description = "Restores 100 HP to all allies."
	elixir.item_type = Item.ItemType.HP_RESTORE
	elixir.effect_value = 100
	elixir.quantity = 1
	elixir.target_type = Item.TargetType.ALL_ALLIES
	items.append(elixir)

	var revive = Item.new()
	revive.item_name = "Phoenix Down"
	revive.description = "Revives a defeated ally with 50% HP."
	revive.item_type = Item.ItemType.REVIVAL
	revive.effect_value = 50
	revive.quantity = 1
	revive.target_type = Item.TargetType.SINGLE_ALLY
	items.append(revive)

	var antidote = Item.new()
	antidote.item_name = "Antidote"
	antidote.description = "Cures poison and burn from one ally."
	antidote.item_type = Item.ItemType.ANTIDOTE
	antidote.effect_value = 0
	antidote.quantity = 2
	antidote.target_type = Item.TargetType.SINGLE_ALLY
	items.append(antidote)

	var bomb = Item.new()
	bomb.item_name = "Fire Bomb"
	bomb.description = "Deals 40 fire damage to all enemies."
	bomb.item_type = Item.ItemType.DAMAGE
	bomb.effect_value = 40
	bomb.quantity = 2
	bomb.target_type = Item.TargetType.ALL_ENEMIES
	items.append(bomb)

	return items

# Themes a VScrollBar to match the amethyst aesthetic — dark plum track, a
# softer-plum grabber that brightens on hover/press. Centralized here so the
# inventory menu (and any future scrollable battle menu) can share it.
func _style_scrollbar(bar: VScrollBar) -> void:
	if bar == null:
		return
	bar.custom_minimum_size.x = 5

	# Track (the channel the grabber slides in)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.06, 0.05, 0.10, 0.85)
	track.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)

	# Grabber default
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(0.45, 0.30, 0.70, 0.85)
	grabber.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("grabber", grabber)

	# Grabber hover
	var grabber_hover := grabber.duplicate()
	grabber_hover.bg_color = Color(0.62, 0.42, 0.92, 0.95)
	bar.add_theme_stylebox_override("grabber_highlight", grabber_hover)

	# Grabber pressed
	var grabber_pressed := grabber.duplicate()
	grabber_pressed.bg_color = Color(0.75, 0.55, 1.00, 1.0)
	bar.add_theme_stylebox_override("grabber_pressed", grabber_pressed)
