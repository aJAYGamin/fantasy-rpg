class_name VirtualCursor
extends Node

## The game's own mouse cursor, drawn in the player's chosen shape and colour and
## moved by the mouse at the in-game sensitivity instead of the computer's speed.
##
## To set the speed the game has to own the pointer, so install() replaces the main
## window's input callback with route_os_event. The OS -> Input step still runs
## first (Input.is_action_pressed, the joypad axes and Input's button mask stay
## right for game code); only the window's delivery into the scene tree changes.
## Every mouse event is pushed into the root again at pointer_pos, the cursor's tip,
## and every other event goes in untouched. GameManager makes one at launch as its
## own child, so it outlives scene changes.
##
## A controller drives it too: the right stick moves it (step_stick) and the remappable
## Cursor Click (the stick's press, by default) clicks where it points, a held press
## dragging like a held mouse button. The Controller page needs to see the raw stick and
## button to bind them, so GameManager.raw_input_passthrough hands both back untouched.
##
## The game holds the mouse (captured: the system pointer hidden) while it is in front.
## Windowed, a deliberate push past an edge lets it go (CursorHold decides); switching
## away always does. While let go the system pointer wears the cursor's look, no mouse
## event reaches the game, and a click inside the window (pressing nothing) or the right
## stick picks it up again.
##
## Embedded popups (an OptionButton's list) draw above every CanvasLayer of the
## root, so the cursor is also copied into each open one (update_mirrors).
##
## Over anything clickable the cursor glows (update_glow): cursor_glow.gdshader, one
## material shared by the cursor and every popup copy.

## Above everything else, including the FPS overlay (128).
const LAYER := 200
const GLOW_SHADER := preload("res://scripts/cursor/cursor_glow.gdshader")
## The glow's two blur radii in base pixels: the tight one and the wide one.
const GLOW_RADIUS_1 := 4.0
const GLOW_RADIUS_2 := 8.0
## The most pixels across a system cursor image may be (Godot refuses a bigger one).
const OS_CURSOR_MAX := 256.0
## The longest frame, in seconds, the right stick moves the cursor for. A hitch with the
## stick held (a load, dragging the window) hands _process a delta of a second or more, and
## the cursor must not jump across the screen for it: it slows down for that frame instead.
const MAX_STICK_FRAME := 1.0 / 30.0

## Where the cursor's tip is, in root-viewport (base pixel) coordinates.
var pointer_pos := Vector2.ZERO
## The cursor is drawn. The mouse shows it; keys and controller use hide it.
var shown := true
## install() has hooked the window. Never true headless.
var installed := false
## The drawn cursor.
var sprite: Sprite2D
## The cursor is over something clickable, so it is drawn glowing.
var glowing := false
## Whether the game holds the mouse or has let it go.
var hold := CursorHold.new()

## The mouse buttons this cursor is holding down, as a MouseButtonMask. Kept from
## the button events it routes rather than read from Input, so it is right
## headless and a synthetic click can join it. Every move pushed carries it, so a
## held button drags.
var _buttons := 0
## Cursor Click has been turned into a left press that has not been let go yet.
var _click_down := false
## The Cursor Click control is held down (an edge, so one pull of a trigger is one press).
var _click_held := false
## The game is the app in front, and its window has the system's focus (it can lose it
## with the app still in front: minimised, say). Both start true: the window opens in
## front, and a notification sent before the scene tree existed would never arrive.
var _app_focused := true
var _window_focused := true
## The left click that picked the mouse up has not been let go yet: its release is the
## pick-up's too, so it is swallowed.
var _swallow_release := false
## Each open popup's copy of the cursor, by the popup's instance id.
var _mirrors := {}
## The glow shader's settings, shared by the cursor and every copy of it, so one
## write lights them all. The radii are in texture pixels (RENDER_SCALE per base pixel).
var _glow := _make_glow_material()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = LAYER
	add_child(layer)
	sprite = _new_sprite()
	layer.add_child(sprite)
	pointer_pos = get_tree().root.get_visible_rect().size / 2.0
	# A pad at launch means the menus open on the focus highlight, not the mouse.
	shown = not GameManager.is_controller_mode()
	# The window may not be in front yet: still opening, or the player switched away while
	# the game loaded (focus news from then never reached this node). The mouse is taken
	# when it comes to the front.
	_window_focused = DisplayServer.window_is_focused()
	refresh_style()

