class_name LoadoutScreen
extends Control

## The moveset screen: four attack and four special slots on the left, the rest
## of the character's learned pool on the right.
##
## One screen serves three surfaces with different permissions (pause page,
## campfire, town trainer) — all of which live in LoadoutEditor, so this file
## only decides how things look and what is clickable.
##
## Interaction is select-then-act: click a slot to select it, then click a pool
## move to put it there, or another slot to reorder. That works identically for
## mouse, keyboard and controller, where drag-and-drop would not.

signal closed
## The pause menu drives its sub-views off this name; the campfire and trainer
## use `closed`. Both fire, so either host can listen.
signal back_requested

const SLOT_H := 34

var _editor: LoadoutEditor = null
var _hero_index: int = 0
var _selected_slot: int = -1
var _selected_is_special: bool = false
var _status: Label = null
var _budget: Label = null
## True only when THIS screen paused the tree. Opened from the pause menu the
## game is already paused, and unpausing on exit would resume play underneath a
## still-open menu.
var _paused_by_me: bool = false

func setup(mode: LoadoutEditor.Mode) -> void:
	_editor = LoadoutEditor.new(mode)
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_me = true
	_build()
	GameManager.register_focus_scope(self)

func _exit_tree() -> void:
	GameManager.unregister_focus_scope(self)
	if _paused_by_me and get_tree() != null:
		get_tree().paused = false

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()

func _hero() -> Character:
	var party := GameManager.party
	if party.is_empty():
		return null
	return party[clampi(_hero_index, 0, party.size() - 1)]

func _close() -> void:
	closed.emit()
	back_requested.emit()
	queue_free()

# --- build --------------------------------------------------------------------

