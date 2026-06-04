extends PanelContainer

## ResonanceMenu.gd
## Shows when player clicks Resonance button.
## Displays solo ultimate + combined options with other full-resonance heroes,
## plus the triple-resonance attack when all three heroes are full.
##
## Visual design:
##   - Themed dark panel with rounded amethyst-purple border
##   - Centered title
##   - Each attack is a wide button: name in element-mixed gradient (RichTextLabel),
##     plus a "?" info button to the right
##   - Solo attacks use the hero's element color; combined attacks use a
##     gradient across the participating heroes' elements; the triple uses
##     a 3-color sweep across all three.

signal resonance_action_selected(action_type: String, heroes: Array, targets: Array)
signal menu_closed

# Combined attack names — key is sorted hero names joined with "+"
# Add your hero pairs here as you create more characters
const COMBINED_ATTACK_NAMES = {
	"Aria+Kael":        "Aquatic Pyre",
	"Aria+Lyra":        "Hydraulic Cyclone",
	"Kael+Lyra":        "Ember Dawn",
	# Triple resonance names
	"Aria+Kael+Lyra":   "Amethyst Requiem",
	# Add more pairs/triples here as needed
}

# Visual constants tuned to read cleanly in the cramped action bar.
const MENU_BORDER := Color(0.55, 0.35, 0.95)      # amethyst purple for the container border
const MENU_BG := Color(0.07, 0.05, 0.12, 0.96)    # near-black plum
const SUBTITLE_COLOR := Color(0.78, 0.65, 0.95)
const BUTTON_BG := Color(0.14, 0.10, 0.20, 0.95)
const BUTTON_HOVER_BG := Color(0.22, 0.16, 0.32, 1.0)
const BUTTON_PRESSED_BG := Color(0.30, 0.22, 0.45, 1.0)
const BUTTON_BORDER := Color(0.50, 0.35, 0.80, 0.85)

var _current_hero: Character = null
var _battle_manager: BattleManager = null
var _resonance_system: ResonanceSystem = null

func _ready():
	hide()

func _input(event):
	if not visible:
		return
	# Back: controller B / Esc (ui_cancel) or Backspace returns to the action menu.
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_BACKSPACE):
		close()
		get_viewport().set_input_as_handled()

func setup(battle_mgr: BattleManager, res_system: ResonanceSystem):
	_battle_manager = battle_mgr
	_resonance_system = res_system

func show_menu(hero: Character):
	_current_hero = hero
	_build_menu()
	show()
	GameManager.register_focus_scope(self)

func close():
	GameManager.unregister_focus_scope(self)
	hide()
	# Tear down the description popup (it lives on the parent, so it won't be
	# freed automatically when this menu hides).
	var host := get_parent()
	if host != null:
		var desc_panel = host.get_node_or_null("ResonanceDescPanel")
		if desc_panel != null:
			desc_panel.queue_free()
	emit_signal("menu_closed")