func _process(delta: float) -> void:
	step_stick(_right_stick(), delta)
	sprite.position = pointer_pos
	sprite.visible = shown
	update_mirrors()
	update_glow()

## The right stick of whichever connected pad is tilted furthest.
func _right_stick() -> Vector2:
	var best := Vector2.ZERO
	for pad in Input.get_connected_joypads():
		var axis := Vector2(Input.get_joy_axis(pad, JOY_AXIS_RIGHT_X), Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y))
		if axis.length_squared() > best.length_squared():
			best = axis
	return best

## Moves the cursor with the right stick: `axis` is the tilt, `delta` the seconds since
## the last call. A tilt inside the dead zone does nothing, and so does any tilt while the
## Controller page is waiting for a button (raw_input_passthrough). The move is clamped
## to the window (only the mouse slips out of it) and pushed as a mouse move at the new
## spot, with the stick's speed as its velocity, which a dropdown list needs to light a
## row, and the buttons held, so Cursor Click held drags. A mouse that was let go is
## picked up first, unless another app is in front. A frame longer than MAX_STICK_FRAME
## counts as that long.
func step_stick(axis: Vector2, delta: float) -> void:
	if GameManager.raw_input_passthrough:
		return
	var velocity := CursorMotion.stick_velocity(axis, GameManager.settings.stick_sensitivity_right)
	if velocity == Vector2.ZERO:
		return
	if not _show_for_pad():
		return
	var before := pointer_pos
	# Already in base pixels, so no window scale and no mouse sensitivity.
	pointer_pos = CursorMotion.mouse_step(pointer_pos, velocity * minf(delta, MAX_STICK_FRAME), Vector2.ONE, 1.0,
			get_tree().root.get_visible_rect().size)
	var mm := InputEventMouseMotion.new()
	mm.velocity = velocity
	_push_motion(mm, pointer_pos - before)

# --- The hook ------------------------------------------------------------------

## Hooks the main window, so every OS input event comes to route_os_event instead
## of going straight into the scene tree. Call it again after a display change: a
## recreated window would drop the callback. Headless (the test runner) has no
## window to hook, so it does nothing there.
func install() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_input_event_callback(route_os_event, DisplayServer.MAIN_WINDOW_ID)
	installed = true
	_apply_hold()

## The hook's body, called with every OS input event once install() has run
## (tests call it directly). A mouse move steps pointer_pos at the mouse
## sensitivity; every mouse event is pushed into the root at pointer_pos, so
## clicks, hovers, drags and the wheel act where the cursor is drawn. While the mouse
## is let go, mouse events are the system pointer's (_route_released). The right
## stick and Cursor Click belong to the cursor (_route_other); anything else goes
## in untouched.
func route_os_event(ev: InputEvent) -> void:
	# Godot's own window did this for every event, and the hook stands in for it.
	if EngineDebugger.is_active() and ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_F8:
		EngineDebugger.send_message("request_quit", [])   # the editor's Stop shortcut
	var root := get_tree().root
	if (ev is InputEventMouse or ev is InputEventGesture) and hold.state == CursorHold.State.RELEASED:
		_route_released(ev, root)
	elif ev is InputEventMouseMotion:
		_route_motion(ev, root)
	elif ev is InputEventMouseButton:
		if _swallow_release and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
			_swallow_release = false   # the end of the click that picked the mouse up
			return
		shown = true
		_push_button(ev.duplicate())
	elif ev is InputEventGesture:
		# A trackpad's two-finger scroll (a pan) acts on what the cursor is over.
		shown = true
		var gesture: InputEventGesture = ev.duplicate()
		gesture.position = pointer_pos
		_deliver(gesture, true)
	else:
		_route_other(ev)

