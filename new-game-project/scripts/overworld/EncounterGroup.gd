class_name EncounterGroup
extends Resource

## EncounterGroup — defines a single weighted encounter for an area.
##
## "Flexible" mode (the only mode in Phase 3): randomly draws a number of
## enemies from `enemy_pool`, with the count picked from [min_enemies, max_enemies].
## Same enemy type can appear multiple times in one encounter.
##
## Future "fixed" mode (for tutorial/story battles) will spawn `enemy_pool`
## verbatim, ignoring the count range. Add an `is_fixed: bool` flag when needed.

@export var group_name: String = ""
@export var weight: float = 1.0
@export var min_party_level: int = 1
@export var enemy_pool: Array[Enemy] = []
@export_range(1, 10) var min_enemies: int = 1
@export_range(1, 10) var max_enemies: int = 3
# 0 means "use the enemy's stored level". Otherwise overrides level on spawn —
# so the same Ice Golem .tres can appear as Lv1 in early areas and Lv8 in late game.
@export var enemy_level_override: int = 0

# Builds a battle-ready list of Enemy instances for this group.
# Each instance is a deep copy of its template (so HP/MP state doesn't leak between battles).
func instantiate_encounter() -> Array[Enemy]:
	var instances: Array[Enemy] = []
	if enemy_pool.is_empty():
		return instances
	var lo: int = mini(min_enemies, max_enemies)
	var hi: int = maxi(min_enemies, max_enemies)
	var count: int = randi_range(lo, hi)
	for i in range(count):
		var template: Enemy = enemy_pool[randi() % enemy_pool.size()]
		var enemy: Enemy = template.duplicate(true)
		if enemy_level_override > 0:
			enemy.level = enemy_level_override
		# Recompute HP/MP after level override, since max_hp() depends on level.
		enemy.current_hp = enemy.max_hp()
		enemy.current_mp = enemy.max_mp()
		if enemy.inventory == null:
			enemy.inventory = Inventory.new()
		instances.append(enemy)
	return instances
