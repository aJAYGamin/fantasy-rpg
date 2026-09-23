class_name HoldRepeat
extends RefCounted

## Auto-repeat timing for a held input, shared by menu navigation and the
## category (L1/R1, Q/E) cycling on the Stats / Items / Equipment screens.
##
## Holding a direction should keep moving instead of stopping after one step, and
## a long hold should get you through a long list quickly. So the repeat runs in
## two stages: a normal cadence after a short initial delay, then an accelerated
## one once the input has been held continuously past ACCELERATE_AFTER.
##
## The FIRST press is deliberately NOT reported. Godot already moves focus on the
## initial press, and the menus already act on it in `_input`, so reporting it
## here would double every single tap.

## Wait before the first repeat, so a normal tap never repeats.
const INITIAL_DELAY := 0.42
## Cadence once repeating (~6 steps/sec).
const REPEAT_INTERVAL := 0.16
## How long the input must be held continuously before the fast stage kicks in.
const ACCELERATE_AFTER := 3.0
## Cadence in the fast stage (~20 steps/sec) for getting through long lists.
const FAST_INTERVAL := 0.05

var _held_for: float = 0.0
var _until_next: float = 0.0
var _was_pressed: bool = false

## Advance by `delta` and report whether a repeat should fire this frame.
## Call once per frame with the current pressed state of the input.
## Returns true 0..n times while held, never on the initial press.
func poll(pressed: bool, delta: float) -> bool:
	if not pressed:
		reset()
		return false

	if not _was_pressed:
		# Initial press: the caller already handled it, so just start the clock.
		_was_pressed = true
		_held_for = 0.0
		_until_next = INITIAL_DELAY
		return false

	_held_for += delta
	_until_next -= delta
	if _until_next > 0.0:
		return false
	_until_next = FAST_INTERVAL if _held_for >= ACCELERATE_AFTER else REPEAT_INTERVAL
	return true

## True once the hold has been going long enough to be in the fast stage. Only
## meaningful while held; used by tests and for any UI that wants to show it.
func is_accelerated() -> bool:
	return _was_pressed and _held_for >= ACCELERATE_AFTER

func reset() -> void:
	_held_for = 0.0
	_until_next = 0.0
	_was_pressed = false

## Seconds the input has been held past its initial press (0 when not held).
func held_for() -> float:
	return _held_for if _was_pressed else 0.0
