extends TestSuite

## P8 skill learning: slots unlock by level, the battle menus only offer what is
## learned, level-ups report what was taught, and unlock levels survive a save.

func suite_name() -> String:
	return "SkillLearning"

func _skill(name: String, unlock: int) -> Skill:
	var s := Skill.new()
	s.skill_name = name
	s.unlock_level = unlock
	return s

## A hero shaped like the real ones: the first half of the pool are attacks,
## the second half specials. Categories matter because the stats page and the
## battle menus split on category now, not on index.
func _hero(unlocks: Array) -> Character:
	var c := Character.new()
	c.character_name = "Tester"
	c.base_hp = 100
	c.level = 1
	var list: Array[Skill] = []
	var half := unlocks.size() / 2
	for i in unlocks.size():
		var sk := _skill("Skill%d" % i, int(unlocks[i]))
		sk.category = Skill.SkillCategory.SPECIAL if i >= half else Skill.SkillCategory.ATTACK
		list.append(sk)
	c.skills = list
	return c

# ------------------------------------------------------------ default is open

func test_skills_are_known_by_default() -> void:
	# unlock_level defaults to 1, so enemy skills and every pre-P8 .tres keep
	# working without opting in.
	var s := Skill.new()
	assert_eq(s.unlock_level, 1, "skills default to known at level 1")
	var c := _hero([1, 1, 1, 1])
	assert_eq(c.known_skills().size(), 4, "a level-1 hero knows all level-1 skills")

# ------------------------------------------------------------ gating

func test_is_skill_known_respects_level() -> void:
	var c := _hero([1, 2, 7, 15])
	assert_true(c.is_skill_known(0), "level-1 skill known at level 1")
	assert_false(c.is_skill_known(1), "level-2 skill not yet known")
	c.level = 2
	assert_true(c.is_skill_known(1), "learned on reaching level 2")
	assert_false(c.is_skill_known(2), "level-7 skill still locked")
	c.level = 20
	assert_true(c.is_skill_known(3), "everything known at high level")

func test_is_skill_known_rejects_bad_index() -> void:
	var c := _hero([1, 1])
	assert_false(c.is_skill_known(-1), "negative index is not known")
	assert_false(c.is_skill_known(5), "out-of-range index is not known")

func test_known_skills_keeps_slot_order() -> void:
	var c := _hero([1, 9, 1, 9])
	var known := c.known_skills()
	assert_eq(known.size(), 2, "only the unlocked slots")
	assert_eq(known[0].skill_name, "Skill0", "first known is slot 0")
	assert_eq(known[1].skill_name, "Skill2", "second known is slot 2, order preserved")

# ------------------------------------------------------------ learning on level

func test_level_up_records_what_was_learned() -> void:
	var c := _hero([1, 2, 7, 15])
	c.experience_to_next = 10
	c.gain_experience(10)
	assert_eq(c.level, 2, "levelled once")
	assert_eq(c.pending_learned.size(), 1, "one skill learned")
	assert_eq(c.pending_learned[0].skill_name, "Skill1", "and it is the level-2 skill")

func test_level_up_with_nothing_to_learn() -> void:
	var c := _hero([1, 5, 9, 15])
	c.experience_to_next = 10
	c.gain_experience(10)
	assert_eq(c.level, 2, "levelled")
	assert_true(c.pending_learned.is_empty(), "no skill unlocks at level 2")

func test_multi_level_jump_collects_every_skill() -> void:
	# One big XP award can cross several levels; each one's skills must be
	# reported, not just the last.
	var c := _hero([1, 2, 3, 4])
	c.experience_to_next = 10
	c.gain_experience(500)
	assert_true(c.level >= 4, "jumped several levels (got %d)" % c.level)
	var names: Array[String] = []
	for s in c.pending_learned:
		names.append(s.skill_name)
	assert_true(names.has("Skill1"), "level-2 skill reported")
	assert_true(names.has("Skill2"), "level-3 skill reported")
	assert_true(names.has("Skill3"), "level-4 skill reported")

func test_pending_learned_resets_between_awards() -> void:
	# Otherwise a later battle would re-announce skills learned in an earlier one.
	var c := _hero([1, 2, 9, 15])
	c.experience_to_next = 10
	c.gain_experience(10)
	assert_eq(c.pending_learned.size(), 1, "learned on the first award")
	c.gain_experience(1)
	assert_true(c.pending_learned.is_empty(), "a later award starts clean")

func test_skills_unlocked_at() -> void:
	var c := _hero([1, 4, 4, 15])
	var at4 := c.skills_unlocked_at(4)
	assert_eq(at4.size(), 2, "two skills share level 4")
	assert_true(c.skills_unlocked_at(3).is_empty(), "nothing unlocks at level 3")