func _build_menu():
	for child in get_children():
		child.queue_free()

	var cinzel = load("res://fonts/Cinzel-Regular.ttf")
	var cinzel_bold = load("res://fonts/Cinzel-Bold.ttf")

	# Self IS the themed panel (this node is a PanelContainer). It auto-grows
	# to fit its content and is anchored bottom-right with grow_vertical=BEGIN
	# in the scene, so the menu sizes EXACTLY to however many resonance attacks
	# are available — small for a lone solo, taller when all combined/triple
	# options unlock. No fixed height = no overflow and no empty space.
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = MENU_BG
	panel_style.border_color = MENU_BORDER
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 10
	panel_style.content_margin_right = 10
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8
	panel_style.shadow_color = Color(0, 0, 0, 0.55)
	panel_style.shadow_size = 6
	add_theme_stylebox_override("panel", panel_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	add_child(vbox)

	# --- Title row: centered title with a small back chip on the right ---
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(title_row)

	var title_lbl := Label.new()
	title_lbl.text = "✦  Resonance  ✦"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if cinzel_bold: title_lbl.add_theme_font_override("font", cinzel_bold)
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_lbl.add_theme_color_override("font_color", MENU_BORDER.lerp(Color.WHITE, 0.35))
	title_row.add_child(title_lbl)

	var back_btn := _make_themed_button("← Back", cinzel)
	back_btn.custom_minimum_size = Vector2(58, 22)
	back_btn.pressed.connect(close)
	title_row.add_child(back_btn)

	# --- Solo ultimate ---
	var solo_name: String = (_current_hero.get_meta("ultimate_name")
		if _current_hero.has_meta("ultimate_name") else "Ultimate")
	var solo_desc: String = "%s unleashes their ultimate power!" % _current_hero.character_name
	if _current_hero.has_meta("ultimate_desc"):
		solo_desc = _current_hero.get_meta("ultimate_desc")

	var solo_colors: Array = _element_colors_for_heroes([_current_hero])
	var solo_row := _create_resonance_btn(
		"✦ " + solo_name,
		solo_desc,
		solo_colors,
		cinzel, cinzel_bold
	)
	solo_row.get_meta("main_btn").pressed.connect(_on_solo_ultimate)
	vbox.add_child(solo_row)

	# --- Combined resonance options ---
	var full_heroes := _resonance_system.get_full_resonance_characters()
	full_heroes = full_heroes.filter(func(h): return h != _current_hero)

	if not full_heroes.is_empty():
		# Decorative tier divider (amber, matching the ✦✦ duo theme).
		vbox.add_child(_make_section_divider("✦ Duo Resonance ✦", Color(0.95, 0.78, 0.35)))

		for partner in full_heroes:
			var pair_key := _get_pair_key(_current_hero, partner)
			var combined_name: String = COMBINED_ATTACK_NAMES.get(pair_key, "Resonance Strike")
			var combined_desc := "%s and %s combine their resonance!" % [_current_hero.character_name, partner.character_name]
			var pair_colors: Array = _element_colors_for_heroes([_current_hero, partner])
			var combined_row := _create_resonance_btn(
				"✦✦ " + combined_name,
				combined_desc,
				pair_colors,
				cinzel, cinzel_bold
			)
			combined_row.get_meta("main_btn").pressed.connect(_on_combined_resonance.bind(partner))
			vbox.add_child(combined_row)

	# --- Triple resonance — always check regardless of pairs above ---
	_add_triple_resonance(vbox, cinzel, cinzel_bold)

# Builds a button with element-gradient-colored attack name + a "?" info button.
# colors[] is the list of element colors to gradient across (1, 2, or 3 entries).
func _create_resonance_btn(title: String, subtitle: String, colors: Array, cinzel, cinzel_bold) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)

	# Main button — uses RichTextLabel inside so we can color characters
	# individually for the gradient effect. Fixed-height (the menu auto-grows
	# to fit all rows, so rows don't need to stretch).
	var btn := _make_themed_button("", cinzel)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 30)
	btn.clip_text = false

	# RichTextLabel overlay (Button can't render BBCode natively). Wrapped in a
	# CenterContainer so the label is centered both horizontally AND vertically
	# within the button — the previous [center] only handled horizontal, leaving
	# the text hugging the top.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(center)

	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.autowrap_mode = TextServer.AUTOWRAP_OFF
	rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cinzel_bold: rich.add_theme_font_override("normal_font", cinzel_bold)
	rich.add_theme_font_size_override("normal_font_size", 11)
	# CenterContainer sizes the label to its content and centers it, so no
	# [center] BBCode is needed.
	rich.text = _gradient_bbcode(title, colors)
	center.add_child(rich)

	row.add_child(btn)

	# "?" info button — same themed style, slim.
	var info_btn := _make_themed_button("?", cinzel)
	info_btn.custom_minimum_size = Vector2(22, 28)
	info_btn.pressed.connect(func(): _show_description(subtitle, title))
	row.add_child(info_btn)

	row.set_meta("main_btn", btn)
	return row

