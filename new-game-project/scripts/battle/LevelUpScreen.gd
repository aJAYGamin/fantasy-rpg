extends Control

signal level_up_complete

const STAT_NAMES = ["HP", "MP", "ATK", "DEF", "MAG", "ARC", "SPD"]
const ANIM_DURATION = 0.6

# Per-hero palette is now centralized in HeroPalette so the in-battle hero
# panels and any future hero-themed UI share the same colors.
static func _palette_for(hero_name: String) -> Dictionary:
	return HeroPalette.for_hero(hero_name)

# Slot machine weighted values
# 2-5: 40%, 6-8: 30%, 9-10: 30%
const SLOT_WEIGHTS = {
	2: 10, 3: 10, 4: 10, 5: 10,  # 40%
	6: 10, 7: 10, 8: 10,          # 30%
	9: 15, 10: 15                  # 30%
}

var heroes_to_show: Array[Character] = []
var choices_made: int = 0
var _spinning: bool = false
var _current_spin_label: Label = null
var _current_spin_stat: String = ""
var _current_spin_hero: Character = null
var _spin_timer: float = 0.0
var _spin_interval: float = 0.06
var _spin_slowing: bool = false
var _final_value: int = 0
var _confirmed_stat: String = ""
var _stat_buttons: Dictionary = {}  # hero_name -> {stat -> Button}
# The active scroll-bounce tween on the spinning number label, tracked so it can
# be killed when the spin stops (otherwise it can leave the label off-center).
var _label_tween: Tween = null

func _kill_label_tween() -> void:
	if _label_tween != null and _label_tween.is_valid():
		_label_tween.kill()
	_label_tween = null

func _ready():
	hide()

func _input(event):
	if not visible:
		return
	# Stop the spin: mouse click, or the confirm action (ui_accept covers Enter/
	# Space on keyboard and the A / confirm button on controller).
	if _spinning:
		if (event is InputEventMouseButton and event.pressed) or event.is_action_pressed("ui_accept"):
			_stop_spin()
			get_viewport().set_input_as_handled()
		return
	# Cancel stat selection: controller B / Esc (ui_cancel) or Backspace.
	if _confirmed_stat != "":
		if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_BACKSPACE):
			_cancel_confirmation()
			get_viewport().set_input_as_handled()

func show_level_ups(heroes: Array[Character]):
	if heroes.is_empty():
		emit_signal("level_up_complete")
		return
	heroes_to_show = heroes
	choices_made = 0
	show()
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.4)
	await tween.finished
	_build_panels()

func _build_panels():
	for child in $PanelsRow.get_children():
		child.queue_free()
	_stat_buttons.clear()

	var cinzel_bold = load("res://fonts/Cinzel-Bold.ttf")
	var cinzel = load("res://fonts/Cinzel-Regular.ttf")

	for hero in heroes_to_show:
		var panel = _create_hero_panel(hero, cinzel, cinzel_bold)
		$PanelsRow.add_child(panel)

	await get_tree().create_timer(0.3).timeout
	for i in range(heroes_to_show.size()):
		var panel = $PanelsRow.get_child(i)
		_animate_stats(panel, heroes_to_show[i])

	# Central focus guard makes the stat-choice buttons selectable and maintains
	# controller focus as panels resolve.
	GameManager.register_focus_scope(self)

