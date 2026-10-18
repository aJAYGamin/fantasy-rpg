class_name SystemPointer
extends RefCounted

## The computer's own mouse pointer, as the themed cursor uses it: captured (hidden, deltas
## only) while the game holds the mouse, and shown, dressed as the cursor, while it lets go.
##
## Every call here reaches the operating system's pointer, and nothing else in the game
## makes one (test_system_pointer checks): the drawn cursor stands in for it everywhere, and
## with the mouse held the hidden pointer's position means nothing. VirtualCursor calls these
## only once install() has hooked a real window, never headless, and it and CursorHold decide
## when; this file only does it.

## The most pixels across a system cursor image may be (Godot refuses a bigger one).
const OS_CURSOR_MAX := 256.0

## Puts the system mouse in `mode`, an Input.MOUSE_MODE_*.
static func set_mode(mode: int) -> void:
	Input.mouse_mode = mode

## Shows the let-go pointer at `root_pos` (root-viewport coordinates), where the cursor was,
## as a plain arrow. Only a visible pointer can be warped, so call it after the switch.
static func appear_at(root: Window, root_pos: Vector2) -> void:
	Input.warp_mouse(root.get_final_transform() * root_pos)
	# The last control under the cursor may have asked for an I-beam or a hand.
	DisplayServer.cursor_set_shape(DisplayServer.CURSOR_ARROW)

## Where the visible pointer is, in root-viewport coordinates. The one place the game reads
## the OS mouse position: only while the pointer is still visible, just before capturing it,
## so the cursor carries on from where the player last saw it.
static func read_position(root: Window) -> Vector2:
	return root.get_mouse_position()

## Dresses the pointer as the cursor in `shape` and `colour`, at the size the cursor is drawn
## in a window `window_scale` window pixels to the base pixel: while the mouse is let go it is
## all the player sees of the cursor. The hand too, in case a control under it asks for it.
static func dress(shape: String, colour: String, window_scale: float) -> void:
	var s := os_cursor_scale(window_scale, DisplayServer.screen_get_max_scale(), shape)
	if not (s > 0.0 and is_finite(s)):
		return   # a minimised window
	# An Image, not a texture: the system keeps what it is given until after the renderer
	# has shut down, and a texture freed then is an error at every quit. Drawn straight to
	# one, so the cursor's own cached texture stays put.
	var image := CursorArt.image(shape, colour, s)
	var tip := CursorArt.hotspot(shape) * s
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
