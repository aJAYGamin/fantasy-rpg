class_name MapArea
extends Resource

## MapArea — data describing a single overworld area.
## OverworldScene reads this to configure spawn point, battle background, and encounters.

@export var area_name: String = ""
# Key into BattleScene.BACKGROUNDS for the battle backdrop in this area.
@export var battle_background_id: String = "fallster_plains"
@export var default_spawn: Vector2 = Vector2(2000, 1500)
@export var encounter_groups: Array[EncounterGroup] = []

# Safe zones (towns/sanctuaries) in this area, in world coordinates. Entering one
# triggers an auto-save (P5). Encounters never roll while the player stands in a
# safe zone. Each Rect2 is position + size in the same space as the player.
@export var safe_zones: Array[Rect2] = []
