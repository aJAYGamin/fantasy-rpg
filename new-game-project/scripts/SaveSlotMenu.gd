extends Control

## SaveSlotMenu — slot picker shown from MainMenu's "New Game" button.
## Each row displays hero icons, levels, location, and playtime for occupied slots,
## or "Empty" for unused ones. Per-slot Copy and Delete actions live on the row.

signal slot_chosen(slot: int)
signal menu_closed

# Color by hero name — matches the colored letter cards on the battlefield.
const HERO_COLORS: Dictionary = {
	"Aria": Color(0.30, 0.65, 1.00),   # mage / water
	"Kael": Color(0.95, 0.35, 0.25),   # warrior / fire
	"Lyra": Color(0.45, 0.85, 0.55),   # healer / wind
}
const DEFAULT_HERO_COLOR := Color(0.6, 0.6, 0.6)

# Themed palette — keep in sync with the title color elsewhere in the menu.
const ACCENT_COLOR := Color(0.85, 0.7, 1.0)
const PANEL_BG_COLOR := Color(0.10, 0.08, 0.16, 0.96)
const PANEL_BORDER_COLOR := Color(0.4, 0.3, 0.55, 1.0)
const TEXT_PRIMARY := Color(0.88, 0.82, 1.0)
const TEXT_SECONDARY := Color(0.7, 0.65, 0.85)
const TEXT_MUTED := Color(0.55, 0.5, 0.65)
const TEXT_DANGER := Color(0.95, 0.6, 0.55)

const MONTH_NAMES := [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
]

var _cinzel: Font
var _cinzel_bold: Font
# "new" = slot picker for New Game (Overwrite & Start + Copy + Delete; empty slots interactive).
# "load" = slot picker for Continue (Load + Copy + Delete; empty slots are non-interactive labels).
var _mode: String = "new"

func _ready() -> void:
	_cinzel = load("res://fonts/Cinzel-Regular.ttf")
	_cinzel_bold = load("res://fonts/Cinzel-Bold.ttf")
	hide()

func open(mode: String = "new") -> void:
	_mode = mode
	_rebuild()
	show()

func _close() -> void:
	hide()
	menu_closed.emit()

# --- Layout ---
func _rebuild() -> void:
	for c in get_children():
		c.queue_free()

	var bg = ColorRect.new()
	bg.color = Color(0.04, 0.02, 0.10, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var v = VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(v)

	# Title — wording reflects the picker's purpose.
	var title = Label.new()
	title.text = "— Load Game —" if _mode == "load" else "— Select a Save Slot —"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _cinzel_bold: title.add_theme_font_override("font", _cinzel_bold)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", ACCENT_COLOR)
	v.add_child(title)

	var rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rows.custom_minimum_size = Vector2(820, 0)
	rows.add_theme_constant_override("separation", 10)
	v.add_child(rows)
	for i in range(GameManager.SAVE_SLOT_COUNT):
		rows.add_child(_build_slot_row(i))

	var back = _styled_button("Back", false)
	back.custom_minimum_size = Vector2(160, 36)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_close)
	v.add_child(back)

