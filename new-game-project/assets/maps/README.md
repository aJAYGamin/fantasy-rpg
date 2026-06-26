# Overworld Map Art

Top-down overworld map images live here (distinct from `assets/backgrounds/`,
which holds **battle** backdrops).

## Drop your Fallster Plains map here

- **Filename:** `FallsterPlains.png`
- **Full path:** `assets/maps/FallsterPlains.png`
- Godot will auto-import it on next editor focus / project reload.

`OverworldScene.tscn` uses this as the world map sprite, replacing the old green
`Background` ColorRect + the `Marker1/2/3` placeholder town squares. Interaction
zones (town safe-zones, mountain gate, goblin-castle entrance) are pinned to
coordinates over this image — see `data/maps/fallster_plains.tres`.

Future region maps (e.g. the mountain pass beyond the gate, the goblin-castle
interior) go here too, one PNG per region.
