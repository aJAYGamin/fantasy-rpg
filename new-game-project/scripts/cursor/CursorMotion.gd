class_name CursorMotion
extends RefCounted

## The themed cursor's movement maths: how a mouse delta and the right stick move it, and
## how far a push past the window's edge counts towards letting the mouse go.
##
## Pure static functions with no nodes, so the cursor and CursorHold (which decides when a
## windowed mouse slips out) share one definition of speed and edges. Positions are base
## pixels (the 1152 x 648 design resolution); window pixels are converted by window_scale.

## Stick input inside this radius does nothing, so a resting stick doesn't creep the cursor.
## 0.25 rather than a tighter 0.2: a worn pad's stick can rest past 0.2 (XInput's recommended
## right-stick dead zone is about 0.27).
const STICK_DEADZONE := 0.25
## A hidden cursor comes back only for a stick pushed past this: the 0.5 GameManager._input
## sets for a stick to count as controller use, measured here on the stick's magnitude (a
## diagonal of 0.4 on each axis wakes it, though GameManager, reading each axis, wouldn't count it). A stick drifting past the dead zone would
## otherwise bring the cursor back every frame, taking the menus off the highlight and, after a
## windowed slip-out, the mouse back from the desktop.
const STICK_WAKE := 0.5
## Speed at full tilt and 1.00x, in base px/s: 1152 px across the screen in about 1.5 s.
const STICK_FULL_SPEED := 768.0
## How far a windowed mouse must push past an edge before it slips out to the desktop.
const SLIP_OUT_DISTANCE := 24.0

## Moves the cursor by a mouse delta given in window pixels, scaled to base pixels and then
## by the mouse sensitivity, and clamps it to the playfield, [0, bounds - 1] on each axis.
static func mouse_step(pos: Vector2, rel_window: Vector2, window_scale: Vector2, sensitivity: float, bounds: Vector2) -> Vector2:
	var next := pos + rel_window / window_scale * sensitivity
	return Vector2(clampf(next.x, 0.0, bounds.x - 1.0), clampf(next.y, 0.0, bounds.y - 1.0))

## Velocity in base px/s for a right-stick deflection. The dead zone and the curve read the
## stick's magnitude (capped at full tilt); the direction is the stick's own. The square
## curve keeps small tilts fine near the centre.
static func stick_velocity(axis: Vector2, sensitivity: float) -> Vector2:
	var m := minf(axis.length(), 1.0)
	if m <= STICK_DEADZONE:
		return Vector2.ZERO
	var t := (m - STICK_DEADZONE) / (1.0 - STICK_DEADZONE)
	return axis.normalized() * (t * t * STICK_FULL_SPEED * sensitivity)

## Whether a right-stick tilt is a deliberate push, enough to bring a hidden cursor back
## (STICK_WAKE). Read on the stick's magnitude, like the dead zone.
static func stick_wakes(axis: Vector2) -> bool:
	return axis.length() > STICK_WAKE

## How far `rel` pushes past an edge the cursor is already on, summed over both axes, so a
## corner push counts twice. A push along an edge, or one that moves back in, counts nothing.
static func overshoot(pos: Vector2, rel: Vector2, bounds: Vector2) -> float:
	return _outward(pos.x, rel.x, bounds.x - 1.0) + _outward(pos.y, rel.y, bounds.y - 1.0)

## One axis of overshoot: rel's size if it pushes outward from an edge pos is already on,
## otherwise 0. `last` is the far end of the playfield; the near end is 0.
static func _outward(pos: float, rel: float, last: float) -> float:
	if rel > 0.0 and pos >= last:
		return rel
	if rel < 0.0 and pos <= 0.0:
		return -rel
	return 0.0
