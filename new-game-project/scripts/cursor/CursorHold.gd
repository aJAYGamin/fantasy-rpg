class_name CursorHold
extends RefCounted

## Whether the game is holding the mouse (it draws its own cursor and the system pointer is
## hidden) or has let it go (the pointer has slipped out of a window onto the desktop).
##
## Fullscreen and borderless hold while the game is in front. Windowed play lets go only on a
## deliberate push past an edge, so a nudge at the window's edge keeps the cursor. Once let go,
## a click inside the window or a right-stick move picks it up again. Losing focus always lets
## go, and coming back to a windowed game waits for a click, so the player is never left with a
## pointer they cannot get back into the window.

enum State { HELD, RELEASED }

var state := State.HELD

## Overshoot piled up by consecutive pushes past an edge, while held and windowed.
var _pushed := 0.0

## Feeds the overshoot of one motion (CursorMotion.overshoot). Returns true on the call that
## lets go. Fullscreen never releases, and nothing changes once released.
func on_motion(overshoot: float, windowed: bool) -> bool:
	if not windowed or state == State.RELEASED:
		return false
	if overshoot <= 0.0:
		# A motion that doesn't push out starts the push again from zero.
		_pushed = 0.0
		return false
	_pushed += overshoot
	if _pushed < CursorMotion.SLIP_OUT_DISTANCE:
		return false
	_transition(State.RELEASED)
	return true

## Focus left the game: always let go. Focus came back: fullscreen and borderless pick the
## mouse up straight away; windowed waits for a click or a stick move.
func on_focus(focused: bool, windowed: bool) -> void:
	if not focused:
		_transition(State.RELEASED)
	elif not windowed:
		_transition(State.HELD)

## A click while released picks the mouse up. The caller swallows that press and its release,
## so the click doesn't also press whatever the cursor landed on.
func on_click_while_released() -> void:
	_transition(State.HELD)

## Moving the right stick in a focused window picks the mouse up, so the drawn cursor and a
## released system pointer are never both on screen.
func on_stick() -> void:
	_transition(State.HELD)

## Captured (pointer hidden, deltas only) while held; visible while released.
func mouse_mode() -> int:
	return Input.MOUSE_MODE_CAPTURED if state == State.HELD else Input.MOUSE_MODE_VISIBLE

func _transition(next: State) -> void:
	state = next
	_pushed = 0.0
