class_name MapTransition
extends Resource

## MapTransition — a map-to-map travel point (P7p2): a mountain gate to another
## region, a dungeon entrance, or the return trip back. OverworldScene watches the
## player's position; entering `trigger_rect` (in world space) fades to black, loads
## `target_scene`, and drops the player at `target_spawn` in that scene (which fades
## back in). `target_spawn` must sit OUTSIDE the destination's own trigger rects so
## the player doesn't immediately bounce back through.

@export var label: String = ""                 # e.g. "Mountain Gate", "Goblin Castle"
@export var trigger_rect: Rect2 = Rect2()       # world-space zone that fires the transition
@export var target_scene: String = ""           # res:// path of the destination scene
@export var target_spawn: Vector2 = Vector2.ZERO  # where the player appears in the destination
