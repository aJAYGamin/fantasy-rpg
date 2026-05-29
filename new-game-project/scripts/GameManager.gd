## GameManager.gd — Autoload Singleton
## Add to Project > Project Settings > Autoload as "GameManager"
extends Node

signal gold_changed(new_amount: int)
signal party_updated

# ─── Party ───────────────────────────────────────────────
var party: Array[Character] = []
const MAX_PARTY_SIZE = 4

# ─── Species Memory ─────────────────────────────────────
var species_memory: Dictionary = {}

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

# ─── Overworld ↔ Battle Handoff ──────────────────────────
# Set by overworld when an encounter triggers; consumed by BattleScene.
# pending_overworld_scene_path is also used by battle screens to know where to return.
# Enemies are pre-instantiated (deep-copied templates with level/HP/MP set) so
# BattleScene doesn't need to know about EncounterGroup or MapArea details.
var in_overworld_battle: bool = false
var pending_battle_enemies: Array[Enemy] = []
var pending_battle_background: String = "fallster_plains"
var pending_overworld_scene_path: String = ""
var pending_overworld_return_position: Vector2 = Vector2.ZERO

# ─── Save/Load ───────────────────────────────────────────
const SAVE_PATH = "user://savegame.json"  # legacy single-file save (still used by old Continue path)

# Phase S1: 3-slot save system.
# Slot files live at user://save_slot_{0,1,2}.json with full party serialization.
const SAVE_SLOT_COUNT: int = 3
const SAVE_VERSION: int = 1
const SAVE_PATH_FORMAT: String = "user://save_slot_%d.json"
const USER_CONFIG_PATH: String = "user://config.cfg"

# active_slot persists across game restarts via USER_CONFIG_PATH.
# Setter writes the config so Continue always knows which slot to resume.
var active_slot: int = -1:
	set(value):
		active_slot = value
		_save_user_config()

var save_overworld_scene_path: String = ""
var save_overworld_position: Vector2 = Vector2.ZERO
# Set true by the Continue/Load flow so OverworldScene._ready spawns at the
# saved position instead of the area's default_spawn.
var resuming_from_save: bool = false

func _ready():
	_load_user_config()

func _process(delta):
	play_time_seconds += delta

# ─── User Config (persists last-used slot) ───────────────
func _load_user_config():
	var cfg = ConfigFile.new()
	if cfg.load(USER_CONFIG_PATH) != OK:
		return
	# Use the backing var directly to avoid triggering setter -> save (cycle is safe but noisy).
	var saved_slot: int = int(cfg.get_value("save", "last_slot", -1))
	if saved_slot >= 0 and saved_slot < SAVE_SLOT_COUNT and FileAccess.file_exists(SAVE_PATH_FORMAT % saved_slot):
		active_slot = saved_slot
	else:
		active_slot = -1

func _save_user_config():
	var cfg = ConfigFile.new()
	# Re-load existing to preserve other future keys
	cfg.load(USER_CONFIG_PATH)
	cfg.set_value("save", "last_slot", active_slot)
	cfg.save(USER_CONFIG_PATH)

# ─── Party Management ────────────────────────────────────
func ensure_default_party():
	if party.is_empty():
		for hero in PartyFactory.create_default_party():
			party.append(hero)

# Resets per-playthrough state and binds the given slot as active.
# Called from the New Game flow before transitioning to the overworld.
func start_new_game(slot: int):
	party = [] as Array[Character]
	gold = 100
	species_memory = {}
	completed_quests = [] as Array[String]
	story_flags = {}
	play_time_seconds = 0.0
	save_overworld_scene_path = ""
	save_overworld_position = Vector2.ZERO
	resuming_from_save = false
	in_overworld_battle = false
	pending_battle_enemies = [] as Array[Enemy]
	active_slot = slot  # setter persists last_slot to config
	ensure_default_party()

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
# Note: EXP is intentionally NOT applied here. VictoryScreen owns the EXP+level-up
# animation/UX and calls Character.gain_experience() itself. Applying it here too
# would double-count the EXP and silently level heroes past the LevelUpScreen.
func award_rewards(rewards: Dictionary):
	if rewards.has("gold"):
		earn_gold(rewards["gold"])

	if rewards.has("items"):
		for item in rewards["items"]:
			if not party.is_empty():
				party[0].inventory.add_item(item)

	if rewards.has("equipment"):
		for eq in rewards["equipment"]:
			if not party.is_empty():
				party[0].inventory.add_equipment(eq)

