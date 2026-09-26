class_name AutoSaveSystem
extends RefCounted

## Pure, testable safe-zone tracking for auto-save (P5).
##
## The overworld feeds the player's position + the area's safe zones each frame.
## This tracks which safe zone (if any) the player currently occupies and reports
## a one-shot ENTER transition (was outside all zones -> now inside one) so the
## caller can auto-save exactly once per town entry. Staying inside, or moving
## between adjacent zones, does not re-fire; leaving and re-entering does.
##
## Index of the safe zone the player is currently inside, or -1 if outside all.
var _current_zone: int = -1

# Returns the index of the first safe zone containing `pos`, or -1.
static func zone_at(pos: Vector2, zones: Array) -> int:
	for i in zones.size():
		var z: Rect2 = zones[i]
		if z.has_point(pos):
			return i
	return -1

## True when finishing this quest should trigger an auto-save.
##
## SIDE quests only: they are completed by a deliberate player turn-in, which is
## exactly the progress worth protecting. The STORY quest advances through
## scripted beats rather than a turn-in, so saving on it would fire at moments
## the player did not choose.
##
## This decides WHETHER the moment qualifies, not whether saving is allowed —
## GameManager.can_autosave() still gates on the player's auto-save setting, so
## turning that off turns this off with it.
static func wants_quest_autosave(quest) -> bool:
	if quest == null:
		return false
	return int(quest.kind) == Quest.Kind.SIDE

# True if the player currently stands in any safe zone (encounter suppression).
func in_safe_zone() -> bool:
	return _current_zone != -1

# Updates tracking for the player's new position and returns true exactly on the
# frame the player ENTERS a safe zone from outside (the auto-save trigger).
func update(pos: Vector2, zones: Array) -> bool:
	var zone := zone_at(pos, zones)
	var entered := zone != -1 and _current_zone == -1
	_current_zone = zone
	return entered

# Resets tracking (e.g. on scene (re)entry) so the next zone test is fresh.
func reset() -> void:
	_current_zone = -1
