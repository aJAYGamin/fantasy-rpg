extends TestSuite

func suite_name() -> String:
	return "ElementalSystem"

# NORMAL replaced NONE. It's now a real type with a few specific relationships
# (vs SPIRIT = 0.0, vs METAL = 0.5). Everything else falls back to 1.0.
func test_normal_has_specific_relationships() -> void:
	var E = ElementalSystem.Element
	assert_near(ElementalSystem.get_multiplier(E.NORMAL, E.SPIRIT), 0.0, 0.01, "Normal vs Spirit = 0 (no effect)")
	assert_near(ElementalSystem.get_multiplier(E.NORMAL, E.METAL), 0.5, 0.01, "Normal vs Metal = 0.5 (resisted)")
	assert_near(ElementalSystem.get_multiplier(E.NORMAL, E.FIRE), 1.0, 0.01, "Normal vs Fire = 1.0 (unlisted -> neutral)")

# Super-effective is 2.0x. All chart entries that represent weaknesses use 2.0.
func test_super_effective() -> void:
	var E = ElementalSystem.Element
	assert_near(ElementalSystem.get_multiplier(E.WATER, E.FIRE), 2.0, 0.01, "Water vs Fire = 2.0x")
	assert_near(ElementalSystem.get_multiplier(E.LIGHTNING, E.WATER), 2.0, 0.01, "Lightning vs Water = 2.0x")
	assert_near(ElementalSystem.get_multiplier(E.FIRE, E.NATURE), 2.0, 0.01, "Fire vs Nature = 2.0x")
	assert_near(ElementalSystem.get_multiplier(E.LIGHT, E.DARK), 2.0, 0.01, "Light vs Dark = 2.0x")

func test_resisted() -> void:
	var E = ElementalSystem.Element
	assert_near(ElementalSystem.get_multiplier(E.WATER, E.WATER), 0.5, 0.01, "Water vs Water = 0.5 (self-resist)")
	assert_near(ElementalSystem.get_multiplier(E.FIRE, E.FIRE), 0.5, 0.01, "Fire vs Fire = 0.5 (self-resist)")
	assert_near(ElementalSystem.get_multiplier(E.FIRE, E.WATER), 0.5, 0.01, "Fire vs Water = 0.5 (doused)")

func test_immunity() -> void:
	var E = ElementalSystem.Element
	assert_near(ElementalSystem.get_multiplier(E.LIGHTNING, E.EARTH), 0.0, 0.01, "Lightning vs Earth = 0 (grounded)")
	assert_near(ElementalSystem.get_multiplier(E.EARTH, E.WIND), 0.0, 0.01, "Earth vs Wind = 0 (blocked)")

func test_unlisted_pair_neutral() -> void:
	var E = ElementalSystem.Element
	# Fire vs Light has no chart entry -> falls back to NORMAL_MULTIPLIER.
	assert_near(ElementalSystem.get_multiplier(E.FIRE, E.LIGHT), 1.0, 0.01, "unlisted pair -> 1.0")

func test_combined_multiplier_aquatic_pyre_on_fire_drake() -> void:
	var E = ElementalSystem.Element
	# Aquatic Pyre (Fire + Water) hits Fire Drake (Fire + Dragon).
	# Pairs: water×fire=2.0, water×dragon=0.5, fire×fire=0.5, fire×dragon=0.5
	# Product = 2.0 * 0.5 * 0.5 * 0.5 = 0.25 (user's worked example).
	var m = ElementalSystem.get_combined_multiplier(E.WATER, E.FIRE, E.FIRE, E.DRAGON)
	assert_near(m, 0.25, 0.001, "Aquatic Pyre vs Fire Drake = 0.25")

func test_combined_multiplier_single_attacker_dual_defender() -> void:
	var E = ElementalSystem.Element
	# Water vs Fire+Dragon: water×fire=2.0, water×dragon=0.5 → 1.0
	var m = ElementalSystem.get_combined_multiplier(E.WATER, E.NORMAL, E.FIRE, E.DRAGON)
	assert_near(m, 1.0, 0.001, "Water vs Fire+Dragon = 2.0 * 0.5")

