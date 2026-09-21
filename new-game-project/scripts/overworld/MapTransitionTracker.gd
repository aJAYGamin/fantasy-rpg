class_name MapTransitionTracker
extends RefCounted

## Pure, testable map-transition entry tracking (P7p2). Mirrors AutoSaveSystem.
##
## The overworld feeds the player's position + the area's transitions each frame.
## This reports a one-shot ENTER transition (was outside all trigger rects -> now
## inside one) so the caller fires the fade/scene-change exactly once per entry.
## Standing inside, or sliding between adjacent triggers, does not re-fire; leaving
## and re-entering does.
##
## Index of the transition the player currently occupies, or -1 if outside all.
var _current: int = -1

# Index of the first transition whose trigger_rect contains `pos`, or -1.
static func transition_at(pos: Vector2, transitions: Array) -> int:
	for i in transitions.size():
		var t = transitions[i]
		if t != null and (t.trigger_rect as Rect2).has_point(pos):
			return i
	return -1

# Updates tracking for the new position and returns the index of a transition just
# ENTERED this frame (outside -> inside), or -1 if none.
func update(pos: Vector2, transitions: Array) -> int:
	var idx := transition_at(pos, transitions)
	var entered := idx != -1 and _current == -1
	_current = idx
	return idx if entered else -1

# Resets tracking (e.g. on scene (re)entry) so the next test is fresh.
func reset() -> void:
	_current = -1