func _create_hero_panel(hero: Character, cinzel: FontFile, cinzel_bold: FontFile) -> PanelContainer:
	var palette = _palette_for(hero.character_name)

	# Themed panel — colors derived from the hero's accent.
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(240, 0)
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = palette["panel_bg"]
	panel_style.border_color = palette["accent"]
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 18
	panel_style.content_margin_right = 18
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", panel_style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# Banner: small "LEVEL UP" line above the hero name for celebratory framing.
	var banner = Label.new()
	banner.text = "✦  LEVEL UP  ✦"
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if cinzel: banner.add_theme_font_override("font", cinzel)
	banner.add_theme_font_size_override("font_size", 11)
	banner.add_theme_color_override("font_color", palette["accent"])
	vbox.add_child(banner)

	# Hero name — larger, accent color, bold.
	var name_lbl = Label.new()
	name_lbl.text = hero.character_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if cinzel_bold: name_lbl.add_theme_font_override("font", cinzel_bold)
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", palette["accent"])
	vbox.add_child(name_lbl)

	# New level subtitle.
	var lvl_lbl = Label.new()
	lvl_lbl.text = "Reached Level %d" % hero.level
	lvl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if cinzel: lvl_lbl.add_theme_font_override("font", cinzel)
	lvl_lbl.add_theme_font_size_override("font_size", 12)
	lvl_lbl.add_theme_color_override("font_color", palette["subtitle"])
	vbox.add_child(lvl_lbl)

	# Themed separator — hero-tinted thin line.
	var sep_wrap = MarginContainer.new()
	sep_wrap.add_theme_constant_override("margin_top", 4)
	sep_wrap.add_theme_constant_override("margin_bottom", 4)
	vbox.add_child(sep_wrap)
	var sep_line = ColorRect.new()
	sep_line.color = palette["separator"]
	sep_line.custom_minimum_size = Vector2(0, 1)
	sep_wrap.add_child(sep_line)

	# Stat rows — one independent HBoxContainer per stat. Using a single
	# GridContainer made the rows fragile: any time a child got freed (or its
	# index changed), every row after it would shift sideways. Independent rows
	# can't influence each other's column alignment.
	var old_stats = _get_old_stats(hero)
	var new_stats = _get_new_stats(hero)

	var stat_rows = VBoxContainer.new()
	stat_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_rows.add_theme_constant_override("separation", 4)
	vbox.add_child(stat_rows)

	for stat in STAT_NAMES:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		stat_rows.add_child(row)

		var stat_lbl = Label.new()
		stat_lbl.text = stat
		stat_lbl.custom_minimum_size = Vector2(40, 0)
		if cinzel: stat_lbl.add_theme_font_override("font", cinzel)
		stat_lbl.add_theme_font_size_override("font_size", 12)
		stat_lbl.add_theme_color_override("font_color", palette["label"])
		row.add_child(stat_lbl)

		var val_lbl = Label.new()
		val_lbl.name = "Val_%s_%s" % [hero.character_name, stat]
		val_lbl.text = str(old_stats[stat])
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_lbl.custom_minimum_size = Vector2(42, 0)
		val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if cinzel_bold: val_lbl.add_theme_font_override("font", cinzel_bold)
		val_lbl.add_theme_font_size_override("font_size", 13)
		val_lbl.add_theme_color_override("font_color", palette["value"])
		row.add_child(val_lbl)

		var diff = new_stats[stat] - old_stats[stat]
		var inc_lbl = Label.new()
		inc_lbl.name = "Inc_%s_%s" % [hero.character_name, stat]
		inc_lbl.text = _format_diff(diff)
		inc_lbl.custom_minimum_size = Vector2(34, 0)
		inc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		inc_lbl.modulate.a = 0.0
		if cinzel_bold: inc_lbl.add_theme_font_override("font", cinzel_bold)
		inc_lbl.add_theme_font_size_override("font_size", 12)
		inc_lbl.add_theme_color_override("font_color", palette["increment"])
		row.add_child(inc_lbl)

	return panel

func _animate_stats(panel: PanelContainer, hero: Character):
	var old_stats = _get_old_stats(hero)
	var new_stats = _get_new_stats(hero)
	var cinzel = load("res://fonts/Cinzel-Regular.ttf")

	for stat in STAT_NAMES:
		var val_lbl = _find_node("Val_%s_%s" % [hero.character_name, stat], panel)
		var inc_lbl = _find_node("Inc_%s_%s" % [hero.character_name, stat], panel)
		if val_lbl == null:
			continue

		var old_val = old_stats[stat]
		var new_val = new_stats[stat]

		# Fade in increment
		await get_tree().create_timer(0.3).timeout
		if inc_lbl:
			var t1 = create_tween()
			t1.tween_property(inc_lbl, "modulate:a", 1.0, 0.25)

		# Count up
		var tween = create_tween()
		tween.tween_method(
			func(v: float):
				val_lbl.text = str(int(v))
				val_lbl.add_theme_color_override("font_color", Color.WHITE),
			float(old_val), float(new_val), ANIM_DURATION
		)
		await tween.finished

		# Fade out increment — keep the node in the grid (just invisible) so the
		# row layout stays aligned. queue_free here would collapse subsequent cells.
		if inc_lbl:
			var fade = create_tween()
			fade.tween_property(inc_lbl, "modulate:a", 0.0, 0.3)
			await fade.finished

	# All stats done — show bonus picker after delay
	await get_tree().create_timer(0.5).timeout
	_show_bonus_picker(panel, hero, cinzel)

