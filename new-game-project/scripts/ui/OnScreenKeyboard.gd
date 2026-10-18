class_name OnScreenKeyboard
extends Control

## A themed QWERTY on-screen keyboard: a dimmed full-screen overlay holding a panel with the
## name being typed, its length, and a grid of keys. Letters are added and deleted at the END
## of the draft only; there is no caret to move.
##
## Add it to the tree, then call open(). While open it is a focus scope of its own, so the
## d-pad walks the keys and the page behind is locked out. It reports through finished /
## cancelled, once, and then frees itself.
##
## While open it also takes the pad's buttons and a real keyboard's keys (see _input): what
## it acts on or swallows stops here, so nothing behind it hears it.

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
const LEGEND_FONT_SIZE := 11
## The actions a pad button can already be, and so cannot also be one of the fixed buttons
## (X, Y, LB): the player's Pause, Cancel / Back and Confirm. ui_cancel and ui_accept are
## Cancel and Confirm as the Controller page mirrors them.
const PLAYERS_ACTIONS := ["pause", "ui_cancel", "ui_accept"]
## The pad's directions, which move the highlight and so are left to the focus system.
const DIRECTION_ACTIONS := ["ui_up", "ui_down", "ui_left", "ui_right"]
## The actions the panel takes when the player has put them on a stick or trigger.
const AXIS_ACTIONS := ["pause", "ui_cancel"]

var caps := false
var symbols := false

var _draft := ""
var _max_length := 0
var _closed := false
var _hold := HoldRepeat.new()   # holding Cancel / Back keeps deleting
var _axis_held := {}   # action -> true while a stick or trigger bound to it is held past its threshold
var _draining := false   # closed, but a held trigger is still sending samples that are ours to swallow
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

# --- Input ---------------------------------------------------------------------------

## The pad's buttons and a real keyboard's keys, while the panel is open. What the panel
## acts on or swallows goes no further (the page, the pause menu and the overworld's pause
## handler are all behind it, and they get their turn after this); what it lets by is the
## pad's directions and Confirm, which walk and press the keys, the arrow keys, every
## release and the mouse.
##
## GameManager's own `_input` runs after every scene node's, so it never sees a press
## taken here: the panel tells it, first, so the highlight still comes back for a player
## who pressed a button the panel only swallowed.
func _input(event: InputEvent) -> void:
	if _draining:
		_drain(event)
		return
	if not _is_live():
		return
	var response := Callable()
	if event is InputEventJoypadButton and event.pressed:
		response = _pad_response(event)
	elif event is InputEventJoypadMotion:
		response = _axis_response(event)
	elif event is InputEventKey and event.pressed:
		response = _key_response(event)
	if response.is_null():
		return
	GameManager.note_input_device(event)
	get_viewport().set_input_as_handled()
	response.call()   # last: it can close the panel

## What a pressed pad button does here, or a null Callable to let it through. The player's
## own Pause, Cancel / Back and Confirm come first, so a fixed button they have moved onto
## one of those acts as that binding.
func _pad_response(event: InputEventJoypadButton) -> Callable:
	if event.is_action_pressed("pause"):
		return finish
	if event.is_action_pressed("ui_cancel"):
		return delete_last
	# Confirm presses the highlighted key, which the key's own Button does on this very press.
	if event.is_action("ui_accept"):
		return Callable()
	for action: String in DIRECTION_ACTIONS:
		if event.is_action(action):
			return Callable()
	match event.button_index:
		JOY_BUTTON_X:
			return cancel
		JOY_BUTTON_Y:
			return type_char.bind(" ")
		JOY_BUTTON_LEFT_SHOULDER:
			return toggle_caps
	return _swallow

## What a stick or trigger sample does here, or a null Callable to let it through. The
## player can put Pause / Menu or Cancel / Back on an axis ("LT / L2"). A held trigger
## sends a stream of samples that all match its action, so only the one that takes it from
## not held to held acts; every sample of the hold, and the one that lets it go, is taken
## too, so nothing behind hears any of it. Confirm on an axis and the sticks' directions
## pass through, as their buttons do.
func _axis_response(event: InputEventJoypadMotion) -> Callable:
	var edge := ""
	var taken := false
	for action: String in AXIS_ACTIONS:
		if not event.is_action(action):
			continue
		var held := event.is_action_pressed(action)
		var was: bool = _axis_held.get(action, false)
		_axis_held[action] = held
		if held and not was and edge.is_empty():
			edge = action
		taken = taken or held or was
	match edge:
		"pause":
			return finish
		"ui_cancel":
			return delete_last
	return _swallow if taken else Callable()

## What a pressed key does here, or a null Callable to let it through. Space and Enter are
## the keyboard's Confirm, but here a typed Space is a space and Enter is Done, so the
## highlighted key is never pressed by either.
func _key_response(event: InputEventKey) -> Callable:
	var code: Key = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
	match code:
		KEY_ESCAPE:
			return cancel
		KEY_ENTER, KEY_KP_ENTER:
			return finish
		KEY_BACKSPACE:
			return delete_last   # its echo too, so holding it keeps deleting
		KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT:
			return Callable()
	if _is_printable(event.unicode) and not (event.ctrl_pressed or event.meta_pressed or event.alt_pressed):
		return type_char.bind(char(event.unicode))
	return _swallow

