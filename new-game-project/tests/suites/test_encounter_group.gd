extends TestSuite

func suite_name() -> String:
	return "EncounterGroup"

func _enemy(name: String, lv := 1) -> Enemy:
	var e = Enemy.new()
	e.character_name = name
	e.species = name
	e.base_hp = 40
	e.level = lv
	e.current_hp = e.max_hp()
	return e

func _group() -> EncounterGroup:
	var g = EncounterGroup.new()
	g.group_name = "Test Group"
	g.weight = 1.0
	g.min_party_level = 1
	g.enemy_pool = [_enemy("Slime A"), _enemy("Slime B")] as Array[Enemy]
	g.min_enemies = 2
	g.max_enemies = 2
	g.enemy_level_override = 0
	return g

func test_instantiate_respects_count_range() -> void:
	var g = _group()
	g.min_enemies = 1
	g.max_enemies = 3
	for i in range(20):
		var enc = g.instantiate_encounter()
		assert_in_range(enc.size(), 1, 3, "encounter size within [1,3]")

func test_instantiate_fixed_count() -> void:
	var g = _group()  # min==max==2
	var enc = g.instantiate_encounter()
	assert_eq(enc.size(), 2, "min==max yields exactly that many")

func test_instances_are_deep_copies() -> void:
	var g = _group()
	var a = g.instantiate_encounter()
	var b = g.instantiate_encounter()
	# Mutating one instance must not affect another
	if a.size() > 0 and b.size() > 0:
		a[0].current_hp = 1
		assert_ne(b[0].current_hp, 1, "separate encounters are independent instances")
	# instances must not be the same object as pool templates
	var same_as_template := false
	for inst in a:
		for tmpl in g.enemy_pool:
			if inst == tmpl:
				same_as_template = true
	assert_false(same_as_template, "instances are copies, not pool templates")

func test_level_override_applied() -> void:
	var g = _group()
	g.enemy_level_override = 5
	var enc = g.instantiate_encounter()
	for e in enc:
		assert_eq(e.level, 5, "level override applied to spawned enemy")
		assert_eq(e.current_hp, e.max_hp(), "HP recomputed to max at overridden level")

func test_level_zero_keeps_template_level() -> void:
	var g = _group()
	g.enemy_pool = [_enemy("Slime", 3)] as Array[Enemy]
	g.enemy_level_override = 0
	var enc = g.instantiate_encounter()
	assert_eq(enc[0].level, 3, "level 0 override keeps template's stored level")

func test_empty_pool_returns_empty() -> void:
	var g = _group()
	g.enemy_pool = [] as Array[Enemy]
	assert_eq(g.instantiate_encounter().size(), 0, "empty pool -> no enemies")