## Keys and controller input. The right stick moves the cursor (see step_stick) and
## Cursor Click clicks it, so the cursor keeps both to itself, except while the
## Controller page is binding a button: then every event goes in raw. Cursor Click may
## share its button with another action: while the cursor is hidden that button is
## the other action's, and goes in untouched without bringing the cursor back.
func _route_other(ev: InputEvent) -> void:
	var is_click := ev.is_action("cursor_click")
	var down := is_click and ev.is_action_pressed("cursor_click")
	# Only the moment the control goes down counts as a press: a trigger sends a stream
	# of samples while it is held, and every one after the first is the same press.
	var pressed_now := down and not _click_held
	if is_click:
		_click_held = down
	# A click the cursor pressed is always let go, whatever has changed since (a rebind
	# began, the d-pad hid the cursor): a drag must never stick.
	if is_click and not down and _click_down:
		_click_down = false
		_push_click(false)
	if not GameManager.raw_input_passthrough:
		if ev is InputEventJoypadMotion and (ev.axis == JOY_AXIS_RIGHT_X or ev.axis == JOY_AXIS_RIGHT_Y):
			return
		if is_click and (shown or not _shares_binding(ev)):
			if pressed_now:
				if shown:
					_click_down = true
					_push_click(true)
				elif _show_for_pad():
					# The first press only shows the cursor, so a click never lands unseen. A
					# still move lets the menus leave the focus highlight for it, as any mouse
					# use does: the cursor and the highlight are never both up.
					_push_still_move()
			return
	if _hides_cursor(ev):
		shown = false
	_deliver(ev)

## Whether `ev` also triggers some action other than Cursor Click.
func _shares_binding(ev: InputEvent) -> bool:
	for action in InputMap.get_actions():
		if action != &"cursor_click" and ev.is_action(action):
			return true
	return false

func _route_motion(ev: InputEventMouseMotion, root: Window) -> void:
	var window_scale := root.get_final_transform().get_scale()
	# A minimised window can report a zero scale; there is no sensible move then.
	if not window_scale.is_finite() or window_scale.x <= 0.0 or window_scale.y <= 0.0:
		return
	shown = true
	var sensitivity := GameManager.settings.mouse_sensitivity
	var bounds := root.get_visible_rect().size
	var before := pointer_pos
	pointer_pos = CursorMotion.mouse_step(pointer_pos, ev.relative, window_scale, sensitivity, bounds)
	# A windowed game lets go once the cursor is pushed far enough past an edge. The push
	# is the move mouse_step made, in base pixels at the sensitivity, from where the cursor
	# stood before it; a report with no movement in it neither adds to it nor restarts it.
	var step := ev.relative / window_scale * sensitivity
	if step != Vector2.ZERO and hold.on_motion(CursorMotion.overshoot(before, step, bounds), _windowed()):
		_let_go()
		return
	# A copy keeps the modifier keys. Its speed goes into base pixels like the move:
	# a dropdown list ignores a move with no speed when it lights up the row under it.
	var mm: InputEventMouseMotion = ev.duplicate()
	mm.velocity = ev.velocity / window_scale * sensitivity
	_push_motion(mm, pointer_pos - before)

## Pushes a mouse move into the root at pointer_pos; `rel` is the move in base
## pixels. The buttons this cursor holds ride along.
func _push_motion(mm: InputEventMouseMotion, rel: Vector2) -> void:
	mm.position = pointer_pos
	mm.global_position = pointer_pos
	mm.relative = rel
	mm.button_mask = _buttons
	_deliver(mm, true)

## A mouse move that goes nowhere, at pointer_pos: whatever is under the cursor lights up
## (and glows), and GameManager takes it as mouse use, so the menus leave the focus
## highlight for the mouse before it moves again. It presses nothing.
func _push_still_move() -> void:
	_push_motion(InputEventMouseMotion.new(), Vector2.ZERO)

## Notes a mouse button as held or let go, then pushes it into the root at
## pointer_pos.
func _push_button(mb: InputEventMouseButton) -> void:
	if mb.button_index > MOUSE_BUTTON_NONE:
		var bit := 1 << (mb.button_index - 1)
		_buttons = (_buttons | bit) if mb.pressed else (_buttons & ~bit)
	mb.button_mask = _buttons
	mb.position = pointer_pos
	mb.global_position = pointer_pos
	_deliver(mb, true)

