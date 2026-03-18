## GameManager.gd — Autoload Singleton
## Add to Project > Project Settings > Autoload as "GameManager"
extends Node

signal gold_changed(new_amount: int)
signal party_updated

# ─── Party ───────────────────────────────────────────────
var party: Array[Character] = []
const MAX_PARTY_SIZE = 4

# ─── Economy ─────────────────────────────────────────────
var gold: int = 100:
	set(value):
		gold = max(0, value)
		emit_signal("gold_changed", gold)

# ─── World State ─────────────────────────────────────────
var current_map: String = "world_map"
var completed_quests: Array[String] = []
var story_flags: Dictionary = {}   # e.g. {"met_elder": true, "darkwood_cleared": false}
var play_time_seconds: float = 0.0

# ─── Save/Load ───────────────────────────────────────────
const SAVE_PATH = "user://savegame.json"

func _process(delta):
	play_time_seconds += delta

# ─── Party Management ────────────────────────────────────
func add_to_party(character: Character) -> bool:
	if party.size() >= MAX_PARTY_SIZE:
		print("Party is full!")
		return false
	party.append(character)
	emit_signal("party_updated")
	return true

func remove_from_party(character: Character):
	party.erase(character)
	emit_signal("party_updated")

func get_party_leader() -> Character:
	return party[0] if not party.is_empty() else null

func is_party_alive() -> bool:
	return party.any(func(c): return c.is_alive())

func revive_party():
	for c in party:
		if not c.is_alive():
			c.current_hp = int(c.max_hp() * 0.5)

# ─── Gold ────────────────────────────────────────────────
func earn_gold(amount: int):
	gold += amount
	print("Earned %d gold. Total: %d" % [amount, gold])

func spend_gold(amount: int) -> bool:
	if gold >= amount:
		gold -= amount
		return true
	print("Not enough gold!")
	return false

# ─── Quest & Flags ───────────────────────────────────────
func complete_quest(quest_id: String):
	if not quest_id in completed_quests:
		completed_quests.append(quest_id)

func is_quest_done(quest_id: String) -> bool:
	return quest_id in completed_quests

func set_flag(flag: String, value = true):
	story_flags[flag] = value

func get_flag(flag: String, default = false):
	return story_flags.get(flag, default)

# ─── Award battle rewards to party ───────────────────────
func award_rewards(rewards: Dictionary):
	if rewards.has("gold"):
		earn_gold(rewards["gold"])

	if rewards.has("exp") and rewards["exp"] > 0:
		var exp_share = int(rewards["exp"] / max(1, party.size()))
		for character in party:
			if character.is_alive():
				var leveled = character.gain_experience(exp_share)
				if leveled:
					print("%s leveled up to %d!" % [character.character_name, character.level])

	if rewards.has("items"):
		for item in rewards["items"]:
			if not party.is_empty():
				party[0].inventory.add_item(item)

# ─── Save System ─────────────────────────────────────────
func save_game():
	var save_data = {
		"gold": gold,
		"current_map": current_map,
		"completed_quests": completed_quests,
		"story_flags": story_flags,
		"play_time": play_time_seconds,
		"party": []
	}
	for c in party:
		save_data["party"].append({
			"name": c.character_name,
			"level": c.level,
			"exp": c.experience,
			"current_hp": c.current_hp,
			"current_mp": c.current_mp
		})

	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	print("Game saved!")

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()

	if err != OK:
		push_error("Failed to parse save file.")
		return false

	var data = json.data
	gold = data.get("gold", 100)
	current_map = data.get("current_map", "world_map")
	completed_quests = data.get("completed_quests", [])
	story_flags = data.get("story_flags", {})
	play_time_seconds = data.get("play_time", 0.0)
	print("Game loaded!")
	return true

func delete_save():
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

func get_formatted_playtime() -> String:
	var hours = int(play_time_seconds / 3600)
	var minutes = int(fmod(play_time_seconds, 3600) / 60)
	var seconds = int(fmod(play_time_seconds, 60))
	return "%02d:%02d:%02d" % [hours, minutes, seconds]
