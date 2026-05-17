class_name MapArea
extends Resource

## MapArea — data describing a single overworld area.
## OverworldScene reads this to configure spawn point, battle background, and encounters.

@export var area_name: String = ""
# Key into BattleScene.BACKGROUNDS for the battle backdrop in this area.
@export var battle_background_id: String = "fallster_plains"
@export var default_spawn: Vector2 = Vector2(2000, 1500)
@export var encounter_groups: Array[EncounterGroup] = []
