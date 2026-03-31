extends Control

## ResonanceMenu.gd
## Shows when player clicks Resonance button
## Displays solo ultimate and combined options with other full-resonance heroes

signal resonance_action_selected(action_type: String, heroes: Array, targets: Array)
signal menu_closed

# Combined attack names — key is sorted hero names joined with "+"
# Add your hero pairs here as you create more characters
const COMBINED_ATTACK_NAMES = {
	"Aria+Kael":   "Celestial Pyre",
	"Aria+Lyra":   "Moonlit Requiem",
	"Kael+Lyra":   "Ember Dawn",
	# Add more pairs here as needed
}

var _current_hero: Character = null
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

func show_menu(hero: Character):
	_current_hero = hero
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

	# Dark background
	var bg = ColorRect.new()
	bg.color = Color(0.04, 0.02, 0.10, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	# Title row with back button
	var title_row = HBoxContainer.new()
	vbox.add_child(title_row)

	var back_btn = Button.new()
	back_btn.text = "← Back"
	back_btn.custom_minimum_size = Vector2(60, 20)
	if cinzel: back_btn.add_theme_font_override("font", cinzel)
	back_btn.add_theme_font_size_override("font_size", 9)
	back_btn.pressed.connect(close)
	title_row.add_child(back_btn)

	var title_lbl = Label.new()
	title_lbl.text = "— Resonance —"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if cinzel: title_lbl.add_theme_font_override("font", cinzel)
	title_lbl.add_theme_font_size_override("font_size", 11)
	title_lbl.add_theme_color_override("font_color", Color(0.85, 0.6, 1.0))
	title_row.add_child(title_lbl)

	# Solo ultimate button
	var solo_name = _current_hero.get_meta("ultimate_name") if _current_hero.has_meta("ultimate_name") else "Ultimate"
	var solo_desc = "%s unleashes their ultimate power!" % _current_hero.character_name
	if _current_hero.has_meta("ultimate_desc"):
		solo_desc = _current_hero.get_meta("ultimate_desc")
	var solo_row = _create_resonance_btn(
		"💜 %s" % solo_name,
		solo_desc,
		Color(0.75, 0.4, 1.0),
		cinzel, cinzel_bold
	)
	solo_row.get_meta("main_btn").pressed.connect(_on_solo_ultimate)
	vbox.add_child(solo_row)

	# Combined resonance options
	var full_heroes = _resonance_system.get_full_resonance_characters()
	full_heroes = full_heroes.filter(func(h): return h != _current_hero)

	if not full_heroes.is_empty():
		var combined_lbl = Label.new()
		combined_lbl.text = "— Combined Resonance —"
		combined_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if cinzel: combined_lbl.add_theme_font_override("font", cinzel)
		combined_lbl.add_theme_font_size_override("font_size", 9)
		combined_lbl.add_theme_color_override("font_color", Color(0.7, 0.55, 0.9))
		vbox.add_child(combined_lbl)

		for partner in full_heroes:
			# Get unique combined name — always current hero first
			var pair_key = _get_pair_key(_current_hero, partner)
			var combined_name = COMBINED_ATTACK_NAMES.get(pair_key, "Resonance Strike")
			var combined_desc = "%s and %s combine their resonance!" % [_current_hero.character_name, partner.character_name]
			var combined_row = _create_resonance_btn(
				"✦ %s" % combined_name,
				combined_desc,
				Color(1.0, 0.75, 0.3),
				cinzel, cinzel_bold
			)
			combined_row.get_meta("main_btn").pressed.connect(_on_combined_resonance.bind(partner))
			vbox.add_child(combined_row)

func _create_resonance_btn(title: String, subtitle: String, color: Color, cinzel, cinzel_bold) -> HBoxContainer:
	# Outer row: button + ? button side by side
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 2)

	var btn = Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 24)

	var inner = VBoxContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.add_theme_constant_override("separation", 0)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(inner)

	var title_lbl = Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cinzel_bold: title_lbl.add_theme_font_override("font", cinzel_bold)
	title_lbl.add_theme_font_size_override("font_size", 10)
	title_lbl.add_theme_color_override("font_color", color)
	inner.add_child(title_lbl)

	row.add_child(btn)

	# ? button for description
	var desc_btn = Button.new()
	desc_btn.text = "?"
	desc_btn.custom_minimum_size = Vector2(20, 24)
	desc_btn.flat = true
	if cinzel: desc_btn.add_theme_font_override("font", cinzel)
	desc_btn.add_theme_font_size_override("font_size", 10)
	desc_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
	desc_btn.pressed.connect(func(): _show_description(subtitle, title))
	row.add_child(desc_btn)

	# Store main btn reference for connecting pressed signal
	row.set_meta("main_btn", btn)
	return row

func _show_description(desc: String, attack_name: String):
	var desc_panel = get_node_or_null("DescPanel")
	if desc_panel == null:
		var cinzel = load("res://fonts/Cinzel-Regular.ttf")
		desc_panel = PanelContainer.new()
		desc_panel.name = "DescPanel"
		desc_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
		desc_panel.position = Vector2(0, -55)
		desc_panel.custom_minimum_size = Vector2(0, 45)
		var lbl = Label.new()
		lbl.name = "DescLbl"
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if cinzel: lbl.add_theme_font_override("font", cinzel)
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(0.88, 0.82, 1.0))
		desc_panel.add_child(lbl)
		add_child(desc_panel)

	var lbl = desc_panel.get_node("DescLbl")
	var new_text = "%s — %s" % [attack_name, desc]
	if desc_panel.visible and lbl.text == new_text:
		desc_panel.visible = false
	else:
		lbl.text = new_text
		desc_panel.visible = true

func _get_pair_key(hero_a: Character, hero_b: Character) -> String:
	# Always sort alphabetically so Aria+Kael == Kael+Aria in the lookup
	var names = [hero_a.character_name, hero_b.character_name]
	names.sort()
	return "+".join(names)

func _on_solo_ultimate():
	if not _resonance_system.spend_solo_ultimate(_current_hero):
		return
	var targets = _battle_manager.get_alive_enemies()
	emit_signal("resonance_action_selected", "solo", [_current_hero], Array(targets))
	close()

func _on_combined_resonance(partner: Character):
	var heroes: Array[Character] = [_current_hero, partner]
	if not _resonance_system.spend_combined_resonance(heroes):
		return
	var targets = _battle_manager.get_alive_enemies()
	emit_signal("resonance_action_selected", "combined", Array(heroes), Array(targets))
	close()