# Decorative section divider: a centered tier label flanked by thin lines that
# fade IN toward the text. Replaces the old flat "— Combined Resonance —" label
# and bare separator line for a more polished tier break.
func _make_section_divider(text: String, accent: Color) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Left line — opaque at its RIGHT end so it brightens toward the label.
	row.add_child(_make_divider_line(accent, true))

	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.25))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	var f := BattleUITheme.font_bold()
	if f: lbl.add_theme_font_override("font", f)
	row.add_child(lbl)

	# Right line — opaque at its LEFT end, fading out away from the label.
	row.add_child(_make_divider_line(accent, false))

	return row

# A thin horizontal gradient line for section dividers. solid_at_end=true →
# opaque on the right (left-side line); false → opaque on the left (right-side
# line). The fade makes the divider feel like it emanates from the label.
func _make_divider_line(color: Color, solid_at_end: bool) -> TextureRect:
	var grad := Gradient.new()
	var clear := Color(color.r, color.g, color.b, 0.0)
	var solid := Color(color.r, color.g, color.b, 0.80)
	if solid_at_end:
		grad.set_color(0, clear)
		grad.set_color(1, solid)
	else:
		grad.set_color(0, solid)
		grad.set_color(1, clear)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 80
	tex.height = 2
	var line := TextureRect.new()
	line.texture = tex
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.custom_minimum_size = Vector2(24, 2)
	line.stretch_mode = TextureRect.STRETCH_SCALE
	return line

# Builds BBCode that colors each character along a gradient through `colors`.
# - 1 color  → flat fill
# - 2 colors → linear lerp from start to end across the string
# - 3 colors → first->middle for first half, middle->last for second half
func _gradient_bbcode(text: String, colors: Array) -> String:
	if colors.is_empty():
		return text
	if colors.size() == 1:
		return "[color=#%s]%s[/color]" % [colors[0].to_html(false), text]

	var n := text.length()
	if n == 0:
		return text
	var out := ""
	for i in range(n):
		var ch := text[i]
		if ch == " ":
			# Don't tint spaces — they're invisible anyway and skipping keeps
			# the BBCode shorter.
			out += " "
			continue
		var t: float = float(i) / float(max(1, n - 1))  # 0..1 across the string
		var c: Color = _sample_gradient(colors, t)
		out += "[color=#%s]%s[/color]" % [c.to_html(false), ch]
	return out

# Samples a color from a 2- or 3-stop gradient at position t (0..1).
func _sample_gradient(colors: Array, t: float) -> Color:
	t = clamp(t, 0.0, 1.0)
	if colors.size() == 2:
		return (colors[0] as Color).lerp(colors[1] as Color, t)
	if colors.size() >= 3:
		# Three-stop: [0..0.5] -> color0->color1, [0.5..1] -> color1->color2.
		if t < 0.5:
			return (colors[0] as Color).lerp(colors[1] as Color, t / 0.5)
		else:
			return (colors[1] as Color).lerp(colors[2] as Color, (t - 0.5) / 0.5)
	return colors[0]

# Element colors for a group of heroes. For a single hero who is dual-typed,
# we include BOTH of their element colors so even solo attacks can show a
# subtle gradient when the hero is dual-element.
func _element_colors_for_heroes(heroes: Array) -> Array:
	var out: Array = []
	for h in heroes:
		var primary: Color = ElementalSystem.get_element_color(h.element)
		out.append(primary)
		if h.secondary_element != ElementalSystem.Element.NORMAL \
				and h.secondary_element != h.element:
			out.append(ElementalSystem.get_element_color(h.secondary_element))
	# Ensure at least one color
	if out.is_empty():
		out.append(Color.WHITE)
	return out

