class_name RoamerSpawn
extends Resource

## RoamerSpawn — a pinned roaming-enemy territory (P7p2). Lets a MapArea place
## roamers at hand-authored spots (sensible terrain, a boss room) instead of fully
## random territories. `home` is the wander/chase rect in world space. `group` names
## the encounter that roamer carries; leave it null to weighted-pick from the area's
## `encounter_groups`. A non-null `group` must also appear in the area's
## `encounter_groups` so the roamer can be persisted across battles (its index is
## stored) — give fixed/boss groups weight 0 there so they're never randomly drawn.

@export var home: Rect2 = Rect2(0, 0, 600, 450)
@export var group: EncounterGroup = null
