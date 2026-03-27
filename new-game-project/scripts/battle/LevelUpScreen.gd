extends Control

signal level_up_complete

const STAT_NAMES = ["HP", "MP", "ATK", "DEF", "MAG", "SPD"]
const ANIM_DURATION = 0.6

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

func _ready():
	hide()

func _input(event):
	if not visible:
		return
	# Stop spin on click or Enter
	if _spinning:
		if event is InputEventMouseButton and event.pressed:
			_stop_spin()
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
			_stop_spin()
	# Cancel stat selection on Backspace
	if _confirmed_stat != "":
		if event is InputEventKey and event.pressed and event.keycode == KEY_BACKSPACE:
			_cancel_confirmation()

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

func _create_hero_panel(hero: Character, cinzel: FontFile, cinzel_bold: FontFile) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(220, 0)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Hero name
	var name_lbl = Label.new()
	name_lbl.text = hero.character_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if cinzel_bold: name_lbl.add_theme_font_override("font", cinzel_bold)
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	vbox.add_child(name_lbl)

	var lvl_lbl = Label.new()
	lvl_lbl.text = "Level Up!  Lv %d" % hero.level
	lvl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if cinzel: lvl_lbl.add_theme_font_override("font", cinzel)
	lvl_lbl.add_theme_font_size_override("font_size", 12)
	lvl_lbl.add_theme_color_override("font_color", Color(0.88, 0.78, 1.0))
	vbox.add_child(lvl_lbl)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Stat rows
	var old_stats = _get_old_stats(hero)
	var new_stats = _get_new_stats(hero)

	for stat in STAT_NAMES:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		vbox.add_child(row)

		var stat_lbl = Label.new()
		stat_lbl.text = stat
		stat_lbl.custom_minimum_size = Vector2(32, 0)
		if cinzel: stat_lbl.add_theme_font_override("font", cinzel)
		stat_lbl.add_theme_font_size_override("font_size", 11)
		stat_lbl.add_theme_color_override("font_color", Color(0.7, 0.65, 0.85))
		row.add_child(stat_lbl)

		var val_lbl = Label.new()
		val_lbl.name = "Val_%s_%s" % [hero.character_name, stat]
		val_lbl.text = str(old_stats[stat])
		val_lbl.custom_minimum_size = Vector2(28, 0)
		if cinzel: val_lbl.add_theme_font_override("font", cinzel)
		val_lbl.add_theme_font_size_override("font_size", 12)
		val_lbl.add_theme_color_override("font_color", Color.WHITE)
		row.add_child(val_lbl)

		var diff = new_stats[stat] - old_stats[stat]
		var inc_lbl = Label.new()
		inc_lbl.name = "Inc_%s_%s" % [hero.character_name, stat]
		inc_lbl.text = "+%d" % diff
		inc_lbl.modulate.a = 0.0
		if cinzel: inc_lbl.add_theme_font_override("font", cinzel)
		inc_lbl.add_theme_font_size_override("font_size", 10)
		inc_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
		row.add_child(inc_lbl)

		# Spacer
		var spacer = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)

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

		# Fade out increment
		if inc_lbl:
			var fade = create_tween()
			fade.tween_property(inc_lbl, "modulate:a", 0.0, 0.3)
			await fade.finished
			inc_lbl.queue_free()

	# All stats done — show bonus picker after delay
	await get_tree().create_timer(0.5).timeout
	_show_bonus_picker(panel, hero, cinzel)

func _show_bonus_picker(panel: PanelContainer, hero: Character, cinzel):
	var vbox = panel.get_child(0)

	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	var pick_lbl = Label.new()
	pick_lbl.name = "PickLabel_%s" % hero.character_name
	pick_lbl.text = "Choose a stat to upgrade:"
	pick_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if cinzel: pick_lbl.add_theme_font_override("font", cinzel)
	pick_lbl.add_theme_font_size_override("font_size", 11)
	pick_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	vbox.add_child(pick_lbl)

	var btn_grid = GridContainer.new()
	btn_grid.name = "BtnGrid_%s" % hero.character_name
	btn_grid.columns = 3
	btn_grid.add_theme_constant_override("h_separation", 6)
	btn_grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(btn_grid)

	_stat_buttons[hero.character_name] = {}

	for stat in STAT_NAMES:
		var btn = Button.new()
		btn.text = stat
		btn.custom_minimum_size = Vector2(60, 28)
		if cinzel: btn.add_theme_font_override("font", cinzel)
		btn.add_theme_font_size_override("font_size", 10)
		btn_grid.add_child(btn)
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
		# First time — create the button
		confirm_btn = Button.new()
		confirm_btn.name = "ConfirmBtn_%s" % hero.character_name
		confirm_btn.custom_minimum_size = Vector2(160, 30)
		if cinzel: confirm_btn.add_theme_font_override("font", cinzel)
		confirm_btn.add_theme_font_size_override("font_size", 10)
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
	hint_lbl.text = "Click or press Enter to stop"
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
			var tween = create_tween()
			tween.tween_property(slot_lbl, "position:y", 8.0, interval * 0.5)
			tween.tween_property(slot_lbl, "position:y", 0.0, interval * 0.5)

		elapsed += interval
		# Slow down after minimum time
		if elapsed > total_spin_time:
			interval = min(interval * 1.08, 0.25)

		await get_tree().create_timer(interval).timeout

	# Land on final value
	if slot_lbl and is_instance_valid(slot_lbl):
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
		"SPD": hero.base_speed += bonus

	# Find the stat value label and animate the increase
	var val_lbl = _find_node("Val_%s_%s" % [hero.character_name, stat], panel)
	var old_val = 0
	if val_lbl:
		old_val = int(val_lbl.text)

	# Show increment label next to stat
	if val_lbl:
		var row = val_lbl.get_parent()
		var inc = Label.new()
		inc.text = "+%d" % bonus
		inc.modulate.a = 0.0
		if cinzel: inc.add_theme_font_override("font", cinzel)
		inc.add_theme_font_size_override("font_size", 10)
		inc.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
		# Insert right after val_lbl (index + 1) so it sits next to the value
		row.add_child(inc)
		row.move_child(inc, val_lbl.get_index() + 1)

		# Fade in increment
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

		# Fade out increment
		var fade = create_tween()
		fade.tween_property(inc, "modulate:a", 0.0, 0.3)
		await fade.finished
		inc.queue_free()

	# Done — increment choices made
	choices_made += 1
	if choices_made >= heroes_to_show.size():
		await get_tree().create_timer(0.8).timeout
		var out = create_tween()
		out.tween_property(self, "modulate:a", 0.0, 0.4)
		await out.finished
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

func _get_old_stats(hero: Character) -> Dictionary:
	return {
		"HP":  hero.base_hp + (hero.level - 2) * 15,
		"MP":  hero.base_mp + (hero.level - 2) * 8,
		"ATK": hero.base_attack + (hero.level - 2) * 2,
		"DEF": hero.base_defense + (hero.level - 2) * 1,
		"MAG": hero.base_magic + (hero.level - 2) * 2,
		"SPD": hero.base_speed + (hero.level - 2) * 1,
	}

func _get_new_stats(hero: Character) -> Dictionary:
	return {
		"HP":  hero.max_hp(),
		"MP":  hero.max_mp(),
		"ATK": hero.attack_power(),
		"DEF": hero.defense_power(),
		"MAG": hero.magic_power(),
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