func test_combined_multiplier_dual_attacker_single_defender() -> void:
	var E = ElementalSystem.Element
	# Fire+Water vs Fire: water×fire=2.0, fire×fire=0.5 → 1.0
	var m = ElementalSystem.get_combined_multiplier(E.FIRE, E.WATER, E.FIRE, E.NORMAL)
	assert_near(m, 1.0, 0.001, "Fire+Water vs Fire = 2.0 * 0.5")

func test_combined_multiplier_single_vs_single_matches_get_multiplier() -> void:
	var E = ElementalSystem.Element
	var single = ElementalSystem.get_multiplier(E.WATER, E.FIRE)
	var combined = ElementalSystem.get_combined_multiplier(E.WATER, E.NORMAL, E.FIRE, E.NORMAL)
	assert_near(combined, single, 0.001, "single-vs-single combined == basic multiplier")

func test_amethyst_is_super_effective_against_all() -> void:
	var E = ElementalSystem.Element
	for def in [E.FIRE, E.WATER, E.ICE, E.DRAGON, E.LIGHT, E.DARK, E.SPIRIT]:
		assert_near(ElementalSystem.get_multiplier(E.AMETHYST, def), 2.0, 0.01,
			"Amethyst vs %d = 2.0" % def)

func test_names_and_icons_nonempty() -> void:
	var E = ElementalSystem.Element
	# Every element — including NORMAL — has a non-empty name AND icon, so
	# Normal-typed moves still read as a type on the stats screen and in battle.
	var all_elements = [
		E.NORMAL, E.FIRE, E.WATER, E.NATURE, E.ICE, E.LIGHTNING, E.EARTH, E.WIND,
		E.SOUND, E.PSYCHIC, E.SPIRIT, E.DRAGON, E.METAL, E.LIGHT, E.DARK, E.AMETHYST,
	]
	for e in all_elements:
		assert_ne(ElementalSystem.get_element_name(e), "", "name for element %d non-empty" % e)
		assert_ne(ElementalSystem.get_element_icon(e), "", "icon for element %d non-empty" % e)

# --------------------------------------------------- Spec B: element override

func test_an_override_replaces_exactly_one_pairing() -> void:
	var W := ElementalSystem.Element.WATER
	var N := ElementalSystem.Element.NORMAL
	assert_eq(ElementalSystem.get_combined_multiplier(W, N, W, N), 0.5, "water normally resists water")
	assert_eq(ElementalSystem.get_combined_multiplier(W, N, W, N, W, 2.0), 2.0, "the override makes it super-effective")
	assert_eq(ElementalSystem.get_combined_multiplier(W, N, W, N, W, 1.0), 1.0, "or merely effective")

func test_an_override_turns_an_immunity_into_a_hit() -> void:
	var W := ElementalSystem.Element.WATER
	var N := ElementalSystem.Element.NORMAL
	var NAT := ElementalSystem.Element.NATURE
	assert_eq(ElementalSystem.get_combined_multiplier(W, N, NAT, N), 0.0, "nature is immune to water")
	assert_eq(ElementalSystem.get_combined_multiplier(W, N, NAT, N, NAT, 1.0), 1.0, "an override can lift an immunity")

func test_a_dual_typed_defenders_other_element_still_counts() -> void:
	var W := ElementalSystem.Element.WATER
	var F := ElementalSystem.Element.FIRE
	var N := ElementalSystem.Element.NORMAL
	# Water vs Water (overridden to 2.0) x Water vs Fire (chart 2.0) = 4.0
	assert_eq(ElementalSystem.get_combined_multiplier(W, N, W, F, W, 2.0), 4.0, "only the named pairing changes")

func test_no_override_when_unset() -> void:
	var W := ElementalSystem.Element.WATER
	var N := ElementalSystem.Element.NORMAL
	assert_eq(ElementalSystem.get_combined_multiplier(W, N, W, N, N, 2.0), 0.5, "NORMAL means no override")
