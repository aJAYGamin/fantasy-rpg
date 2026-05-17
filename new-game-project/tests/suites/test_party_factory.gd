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
		assert_eq(h.skills.size(), 8, "%s has 8 skills (4 attack + 4 special)" % h.character_name)

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