func test_next_skill_to_learn() -> void:
	var c := _hero([1, 7, 4, 15])
	var nxt := c.next_skill_to_learn()
	assert_false(nxt.is_empty(), "there is something still to learn")
	assert_eq(int(nxt["level"]), 4, "reports the SOONEST upcoming unlock, not slot order")
	assert_eq((nxt["skill"] as Skill).skill_name, "Skill2", "and the matching skill")
	c.level = 99
	assert_true(c.next_skill_to_learn().is_empty(), "nothing left once all learned")

# ------------------------------------------------------------ the real curve

func test_party_curve_is_applied() -> void:
	var party := PartyFactory.create_default_party()
	assert_eq(party.size(), 3, "three heroes")
	for hero in party:
		assert_eq(hero.skills.size(), 12, "%s keeps its whole pool" % hero.character_name)
		for i in 8:
			assert_eq(hero.skills[i].unlock_level, PartyFactory.SKILL_UNLOCK_LEVELS[i],
				"%s slot %d uses the shared curve" % [hero.character_name, i])

func test_starting_party_opens_with_a_usable_kit() -> void:
	# A hero that starts with no attack, or with no special, would break the
	# battle menus on turn one.
	for hero in PartyFactory.create_default_party():
		hero.level = 1
		var attacks := 0
		var specials := 0
		for i in 8:
			if not hero.is_skill_known(i):
				continue
			if i < 4:
				attacks += 1
			else:
				specials += 1
		assert_true(attacks >= 1, "%s starts with at least one attack" % hero.character_name)
		assert_true(specials >= 1, "%s starts with at least one special" % hero.character_name)
		assert_true(attacks + specials < 8, "%s does not start with everything" % hero.character_name)

func test_first_level_up_teaches_something() -> void:
	# An empty first level-up makes the feature look broken to a new player.
	assert_true(PartyFactory.SKILL_UNLOCK_LEVELS.has(2),
		"some slot unlocks at level 2 so the first level-up teaches a skill")

func test_curve_covers_every_slot_and_is_reachable() -> void:
	assert_eq(PartyFactory.SKILL_UNLOCK_LEVELS.size(), 12, "one entry per pool slot")
	for lvl in PartyFactory.SKILL_UNLOCK_LEVELS:
		assert_true(lvl >= 1, "no slot unlocks below level 1")
		assert_true(lvl <= 30, "every slot is reachable in a normal playthrough")

# ------------------------------------------------------------ persistence

func test_unlock_level_survives_a_save_round_trip() -> void:
	# Without this the level is lost on load and every skill silently becomes
	# available, handing the player their whole kit early.
	var c := _hero([1, 2, 7, 15])
	c.level = 3
	var d := SaveSerializer.serialize_character(c)
	var back := SaveSerializer.deserialize_character(d)
	assert_eq(back.skills.size(), 4, "all slots round-trip")
	for i in 4:
		assert_eq(back.skills[i].unlock_level, c.skills[i].unlock_level,
			"slot %d keeps its unlock level" % i)
	assert_true(back.is_skill_known(1), "a learned skill is still known after loading")
	assert_false(back.is_skill_known(2), "an unlearned skill is still locked after loading")

func test_pre_p8_save_loads_with_everything_known() -> void:
	# Old saves have no unlock_level key; defaulting to 1 keeps those players
	# able to use the skills they already had.
	var d := {"skill_name": "Legacy", "power": 1.0}
	var s := SaveSerializer.deserialize_skill(d)
	assert_eq(s.unlock_level, 1, "a skill without the key defaults to known")

# ------------------------------------------------------------ UI surfaces

func test_stats_page_lists_only_equipped_moves() -> void:
	# Locked and merely-learned moves are both absent: the page shows the kit the
	# character fights with, which is also the only thing that can be reordered.
	var c := _hero([1, 9, 1, 9, 1, 9, 1, 9])
	c.character_name = "Aria"
	c.level = 1
	c.auto_equip_unslotted()
	var vm := StatsScreen.build_hero_view_model(c)
	var attacks: Array = vm["attacks"]
	assert_eq(attacks.size(), c.equipped_skills(false).size(), "only equipped attacks appear")
	assert_true(attacks.size() < 4, "the level-9 moves are not listed at level 1")
	for a in attacks:
		assert_true(int(a["slot"]) >= 0, "every listed move carries a slot to reorder by")

func test_stats_page_hides_everything_when_nothing_is_equipped() -> void:
	var c := _hero([9, 9, 9, 9, 9, 9, 9, 9])
	c.level = 1
	var vm := StatsScreen.build_hero_view_model(c)
	assert_true((vm["attacks"] as Array).is_empty(), "no unlearned move is listed")
	assert_true((vm["specials"] as Array).is_empty(), "nor any unlearned special")