## Presses or lets go of the left button at pointer_pos: Cursor Click, as a mouse.
func _push_click(pressed: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	_push_button(mb)

## Announces an event on the root window's window_input signal, as the engine's own
## window does before delivering, then delivers it. `in_root_units`: the event's
## positions are already in root-viewport units (pushed events are; the OS's are not).
func _deliver(ev: InputEvent, in_root_units := false) -> void:
	var root := get_tree().root
	root.window_input.emit(ev)
	root.push_input(ev, in_root_units)

## Keys and controller use hide the cursor: the same events GameManager._input
## takes as a switch to the focus highlight, so the cursor and the highlight are
## never both showing. A resting stick's jitter counts for neither.
func _hides_cursor(ev: InputEvent) -> bool:
	if ev is InputEventKey:
		return true
	if ev is InputEventJoypadButton:
		return ev.pressed
	if ev is InputEventJoypadMotion:
		return absf(ev.axis_value) > 0.5
	return false

# --- Holding and letting go of the mouse --------------------------------------------

## Switching away, or the window losing focus any other way (minimised, say), always lets
## the mouse go, so a player is never stuck with a mouse they can't take elsewhere. Coming
## back to a fullscreen or borderless game picks it up at once; a windowed one waits for the
## pointer to come into it, or a click inside it. A let-go pointer leaving the window and
## coming back in picks it up too (_on_pointer_back).
func _notification(what: int) -> void:
	var was_in_front := _in_front()
	match what:
		NOTIFICATION_WM_MOUSE_EXIT:
			hold.on_pointer_left()
			return
		NOTIFICATION_WM_MOUSE_ENTER:
			_on_pointer_back()
			return
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_app_focused = false
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_app_focused = true
		NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			# A dropdown list taking focus inside the window sends these too: only the
			# system's word on the window itself counts.
			_window_focused = DisplayServer.window_is_focused()
		_:
			return
	if was_in_front and not _in_front():
		if hold.state == CursorHold.State.HELD:
			hold.on_focus(false, _windowed())
			_let_go()
		else:
			_let_go_of_buttons()   # nothing should be held while let go; make sure
	elif not was_in_front and _in_front():
		if hold.state == CursorHold.State.RELEASED:
			hold.on_focus(true, _windowed())
			if hold.state == CursorHold.State.HELD:
				_hold_again()
		else:
			_apply_hold()   # held all along (the game opened behind another app): take it now

func _in_front() -> bool:
	return _app_focused and _window_focused

## After a window mode or size change. The window is hooked again (a recreated one would
## drop the hook) and held as its new mode wants: a let-go mouse is picked up if the game,
## in front, is now fullscreen or borderless; a let-go pointer is re-dressed at the new size.
func on_display_changed() -> void:
	if hold.state == CursorHold.State.RELEASED and _in_front() and not _windowed():
		hold.on_focus(true, false)
		_hold_again()
	install()

## A mouse event while the mouse is let go: the system pointer is the player's and reaches
## nothing, except a left press inside the window, which picks the mouse up with the
## cursor where it was pressed. That click, press and release, presses nothing.
func _route_released(ev: InputEvent, root: Window) -> void:
	var mb := ev as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var to_root := root.get_final_transform()
	if not is_finite(to_root.determinant()) or is_zero_approx(to_root.determinant()):
		return   # a minimised window: no sensible spot
	var spot := to_root.affine_inverse() * mb.position
	if not root.get_visible_rect().has_point(spot):
		return
	hold.on_click_while_released()
	pointer_pos = spot
	_swallow_release = true
	shown = true
	_apply_hold()
	# So whatever is under the new spot lights up before the mouse moves again.
	_push_still_move()

## The let-go system pointer came back over the window. It is picked up if it has been out
## since it was let go (hold decides) and the game is in front: the system moves a pointer the
## game doesn't hold at desktop speed, so the cursor runs at the game's sensitivity only once
## the game holds it again. It carries on from where the pointer came in (_hold_again), and a
## still move there tells the menus the mouse is in use, as after a pick-up click. (Godot marks
## the pointer as in the window only after this notification, so hover follows the next move.)
func _on_pointer_back() -> void:
	if not _in_front() or not hold.on_pointer_back():
		return
	_hold_again()
	shown = true
	_push_still_move()

## The pad brings the cursor back. A let-go mouse is picked up first, so the drawn
## cursor and the system pointer never both show, but never while another app is in
## front: that would take the mouse from it. Returns whether the cursor shows.
func _show_for_pad() -> bool:
	if hold.state == CursorHold.State.RELEASED:
		if not _in_front():
			return false
		hold.on_stick()
		_apply_hold()
	shown = true
	return true

## The mouse has just been let go (hold says so already). Anything held is let go, the
## drawn cursor hides, and the system pointer, dressed as the cursor, appears where the
## cursor was and carries on from there.
func _let_go() -> void:
	_let_go_of_buttons()
	_swallow_release = false   # a let-go mouse's events are all ignored, that release too
	shown = false
	_apply_hold()
	if installed:
		var root := get_tree().root
		# Only a visible pointer can be warped, so this comes after the switch.
		Input.warp_mouse(root.get_final_transform() * pointer_pos)
		# The last control under the cursor may have asked for an I-beam or a hand.
		DisplayServer.cursor_set_shape(DisplayServer.CURSOR_ARROW)

## Lets go of every button the cursor holds down and of Cursor Click, so nothing stays
## pressed while the game isn't holding the mouse: a slider being dragged lets go.
func _let_go_of_buttons() -> void:
	for index in range(MOUSE_BUTTON_LEFT, MOUSE_BUTTON_XBUTTON2 + 1):
		if _buttons & (1 << (index - 1)):
			var mb := InputEventMouseButton.new()
			mb.button_index = index
			mb.pressed = false
			_push_button(mb)
	_click_down = false
	_click_held = false

## The mouse is held again without a click: the game came back to the front, became
## fullscreen, or the let-go pointer came back over it. The cursor carries on from the system
## pointer if it is over the game, so a click that brought a borderless game back lands where
## it was aimed. The cursor shows when the mouse next moves (_on_pointer_back shows it at once).
func _hold_again() -> void:
	if installed:
		var root := get_tree().root
		# The one place the system pointer is read: it is still visible here, where the
		# player last saw it, and capturing will hide it.
		var spot := root.get_mouse_position()
		if root.get_visible_rect().has_point(spot):
			pointer_pos = spot
	_apply_hold()

## Puts the system mouse in the mode hold wants (_wanted_mouse_mode), dressed as the
## cursor while let go. Nothing headless.
func _apply_hold() -> void:
	if not installed:
		return
	if hold.state == CursorHold.State.RELEASED:
		_dress_system_pointer()
	Input.mouse_mode = _wanted_mouse_mode()

## Captured while held (hidden, deltas only), but never while the game isn't in front: that
## would take the mouse from the app that is. Visible while let go.
func _wanted_mouse_mode() -> int:
	return hold.mouse_mode() if _in_front() else Input.MOUSE_MODE_VISIBLE

## Dresses the system pointer as the cursor, at the size the cursor is drawn: while the
## mouse is let go it is all the player sees of the cursor. The hand too, in case a
## control under the pointer asks for it.
func _dress_system_pointer() -> void:
	var style := _style()
	var window_scale := get_tree().root.get_final_transform().get_scale()
	var s := os_cursor_scale(minf(window_scale.x, window_scale.y), DisplayServer.screen_get_max_scale(), style[0])
	if not (s > 0.0 and is_finite(s)):
		return   # a minimised window
	# An Image, not the texture: the system keeps what it is given until after the renderer
	# has shut down, and a texture freed then is an error at every quit.
	var image := CursorArt.texture(style[0], style[1], s).get_image()
	var tip := CursorArt.hotspot(style[0]) * s
	Input.set_custom_mouse_cursor(image, Input.CURSOR_ARROW, tip)
	Input.set_custom_mouse_cursor(image, Input.CURSOR_POINTING_HAND, tip)

## System-cursor pixels per symbol unit for the system pointer to look the size the cursor
## is drawn. `window_scale` is window pixels per base pixel; `screen_scale` is window
## pixels per screen point (DisplayServer.screen_get_max_scale: 2 on a Retina Mac, whose
## cursor images Godot sizes in points, 1 elsewhere). Capped so the image, glow margin
## and all, stays within a system cursor's OS_CURSOR_MAX pixels.
static func os_cursor_scale(window_scale: float, screen_scale: float, shape: String) -> float:
	var view: Rect2 = CursorArt.SHAPE_DATA[shape]["view"]
	var art := maxf(view.size.x, view.size.y) + 2.0 * CursorArt.GLOW_MARGIN
	return minf(window_scale / screen_scale, OS_CURSOR_MAX / art)

func _windowed() -> bool:
	return GameManager.settings.window_mode == SettingsModel.WindowMode.WINDOWED

## The shape and colour chosen in Settings, or the defaults if config.cfg names ones the
## catalogue doesn't know (a hand-edited file).
func _style() -> Array[String]:
	var style: Array[String] = [GameManager.settings.cursor_shape, GameManager.settings.cursor_colour]
	if not CursorArt.is_known(style[0], style[1]):
		style = [CursorArt.DEFAULT_SHAPE, CursorArt.DEFAULT_COLOUR]
	return style

# --- Drawing -------------------------------------------------------------------

## Dresses the cursor, every open popup's copy, and a let-go system pointer, in the
## shape and colour chosen in Settings.
func refresh_style() -> void:
	var style := _style()
	var shape := style[0]
	var colour := style[1]
	sprite.texture = CursorArt.texture(shape, colour)
	# The art is drawn from the texture's corner; this offset puts the tip on the
	# sprite's position.
	sprite.offset = -CursorArt.hotspot(shape) * CursorArt.RENDER_SCALE
	var glow := CursorArt.glow_colours(colour)
	_glow.set_shader_parameter("glow1", glow[0])
	_glow.set_shader_parameter("glow2", glow[1])
	for id in _mirrors:
		if is_instance_valid(_mirrors[id]):   # a freed popup's copy waits for update_mirrors
			_copy_style(_mirrors[id])
	if installed and hold.state == CursorHold.State.RELEASED:
		_dress_system_pointer()

## Keeps a copy of the cursor in every open embedded popup, at the cursor: popups
## draw above every CanvasLayer of the root, so an open dropdown list would
## otherwise cover the cursor. Called every frame.
func update_mirrors() -> void:
	for id in _mirrors.keys():
		if not is_instance_valid(instance_from_id(id)):
			_mirrors.erase(id)   # the popup was freed, and its copy with it
	for w: Window in get_tree().root.get_embedded_subwindows():
		if not w.visible:
			continue
		var id: int = w.get_instance_id()
		if not _mirrors.has(id):
			_mirrors[id] = _add_mirror(w)
		var mirror: Sprite2D = _mirrors[id]
		var f: float = w.content_scale_factor
		mirror.position = (pointer_pos - Vector2(w.position)) / f
		mirror.scale = Vector2.ONE / (CursorArt.RENDER_SCALE * f)
		mirror.visible = shown

## Lights or puts out the glow: on while the cursor is shown over something
## clickable. Called every frame.
func update_glow() -> void:
	var on := shown and _over_clickable()
	if on == glowing:
		return
	glowing = on
	_glow.set_shader_parameter("glowing", on)

## True when the cursor's tip is on an open dropdown list or on a control that is_clickable.
func _over_clickable() -> bool:
	for w: Window in get_tree().root.get_embedded_subwindows():
		# A dropdown's rows are all clickable; a tooltip is a popup too, and is not.
		if w is PopupMenu and w.visible and Rect2(Vector2(w.position), Vector2(w.size)).has_point(pointer_pos):
			return true
	var c := get_tree().root.gui_get_hovered_control()
	if c == null:
		return false
	# Not get_local_mouse_position(): the OS mouse is not where the cursor is.
	var local := c.get_global_transform_with_canvas().affine_inverse() * pointer_pos
	return is_clickable(c, local)

## Whether a click on `c` at `local_pos` (in its own space) would do something: an
## enabled button, a slider or scrollbar that can move, a text field that can be
## typed in, or anything that asks for the pointing hand (the Stats screen's hit areas).
static func is_clickable(c: Control, local_pos: Vector2) -> bool:
	if c is BaseButton:
		return not (c as BaseButton).disabled
	if c is Slider:
		return (c as Slider).editable
	if c is ScrollBar:
		# One whose page covers its whole range has nothing to drag.
		var bar := c as ScrollBar
		return bar.max_value - bar.min_value > bar.page
	if c is LineEdit:
		return (c as LineEdit).editable
	return c.get_cursor_shape(local_pos) == Control.CURSOR_POINTING_HAND

static func _make_glow_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("glowing", false)
	m.set_shader_parameter("r1_px", GLOW_RADIUS_1 * CursorArt.RENDER_SCALE)
	m.set_shader_parameter("r2_px", GLOW_RADIUS_2 * CursorArt.RENDER_SCALE)
	return m

func _add_mirror(w: Window) -> Sprite2D:
	var layer := CanvasLayer.new()
	layer.layer = LAYER
	var mirror := _new_sprite()
	layer.add_child(mirror)
	# Internal, so the popup's own handling of its children never sees it.
	w.add_child(layer, false, Node.INTERNAL_MODE_BACK)
	_copy_style(mirror)
	return mirror

## A cursor sprite, drawn from the texture's corner at one base pixel per symbol
## unit (the texture is rasterised RENDER_SCALE times larger, to stay sharp when
## the window scales up).
func _new_sprite() -> Sprite2D:
	var s := Sprite2D.new()
	s.centered = false
	s.scale = Vector2.ONE / CursorArt.RENDER_SCALE
	s.material = _glow
	return s

func _copy_style(mirror: Sprite2D) -> void:
	mirror.texture = sprite.texture
	mirror.offset = sprite.offset