func _show_bonus_picker(panel: PanelContainer, hero: Character, cinzel):
	var vbox = panel.get_child(0)
	var palette = _palette_for(hero.character_name)

	# Themed separator (matches the one above the stat grid).
	var sep_wrap = MarginContainer.new()
	sep_wrap.add_theme_constant_override("margin_top", 6)
	sep_wrap.add_theme_constant_override("margin_bottom", 4)
	vbox.add_child(sep_wrap)
	var sep_line = ColorRect.new()
	sep_line.color = palette["separator"]
	sep_line.custom_minimum_size = Vector2(0, 1)
	sep_wrap.add_child(sep_line)

	var pick_lbl = Label.new()
	pick_lbl.name = "PickLabel_%s" % hero.character_name
	pick_lbl.text = "Choose a Stat to Upgrade"
	pick_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if cinzel: pick_lbl.add_theme_font_override("font", cinzel)
	pick_lbl.add_theme_font_size_override("font_size", 13)
	pick_lbl.add_theme_color_override("font_color", palette["accent"])
	vbox.add_child(pick_lbl)

	# Two centered HBox rows so the second (incomplete) row stays centered.
	# A GridContainer would left-align the trailing row of buttons.
	var rows_container = VBoxContainer.new()
	rows_container.name = "BtnGrid_%s" % hero.character_name
	rows_container.add_theme_constant_override("separation", 8)
	rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(rows_container)

	_stat_buttons[hero.character_name] = {}

	# Split into halves: top row gets the first half (rounded up), bottom row the rest.
	# For 7 stats → 4 on top, 3 on bottom; both rows are independently centered.
	var split: int = int(ceil(STAT_NAMES.size() / 2.0))
	var top_row = HBoxContainer.new()
	top_row.alignment = BoxContainer.ALIGNMENT_CENTER
	top_row.add_theme_constant_override("separation", 6)
	rows_container.add_child(top_row)

	var bottom_row = HBoxContainer.new()
	bottom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_row.add_theme_constant_override("separation", 6)
	rows_container.add_child(bottom_row)

	for i in range(STAT_NAMES.size()):
		var stat = STAT_NAMES[i]
		var btn = _make_themed_button(stat, cinzel, false, palette)
		btn.custom_minimum_size = Vector2(60, 28)
		if i < split:
			top_row.add_child(btn)
		else:
			bottom_row.add_child(btn)
		_stat_buttons[hero.character_name][stat] = btn
		btn.pressed.connect(_on_stat_selected.bind(hero, stat, panel, cinzel))

func _on_stat_selected(hero: Character, stat: String, panel: PanelContainer, cinzel):
	if _spinning:
		return
	# Same stat clicked again — do nothing
	if _confirmed_stat == stat and _current_spin_hero == hero:
		return
	_confirmed_stat = stat
	_current_spin_hero = hero
	_update_confirmation(hero, stat, panel, cinzel)

func _update_confirmation(hero: Character, stat: String, panel: PanelContainer, cinzel):
	var vbox = panel.get_child(0)
	# Find existing confirm button or create it once
	var confirm_btn = _find_node("ConfirmBtn_%s" % hero.character_name, panel)
	if confirm_btn == null:
		# First time — create the themed, centered confirm button using the hero palette.
		var palette = _palette_for(hero.character_name)
		confirm_btn = _make_themed_button("", cinzel, true, palette)
		confirm_btn.name = "ConfirmBtn_%s" % hero.character_name
		confirm_btn.custom_minimum_size = Vector2(200, 34)
		confirm_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(confirm_btn)
		# Connect once
		confirm_btn.pressed.connect(func():
			confirm_btn.queue_free()
			_start_spin(hero, _confirmed_stat, panel, cinzel)
		)
	# Just update the text
	confirm_btn.text = "Yes, Upgrade %s!" % stat

func _cancel_confirmation():
	if _current_spin_hero == null:
		return
	var panel = _find_panel_for_hero(_current_spin_hero)
	if panel == null:
		return
	var confirm_btn = _find_node("ConfirmBtn_%s" % _current_spin_hero.character_name, panel)
	if confirm_btn:
		confirm_btn.queue_free()
	_confirmed_stat = ""
	_current_spin_hero = null

