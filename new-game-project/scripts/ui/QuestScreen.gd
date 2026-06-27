class_name QuestScreen
extends Control

## QuestScreen — the pause-menu Quests page (two tabs, like the Items screen).
##   • Active tab     — the always-on story quest (pastel-yellow marker) and the one
##                      selected side quest (pastel-blue marker).
##   • Side Quests tab — every accepted side quest; pick one to make it the active
##                      side quest. Completed ones are shaded green with a ✓ and show
##                      their reward.
## Opened by PauseMenu as a replace-don't-stack sub-view. ←/→ via Q/E or clicking the
## tabs; Back / Esc / B return. Themed with BattleUITheme.

signal back_requested

const TAB_DEFS := ["Active", "Side Quests"]
const TAB_ACTIVE := 0
const TAB_SIDE := 1

# The two waypoint/marker colours (also used as card accents in the Active tab).
const STORY_COLOR := Color(0.98, 0.90, 0.52)   # pastel yellow — main/story quest
const SIDE_COLOR := Color(0.56, 0.78, 0.98)    # pastel blue — active side quest
const DONE_COLOR := Color(0.55, 0.78, 0.55)    # green — completed
const READY_COLOR := Color(0.96, 0.83, 0.36)   # gold — objective met, ready to turn in

var _selected_tab: int = 0
var _tab_buttons: Array[Button] = []
var _content_host: VBoxContainer = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)

func setup(_party: Array = []) -> void:
	_build_chrome()
	_select_tab(0)
	for tb in _tab_buttons:
		BattleUITheme.mark_no_focus(tb)
	GameManager.register_focus_scope(self)

