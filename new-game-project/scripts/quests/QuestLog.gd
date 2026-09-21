class_name QuestLog
extends RefCounted

## Pure quest bookkeeping (no rewards, no signals — GameManager wraps those).
## Structure:
##   • story         — the single always-active main quest (or null).
##   • side_quests   — every accepted side quest, kept even once completed (the Side
##                     Quests tab lists them all; completed ones show green/✓).
##   • active_side_id — which side quest is pinned in the Active tab (blue marker).
##   • completed     — all completed quest ids (story + side), the authoritative list.
## All ACCEPTED quests track progress in the background; "active side" is only which
## one is highlighted. Fully testable without a scene tree.

var story: Quest = null
var side_quests: Array[Quest] = []
var active_side_id: String = ""
var completed: Array[String] = []

# --- Queries ------------------------------------------------------------------

func has(id: String) -> bool:
	return get_quest(id) != null or is_completed(id)

func is_completed(id: String) -> bool:
	return id in completed

func get_quest(id: String) -> Quest:
	if story != null and story.id == id:
		return story
	return get_side(id)

func get_side(id: String) -> Quest:
	for q in side_quests:
		if q.id == id:
			return q
	return null

# True if the quest is an accepted side quest still in progress (not yet completed).
func is_active(id: String) -> bool:
	var q := get_side(id)
	return q != null and q.is_active()

# The side quest currently pinned in the Active tab (null if none / it's completed).
func active_side() -> Quest:
	if active_side_id == "":
		return null
	var q := get_side(active_side_id)
	return q if (q != null and q.is_active()) else null

# Side quests that haven't been completed yet (selectable as the active side quest).
func incomplete_sides() -> Array:
	return side_quests.filter(func(q): return q.is_active())

# "story" if this NPC is the story quest's current waypoint target, "side" if it's
# the active side quest's, else "" — drives the yellow/blue marker on NPCs.
func waypoint_kind_for_npc(npc_name: String) -> String:
	if npc_name == "":
		return ""
	if story != null and story.is_active() and String(story.current_waypoint().get("npc", "")) == npc_name:
		return "story"
	var side := active_side()
	if side != null and String(side.current_waypoint().get("npc", "")) == npc_name:
		return "side"
	return ""

# --- Story --------------------------------------------------------------------

func set_story(quest: Quest) -> void:
	story = quest
	if quest != null:
		quest.kind = Quest.Kind.STORY
		quest.state = Quest.State.ACTIVE

# --- Side quests --------------------------------------------------------------

# Accepts a side quest into the accumulated list. The FIRST accepted side quest with
# no active selection becomes active automatically (convenience); after that the
# player selects which one is active.
func accept_side(quest: Quest) -> bool:
	if quest == null or has(quest.id):
		return false
	quest.kind = Quest.Kind.SIDE
	quest.state = Quest.State.ACTIVE
	side_quests.append(quest)
	if active_side_id == "":
		active_side_id = quest.id
	return true

func select_active_side(id: String) -> bool:
	var q := get_side(id)
	if q == null or not q.is_active():
		return false
	active_side_id = id
	return true

# --- Progress (advances ALL accepted active quests: story + every side) -------

func report(event_key: String, amount: int = 1) -> Array:
	var pool: Array = []
	if story != null and story.is_active():
		pool.append(story)
	for q in side_quests:
		if q.is_active():
			pool.append(q)
	var newly_ready: Array = []
	for q in pool:
		if q.objective_key == event_key and q.has_counter() and not q.is_objective_met():
			q.advance(amount)
			if q.is_objective_met():
				newly_ready.append(q)
	return newly_ready

# --- Turn-in (side quests only; the story quest is advanced via set_story) -----

func can_turn_in(id: String) -> bool:
	var q := get_side(id)
	return q != null and q.is_active() and q.is_objective_met()

func mark_completed(id: String) -> Quest:
	var q := get_side(id)
	if q == null or not q.is_active() or not q.is_objective_met():
		return null
	q.state = Quest.State.COMPLETED
	if not (id in completed):
		completed.append(id)
	if active_side_id == id:
		active_side_id = ""   # active slot freed; the player picks the next one
	return q

func reset() -> void:
	story = null
	side_quests.clear()
	active_side_id = ""
	completed.clear()

# --- Save round-trip ----------------------------------------------------------

func to_save() -> Dictionary:
	var sides: Array = []
	for q in side_quests:
		sides.append(q.to_dict())
	return {
		"story": story.to_dict() if story != null else {},
		"side": sides,
		"active_side": active_side_id,
		"completed": completed,
	}

func from_save(d: Dictionary) -> void:
	reset()
	var sd = d.get("story", {})
	if sd is Dictionary and sd.has("id"):
		story = QuestFactory.create(String(sd["id"]))
		if story != null:
			story.apply_progress_dict(sd)
	for e in d.get("side", []):
		var q := QuestFactory.create(String((e as Dictionary).get("id", "")))
		if q != null:
			q.apply_progress_dict(e)
			side_quests.append(q)
	active_side_id = String(d.get("active_side", ""))
	for c in d.get("completed", []):
		var s := str(c)
		if not (s in completed):
			completed.append(s)
