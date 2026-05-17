extends TestSuite

func suite_name() -> String:
	return "ElementalSystem"

func test_none_is_neutral() -> void:
	var E = ElementalSystem.Element
	assert_near(ElementalSystem.get_multiplier(E.NONE, E.FIRE), 1.0, 0.01, "NONE attack -> neutral")
	assert_near(ElementalSystem.get_multiplier(E.FIRE, E.NONE), 1.0, 0.01, "NONE target -> neutral")

func test_super_effective() -> void:
	var E = ElementalSystem.Element
	assert_near(ElementalSystem.get_multiplier(E.WATER, E.FIRE), 2.0, 0.01, "Water vs Fire = 2x")
	assert_near(ElementalSystem.get_multiplier(E.LIGHT, E.DARK), 2.0, 0.01, "Light vs Dark = 2x")
	assert_near(ElementalSystem.get_multiplier(E.LIGHTNING, E.WATER), 2.0, 0.01, "Lightning vs Water = 2x")

func test_resisted() -> void:
	var E = ElementalSystem.Element
	assert_near(ElementalSystem.get_multiplier(E.WATER, E.WATER), 0.5, 0.01, "Water vs Water = 0.5x")
	assert_near(ElementalSystem.get_multiplier(E.EARTH, E.FIRE), 0.5, 0.01, "Earth vs Fire = 0.5x")

func test_unlisted_pair_neutral() -> void:
	var E = ElementalSystem.Element
	# Fire vs Light has no chart entry -> neutral
	assert_near(ElementalSystem.get_multiplier(E.FIRE, E.LIGHT), 1.0, 0.01, "unlisted pair -> 1.0")

func test_names_and_icons_nonempty() -> void:
	var E = ElementalSystem.Element
	for e in [E.FIRE, E.ICE, E.LIGHTNING, E.WATER, E.EARTH, E.WIND, E.LIGHT, E.DARK, E.ARCANE]:
		assert_ne(ElementalSystem.get_element_name(e), "", "name for element %d non-empty" % e)
		assert_ne(ElementalSystem.get_element_icon(e), "", "icon for element %d non-empty" % e)