func _exit_tree() -> void:
	GameManager.unregister_focus_scope(self)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()
	elif FocusUtil.is_prev_category(event):
		_select_tab((_selected_tab - 1 + TAB_DEFS.size()) % TAB_DEFS.size())
		get_viewport().set_input_as_handled()
	elif FocusUtil.is_next_category(event):
		_select_tab((_selected_tab + 1) % TAB_DEFS.size())
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
		pstyle.content_margin_left = 28
		pstyle.content_margin_right = 28
		pstyle.content_margin_top = 16
		pstyle.content_margin_bottom = 16
	center.add_child(panel)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 8)
	panel.add_child(root_v)

	# Header: title + Back.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root_v.add_child(header)
	var title := _label("✦  Quests  ✦", BattleUITheme.font_bold(), 20, BattleUITheme.TEXT_ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back_btn := BattleUITheme.make_button("← Back", 12)
	back_btn.custom_minimum_size = Vector2(90, 30)
	back_btn.pressed.connect(func(): back_requested.emit())
	header.add_child(back_btn)

	# Tabs.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	root_v.add_child(tabs)
	for i in range(TAB_DEFS.size()):
		var tab := _make_tab(TAB_DEFS[i], i)
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
	_content_host.add_theme_constant_override("separation", 8)
	margin.add_child(_content_host)

# --- Tabs ---------------------------------------------------------------------

func _select_tab(index: int) -> void:
	_selected_tab = clampi(index, 0, TAB_DEFS.size() - 1)
	for i in range(_tab_buttons.size()):
		_style_tab(_tab_buttons[i], i == _selected_tab)
	_build_content()

func _build_content() -> void:
	if _content_host == null:
		return
	for c in _content_host.get_children():
		c.queue_free()
	if _selected_tab == TAB_ACTIVE:
		_build_active_tab()
	else:
		_build_side_tab()

# --- Active tab ---------------------------------------------------------------

func _build_active_tab() -> void:
	var log := GameManager.quest_log

	_content_host.add_child(_section_header("Main Quest", STORY_COLOR))
	if log.story != null:
		_content_host.add_child(_quest_card(log.story, STORY_COLOR, false))
	else:
		_content_host.add_child(_muted_line("No story quest right now."))

	_content_host.add_child(_section_header("Side Quest", SIDE_COLOR))
	var side := log.active_side()
	if side != null:
		_content_host.add_child(_quest_card(side, SIDE_COLOR, false))
	else:
		_content_host.add_child(_muted_line("None selected. Choose one in the Side Quests tab."))

# --- Side Quests tab ----------------------------------------------------------

func _build_side_tab() -> void:
	var sides: Array = GameManager.quest_log.side_quests
	if sides.is_empty():
		_content_host.add_child(_muted_line("No side quests yet. Seek out townsfolk who need help."))
		return
	for q in sides:
		_content_host.add_child(_quest_card(q, SIDE_COLOR, true))

# --- Quest card ---------------------------------------------------------------

# in_side_tab = show the Set-Active button / ACTIVE tag (Side Quests tab). The card
# keeps its pastel accent (yellow story / blue side) even when ready to turn in;
# only a COMPLETED quest recolors to green.
func _quest_card(quest: Quest, accent: Color, in_side_tab: bool) -> Control:
	var done := quest.is_completed()
	var ready := (not done) and (not quest.is_story()) and quest.is_objective_met()
	var is_active_side := (not done) and (GameManager.quest_log.active_side_id == quest.id)

	var border := DONE_COLOR if done else accent

	var slot := PanelContainer.new()
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := BattleUITheme.panel_style(border, BattleUITheme.SUBPANEL_BG, 1, 6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	slot.add_theme_stylebox_override("panel", style)
	if done:
		slot.modulate = Color(1, 1, 1, 0.62)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	slot.add_child(v)

	# Title row: title  ............  [status tag]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var title_color := DONE_COLOR if done else BattleUITheme.TEXT_ACCENT
	var title := _label(("✓ " if done else "") + quest.title, BattleUITheme.font_bold(), 16, title_color)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	if done:
		pass
	elif ready:
		row.add_child(_label("READY", BattleUITheme.font_bold(), 11, accent))
	elif is_active_side:
		row.add_child(_label("ACTIVE", BattleUITheme.font_bold(), 11, SIDE_COLOR))

	# From: <giver>, <place>   (story shows just its place)
	var src := ""
	if quest.giver != "" and quest.place != "":
		src = "From: %s  ·  %s" % [quest.giver, quest.place]
	elif quest.place != "":
		src = quest.place
	elif quest.giver != "":
		src = "From: %s" % quest.giver
	if src != "":
		v.add_child(_label(src, BattleUITheme.font_regular(), 11, BattleUITheme.TEXT_SUBTITLE))

	var desc := _label(quest.description, BattleUITheme.font_regular(), 12, BattleUITheme.TEXT_PRIMARY)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)

	# Objective + progress (story quests show no counter).
	var obj_color := DONE_COLOR if done else BattleUITheme.TEXT_PRIMARY
	v.add_child(_label("◆ " + quest.progress_text(), BattleUITheme.font_bold(), 12, obj_color))

	# Reward — only revealed once the quest is completed.
	if done:
		v.add_child(_label("Reward:  " + quest.reward_text(), BattleUITheme.font_regular(), 11, BattleUITheme.TEXT_SUBTITLE))

	# Side Quests tab: let the player make an incomplete quest the active side quest.
	if in_side_tab and not done:
		if is_active_side:
			v.add_child(_label("Active side quest", BattleUITheme.font_regular(), 11, SIDE_COLOR))
		else:
			var btn := BattleUITheme.make_button("Set as Active", 12)
			btn.custom_minimum_size = Vector2(140, 30)
			btn.size_flags_horizontal = Control.SIZE_SHRINK_END
			btn.pressed.connect(func(): _on_set_active(quest.id))
			v.add_child(btn)

	return slot

func _on_set_active(quest_id: String) -> void:
	GameManager.select_active_side_quest(quest_id)
	# Rebuild AFTER the press resolves (freeing the button mid-press wedges GUI state).
	call_deferred("_build_content")

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

func _section_header(text: String, color: Color = BattleUITheme.TEXT_ACCENT) -> Control:
	var l := _label(text, BattleUITheme.font_bold(), 15, color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _muted_line(text: String) -> Control:
	return _label("   " + text, BattleUITheme.font_regular(), 12, BattleUITheme.TEXT_SUBTITLE)

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