# ─── Save System ─────────────────────────────────────────
func save_game():
	var save_data = {
		"gold": gold,
		"current_map": current_map,
		"completed_quests": completed_quests,
		"story_flags": story_flags,
		"play_time": play_time_seconds,
		"species_memory": species_memory,
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
	species_memory = data.get("species_memory", {})
	play_time_seconds = data.get("play_time", 0.0)
	print("Game loaded!")
	return true

func delete_save():
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

# ─── Slot Save System (Phase S1) ─────────────────────────
func _slot_path(slot: int) -> String:
	return SAVE_PATH_FORMAT % slot

func _is_valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < SAVE_SLOT_COUNT

func slot_exists(slot: int) -> bool:
	if not _is_valid_slot(slot):
		return false
	return FileAccess.file_exists(_slot_path(slot))

# Builds the full save payload for the current GameManager state.
# Separated from save_to_slot so tests/UI previews can introspect without writing.
func _build_save_dict() -> Dictionary:
	var max_lv: int = 1
	var heroes_meta: Array = []
	for c in party:
		if c.level > max_lv:
			max_lv = c.level
		heroes_meta.append({
			"name": c.character_name,
			"class": c.character_class,
			"level": c.level,
		})
	var area_name: String = ""
	if save_overworld_scene_path != "":
		area_name = save_overworld_scene_path.get_file().get_basename()
	return {
		"version": SAVE_VERSION,
		"timestamp": Time.get_datetime_string_from_system(),
		"metadata": {
			"playtime_seconds": play_time_seconds,
			"max_party_level": max_lv,
			"party_size": party.size(),
			"area_name": area_name,
			"heroes": heroes_meta,
		},
		"gold": gold,
		"party": SaveSerializer.serialize_party(party),
		"species_memory": species_memory,
		"completed_quests": completed_quests,
		"story_flags": story_flags,
		"current_map": current_map,
		"overworld_scene_path": save_overworld_scene_path,
		"overworld_position": {
			"x": save_overworld_position.x,
			"y": save_overworld_position.y,
		},
	}

func save_to_slot(slot: int) -> bool:
	if not _is_valid_slot(slot):
		push_error("Invalid save slot: %d" % slot)
		return false
	var data = _build_save_dict()
	var file = FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("Failed to open save slot %d for write" % slot)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	active_slot = slot
	print("Game saved to slot %d." % slot)
	return true

func load_from_slot(slot: int) -> bool:
	if not slot_exists(slot):
		return false
	var file = FileAccess.open(_slot_path(slot), FileAccess.READ)
	if file == null:
		return false
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("Failed to parse save slot %d" % slot)
		return false
	var data = json.data
	gold = int(data.get("gold", 100))
	species_memory = data.get("species_memory", {})
	# JSON.parse returns untyped Array, so quests must be re-typed before assignment.
	var typed_quests: Array[String] = []
	for q in data.get("completed_quests", []):
		typed_quests.append(str(q))
	completed_quests = typed_quests
	story_flags = data.get("story_flags", {})
	current_map = data.get("current_map", "world_map")
	play_time_seconds = float(data.get("metadata", {}).get("playtime_seconds", 0.0))
	save_overworld_scene_path = data.get("overworld_scene_path", "")
	var pos_data = data.get("overworld_position", {"x": 0, "y": 0})
	save_overworld_position = Vector2(float(pos_data.get("x", 0)), float(pos_data.get("y", 0)))
	party = SaveSerializer.deserialize_party(data.get("party", []))
	active_slot = slot
	emit_signal("party_updated")
	emit_signal("gold_changed", gold)
	print("Game loaded from slot %d." % slot)
	return true

# Reads just the metadata block (cheap — no party deserialization) for slot pickers.
# Returns {} if the slot is empty/invalid/unparseable.
func get_slot_metadata(slot: int) -> Dictionary:
	if not slot_exists(slot):
		return {}
	var file = FileAccess.open(_slot_path(slot), FileAccess.READ)
	if file == null:
		return {}
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		return {}
	var data = json.data
	var meta: Dictionary = data.get("metadata", {}).duplicate()
	meta["timestamp"] = data.get("timestamp", "")
	return meta

func delete_slot(slot: int) -> bool:
	if not slot_exists(slot):
		return false
	DirAccess.remove_absolute(_slot_path(slot))
	if active_slot == slot:
		active_slot = -1
	return true

# Copies an existing slot's file to another slot index. Overwrites destination.
func copy_slot(from_slot: int, to_slot: int) -> bool:
	if from_slot == to_slot:
		return false
	if not _is_valid_slot(from_slot) or not _is_valid_slot(to_slot):
		return false
	if not slot_exists(from_slot):
		return false
	var src = FileAccess.open(_slot_path(from_slot), FileAccess.READ)
	if src == null:
		return false
	var bytes = src.get_buffer(src.get_length())
	src.close()
	var dst = FileAccess.open(_slot_path(to_slot), FileAccess.WRITE)
	if dst == null:
		return false
	dst.store_buffer(bytes)
	dst.close()
	return true

func get_formatted_playtime() -> String:
	var hours = int(play_time_seconds / 3600)
	var minutes = int(fmod(play_time_seconds, 3600) / 60)
	var seconds = int(fmod(play_time_seconds, 60))
	return "%02d:%02d:%02d" % [hours, minutes, seconds]

func get_species_memory(species: String) -> int:
	return species_memory.get(species, 0)
 
func record_battle_against(species: String):
	if not species_memory.has(species):
		species_memory[species] = 0
	species_memory[species] += 1
	print("Memory Echo: %s has been fought %d times" % [species, species_memory[species]])
 
func get_memory_level_description(species: String) -> String:
	var count = get_species_memory(species)
	if count < 3:
		return ""
	elif count < 7:
		return "%s senses something familiar..." % species
	elif count < 15:
		return "%s has learned from past encounters!" % species
	else:
		return "%s has fully adapted to your tactics!" % species
