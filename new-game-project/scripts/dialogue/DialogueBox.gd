extends CanvasLayer

## Global themed dialogue box, driven entirely by DialogueManager signals. The
## DialogueManager autoload creates one instance, so it renders in every scene.
##
## Behaviour: a bottom panel types the current line out (confirm/click skips the
## typewriter); a no-choice line advances on confirm/click; a choice line reveals
## themed buttons once the text finishes and hands focus to the central guard so
## they're keyboard/controller navigable. Styled with BattleUITheme.

const CHARS_PER_SEC := 48.0

# The DialogueManager instance, reached via get_parent() as an UNTYPED ref so the
# parser never has to resolve the `DialogueManager` autoload type (this script is
# load()-compiled by the manager, and a typed reference would fail re-entrantly).
var _mgr = null
var _root: Control
var _speaker_lbl: Label
var _text_lbl: Label
var _continue_lbl: Label
var _choices_box: HBoxContainer
var _choice_buttons: Array = []
var _pending_choices: Array = []
var _choices_registered: bool = false
var _full_text: String = ""
var _revealed: float = 0.0
var _typing: bool = false

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false
	set_process(false)
	_start_bob()
	_mgr = get_parent()   # the DialogueManager autoload (untyped on purpose)
	_mgr.dialogue_started.connect(_on_started)
	_mgr.line_displayed.connect(_on_line)
	_mgr.choices_presented.connect(_on_choices)
	_mgr.dialogue_ended.connect(_on_ended)

# --- Build ---------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE  # advance handled in _unhandled_input
	add_child(_root)

	var panel := BattleUITheme.make_panel()
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 40
	panel.offset_right = -40
	panel.offset_top = -185
	panel.offset_bottom = -28
	# Grow UP from the bottom so choice buttons (which add height) are never pushed
	# off the bottom of the screen — the box gets taller instead.
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var pstyle := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if pstyle:
		pstyle.content_margin_left = 22
		pstyle.content_margin_right = 22
		pstyle.content_margin_top = 14
		pstyle.content_margin_bottom = 12
	_root.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	_speaker_lbl = _label("", BattleUITheme.font_bold(), 18, BattleUITheme.TEXT_ACCENT)
	v.add_child(_speaker_lbl)

	var line := ColorRect.new()
	line.color = Color(0.40, 0.30, 0.55, 0.6)
	line.custom_minimum_size = Vector2(0, 1)
	v.add_child(line)

	_text_lbl = _label("", BattleUITheme.font_regular(), 16, BattleUITheme.TEXT_PRIMARY)
	_text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_lbl.custom_minimum_size = Vector2(0, 86)
	_text_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	v.add_child(_text_lbl)

	# Horizontal so choices sit side by side (Accept | Decline), splitting the width.
	_choices_box = HBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 10)
	_choices_box.visible = false
	v.add_child(_choices_box)

	# Continue indicator lives OUTSIDE the VBox (in a free Control pinned to the
	# panel's bottom-right) so the looping bob tween can move its Y without the
	# container resetting it every layout pass.
	var ind_slot := Control.new()
	ind_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ind_slot.anchor_left = 1.0
	ind_slot.anchor_top = 1.0
	ind_slot.anchor_right = 1.0
	ind_slot.anchor_bottom = 1.0
	ind_slot.offset_left = -78
	ind_slot.offset_top = -66
	ind_slot.offset_right = -52
	ind_slot.offset_bottom = -44
	_root.add_child(ind_slot)
	_continue_lbl = _label("▼", BattleUITheme.font_bold(), 18, BattleUITheme.TEXT_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_continue_lbl.visible = false
	ind_slot.add_child(_continue_lbl)

# Looping up/down bob for the continue indicator (runs always; visibility is what
# gates whether it's seen).
func _start_bob() -> void:
	var t := create_tween().set_loops()
	t.tween_property(_continue_lbl, "position:y", -6.0, 0.45) \
		.from(0.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_continue_lbl, "position:y", 0.0, 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# --- Signal handlers -----------------------------------------------------------

func _on_started(_id: String) -> void:
	_root.visible = true
	_pending_choices = []
	_clear_choices()

func _on_line(speaker: String, text: String) -> void:
	_clear_choices()
	_pending_choices = []
	_speaker_lbl.text = speaker
	_speaker_lbl.visible = speaker != ""
	_full_text = text
	_text_lbl.text = text
	_text_lbl.visible_characters = 0
	_revealed = 0.0
	_typing = true
	_continue_lbl.visible = false
	set_process(true)

func _on_choices(choices: Array) -> void:
	# Built/revealed only once the text finishes typing (or is skipped).
	_pending_choices = choices
	if not _typing:
		_reveal_choices()

func _on_ended() -> void:
	_clear_choices()
	_pending_choices = []
	_typing = false
	set_process(false)
	_root.visible = false

# --- Typewriter ----------------------------------------------------------------

func _process(delta: float) -> void:
	if not _typing:
		return
	_revealed += CHARS_PER_SEC * delta
	_text_lbl.visible_characters = int(_revealed)
	if _revealed >= float(_full_text.length()):
		_finish_typing()

func _finish_typing() -> void:
	_typing = false
	_text_lbl.visible_characters = -1
	set_process(false)
	if not _pending_choices.is_empty():
		_reveal_choices()
	else:
		_continue_lbl.visible = true

# --- Choices -------------------------------------------------------------------

func _reveal_choices() -> void:
	_clear_choices()
	for i in _pending_choices.size():
		var btn := BattleUITheme.make_button(String(_pending_choices[i].get("label", "...")), 15)
		btn.custom_minimum_size = Vector2(0, 36)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # split the row evenly
		btn.pressed.connect(_on_choice_pressed.bind(i))
		_choices_box.add_child(btn)
		_choice_buttons.append(btn)
	_choices_box.visible = true
	_continue_lbl.visible = false
	GameManager.register_focus_scope(_choices_box)
	_choices_registered = true

func _on_choice_pressed(index: int) -> void:
	_pending_choices = []
	# Defer: choosing rebuilds/hides the box, which frees this very button — doing
	# it during the button's own `pressed` corrupts the viewport GUI mouse state
	# (same gotcha as the items menu).
	_mgr.choose.call_deferred(index)

func _clear_choices() -> void:
	if _choices_registered:
		GameManager.unregister_focus_scope(_choices_box)
		_choices_registered = false
	for b in _choice_buttons:
		if is_instance_valid(b):
			b.queue_free()
	_choice_buttons.clear()
	if _choices_box != null:
		_choices_box.visible = false

# --- Input ---------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _mgr == null or not _mgr.is_active():
		return
	if not _is_advance(event):
		return
	# While typing, confirm/click skips the typewriter (and reveals choices if any).
	if _typing:
		get_viewport().set_input_as_handled()
		_finish_typing()
		return
	# A revealed choice must be picked via its button (focus/click), not advanced.
	if _choices_box.visible:
		return
	get_viewport().set_input_as_handled()
	_mgr.advance()

func _is_advance(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("confirm"):
		return true
	return event is InputEventMouseButton and event.pressed \
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT

# --- Primitive -----------------------------------------------------------------

func _label(text: String, font: Font, size: int, color: Color, h_align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = h_align
	if font:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
