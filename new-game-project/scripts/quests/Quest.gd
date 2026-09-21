class_name Quest
extends Resource

## A single quest instance. Definitions live in QuestFactory; the QuestLog holds
## live ACTIVE instances (with progress) and a list of COMPLETED ids. Only the id +
## progress + state are saved — the rest is rehydrated from QuestFactory on load.

enum State { ACTIVE, COMPLETED }
# STORY = the single always-active main quest (yellow marker); SIDE = optional
# quests the player accumulates and selects one of as the "active side quest" (blue).
enum Kind { STORY, SIDE }

@export var id: String = ""
@export var kind: int = Kind.SIDE
@export var title: String = ""
@export var giver: String = ""
@export var place: String = ""            # where it was given (e.g. "West Town")
@export var turn_in_npc: String = ""      # who to return to; defaults to the giver
@export_multiline var description: String = ""
@export var objective: String = ""        # human-readable ("Defeat 3 goblins")
# Counter objective: advanced by GameManager.report_quest_event(objective_key).
# objective_target == 0 means "no counter" — the quest is ready to turn in as soon
# as it's accepted (e.g. a simple talk/fetch quest you return to the giver for).
@export var objective_key: String = ""    # e.g. "defeat:goblin"
@export var objective_target: int = 0
@export var objective_progress: int = 0
# Waypoint targets (the visible markers are placed as scenes get wired; this is the
# data they read). While the objective is unmet the marker points at the objective
# target; once met it points at the turn-in NPC/location.
@export var objective_target_npc: String = ""
@export var objective_target_location: String = ""
@export var turn_in_target_location: String = ""
@export var reward_gold: int = 0
@export var reward_items: Array = []      # ItemFactory names (quests never grant XP)
@export var state: int = State.ACTIVE

func is_active() -> bool:
	return state == State.ACTIVE

func is_completed() -> bool:
	return state == State.COMPLETED

func has_counter() -> bool:
	return objective_target > 0

# True once the objective is satisfied (always true for non-counter quests).
func is_objective_met() -> bool:
	return (not has_counter()) or objective_progress >= objective_target

func advance(amount: int = 1) -> void:
	if has_counter():
		objective_progress = clampi(objective_progress + amount, 0, objective_target)

func progress_text() -> String:
	if has_counter():
		return "%s  (%d/%d)" % [objective, objective_progress, objective_target]
	return objective

# Collapses a name list into "Name xN" parts, first-seen order preserved (e.g.
# ["Potion","Potion","Ether"] -> ["Potion x2","Ether"]). Shared by the quest menu
# and the reward dialogue so identical items are never listed separately.
static func stack_names(names: Array) -> Array:
	var counts := {}
	var order: Array = []
	for n in names:
		var s := String(n)
		if not counts.has(s):
			order.append(s)
		counts[s] = int(counts.get(s, 0)) + 1
	var out: Array = []
	for s in order:
		out.append(s if counts[s] == 1 else "%s x%d" % [s, counts[s]])
	return out

func reward_text() -> String:
	var parts: Array = []
	if reward_gold > 0:
		parts.append("%d Gold" % reward_gold)
	parts.append_array(stack_names(reward_items))
	return "   •   ".join(parts) if not parts.is_empty() else "—"

func is_story() -> bool:
	return kind == Kind.STORY

func effective_turn_in_npc() -> String:
	return turn_in_npc if turn_in_npc != "" else giver

# Where the "go here next" marker should point while this quest is active: the
# objective target until the objective is met, then the turn-in target. If a quest
# has no specific objective spot (e.g. "defeat goblins anywhere"), the player does
# the task then returns to the turn-in person — so mark that person the whole time.
func current_waypoint() -> Dictionary:
	if not is_objective_met() and (objective_target_npc != "" or objective_target_location != ""):
		return {"npc": objective_target_npc, "location": objective_target_location}
	return {"npc": effective_turn_in_npc(), "location": turn_in_target_location}

# Reward phrasing for the "received" line ("150 Gold and Potion x2").
func reward_received_text() -> String:
	var parts: Array = []
	if reward_gold > 0:
		parts.append("%d Gold" % reward_gold)
	parts.append_array(stack_names(reward_items))
	if parts.is_empty():
		return ""
	if parts.size() == 1:
		return String(parts[0])
	var last: String = parts.pop_back()
	return "%s and %s" % [", ".join(parts), last]

# --- Save (id + live progress only; definition comes from QuestFactory) --------

func to_dict() -> Dictionary:
	return {"id": id, "progress": objective_progress, "state": state}

func apply_progress_dict(d: Dictionary) -> void:
	objective_progress = int(d.get("progress", 0))
	state = int(d.get("state", State.ACTIVE))