func _show_description(desc: String, attack_name: String):
	# DescPanel lives on the PARENT (UIRoot), not on self — self is now a
	# PanelContainer that would lay out any child into its panel area. Parenting
	# the popup to UIRoot lets us free-position it above the menu.
	var host := get_parent()
	if host == null:
		return
	var desc_panel = host.get_node_or_null("ResonanceDescPanel")
	if desc_panel == null:
		var cinzel = load("res://fonts/Cinzel-Regular.ttf")
		desc_panel = PanelContainer.new()
		desc_panel.name = "ResonanceDescPanel"
		var desc_style := StyleBoxFlat.new()
		desc_style.bg_color = MENU_BG
		desc_style.border_color = MENU_BORDER
		desc_style.set_border_width_all(2)
		desc_style.set_corner_radius_all(8)
		desc_style.content_margin_left = 10
		desc_style.content_margin_right = 10
		desc_style.content_margin_top = 5
		desc_style.content_margin_bottom = 5
		desc_panel.add_theme_stylebox_override("panel", desc_style)
		var lbl := Label.new()
		lbl.name = "DescLbl"
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if cinzel: lbl.add_theme_font_override("font", cinzel)
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(0.92, 0.86, 1.0))
		desc_panel.add_child(lbl)
		host.add_child(desc_panel)

	# Position above the resonance menu, matching its width.
	desc_panel.custom_minimum_size = Vector2(size.x, 46)
	desc_panel.size = Vector2(size.x, 46)
	desc_panel.global_position = global_position + Vector2(0, -52)

	var lbl: Label = desc_panel.get_node("DescLbl")
	var new_text := "%s — %s" % [attack_name, desc]
	if desc_panel.visible and lbl.text == new_text:
		desc_panel.visible = false
	else:
		lbl.text = new_text
		desc_panel.visible = true

func _add_triple_resonance(vbox: VBoxContainer, cinzel, cinzel_bold):
	var all_heroes: Array = _battle_manager.party
	if all_heroes.size() < 3:
		return
	for hero in all_heroes:
		if not _resonance_system.is_full(hero):
			return
	var triple_key := _get_triple_key(all_heroes)
	var triple_name: String = COMBINED_ATTACK_NAMES.get(triple_key, "United Resonance")
	var triple_desc := "All heroes unleash their resonance together!"

	# Decorative tier divider (bright amethyst, matching the ✦✦✦ trio theme).
	vbox.add_child(_make_section_divider("✦ Trio Resonance ✦", Color(0.72, 0.50, 1.00)))

	var triple_colors: Array = _element_colors_for_heroes(all_heroes)
	var triple_row := _create_resonance_btn(
		"✦✦✦ " + triple_name,
		triple_desc,
		triple_colors,
		cinzel, cinzel_bold
	)
	triple_row.get_meta("main_btn").pressed.connect(_on_triple_resonance.bind(all_heroes))
	vbox.add_child(triple_row)

func _on_triple_resonance(heroes: Array):
	var typed_heroes: Array[Character] = []
	for h in heroes:
		typed_heroes.append(h)
	if not _resonance_system.spend_combined_resonance(typed_heroes):
		return
	var targets = _battle_manager.get_alive_enemies()
	emit_signal("resonance_action_selected", "triple", Array(typed_heroes), Array(targets))
	close()

func _get_triple_key(heroes: Array) -> String:
	var names: Array = []
	for h in heroes:
		names.append(h.character_name)
	names.sort()
	return "+".join(names)

func _get_pair_key(hero_a: Character, hero_b: Character) -> String:
	var names := [hero_a.character_name, hero_b.character_name]
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

# Themed button: amethyst-tinted bg, accent border on hover/press. Centralized
# so every button in this menu looks consistent.
func _make_themed_button(text: String, font: FontFile) -> Button:
	var b := Button.new()
	b.text = text
	if font: b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", Color(0.92, 0.86, 1.00))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)

	var normal := StyleBoxFlat.new()
	normal.bg_color = BUTTON_BG
	normal.border_color = BUTTON_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 8
	normal.content_margin_right = 8
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	b.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.bg_color = BUTTON_HOVER_BG
	hover.border_color = MENU_BORDER
	b.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate()
	pressed.bg_color = BUTTON_PRESSED_BG
	pressed.border_color = MENU_BORDER
	b.add_theme_stylebox_override("pressed", pressed)
	return b
