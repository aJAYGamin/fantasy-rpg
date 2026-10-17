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
## Embedded popups (an OptionButton's list) draw above every CanvasLayer of the
## root, so the cursor is also copied into each open one (update_mirrors).

## Above everything else, including the FPS overlay (128).
const LAYER := 200

## Where the cursor's tip is, in root-viewport (base pixel) coordinates.
var pointer_pos := Vector2.ZERO
## The cursor is drawn. The mouse shows it; keys and controller use hide it.
var shown := true
## install() has hooked the window. Never true headless.
var installed := false
## The drawn cursor.
var sprite: Sprite2D

## The mouse buttons this cursor is holding down, as a MouseButtonMask. Kept from
## the button events it routes rather than read from Input, so it is right
## headless and a synthetic click can join it. Every move pushed carries it, so a
## held button drags.
var _buttons := 0
## Each open popup's copy of the cursor, by the popup's instance id.
var _mirrors := {}

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
	refresh_style()

func _process(_delta: float) -> void:
	sprite.position = pointer_pos
	sprite.visible = shown
	update_mirrors()

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
	_apply_mouse_mode()

## The game holds the mouse: the OS pointer is hidden and relative motion keeps
## coming past the window's edges. One place, so letting the mouse go can take
## it over.
func _apply_mouse_mode() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## The hook's body, called with every OS input event once install() has run
## (tests call it directly). A mouse move steps pointer_pos at the mouse
## sensitivity; every mouse event is pushed into the root at pointer_pos, so
## clicks, hovers, drags and the wheel act where the cursor is drawn. Anything
## else goes in untouched.
func route_os_event(ev: InputEvent) -> void:
	var root := get_tree().root
	if ev is InputEventMouseMotion:
		_route_motion(ev, root)
	elif ev is InputEventMouseButton:
		shown = true
		_push_button(ev.duplicate())
	elif ev is InputEventGesture:
		# A trackpad's two-finger scroll (a pan) acts on what the cursor is over.
		shown = true
		var gesture: InputEventGesture = ev.duplicate()
		gesture.position = pointer_pos
		root.push_input(gesture, true)
	else:
		if _hides_cursor(ev):
			shown = false
		root.push_input(ev)

func _route_motion(ev: InputEventMouseMotion, root: Window) -> void:
	var window_scale := root.get_final_transform().get_scale()
	# A minimised window can report a zero scale; there is no sensible move then.
	if not window_scale.is_finite() or window_scale.x <= 0.0 or window_scale.y <= 0.0:
		return
	shown = true
	var sensitivity := GameManager.settings.mouse_sensitivity
	var before := pointer_pos
	pointer_pos = CursorMotion.mouse_step(pointer_pos, ev.relative, window_scale, sensitivity,
			root.get_visible_rect().size)
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
	get_tree().root.push_input(mm, true)   # true: already in root-viewport units

## Notes a mouse button as held or let go, then pushes it into the root at
## pointer_pos.
func _push_button(mb: InputEventMouseButton) -> void:
	if mb.button_index > MOUSE_BUTTON_NONE:
		var bit := 1 << (mb.button_index - 1)
		_buttons = (_buttons | bit) if mb.pressed else (_buttons & ~bit)
	mb.button_mask = _buttons
	mb.position = pointer_pos
	mb.global_position = pointer_pos
	get_tree().root.push_input(mb, true)

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

# --- Drawing -------------------------------------------------------------------

## Dresses the cursor, and every open popup's copy, in the shape and colour chosen
## in Settings.
func refresh_style() -> void:
	var shape := GameManager.settings.cursor_shape
	var colour := GameManager.settings.cursor_colour
	if not CursorArt.is_known(shape, colour):   # a hand-edited config.cfg
		shape = CursorArt.DEFAULT_SHAPE
		colour = CursorArt.DEFAULT_COLOUR
	sprite.texture = CursorArt.texture(shape, colour)
	# The art is drawn from the texture's corner; this offset puts the tip on the
	# sprite's position.
	sprite.offset = -CursorArt.hotspot(shape) * CursorArt.RENDER_SCALE
	for id in _mirrors:
		if is_instance_valid(_mirrors[id]):   # a freed popup's copy waits for update_mirrors
			_copy_style(_mirrors[id])

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
	return s

func _copy_style(mirror: Sprite2D) -> void:
	mirror.texture = sprite.texture
	mirror.offset = sprite.offset