func _start_spin(hero: Character, stat: String, panel: PanelContainer, cinzel):
	# Disable all stat buttons
	if _stat_buttons.has(hero.character_name):
		for s in _stat_buttons[hero.character_name]:
			_stat_buttons[hero.character_name][s].disabled = true

	# Hide picker UI
	var btn_grid = _find_node("BtnGrid_%s" % hero.character_name, panel)
	var pick_lbl = _find_node("PickLabel_%s" % hero.character_name, panel)
	if btn_grid: btn_grid.hide()
	if pick_lbl: pick_lbl.hide()

	_current_spin_stat = stat
	_spinning = true
	_spin_slowing = false
	_final_value = _get_weighted_random()

	# Create slot machine display
	var vbox = panel.get_child(0)

	var slot_lbl_title = Label.new()
	slot_lbl_title.text = "Spinning %s bonus..." % stat
	slot_lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if cinzel: slot_lbl_title.add_theme_font_override("font", cinzel)
	slot_lbl_title.add_theme_font_size_override("font_size", 11)
	slot_lbl_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	vbox.add_child(slot_lbl_title)

	var slot_container = PanelContainer.new()
	slot_container.name = "SlotContainer_%s" % hero.character_name
	slot_container.custom_minimum_size = Vector2(80, 40)
	vbox.add_child(slot_container)

	var slot_lbl = Label.new()
	slot_lbl.name = "SlotLabel_%s" % hero.character_name
	slot_lbl.text = "?"
	slot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if cinzel: slot_lbl.add_theme_font_override("font", cinzel)
	slot_lbl.add_theme_font_size_override("font_size", 22)
	slot_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	slot_container.add_child(slot_lbl)

	var hint_lbl = Label.new()
	hint_lbl.text = "Press Confirm (Enter / A) or click to stop"
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if cinzel: hint_lbl.add_theme_font_override("font", cinzel)
	hint_lbl.add_theme_font_size_override("font_size", 9)
	hint_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(hint_lbl)

	_current_spin_label = slot_lbl
	_spin_numbers(slot_lbl, hero, stat, panel, cinzel)

func _spin_numbers(slot_lbl: Label, hero: Character, stat: String, panel: PanelContainer, cinzel):
	var elapsed = 0.0
	var total_spin_time = 2.5  # Minimum spin time before player can stop
	var interval = 0.06

	while _spinning:
		# Pick random number to display while spinning
		var display_val = _get_weighted_random()
		if slot_lbl and is_instance_valid(slot_lbl):
			# Scroll effect — move label down then snap back
			slot_lbl.text = str(display_val)
			_kill_label_tween()
			_label_tween = create_tween()
			_label_tween.tween_property(slot_lbl, "position:y", 8.0, interval * 0.5)
			_label_tween.tween_property(slot_lbl, "position:y", 0.0, interval * 0.5)

		elapsed += interval
		# Slow down after minimum time
		if elapsed > total_spin_time:
			interval = min(interval * 1.08, 0.25)

		await get_tree().create_timer(interval).timeout

	# Land on final value. Reset position:y — the spin can be stopped mid-scroll
	# tween, which would otherwise leave the number parked off-center (above the
	# box). Kill any in-flight tween on the label first so it can't move it after.
	if slot_lbl and is_instance_valid(slot_lbl):
		_kill_label_tween()
		slot_lbl.position.y = 0.0
		slot_lbl.text = str(_final_value)
		slot_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))

	await get_tree().create_timer(0.8).timeout
	_apply_bonus(hero, stat, panel, cinzel)

func _stop_spin():
	if not _spinning:
		return
	_spinning = false

func _apply_bonus(hero: Character, stat: String, panel: PanelContainer, cinzel):
	var bonus = _final_value

	# Apply bonus to hero stat
	match stat:
		"HP":  hero.base_hp += bonus
		"MP":  hero.base_mp += bonus
		"ATK": hero.base_attack += bonus
		"DEF": hero.base_defense += bonus
		"MAG": hero.base_magic += bonus
		"ARC": hero.base_arcane += bonus
		"SPD": hero.base_speed += bonus

	# Find the stat value label and animate the increase
	var val_lbl = _find_node("Val_%s_%s" % [hero.character_name, stat], panel)
	var old_val = 0
	if val_lbl:
		old_val = int(val_lbl.text)

	# Reuse the existing increment label (the one created in _create_hero_panel
	# and faded out after the stat animation). Inserting a new Label here would
	# shift every subsequent grid cell, breaking SPD's row alignment.
	if val_lbl:
		var inc = _find_node("Inc_%s_%s" % [hero.character_name, stat], panel)
		if inc:
			inc.text = _format_diff(bonus)
			inc.modulate.a = 0.0
			var t1 = create_tween()
			t1.tween_property(inc, "modulate:a", 1.0, 0.3)
			await t1.finished

		# Count up stat value
		var new_val = old_val + bonus
		var tween = create_tween()
		tween.tween_method(
			func(v: float): val_lbl.text = str(int(v)),
			float(old_val), float(new_val), 0.8
		)
		await tween.finished

		# Fade out increment but DON'T free it — the inc_lbl reserves the right-hand
		# column width. Removing the node lets val_lbl (SIZE_EXPAND_FILL) eat that
		# space and shifts its right-aligned text to the row's right edge, breaking
		# alignment with the other (un-upgraded) rows.
		if inc:
			var fade = create_tween()
			fade.tween_property(inc, "modulate:a", 0.0, 0.3)
			await fade.finished

	# Done — increment choices made
	choices_made += 1
	if choices_made >= heroes_to_show.size():
		await get_tree().create_timer(0.8).timeout
		var out = create_tween()
		out.tween_property(self, "modulate:a", 0.0, 0.4)
		await out.finished
		GameManager.unregister_focus_scope(self)
		hide()
		emit_signal("level_up_complete")

