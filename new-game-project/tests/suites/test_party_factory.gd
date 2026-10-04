extends TestSuite

func suite_name() -> String:
	return "PartyFactory"

func test_creates_three_heroes() -> void:
	var party = PartyFactory.create_default_party()
	assert_eq(party.size(), 3, "default party size = 3")

func test_expected_heroes_present() -> void:
	var party = PartyFactory.create_default_party()
	var names: Array = []
	for h in party:
		names.append(h.character_name)
	assert_true(names.has("Aria"), "party includes Aria")
	assert_true(names.has("Kael"), "party includes Kael")
	assert_true(names.has("Lyra"), "party includes Lyra")

func test_each_hero_has_eight_skills() -> void:
	var party = PartyFactory.create_default_party()
	for h in party:
		assert_eq(h.skills.size(), 15, "%s has a 15-move pool (7 attack + 8 special)" % h.character_name)

func test_heroes_start_at_full_hp_mp() -> void:
	var party = PartyFactory.create_default_party()
	for h in party:
		assert_eq(h.current_hp, h.max_hp(), "%s starts at full HP" % h.character_name)
		assert_eq(h.current_mp, h.max_mp(), "%s starts at full MP" % h.character_name)

func test_heroes_have_ultimate_metadata() -> void:
	var party = PartyFactory.create_default_party()
	for h in party:
		assert_true(h.has_meta("ultimate_name"), "%s has ultimate_name meta" % h.character_name)
		assert_true(h.has_meta("ultimate_desc"), "%s has ultimate_desc meta" % h.character_name)

func test_fresh_instances_each_call() -> void:
	var a = PartyFactory.create_default_party()
	var b = PartyFactory.create_default_party()
	a[0].current_hp = 1
	assert_ne(b[0].current_hp, 1, "separate calls produce independent hero instances")

# --------------------------------------------------- Spec B: pool top-up

## A hero as an older save would load it: missing the last `n` moves of its
## factory pool.
func _older_save(hero: Character, n: int) -> Character:
	hero.skills.resize(hero.skills.size() - n)
	hero.prune_equipped()
	return SaveSerializer.deserialize_character(SaveSerializer.serialize_character(hero))

func test_top_up_restores_moves_a_save_is_missing() -> void:
	for hero in PartyFactory.create_default_party():
		var full := hero.skills.size()
		var back := _older_save(hero, 3)
		assert_eq(PartyFactory.top_up_pool(back), 3, "%s gains its three missing moves" % back.character_name)
		assert_eq(back.skills.size(), full, "back to the whole pool")
		for slot in range(full - 3, full):
			var want := 1 if PartyFactory.TEST_UNLOCK_ALL_SKILLS else PartyFactory.SKILL_UNLOCK_LEVELS[slot]
			assert_eq(back.skills[slot].unlock_level, want, "%s slot %d unlock level" % [back.character_name, slot])
			assert_eq(int(back.skills[slot].category), PartyFactory.SKILL_CATEGORIES[slot], "%s slot %d category" % [back.character_name, slot])
			assert_eq(back.skills[slot].source_path, PartyFactory.MOVES + PartyFactory.POOLS[back.character_name][slot], "the right file")

func test_top_up_is_a_no_op_on_a_full_pool() -> void:
	for hero in PartyFactory.create_default_party():
		assert_eq(PartyFactory.top_up_pool(hero), 0, "%s already has everything" % hero.character_name)

func test_top_up_matches_a_legacy_move_by_name() -> void:
	var hero: Character = PartyFactory.create_default_party()[0]
	hero.skills[0].source_path = ""   # a move saved before moves had files
	assert_eq(PartyFactory.top_up_pool(hero), 0, "matched by name, not added twice")

func test_top_up_leaves_unknown_heroes_alone() -> void:
	var stranger := Character.new()
	stranger.character_name = "Stranger"
	assert_eq(PartyFactory.top_up_pool(stranger), 0, "no pool to top up from")

func test_top_up_keeps_the_players_loadout() -> void:
	var hero: Character = PartyFactory.create_default_party()[0]
	var back := _older_save(hero, 3)
	var before_atk := back.equipped_attacks.duplicate()
	var before_spc := back.equipped_specials.duplicate()
	PartyFactory.top_up_party([back])
	for slot in before_atk.size():
		if before_atk[slot] != -1:
			assert_eq(back.equipped_attacks[slot], before_atk[slot], "attack slot %d keeps the player's choice" % slot)
	for slot in before_spc.size():
		if before_spc[slot] != -1:
			assert_eq(back.equipped_specials[slot], before_spc[slot], "special slot %d keeps the player's choice" % slot)