func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	# NOTE: the selection deliberately survives a rebuild. Clearing it here would
	# wipe the slot the moment it was picked, since picking one triggers a
	# rebuild to redraw the highlight and re-filter the pool list.

	var screen := get_viewport_rect().size
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.custom_minimum_size = screen
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.custom_minimum_size = screen
	add_child(center)

	var panel := BattleUITheme.make_panel()
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)

	outer.add_child(_label("✦  Moves  ✦", BattleUITheme.font_bold(), 22,
		BattleUITheme.TEXT_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	outer.add_child(_hero_tabs())
	outer.add_child(_divider())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	outer.add_child(cols)
	cols.add_child(_slot_column())
	cols.add_child(_pool_column())

	outer.add_child(_divider())
	_status = _label(_hint_text(), BattleUITheme.font_regular(), 11,
		Color(0.62, 0.56, 0.72), HORIZONTAL_ALIGNMENT_CENTER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_status)

	var back := BattleUITheme.make_button("← Back", 13)
	back.custom_minimum_size = Vector2(0, 36)
	back.pressed.connect(_close)
	outer.add_child(back)

func _hero_tabs() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	for i in GameManager.party.size():
		var c: Character = GameManager.party[i]
		var b := BattleUITheme.make_button(c.character_name, 13)
		b.custom_minimum_size = Vector2(130, 32)
		if i == _hero_index:
			b.add_theme_color_override("font_color", HeroPalette.accent_for(c.character_name))
		b.pressed.connect(func():
			_hero_index = i
			_build())
		row.add_child(b)
	return row

func _slot_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size = Vector2(340, 0)

	_budget = _label(_budget_text(), BattleUITheme.font_bold(), 12,
		BattleUITheme.TEXT_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_budget)

	col.add_child(_label("Attacks", BattleUITheme.font_bold(), 14,
		BattleUITheme.TEXT_SUBTITLE, HORIZONTAL_ALIGNMENT_CENTER))
	for slot in Character.EQUIP_SLOTS:
		col.add_child(_slot_row(false, slot))

	col.add_child(_label("Specials", BattleUITheme.font_bold(), 14,
		BattleUITheme.TEXT_SUBTITLE, HORIZONTAL_ALIGNMENT_CENTER))
	for slot in Character.EQUIP_SLOTS:
		col.add_child(_slot_row(true, slot))
	return col

func _slot_row(is_special: bool, slot: int) -> HBoxContainer:
	var hero := _hero()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var s: Skill = hero.equipped_skill(is_special, slot) if hero != null else null
	var selected := (_selected_slot == slot and _selected_is_special == is_special)
	var text := s.skill_name if s != null else "— empty —"
	var btn := BattleUITheme.make_button(("▸ " if selected else "") + text, 12)
	btn.custom_minimum_size = Vector2(0, SLOT_H)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if s == null:
		btn.add_theme_color_override("font_color", Color(0.55, 0.50, 0.62))
	elif selected:
		btn.add_theme_color_override("font_color", BattleUITheme.TEXT_ACCENT)
	btn.pressed.connect(func(): _on_slot_pressed(is_special, slot))
	row.add_child(btn)

	# Clearing is free wherever it's allowed; hidden entirely on the pause page
	# rather than shown disabled, since nothing there can change the loadout.
	if s != null:
		var info := BattleUITheme.make_button("?", 11)
		info.custom_minimum_size = Vector2(28, SLOT_H)
		info.pressed.connect(func(): _show_details(s))
		row.add_child(info)

	if _editor.can_clear():
		var x := BattleUITheme.make_button("✕", 12)
		x.custom_minimum_size = Vector2(30, SLOT_H)
		x.disabled = s == null
		x.pressed.connect(func(): _on_clear(is_special, slot))
		row.add_child(x)
	return row

func _pool_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size = Vector2(340, 0)
	col.add_child(_label("Known Moves", BattleUITheme.font_bold(), 14,
		BattleUITheme.TEXT_SUBTITLE, HORIZONTAL_ALIGNMENT_CENTER))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 300)
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var hero := _hero()
	if hero == null:
		return col
	# Only moves matching the selected slot's category can go in it, so the list
	# follows the selection instead of offering choices that would be refused.
	var want_special := _selected_is_special if _selected_slot >= 0 else false
	for idx in hero.learned_pool_indices(want_special):
		list.add_child(_pool_row(idx))
	if list.get_child_count() == 0:
		list.add_child(_label("Nothing learned yet.", BattleUITheme.font_regular(), 11,
			Color(0.55, 0.50, 0.62), HORIZONTAL_ALIGNMENT_CENTER))
	return col

func _pool_row(pool_index: int) -> HBoxContainer:
	var hero := _hero()
	var s: Skill = hero.skills[pool_index]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var equipped := hero.is_equipped(pool_index)
	var label := s.skill_name
	if s.mp_cost > 0:
		label += "   MP %d" % s.mp_cost
	var btn := BattleUITheme.make_button(label, 12)
	btn.custom_minimum_size = Vector2(0, SLOT_H)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if equipped:
		# Already carried — dimmed so the player can see it's in the loadout
		# without hunting for it in the slot list.
		btn.add_theme_color_override("font_color", Color(0.55, 0.62, 0.55))
	btn.disabled = not _editor.can_equip() or _selected_slot < 0
	btn.pressed.connect(func(): _on_pool_pressed(pool_index))
	row.add_child(btn)

	# Details stay reachable even when the move itself can't be equipped right
	# now — reading what something does is exactly what a player wants while
	# deciding whether to spend a swap on it.
	var info := BattleUITheme.make_button("?", 11)
	info.custom_minimum_size = Vector2(28, SLOT_H)
	info.pressed.connect(func(): _show_details(s))
	row.add_child(info)
	return row

## Full description, element, target and costs for one move. Costs are listed
## explicitly rather than only as a number on the row, since a move may later
## cost something other than MP.
func _show_details(s: Skill) -> void:
	var host := self
	var existing := host.get_node_or_null("MoveDetail")
	if existing != null:
		existing.queue_free()

	var wrap := Control.new()
	wrap.name = "MoveDetail"
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(wrap)

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(center)

	var panel := BattleUITheme.make_panel()
	panel.custom_minimum_size = Vector2(380, 0)
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	var elem := ElementalSystem.get_element_color(s.element)
	v.add_child(_label(s.skill_name, BattleUITheme.font_bold(), 17,
		elem.lerp(Color.WHITE, 0.25), HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_label("%s  ·  %s %s  ·  %s" % [
			s.get_skill_type_display(),
			ElementalSystem.get_element_icon(s.element),
			ElementalSystem.get_element_name(s.element),
			s.get_target_description()],
		BattleUITheme.font_regular(), 11, BattleUITheme.TEXT_SUBTITLE, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_divider())

	var desc := _label(s.description, BattleUITheme.font_regular(), 12,
		BattleUITheme.TEXT_PRIMARY, HORIZONTAL_ALIGNMENT_CENTER)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)
	v.add_child(_divider())

	v.add_child(_label("Cost", BattleUITheme.font_bold(), 11,
		BattleUITheme.TEXT_SUBTITLE, HORIZONTAL_ALIGNMENT_CENTER))
	var cost_text := "%d MP" % s.mp_cost if s.mp_cost > 0 else "Free"
	v.add_child(_label(cost_text, BattleUITheme.font_bold(), 14,
		Color(0.50, 0.70, 1.0), HORIZONTAL_ALIGNMENT_CENTER))

	var close := BattleUITheme.make_button("Close", 12)
	close.custom_minimum_size = Vector2(0, 32)
	close.pressed.connect(func(): wrap.queue_free())
	v.add_child(close)

# --- actions ------------------------------------------------------------------

func _on_slot_pressed(is_special: bool, slot: int) -> void:
	# Second click on a different slot of the same category reorders; clicking
	# the selected slot again deselects.
	if _selected_slot == slot and _selected_is_special == is_special:
		_selected_slot = -1
		_build()
		return
	if _selected_slot >= 0 and _selected_is_special == is_special:
		if _editor.rearrange(_hero(), is_special, _selected_slot, slot):
			_selected_slot = -1
			_build()
			return
	_selected_slot = slot
	_selected_is_special = is_special
	_build()

func _on_clear(is_special: bool, slot: int) -> void:
	if _editor.clear(_hero(), is_special, slot):
		_selected_slot = -1
		_build()

func _on_pool_pressed(pool_index: int) -> void:
	if _selected_slot < 0:
		return
	if _editor.equip(_hero(), _selected_is_special, _selected_slot, pool_index):
		_selected_slot = -1
		_build()
	else:
		_flash(_editor.equip_blocked_reason())

func _flash(msg: String) -> void:
	if is_instance_valid(_status) and msg != "":
		_status.text = msg
		_status.add_theme_color_override("font_color", Color(1.0, 0.62, 0.28))

# --- text ---------------------------------------------------------------------

func _budget_text() -> String:
	var left := _editor.swaps_remaining()
	if left < 0:
		return ""
	return "Swaps left: %d" % left

func _hint_text() -> String:
	match _editor.mode:
		LoadoutEditor.Mode.TRAINER:
			# Explicitly unlimited: the campfire wording nearby made this read as
			# a two-swap limit, which does not apply to a trainer.
			return "Change moves as often as you like. Pick a slot, then a move."
		LoadoutEditor.Mode.CAMPFIRE:
			if not _editor.can_equip():
				return "Out of swaps here — clearing and reordering are still free."
			return "%d swap(s) left. Clearing and reordering cost nothing." % _editor.swaps_remaining()
	return "Pick two slots to reorder them."

# --- primitives ---------------------------------------------------------------

func _label(text: String, font: Font, size: int, color: Color,
		h_align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = h_align
	if font: l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _divider() -> Control:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_top", 2)
	wrap.add_theme_constant_override("margin_bottom", 2)
	var line := ColorRect.new()
	line.color = Color(0.45, 0.35, 0.65, 0.5)
	line.custom_minimum_size = Vector2(0, 1)
	wrap.add_child(line)
	return wrap
