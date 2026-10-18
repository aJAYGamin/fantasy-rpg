class_name OnScreenKeyboard
extends Control

## A themed QWERTY on-screen keyboard: a dimmed full-screen overlay holding a panel with the
## name being typed, its length, and a grid of keys. Letters are added and deleted at the END
## of the draft only; there is no caret to move.
##
## Add it to the tree, then call open(). While open it is a focus scope of its own, so the
## d-pad walks the keys and the page behind is locked out. It reports through finished /
## cancelled, once, and then frees itself.

## The player is done: the draft exactly as typed. Cleaning it up is the caller's job.
signal finished(text: String)
## The player gave up: nothing to save.
signal cancelled

const NUMBER_ROW := "1234567890"
const LETTER_ROWS := ["QWERTYUIOP", "ASDFGHJKL'", "ZXCVBNM-"]
## What the letter rows turn into on the symbols page, key for key.
const SYMBOL_ROWS := ["!?.,&+#()/", ":;\"@%*=_~'", "<>[]{}$-"]

const PANEL_WIDTH := 470
const NAME_BOX_WIDTH := 230
const KEY_HEIGHT := 32
const KEY_GAP := 5
## A key is a tile, not a text button: the side padding make_button gives would push the
## narrow keys past their share of the row and skew the columns.
const KEY_PADDING := 3
const LETTER_FONT_SIZE := 14
const ACTION_FONT_SIZE := 12
const CARET := "|"

var caps := false
var symbols := false

var _draft := ""
var _max_length := 0
var _closed := false
var _keys: Dictionary = {}   # key id -> Button
var _name_label: Label = null
var _count_label: Label = null

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _exit_tree() -> void:
	# A page rebuild frees the panel without Done or Cancel.
	GameManager.unregister_focus_scope(self)

## Builds the panel and makes it the focus scope on top, with the highlight on Q.
## Call once, after adding it to the tree.
func open(initial: String, max_length: int) -> void:
	_max_length = max_length
	_draft = initial.left(max_length)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_show_draft()
	GameManager.register_focus_scope(self)
	GameManager.set_preferred_focus(self, key_button("Q"))

func get_text() -> String:
	return _draft

## Adds a character to the end of the draft, unless it is already full.
func type_char(c: String) -> void:
	if c.is_empty() or _draft.length() >= _max_length:
		return
	_draft += c
	_show_draft()

## Removes the last character; nothing to remove from an empty draft.
func delete_last() -> void:
	if _draft.is_empty():
		return
	_draft = _draft.substr(0, _draft.length() - 1)
	_show_draft()

func toggle_caps() -> void:
	caps = not caps
	_relabel_keys()

func toggle_symbols() -> void:
	symbols = not symbols
	_relabel_keys()

## The player is done. Reports the draft once, then closes.
func finish() -> void:
	if _closed:
		return
	_closed = true
	finished.emit(_draft)
	_close()

## The player gave up. Reports once, then closes.
func cancel() -> void:
	if _closed:
		return
	_closed = true
	cancelled.emit()
	_close()

## A key by id: a character as written in NUMBER_ROW / LETTER_ROWS (a letter-row key keeps
## its letter's id on the symbols page), or "shift", "backspace", "symbols", "space",
## "cancel" or "done". Null for anything else.
func key_button(id: String) -> Button:
	return _keys.get(id)

# --- Closing -------------------------------------------------------------------------

## Out of the focus guard's sight at once, not at the end of the frame when queue_free
## lands: its next tick must find no scope, nothing visible and nothing holding the focus
## here, so it hands the highlight to the page behind straight away.
func _close() -> void:
	GameManager.unregister_focus_scope(self)
	if is_inside_tree():
		var holder := get_viewport().gui_get_focus_owner()
		if holder != null and is_ancestor_of(holder):
			holder.release_focus()
	hide()
	queue_free()

# --- The draft -----------------------------------------------------------------------

func _show_draft() -> void:
	_name_label.text = _draft + CARET
	_count_label.text = "%d / %d" % [_draft.length(), _max_length]

## What the letter-row key at (row, col) types, and shows.
func _letter_text(row: int, col: int) -> String:
	if symbols:
		var symbol: String = SYMBOL_ROWS[row][col]
		return symbol
	var letter: String = LETTER_ROWS[row][col]
	return letter if caps else letter.to_lower()

func _relabel_keys() -> void:
	for row in LETTER_ROWS.size():
		for col in LETTER_ROWS[row].length():
			key_button(LETTER_ROWS[row][col]).text = _letter_text(row, col)
	key_button("symbols").text = "ABC" if symbols else "! ?"

