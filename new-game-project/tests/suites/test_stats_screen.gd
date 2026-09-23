extends TestSuite

## Tests for StatsScreen.build_hero_view_model (Phase P1).
## Exercises the pure view-model builder against PartyFactory heroes — no scene
## tree needed. Confirms stat values, skill split (attacks 0-3 / specials 4+),
## resonance + bio metadata, and element affinity surface correctly.

func suite_name() -> String:
	return "StatsScreen"

func _aria() -> Character:
	for h in PartyFactory.create_default_party():
		if h.character_name == "Aria":
			return h
	return null

func test_basic_fields() -> void:
	var aria := _aria()
	var vm := StatsScreen.build_hero_view_model(aria)
	assert_eq(vm["name"], "Aria", "name surfaced")
	assert_eq(vm["class"], "Mage", "class surfaced")
	assert_eq(vm["level"], aria.level, "level surfaced")
	assert_eq(vm["element_name"], "Water", "element name surfaced")

func test_stats_match_getters() -> void:
	var aria := _aria()
	var vm := StatsScreen.build_hero_view_model(aria)
	assert_eq(vm["attack"], aria.attack_power(), "ATK matches getter")
	assert_eq(vm["defense"], aria.defense_power(), "DEF matches getter")
	assert_eq(vm["magic"], aria.magic_power(), "MAG matches getter")
	assert_eq(vm["arcane"], aria.arcane_power(), "ARC matches getter")
	assert_eq(vm["speed"], aria.speed(), "SPD matches getter")
	assert_eq(vm["max_hp"], aria.max_hp(), "max HP matches getter")
	assert_eq(vm["max_mp"], aria.max_mp(), "max MP matches getter")

func test_hp_mp_exp_text() -> void:
	var aria := _aria()
	var vm := StatsScreen.build_hero_view_model(aria)
	assert_eq(vm["hp_text"], "%d / %d" % [aria.current_hp, aria.max_hp()], "HP text formatted")
	assert_eq(vm["mp_text"], "%d / %d" % [aria.current_mp, aria.max_mp()], "MP text formatted")
	assert_eq(vm["exp_text"], "%d / %d" % [aria.experience, aria.experience_to_next], "XP text formatted")

func test_skill_split() -> void:
	# The page lists the EQUIPPED kit, not the whole learned pool: a move with no
	# slot has no order to rearrange, and swapping the pool belongs to a camp or
	# a trainer.
	var aria := _aria()
	var vm := StatsScreen.build_hero_view_model(aria)
	var attacks: Array = vm["attacks"]
	var specials: Array = vm["specials"]
	assert_eq(attacks.size(), aria.equipped_skills(false).size(), "equipped attacks listed")
	assert_eq(specials.size(), aria.equipped_skills(true).size(), "equipped specials listed")
	assert_true(attacks.size() < 6, "the unequipped rest of the pool is not shown")
	assert_eq(attacks[0]["name"], "Aqua Slash", "Aria's first attack is Aqua Slash")
	assert_eq(specials[0]["name"], "Tidal Requiem", "Aria's first special is Tidal Requiem")
	# Each entry knows its slot so a click can reorder it.
	assert_eq(int(attacks[0]["slot"]), 0, "first attack reports slot 0")
	assert_false(bool(attacks[0]["is_special"]), "and which list it belongs to")

func test_skill_view_model_shape() -> void:
	var aria := _aria()
	var vm := StatsScreen.build_hero_view_model(aria)
	var frost: Dictionary = vm["attacks"][1]  # Frost Bolt — MAGIC/ICE, 12 MP
	assert_eq(frost["name"], "Frost Bolt", "skill name surfaced")
	assert_eq(frost["mp_cost"], 12, "skill mp_cost surfaced")
	assert_eq(frost["element_name"], "Ice", "skill element surfaced")
	assert_true(str(frost["description"]) != "", "skill has a description")

func test_resonance_metadata() -> void:
	var aria := _aria()
	var vm := StatsScreen.build_hero_view_model(aria)
	assert_eq(vm["resonance_name"], "Tidal Requiem", "solo resonance name from meta")
	assert_true(str(vm["resonance_desc"]) != "", "solo resonance has a description")

func test_resonance_meter_surfaced() -> void:
	var aria := _aria()
	aria.resonance_meter = 42.0
	var vm := StatsScreen.build_hero_view_model(aria)
	assert_near(vm["resonance_meter"], 42.0, 0.01, "resonance meter surfaced")

func test_all_heroes_have_bio() -> void:
	for h in PartyFactory.create_default_party():
		var vm := StatsScreen.build_hero_view_model(h)
		assert_true(str(vm["bio"]) != "", "%s has a non-empty bio" % h.character_name)

func test_resonance_fallbacks_without_meta() -> void:
	var c := Character.new()
	c.character_name = "Nameless"
	var vm := StatsScreen.build_hero_view_model(c)
	assert_eq(vm["resonance_name"], "Ultimate", "resonance name falls back without meta")
	assert_eq(vm["bio"], "", "bio is empty without meta")