func _get_weighted_random() -> int:
	var roll = randi() % 100
	if roll < 40:
		return randi_range(2, 5)
	elif roll < 70:
		return randi_range(6, 8)
	else:
		return randi_range(9, 10)

# Sign-safe delta text: "+3" for positive, "0" for none, "-2" for negative
# (never the broken "+-2" that "+%d" produces for a negative value).
func _format_diff(diff: int) -> String:
	if diff > 0:
		return "+%d" % diff
	return str(diff)

# Per-level stat growth (must match Character's getters: each level adds these).
const LEVEL_GROWTH := {
	"HP": 15, "MP": 8, "ATK": 2, "DEF": 1, "MAG": 2, "ARC": 1, "SPD": 1,
}

# Old stats = the hero's CURRENT total (equipment + status included, same basis as
# _get_new_stats) minus this level's growth. Computing old as "new − growth" keeps
# both columns on the same basis, so the diff is exactly the level gain (always
# the positive growth) and never goes negative because of stat-reducing gear.
func _get_old_stats(hero: Character) -> Dictionary:
	var new_stats := _get_new_stats(hero)
	return {
		"HP":  new_stats["HP"] - LEVEL_GROWTH["HP"],
		"MP":  new_stats["MP"] - LEVEL_GROWTH["MP"],
		"ATK": new_stats["ATK"] - LEVEL_GROWTH["ATK"],
		"DEF": new_stats["DEF"] - LEVEL_GROWTH["DEF"],
		"MAG": new_stats["MAG"] - LEVEL_GROWTH["MAG"],
		"ARC": new_stats["ARC"] - LEVEL_GROWTH["ARC"],
		"SPD": new_stats["SPD"] - LEVEL_GROWTH["SPD"],
	}

func _get_new_stats(hero: Character) -> Dictionary:
	return {
		"HP":  hero.max_hp(),
		"MP":  hero.max_mp(),
		"ATK": hero.attack_power(),
		"DEF": hero.defense_power(),
		"MAG": hero.magic_power(),
		"ARC": hero.arcane_power(),
		"SPD": hero.speed(),
	}

func _find_panel_for_hero(hero: Character) -> PanelContainer:
	for i in range(heroes_to_show.size()):
		if heroes_to_show[i] == hero:
			if i < $PanelsRow.get_child_count():
				return $PanelsRow.get_child(i)
	return null

func _find_node(node_name: String, parent: Node) -> Node:
	for child in parent.get_children():
		if child.name == node_name:
			return child
		var found = _find_node(node_name, child)
		if found:
			return found
	return null

# Themed button using a hero palette. `accent` = highlighted (confirm button) —
# uses the brighter accent color for text so the primary action pops.
func _make_themed_button(text: String, font: FontFile, accent: bool, palette: Dictionary) -> Button:
	var b = Button.new()
	b.text = text
	if font: b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", palette["accent"] if accent else palette["subtitle"])
	b.add_theme_color_override("font_hover_color", palette["accent"])
	b.add_theme_color_override("font_pressed_color", palette["accent"])

	var normal = StyleBoxFlat.new()
	normal.bg_color = palette["button_bg"]
	normal.border_color = palette["border"]
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	b.add_theme_stylebox_override("normal", normal)

	var hover = normal.duplicate()
	hover.bg_color = palette["button_hover_bg"]
	hover.border_color = palette["accent"]
	b.add_theme_stylebox_override("hover", hover)

	var pressed = normal.duplicate()
	pressed.bg_color = palette["button_pressed_bg"]
	pressed.border_color = palette["accent"]
	b.add_theme_stylebox_override("pressed", pressed)
	return b
