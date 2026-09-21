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

# --- Fixed-composition mode (P7p2) --------------------------------------------
func test_is_fixed_defaults_false() -> void:
	assert_false(EncounterGroup.new().is_fixed, "is_fixed defaults to false (flexible)")

func test_fixed_spawns_pool_verbatim() -> void:
	var g = _group()
	g.enemy_pool = [_enemy("Cutthroat"), _enemy("Spearman"), _enemy("Wolf")] as Array[Enemy]
	g.is_fixed = true
	# Count range must be IGNORED in fixed mode.
	g.min_enemies = 1
	g.max_enemies = 1
	var enc = g.instantiate_encounter()
	assert_eq(enc.size(), 3, "fixed mode spawns the whole pool, ignoring count range")
	assert_eq(enc[0].character_name, "Cutthroat", "fixed order preserved [0]")
	assert_eq(enc[1].character_name, "Spearman", "fixed order preserved [1]")
	assert_eq(enc[2].character_name, "Wolf", "fixed order preserved [2]")

func test_fixed_instances_are_deep_copies() -> void:
	var g = _group()
	g.is_fixed = true
	var a = g.instantiate_encounter()
	var same_as_template := false
	for inst in a:
		for tmpl in g.enemy_pool:
			if inst == tmpl:
				same_as_template = true
	assert_false(same_as_template, "fixed instances are copies, not pool templates")

# --- Party-level scaling (P7p2) ------------------------------------------------
func test_scaling_defaults_on() -> void:
	assert_true(EncounterGroup.new().scale_levels_to_party, "scale_levels_to_party defaults true")

func test_party_scaling_sets_levels_near_party() -> void:
	var g = _group()
	g.scale_levels_to_party = true
	for i in range(15):
		for e in g.instantiate_encounter(10):
			assert_in_range(e.level, 9, 11, "scaled level within party level ±1")
			assert_eq(e.current_hp, e.max_hp(), "HP recomputed at scaled level")

func test_party_scaling_never_below_one() -> void:
	var g = _group()
	g.scale_levels_to_party = true
	for i in range(10):
		for e in g.instantiate_encounter(1):
			assert_true(e.level >= 1, "scaled level clamped to >= 1")

func test_scaling_off_keeps_template_level() -> void:
	var g = _group()
	g.scale_levels_to_party = false
	g.enemy_pool = [_enemy("Slime", 3)] as Array[Enemy]
	for e in g.instantiate_encounter(10):
		assert_eq(e.level, 3, "scaling off -> template level kept")

func test_zero_party_level_skips_scaling() -> void:
	var g = _group()
	g.scale_levels_to_party = true
	g.enemy_pool = [_enemy("Slime", 3)] as Array[Enemy]
	for e in g.instantiate_encounter():
		assert_eq(e.level, 3, "no party level supplied -> template level kept")

func test_level_override_beats_scaling() -> void:
	var g = _group()
	g.scale_levels_to_party = true
	g.enemy_level_override = 5
	for e in g.instantiate_encounter(10):
		assert_eq(e.level, 5, "explicit override wins over party scaling")

func test_fixed_applies_level_override() -> void:
	var g = _group()
	g.is_fixed = true
	g.enemy_level_override = 6
	var enc = g.instantiate_encounter()
	for e in enc:
		assert_eq(e.level, 6, "fixed mode honors level override")
		assert_eq(e.current_hp, e.max_hp(), "fixed mode recomputes HP to max")
