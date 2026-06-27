class_name QuestFactory
extends RefCounted

## Single source of named quest definitions (mirrors ItemFactory / EquipmentFactory).
## QuestGiver NPCs and the QuestLog reference quests by id; create(id) builds a fresh
## instance. Completed quests are stored as ids and rehydrated through here, so the
## Quests menu can show a finished quest's title/description without saving all of it.

# The story quest the player starts a new game with (always active; placeholder until
# the story phase fills in the real chain).
const STORY_START := "amethyst_awakening"

const DEFS := {
	# --- Story (always-active main quest) ---
	"amethyst_awakening": {
		"kind": "story",
		"title": "The Amethyst Awakening",
		"place": "Fallster Plains",
		"description": "A violet blight is creeping across Fallster, and the Amethyst stirs in answer. Seek out the source of the corruption and uncover what it wants.",
		"objective": "Investigate the Amethyst corruption",
		# No counter — the story system advances this quest later (not player turn-in).
	},
	# --- Side quests ---
	"cull_goblins": {
		"title": "Cull the Goblins",
		"giver": "Townsperson",
		"place": "West Town",
		"description": "Goblin raiders from the eastern roads have been ambushing our trade wagons. Thin their numbers and West Town will reward you well.",
		"objective": "Defeat 3 goblins",
		"objective_key": "defeat:goblin",
		"objective_target": 3,
		"turn_in_npc": "Townsperson",
		"reward_gold": 150,
		"reward_items": ["Potion", "Potion"],
	},
	"wolf_trouble": {
		"title": "Wolves at the Door",
		"giver": "Townsperson",
		"place": "West Town",
		"description": "A dire wolf pack has been circling the western farms after dark. Put them down before someone gets hurt.",
		"objective": "Defeat 2 dire wolves",
		"objective_key": "defeat:dire",
		"objective_target": 2,
		"turn_in_npc": "Townsperson",
		"reward_gold": 120,
		"reward_items": ["Ether"],
	},
}

static func has_quest(id: String) -> bool:
	return DEFS.has(id)

static func create(id: String) -> Quest:
	if not DEFS.has(id):
		push_error("QuestFactory: unknown quest id '%s'" % id)
		return null
	var d: Dictionary = DEFS[id]
	var q := Quest.new()
	q.id = id
	q.kind = Quest.Kind.STORY if String(d.get("kind", "side")) == "story" else Quest.Kind.SIDE
	q.title = d.get("title", "")
	q.giver = d.get("giver", "")
	q.place = d.get("place", "")
	q.turn_in_npc = d.get("turn_in_npc", "")
	q.description = d.get("description", "")
	q.objective = d.get("objective", "")
	q.objective_key = d.get("objective_key", "")
	q.objective_target = int(d.get("objective_target", 0))
	q.objective_target_npc = d.get("objective_target_npc", "")
	q.objective_target_location = d.get("objective_target_location", "")
	q.turn_in_target_location = d.get("turn_in_target_location", "")
	q.reward_gold = int(d.get("reward_gold", 0))
	q.reward_items = (d.get("reward_items", []) as Array).duplicate()
	return q

static func all_ids() -> Array:
	return DEFS.keys()