func _build_slot_row(slot: int) -> Control:
	var panel = _styled_panel(0, 96)
	# Inner row centered: slot label sits at left, the rest of the content
	# (icons / info / actions) is wrapped in a CenterContainer that occupies
	# the remaining width and centers its children — keeps everything aligned
	# regardless of how much info is shown.
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)

	var slot_lbl = _label("Slot %d" % (slot + 1), _cinzel_bold, 15, ACCENT_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
	slot_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot_lbl.custom_minimum_size = Vector2(72, 0)
	row.add_child(slot_lbl)

	var center = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(center)

	var content = HBoxContainer.new()
	content.add_theme_constant_override("separation", 22)
	center.add_child(content)

	if not GameManager.slot_exists(slot):
		_build_empty_content(content, slot)
	else:
		_build_occupied_content(content, slot)
	return panel

func _build_empty_content(content: HBoxContainer, slot: int) -> void:
	var lbl = _label("— Empty —", _cinzel, 13, TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size = Vector2(200, 0)
	content.add_child(lbl)

	# Load mode: empty slots are non-interactive (nothing to load), so no button.
	if _mode == "load":
		return

	var btn = _styled_button("Start New Game", false)
	btn.custom_minimum_size = Vector2(180, 32)
	btn.pressed.connect(_on_slot_picked.bind(slot, false))
	content.add_child(btn)

func _build_occupied_content(content: HBoxContainer, slot: int) -> void:
	var meta := GameManager.get_slot_metadata(slot)

	# Hero icons cluster
	var icons = HBoxContainer.new()
	icons.add_theme_constant_override("separation", 6)
	icons.alignment = BoxContainer.ALIGNMENT_CENTER
	for h in meta.get("heroes", []):
		icons.add_child(_make_hero_badge(h.get("name", "?"), int(h.get("level", 1))))
	content.add_child(icons)

	# Info column: location + playtime + timestamp
	var info = VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	var area_name: String = str(meta.get("area_name", "")).replace("_", " ").capitalize()
	if area_name == "": area_name = "Unknown Area"
	info.add_child(_label(area_name, _cinzel_bold, 14, TEXT_PRIMARY, HORIZONTAL_ALIGNMENT_CENTER))
	info.add_child(_label("Playtime: " + _format_playtime(float(meta.get("playtime_seconds", 0.0))),
		_cinzel, 11, TEXT_SECONDARY, HORIZONTAL_ALIGNMENT_CENTER))
	var ts_display := _format_timestamp(str(meta.get("timestamp", "")))
	if ts_display != "":
		info.add_child(_label(ts_display, _cinzel, 10, TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	info.custom_minimum_size = Vector2(240, 0)
	content.add_child(info)

	# Actions column (vertically centered)
	var actions = VBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER

	# Primary action: "Load" in load mode, "Overwrite & Start" in new-game mode.
	# In load mode, picking an occupied slot is non-destructive — no confirm needed.
	var primary = _styled_button("Load" if _mode == "load" else "Overwrite & Start", false)
	primary.custom_minimum_size = Vector2(180, 30)
	primary.pressed.connect(_on_slot_picked.bind(slot, true))
	actions.add_child(primary)

	var minor = HBoxContainer.new()
	minor.add_theme_constant_override("separation", 6)
	minor.alignment = BoxContainer.ALIGNMENT_CENTER
	var copy_btn = _styled_button("Copy", false)
	copy_btn.custom_minimum_size = Vector2(86, 26)
	copy_btn.pressed.connect(_on_copy_pressed.bind(slot))
	minor.add_child(copy_btn)
	# Delete is intentionally hidden in load mode — when the user is picking a
	# save to continue, accidental deletion would be too easy.
	if _mode != "load":
		var del_btn = _styled_button("Delete", true)
		del_btn.custom_minimum_size = Vector2(86, 26)
		del_btn.pressed.connect(_on_delete_pressed.bind(slot))
		minor.add_child(del_btn)
	actions.add_child(minor)

	content.add_child(actions)

# --- Hero badge ---
func _make_hero_badge(hero_name: String, level: int) -> Control:
	var wrap = VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon = Label.new()
	icon.text = (hero_name.substr(0, 1) if hero_name.length() > 0 else "?")
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.custom_minimum_size = Vector2(36, 36)
	var color: Color = HERO_COLORS.get(hero_name, DEFAULT_HERO_COLOR)
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	icon.add_theme_stylebox_override("normal", style)
	if _cinzel_bold: icon.add_theme_font_override("font", _cinzel_bold)
	icon.add_theme_font_size_override("font_size", 18)
	icon.add_theme_color_override("font_color", Color(1, 1, 1))
	wrap.add_child(icon)
	var lv = _label("Lv%d" % level, _cinzel, 10, TEXT_PRIMARY, HORIZONTAL_ALIGNMENT_CENTER)
	wrap.add_child(lv)
	return wrap

# --- Formatting ---
func _format_playtime(seconds: float) -> String:
	var h: int = int(seconds / 3600.0)
	var m: int = int(fmod(seconds, 3600.0) / 60.0)
	return "%dh %02dm" % [h, m]

# Converts ISO "2026-05-25T14:31:59" → "2:31 PM May 25, 2026".
func _format_timestamp(iso: String) -> String:
	if iso == "":
		return ""
	# Split "2026-05-25T14:31:59" into date + time.
	var t_idx = iso.find("T")
	if t_idx < 0:
		return iso  # unknown shape; fail soft
	var date_part = iso.substr(0, t_idx)
	var time_part = iso.substr(t_idx + 1)
	var date_segs = date_part.split("-")
	var time_segs = time_part.split(":")
	if date_segs.size() < 3 or time_segs.size() < 2:
		return iso
	var year := int(date_segs[0])
	var month := int(date_segs[1])
	var day := int(date_segs[2])
	var hour_24 := int(time_segs[0])
	var minute := int(time_segs[1])
	var ampm := "AM" if hour_24 < 12 else "PM"
	var hour_12 := hour_24 % 12
	if hour_12 == 0:
		hour_12 = 12
	var month_name = MONTH_NAMES[month - 1] if month >= 1 and month <= 12 else "?"
	return "%d:%02d %s   %s %d, %d" % [hour_12, minute, ampm, month_name, day, year]

# --- Themed primitives ---
func _label(text: String, font: Font, size: int, color: Color, h_align: int) -> Label:
	var l = Label.new()
	l.text = text
	l.horizontal_alignment = h_align
	if font: l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _styled_panel(min_w: float, min_h: float) -> PanelContainer:
	var panel = PanelContainer.new()
	if min_w > 0 or min_h > 0:
		panel.custom_minimum_size = Vector2(min_w, min_h)
	var style = StyleBoxFlat.new()
	style.bg_color = PANEL_BG_COLOR
	style.border_color = PANEL_BORDER_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	return panel

# Themed button with hover/pressed states matching the menu aesthetic.
# `danger` colors the label red (used for Delete / destructive confirm).
func _styled_button(text: String, danger: bool) -> Button:
	var b = Button.new()
	b.text = text
	if _cinzel: b.add_theme_font_override("font", _cinzel)
	b.add_theme_font_size_override("font_size", 12)
	var label_color: Color = TEXT_DANGER if danger else TEXT_PRIMARY
	b.add_theme_color_override("font_color", label_color)
	b.add_theme_color_override("font_hover_color", ACCENT_COLOR)
	b.add_theme_color_override("font_pressed_color", ACCENT_COLOR)
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.06, 0.13, 0.92)
	normal.border_color = PANEL_BORDER_COLOR
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	b.add_theme_stylebox_override("normal", normal)
	var hover = normal.duplicate()
	hover.bg_color = Color(0.18, 0.10, 0.26, 0.96)
	hover.border_color = ACCENT_COLOR
	b.add_theme_stylebox_override("hover", hover)
	var pressed = normal.duplicate()
	pressed.bg_color = Color(0.22, 0.14, 0.32, 0.98)
	pressed.border_color = ACCENT_COLOR
	b.add_theme_stylebox_override("pressed", pressed)
	return b

# Custom themed modal — replaces Godot's stock ConfirmationDialog so the
# overwrite/copy/delete confirmations match the menu's font and colors.
# Returns the modal Control. Caller wires the buttons.
func _make_modal_panel(title_text: String, message_text: String, panel_width: float = 380.0) -> Dictionary:
	var modal = Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_child(dim)

	var center_wrap = CenterContainer.new()
	center_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center_wrap)

	var panel = _styled_panel(panel_width, 0)
	center_wrap.add_child(panel)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var title = _label(title_text, _cinzel_bold, 16, ACCENT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(title)

	if message_text != "":
		var msg = _label(message_text, _cinzel, 12, TEXT_PRIMARY, HORIZONTAL_ALIGNMENT_CENTER)
		msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		msg.custom_minimum_size = Vector2(panel_width - 40, 0)
		v.add_child(msg)

	# Action row container — caller fills it.
	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(actions)
	return {"modal": modal, "actions": actions}

# --- Actions ---
func _on_slot_picked(slot: int, occupied: bool) -> void:
	# Load mode just selects — no overwrite warning regardless of occupied state.
	if _mode == "load":
		slot_chosen.emit(slot)
		return
	if not occupied:
		slot_chosen.emit(slot)
		return
	_show_confirm(
		"Overwrite Slot %d?" % (slot + 1),
		"This save will be lost. This cannot be undone.",
		"Overwrite", true,
		func(): slot_chosen.emit(slot)
	)

func _on_delete_pressed(slot: int) -> void:
	_show_confirm(
		"Delete Slot %d?" % (slot + 1),
		"This save will be lost. This cannot be undone.",
		"Delete", true,
		func():
			GameManager.delete_slot(slot)
			_rebuild()
	)

func _on_copy_pressed(source_slot: int) -> void:
	var built = _make_modal_panel("Copy Slot %d to…" % (source_slot + 1), "")
	var modal: Control = built["modal"]
	var actions: HBoxContainer = built["actions"]
	# Stack destination buttons vertically since labels are long.
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	var stack = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	actions.add_child(stack)
	for s in range(GameManager.SAVE_SLOT_COUNT):
		if s == source_slot:
			continue
		var label_text := "Copy to Slot %d" % (s + 1)
		if GameManager.slot_exists(s):
			label_text += "  (overwrite)"
		var b = _styled_button(label_text, false)
		b.custom_minimum_size = Vector2(240, 30)
		b.pressed.connect(_do_copy.bind(source_slot, s, modal))
		stack.add_child(b)
	var cancel = _styled_button("Cancel", false)
	cancel.custom_minimum_size = Vector2(240, 28)
	cancel.pressed.connect(func(): modal.queue_free())
	stack.add_child(cancel)
	add_child(modal)

func _do_copy(from_slot: int, to_slot: int, picker_modal: Control) -> void:
	if GameManager.slot_exists(to_slot):
		_show_confirm(
			"Overwrite Slot %d?" % (to_slot + 1),
			"Slot %d will be replaced with a copy of Slot %d." % [to_slot + 1, from_slot + 1],
			"Overwrite", true,
			func():
				if is_instance_valid(picker_modal):
					picker_modal.queue_free()
				GameManager.copy_slot(from_slot, to_slot)
				_rebuild()
		)
	else:
		if is_instance_valid(picker_modal):
			picker_modal.queue_free()
		GameManager.copy_slot(from_slot, to_slot)
		_rebuild()

# Themed Yes/Cancel modal. `confirm_text` is the affirmative button label.
# `danger` colors the affirmative red (Delete, Overwrite).
func _show_confirm(title_text: String, message: String, confirm_text: String, danger: bool, on_confirm: Callable) -> void:
	var built = _make_modal_panel(title_text, message)
	var modal: Control = built["modal"]
	var actions: HBoxContainer = built["actions"]
	var cancel = _styled_button("Cancel", false)
	cancel.custom_minimum_size = Vector2(120, 30)
	cancel.pressed.connect(func(): modal.queue_free())
	actions.add_child(cancel)
	var ok = _styled_button(confirm_text, danger)
	ok.custom_minimum_size = Vector2(160, 30)
	ok.pressed.connect(func():
		modal.queue_free()
		on_confirm.call())
	actions.add_child(ok)
	add_child(modal)
