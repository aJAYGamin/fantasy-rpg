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
#
# max_width > 0 caps how wide the row may get: chips that would push past it
# fold into one trailing "+N" chip whose tooltip lists them. Hero panels size
# themselves to their content, so an uncapped row with many effects widened the
# panel and shoved its neighbours sideways. 0 (the default) means no cap.
static func populate_row(row: HBoxContainer, character, max_width: float = 0.0) -> void:
	if row == null:
		return
	# Detach before freeing. queue_free() alone leaves the old chips as children
	# until the end of the frame, and an area attack rebuilds every row once per
	# target in the same frame — so the row briefly held several sets of chips
	# and the panel sized to it jumped wider on every enemy attack.
	for child in row.get_children():
		row.remove_child(child)
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

	if added and max_width > 0.0:
		_fold_overflow(row, max_width)

	if added:
		row.show()
	else:
		row.hide()

# Replaces the tail of an over-wide row with a "+N" chip until it fits. Widths
# are measured on the live row: a chip only knows its size once it is in the
# tree, where its font resolves.
static func _fold_overflow(row: HBoxContainer, max_width: float) -> void:
	if row.get_combined_minimum_size().x <= max_width:
		return
	var more := _build_chip("", "", Color(0.30, 0.24, 0.40), Color(0.72, 0.55, 1.0),
			_BUFF_CHIP_HEIGHT, "")
	row.add_child(more)
	var hidden: Array[String] = []
	# Keep at least one real chip, so the row never shows "+N" alone.
	while row.get_child_count() > 2 and row.get_combined_minimum_size().x > max_width:
		var victim: Control = row.get_child(row.get_child_count() - 2)
		hidden.push_front(victim.tooltip_text)
		row.remove_child(victim)
		victim.free()
		_set_chip_text(more, "+%d" % hidden.size())
	more.tooltip_text = "\n".join(hidden)
	more.set_meta("hidden_count", hidden.size())

# The chip's single text label (built by _build_chip with an empty icon).
static func _set_chip_text(chip: PanelContainer, text: String) -> void:
	var hb := chip.get_child(0)
	var lbl: Label
	if hb.get_child_count() == 0:
		lbl = Label.new()
		lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		lbl.add_theme_font_size_override("font_size", 9)
		var f := _font(_CINZEL_BOLD_PATH)
		if f: lbl.add_theme_font_override("font", f)
		hb.add_child(lbl)
	else:
		lbl = hb.get_child(0)
	lbl.text = text

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
