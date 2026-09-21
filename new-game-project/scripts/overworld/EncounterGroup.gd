class_name EncounterGroup
extends Resource

## EncounterGroup — defines a single encounter for an area.
##
## "Flexible" mode (default, is_fixed == false): randomly draws a number of
## enemies from `enemy_pool`, with the count picked from [min_enemies, max_enemies].
## Same enemy type can appear multiple times in one encounter.
##
## "Fixed" mode (is_fixed == true, for tutorial/story/boss battles): spawns
## `enemy_pool` verbatim — one of each, in order — ignoring the count range. So a
## scripted "Goblin Ambush" of exactly [Cutthroat, Spearman, Wolf] always lands the
## same way.

@export var group_name: String = ""
@export var weight: float = 1.0
@export var min_party_level: int = 1
@export var enemy_pool: Array[Enemy] = []
@export_range(1, 10) var min_enemies: int = 1
@export_range(1, 10) var max_enemies: int = 3
# 0 means "use the enemy's stored level". Otherwise overrides level on spawn —
# so the same Ice Golem .tres can appear as Lv1 in early areas and Lv8 in late game.
@export var enemy_level_override: int = 0
# When true, spawn the pool verbatim (one of each, in order) instead of a random
# draw — used for scripted/tutorial/boss encounters.
@export var is_fixed: bool = false
# When true (default), spawned enemies take their level from the party instead of
# the template: party max level + a random offset in [-1, +1] (min 1). Keeps every
# encounter relevant as the player levels. enemy_level_override still wins, and
# scripted fights (e.g. a story boss) can turn this off to stay at fixed levels.
@export var scale_levels_to_party: bool = true
# Time-of-day gate: which phases (TimeOfDay.Phase ints — 0=Dawn, 1=Day, 2=Dusk,
# 3=Night) this group may spawn in. Empty = any time. e.g. [3] = night-only.
@export var time_phases: Array[int] = []

# True if this group may spawn during the given time phase.
func allowed_at_phase(phase: int) -> bool:
	return time_phases.is_empty() or phase in time_phases

# Builds a battle-ready list of Enemy instances for this group. Pass the party's
# max level so enemies can scale to it (0 = no scaling, use template levels).
# Each instance is a deep copy of its template (so HP/MP state doesn't leak between battles).
func instantiate_encounter(party_level: int = 0) -> Array[Enemy]:
	var instances: Array[Enemy] = []
	if enemy_pool.is_empty():
		return instances
	if is_fixed:
		# Fixed mode: every enemy in the pool, in order, exactly once.
		for template in enemy_pool:
			if template != null:
				instances.append(_spawn_one(template, party_level))
		return instances
	var lo: int = mini(min_enemies, max_enemies)
	var hi: int = maxi(min_enemies, max_enemies)
	var count: int = randi_range(lo, hi)
	for i in range(count):
		instances.append(_spawn_one(enemy_pool[randi() % enemy_pool.size()], party_level))
	return instances

# Deep-copies one template into a battle-ready instance (level + HP recompute).
# Level priority: enemy_level_override > party scaling > the template's own level.
func _spawn_one(template: Enemy, party_level: int = 0) -> Enemy:
	var enemy: Enemy = template.duplicate(true)
	if enemy_level_override > 0:
		enemy.level = enemy_level_override
	elif scale_levels_to_party and party_level > 0:
		enemy.level = maxi(1, party_level + randi_range(-1, 1))
	# Recompute HP after the level change, since max_hp() depends on level.
	# Enemies have no MP pool — skip current_mp init.
	enemy.current_hp = enemy.max_hp()
	if enemy.inventory == null:
		enemy.inventory = Inventory.new()
	return enemy