# --- Building ------------------------------------------------------------------------

func _build() -> void:
	# Pin the dim and the centring container to the viewport, as SettingsScreen does, so the
	# panel is centred even when this control's own rect is (0, 0).
	var screen_size := get_viewport_rect().size

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.custom_minimum_size = screen_size
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing behind it can be clicked
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.custom_minimum_size = screen_size
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	var panel_box := BattleUITheme.panel_style(BattleUITheme.PANEL_BORDER, BattleUITheme.PANEL_BG, 2, 12)
	panel_box.content_margin_left = 18
	panel_box.content_margin_right = 18
	panel_box.content_margin_top = 16
	panel_box.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", panel_box)
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	panel.add_child(column)

	column.add_child(_label("✦ Rename Profile ✦", BattleUITheme.font_bold(), 16, SettingsScreen.ACCENT))
	column.add_child(_gap(8))
	column.add_child(_name_box())
	column.add_child(_gap(4))
	_count_label = _label("", BattleUITheme.font_regular(), 11, SettingsScreen.NOTE_COLOR)
	_count_label.name = "CountText"
	column.add_child(_count_label)
	column.add_child(_gap(10))
	column.add_child(_key_grid())
	column.add_child(_gap(6))
	column.add_child(_bottom_row())

func _label(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _gap(height: int) -> Control:
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, height)
	return g

## The box the draft is shown in, centred, with the caret after the last character.
func _name_box() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(NAME_BOX_WIDTH, 0)
	var style := BattleUITheme.panel_style(BattleUITheme.PANEL_BORDER, BattleUITheme.BUTTON_HOVER_BG, 2, 6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	box.add_theme_stylebox_override("panel", style)
	_name_label = _label("", BattleUITheme.font_regular(), 17, BattleUITheme.TEXT_PRIMARY)
	_name_label.name = "NameText"
	box.add_child(_name_label)
	row.add_child(box)
	return row

func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", KEY_GAP)
	return row

## The number row and the three letter rows: ten columns each, so the d-pad's neighbour
## search walks them as a grid.
func _key_grid() -> VBoxContainer:
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", KEY_GAP)

	var numbers := _row()
	grid.add_child(numbers)
	for digit in NUMBER_ROW:
		_add_key(numbers, digit, digit, LETTER_FONT_SIZE).pressed.connect(type_char.bind(digit))

	for r in LETTER_ROWS.size():
		var row := _row()
		grid.add_child(row)
		var last_row: bool = r == LETTER_ROWS.size() - 1
		if last_row:
			_add_key(row, "shift", "⇧", ACTION_FONT_SIZE, true).pressed.connect(toggle_caps)
		for c in LETTER_ROWS[r].length():
			var key := _add_key(row, LETTER_ROWS[r][c], _letter_text(r, c), LETTER_FONT_SIZE)
			key.pressed.connect(func() -> void: type_char(_letter_text(r, c)))
		if last_row:
			_add_key(row, "backspace", "⌫", ACTION_FONT_SIZE, true).pressed.connect(delete_last)
	return grid

## ! ? / Space / Cancel / Done, on the same ten columns: 2 + 4 + 2 + 2.
func _bottom_row() -> HBoxContainer:
	var row := _row()
	_add_key(row, "symbols", "! ?", ACTION_FONT_SIZE, true, 2.0).pressed.connect(toggle_symbols)
	_add_key(row, "space", "Space", ACTION_FONT_SIZE, true, 4.0).pressed.connect(type_char.bind(" "))
	_add_key(row, "cancel", "✕ Cancel", ACTION_FONT_SIZE, true, 2.0).pressed.connect(cancel)
	_add_key(row, "done", "✓ Done", ACTION_FONT_SIZE, true, 2.0).pressed.connect(finish)
	return row

## One themed key in `row`, registered under `id`. An action key is dimmer and smaller than
## a letter; `ratio` is its share of the row (a wide key takes 2 or 4 columns).
func _add_key(row: HBoxContainer, id: String, text: String, font_size: int,
		action := false, ratio := 1.0) -> Button:
	var key := BattleUITheme.make_button(text, font_size)
	key.custom_minimum_size = Vector2(0, KEY_HEIGHT)
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key.size_flags_stretch_ratio = ratio
	if action:
		key.add_theme_color_override("font_color", BattleUITheme.TEXT_SUBTITLE)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := key.get_theme_stylebox(state) as StyleBoxFlat
		box.content_margin_left = KEY_PADDING
		box.content_margin_right = KEY_PADDING
	row.add_child(key)
	_keys[id] = key
	return key
