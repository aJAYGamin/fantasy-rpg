class_name StatusChipFactory
extends RefCounted

## Builds the small rounded status/buff/debuff chips shown beneath the
## resonance bar (heroes) / HP bar (enemies). Centralized here so HeroCard
## and EnemyCard render identical-looking chips.
##
## Visual style: rounded pill, semi-transparent colored bg, faint matching
## border, white compact text. Tooltip on hover gives the full effect name.

const _CINZEL_PATH := "res://fonts/Cinzel-Regular.ttf"
const _CINZEL_BOLD_PATH := "res://fonts/Cinzel-Bold.ttf"

const _STATUS_CHIP_HEIGHT := 18
const _BUFF_CHIP_HEIGHT := 16

const _BUFF_BG := Color(0.32, 0.78, 0.38)      # vibrant green
const _BUFF_BORDER := Color(0.55, 1.00, 0.60)
const _DEBUFF_BG := Color(0.88, 0.32, 0.32)    # crimson
const _DEBUFF_BORDER := Color(1.00, 0.55, 0.55)

static func _font(path: String) -> FontFile:
	# load() returns null if missing; chip text degrades to default font.
	if ResourceLoader.exists(path):
		return load(path)
	return null

# --- Public: populate a row with all active chips for a character. ---
# Clears existing children and rebuilds. Hides the row when nothing to show.
static func populate_row(row: HBoxContainer, character) -> void:
	if row == null:
		return
	for child in row.get_children():
		child.queue_free()
	if character == null:
		row.hide()
		return

	var added := false

	# 1) Single mutex status chip (poison, sleep, etc.) — at most one.
	var active_status: String = StatusSystem.get_active_mutex_status(character)
	if active_status != "":
		row.add_child(_build_status_chip(active_status))
		added = true

	# 2) Buff/debuff chips per stat — cancelled (both present) renders nothing.
	for stat in StatusSystem.BUFFABLE_STATS:
		if StatusSystem.is_effectively_buffed(character, stat):
			row.add_child(_build_buff_chip(stat, true))
			added = true
		elif StatusSystem.is_effectively_debuffed(character, stat):
			row.add_child(_build_buff_chip(stat, false))
			added = true

	if added:
		row.show()
	else:
		row.hide()

# --- Private builders ---

static func _build_status_chip(status_name: String) -> Control:
	var color: Color = StatusSystem.STATUS_COLORS.get(status_name, Color(0.6, 0.6, 0.7))
	var label_text: String = StatusSystem.STATUS_LABELS.get(status_name, status_name.capitalize())
	var icon_text: String = StatusSystem.STATUS_ICONS.get(status_name, "?")
	return _build_chip(
		icon_text,
		label_text,
		color.darkened(0.35),
		color.lightened(0.15),
		_STATUS_CHIP_HEIGHT,
		label_text  # tooltip = full name
	)

static func _build_buff_chip(stat: String, is_buff: bool) -> Control:
	var short: String = StatusSystem.STAT_SHORT.get(stat, stat.to_upper())
	var arrow: String = "▲" if is_buff else "▼"
	var bg: Color = _BUFF_BG if is_buff else _DEBUFF_BG
	var border: Color = _BUFF_BORDER if is_buff else _DEBUFF_BORDER
	var tooltip := "%s %s (%s)" % [
		short,
		("Buffed +100%" if is_buff else "Debuffed -50%"),
		("x2.0" if is_buff else "x0.5")
	]
	return _build_chip(arrow, short, bg, border, _BUFF_CHIP_HEIGHT, tooltip)

# Generic chip: rounded pill with [icon][label] inside an HBox.
static func _build_chip(icon_text: String, label_text: String, bg: Color,
		border: Color, height: int, tooltip: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.tooltip_text = tooltip
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.custom_minimum_size = Vector2(0, height)

	var style := StyleBoxFlat.new()
	# Slightly translucent so chips read as overlays, not solid blocks.
	style.bg_color = Color(bg.r, bg.g, bg.b, 0.92)
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	chip.add_theme_stylebox_override("panel", style)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 3)
	chip.add_child(hb)

	if icon_text != "":
		var icon := Label.new()
		icon.text = icon_text
		icon.add_theme_color_override("font_color", Color(1, 1, 1))
		icon.add_theme_font_size_override("font_size", 10)
		var f := _font(_CINZEL_BOLD_PATH)
		if f: icon.add_theme_font_override("font", f)
		hb.add_child(icon)

	if label_text != "":
		var name_lbl := Label.new()
		name_lbl.text = label_text
		name_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		name_lbl.add_theme_font_size_override("font_size", 9)
		var f2 := _font(_CINZEL_BOLD_PATH)
		if f2: name_lbl.add_theme_font_override("font", f2)
		hb.add_child(name_lbl)

	return chip