func _swallow() -> void:
	pass

## A character the keyboard sends that belongs in a name: not a control code, DEL, or the
## private-use range macOS puts its function keys in.
static func _is_printable(unicode: int) -> bool:
	return unicode >= 32 and unicode != 127 and not (unicode >= 0xE000 and unicode <= 0xF8FF)

## Not closed, and showing: a closed panel lingers until the end of the frame, hidden.
func _is_live() -> bool:
	return not _closed and is_visible_in_tree()

func _process(delta: float) -> void:
	if _is_live():
		step_hold(_cancel_held(), delta)

## One frame of the held-Cancel / Back repeat: every repeat deletes a letter. The press
## itself deleted one in _input, and the first frame held only starts the clock.
func step_hold(cancel_held: bool, delta: float) -> void:
	if _hold.poll(cancel_held, delta):
		delete_last()

## Closed while a trigger bound to Pause or Cancel / Back is still held (it finished the
## panel): the rest of that hold is still ours, or the pause menu behind would take it as
## a fresh press. The panel stays, hidden, until the trigger is let go.
func _drain(event: InputEvent) -> void:
	if not event is InputEventJoypadMotion or _axis_response(event).is_null():
		return
	GameManager.note_input_device(event)
	get_viewport().set_input_as_handled()
	if not _axis_held.values().has(true):
		_draining = false
		queue_free()

## Whether the player's Cancel / Back is held: a trigger or stick bound to it that the
## samples say is held, or a bound button any connected pad holds.
func _cancel_held() -> bool:
	if _axis_held.get("ui_cancel", false):
		return true
	for pad in Input.get_connected_joypads():
		for ev in InputMap.action_get_events("ui_cancel"):
			if ev is InputEventJoypadButton and Input.is_joy_button_pressed(pad, (ev as InputEventJoypadButton).button_index):
				return true
	return false

# --- The legend ----------------------------------------------------------------------

## The legend's [button name, what it does] pairs, in the order it reads: Type, Delete,
## Cancel, Space, Caps, Done. Type, Delete and Done are the player's Confirm, Cancel / Back
## and Pause / Menu as they have them now; Cancel, Space and Caps are the fixed X, Y and LB,
## left out when the player has put one of their own bindings on that button (it then acts
## as that binding, see _pad_response, and promising it here would be false).
static func legend_entries() -> Array:
	var entries: Array = [
		[InputMapConfig.describe_controller("confirm"), "Type"],
		[InputMapConfig.describe_controller("cancel"), "Delete"],
	]
	for fixed: Array in [[JOY_BUTTON_X, "Cancel"], [JOY_BUTTON_Y, "Space"], [JOY_BUTTON_LEFT_SHOULDER, "Caps"]]:
		if not _is_players_button(fixed[0]):
			entries.append([InputMapConfig.joy_button_name(fixed[0]), fixed[1]])
	entries.append([InputMapConfig.describe_controller("pause"), "Done"])
	return entries

## True when `button` is the player's Pause, Cancel / Back or Confirm.
static func _is_players_button(button: JoyButton) -> bool:
	var probe := InputEventJoypadButton.new()
	probe.button_index = button
	probe.pressed = true
	for action: String in PLAYERS_ACTIONS:
		if probe.is_action(action):
			return true
	return false

## The legend as a label: the entries split over two centred lines, each button name in
## the subtitle colour and the rest in the note colour.
func _legend() -> RichTextLabel:
	var legend := RichTextLabel.new()
	legend.name = "LegendText"
	legend.bbcode_enabled = true
	legend.fit_content = true
	legend.scroll_active = false
	# Two lines of our own: with wrapping on, a label's minimum height is worked out at a
	# width it does not have yet, and a container can lay it out a screen tall.
	legend.autowrap_mode = TextServer.AUTOWRAP_OFF
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Not a stop for the highlight. Godot 4.6 gives a RichTextLabel the accessibility focus
	# mode, which the focus guard counts as a stop: the number keys' wrap link then went to the
	# legend, Godot refused it, and a push up from the number row always ended on Space.
	legend.focus_mode = Control.FOCUS_NONE
	legend.add_theme_font_override("normal_font", BattleUITheme.font_regular())
	legend.add_theme_font_override("bold_font", BattleUITheme.font_bold())
	legend.add_theme_font_size_override("normal_font_size", LEGEND_FONT_SIZE)
	legend.add_theme_font_size_override("bold_font_size", LEGEND_FONT_SIZE)
	legend.add_theme_color_override("default_color", SettingsScreen.NOTE_COLOR)
	var entries := legend_entries()
	var split := ceili(entries.size() / 2.0)
	var lines: Array = []
	for chunk: Array in [entries.slice(0, split), entries.slice(split)]:
		var parts: Array = []
		for entry: Array in chunk:
			parts.append("[b][color=#%s]%s[/color][/b] %s" % [BattleUITheme.TEXT_SUBTITLE.to_html(false), entry[0], entry[1]])
		if not parts.is_empty():
			lines.append(" · ".join(parts))
	legend.text = "[center]%s[/center]" % "\n".join(lines)
	return legend

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
	_draining = _axis_held.values().has(true)
	if not _draining:
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
	column.add_child(_gap(10))
	column.add_child(_legend())

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
