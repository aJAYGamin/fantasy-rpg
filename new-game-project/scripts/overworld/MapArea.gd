class_name MapArea
extends Resource

## MapArea — data describing a single overworld area.
## OverworldScene reads this to configure spawn point, battle background, and encounters.

@export var area_name: String = ""
# Key into BattleScene.BACKGROUNDS for the battle backdrop in this area.
@export var battle_background_id: String = "fallster_plains"
@export var default_spawn: Vector2 = Vector2(2000, 1500)
@export var encounter_groups: Array[EncounterGroup] = []

# P7p2: auto-save when the player ARRIVES in this area via a map transition (town
# interiors set this; villages/dungeons don't). Gated by GameManager.can_autosave()
# (settings toggle + active slot), same as the old safe-zone auto-save.
@export var autosave_on_enter: bool = false

# Safe zones (towns/sanctuaries) in this area, in world coordinates. Entering one
# triggers an auto-save (P5). Encounters never roll while the player stands in a
# safe zone. Each Rect2 is position + size in the same space as the player.
@export var safe_zones: Array[Rect2] = []

# Pinned roamer spawns (P7p2). When non-empty, OverworldScene spawns one roamer per
# entry at that fixed territory instead of scattering them randomly. Each RoamerSpawn
# may name a specific EncounterGroup (e.g. a fixed boss) or leave it null for a
# weighted pick from `encounter_groups`. Empty = fall back to fully-random spawning.
@export var roamer_spawns: Array[RoamerSpawn] = []

# Map-to-map transitions (P7p2): gates / dungeon entrances. Walking into a
# transition's trigger_rect fades out and loads target_scene at target_spawn.
@export var transitions: Array[MapTransition] = []
