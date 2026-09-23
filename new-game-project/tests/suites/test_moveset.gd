extends TestSuite

## Movesets: a pool of up to 20 learnable skills against 4 equipped attack and
## 4 equipped special slots. Covers equip/unequip/rearrange rules, auto-equip,
## repair of a stale loadout, and the save round-trip.

func suite_name() -> String:
	return "Moveset"

func _skill(name: String, special: bool, unlock: int = 1) -> Skill:
	var s := Skill.new()
	s.skill_name = name
	s.unlock_level = unlock
	s.category = Skill.SkillCategory.SPECIAL if special else Skill.SkillCategory.ATTACK
	return s

## Hero with `atk` attacks then `spc` specials, all known at level 1.
func _hero(atk: int, spc: int) -> Character:
	var c := Character.new()
	c.character_name = "Tester"
	c.base_hp = 100
	c.level = 1
	var pool: Array[Skill] = []
	for i in atk:
		pool.append(_skill("Atk%d" % i, false))
	for i in spc:
		pool.append(_skill("Spc%d" % i, true))
	c.skills = pool
	return c

# ------------------------------------------------------------------ categories

func test_skill_category_defaults_to_attack() -> void:
	# Enemy skills and every pre-existing .tres never set a category.
	var s := Skill.new()
	assert_true(s.is_attack_category(), "a bare skill is an attack")
	assert_false(s.is_special_category(), "and not a special")

func test_learned_pool_is_split_by_category() -> void:
	var c := _hero(6, 6)
	assert_eq(c.learned_pool_indices(false).size(), 6, "six attacks in the pool")
	assert_eq(c.learned_pool_indices(true).size(), 6, "six specials in the pool")

func test_pool_excludes_skills_below_their_unlock_level() -> void:
	var c := _hero(2, 2)
	c.skills.append(_skill("Late", false, 9))
	assert_eq(c.learned_pool_indices(false).size(), 2, "the level-9 move is not in the pool yet")
	c.level = 9
	assert_eq(c.learned_pool_indices(false).size(), 3, "and appears once the level is reached")

# ------------------------------------------------------------------ auto-equip

func test_auto_equip_fills_slots_in_pool_order() -> void:
	var c := _hero(6, 6)
	c.auto_equip_unslotted()
	var atk := c.equipped_skills(false)
	var spc := c.equipped_skills(true)
	assert_eq(atk.size(), Character.EQUIP_SLOTS, "four attack slots filled")
	assert_eq(spc.size(), Character.EQUIP_SLOTS, "four special slots filled")
	assert_eq(atk[0].skill_name, "Atk0", "first pool attack takes the first slot")
	assert_eq(spc[0].skill_name, "Spc0", "first pool special takes the first slot")

func test_auto_equip_leaves_the_surplus_in_the_pool() -> void:
	# Six attacks into four slots: the extra two stay learnable but unequipped,
	# which is the whole point of the system.
	var c := _hero(6, 6)
	c.auto_equip_unslotted()
	var equipped := 0
	for i in c.skills.size():
		if c.is_equipped(i):
			equipped += 1
	assert_eq(equipped, Character.EQUIP_SLOTS * 2, "only eight of the twelve are equipped")

func test_auto_equip_does_not_disturb_existing_slots() -> void:
	var c := _hero(6, 6)
	c.equip_skill(false, 0, 2)          # deliberately put Atk2 first
	c.auto_equip_unslotted()
	assert_eq(c.equipped_skill(false, 0).skill_name, "Atk2", "a manual choice survives auto-equip")

# ------------------------------------------------------------------ equipping

func test_equip_rejects_the_wrong_category() -> void:
	var c := _hero(4, 4)
	assert_false(c.equip_skill(false, 0, 4), "a special cannot go in an attack slot")
	assert_false(c.equip_skill(true, 0, 0), "an attack cannot go in a special slot")

func test_equip_rejects_unlearned_and_bad_input() -> void:
	var c := _hero(2, 2)
	c.skills.append(_skill("Late", false, 9))
	assert_false(c.equip_skill(false, 0, 4), "cannot equip a move below its unlock level")
	assert_false(c.equip_skill(false, 9, 0), "slot out of range")
	assert_false(c.equip_skill(false, 0, 99), "pool index out of range")
	assert_false(c.equip_skill(false, 0, -1), "negative pool index")

func test_equipping_a_skill_twice_moves_it() -> void:
	# Otherwise the same move could occupy two slots and the player would lose a
	# slot's worth of loadout without being told.
	var c := _hero(4, 4)
	assert_true(c.equip_skill(false, 0, 0), "equipped into slot 0")
	assert_true(c.equip_skill(false, 2, 0), "same skill into slot 2")
	assert_eq(c.equipped_skill(false, 0), null, "it left slot 0")
	assert_eq(c.equipped_skill(false, 2).skill_name, "Atk0", "and now sits in slot 2")

func test_equip_overwrites_the_occupant() -> void:
	var c := _hero(4, 4)
	c.equip_skill(false, 0, 0)
	c.equip_skill(false, 0, 1)
	assert_eq(c.equipped_skill(false, 0).skill_name, "Atk1", "the slot holds the new move")

# ------------------------------------------------------------------ free edits

func test_unequip_clears_a_slot_without_forgetting_the_skill() -> void:
	var c := _hero(4, 4)
	c.equip_skill(false, 1, 1)
	assert_true(c.unequip_slot(false, 1), "slot cleared")
	assert_eq(c.equipped_skill(false, 1), null, "slot is empty")
	assert_true(c.is_skill_known(1), "the skill is still learned — delete means unequip")
	assert_false(c.unequip_slot(false, 1), "clearing an empty slot is a no-op")

func test_swap_slots_rearranges() -> void:
	var c := _hero(4, 4)
	c.equip_skill(false, 0, 0)
	c.equip_skill(false, 1, 1)
	assert_true(c.swap_slots(false, 0, 1), "slots swapped")
	assert_eq(c.equipped_skill(false, 0).skill_name, "Atk1", "slot 0 now holds the other move")
	assert_eq(c.equipped_skill(false, 1).skill_name, "Atk0", "and vice versa")
	assert_false(c.swap_slots(false, 0, 0), "swapping a slot with itself is a no-op")
	assert_false(c.swap_slots(false, 0, 9), "out-of-range swap refused")

# ------------------------------------------------------------------ battle view

func test_equipped_skills_skips_empty_slots() -> void:
	var c := _hero(4, 4)
	c.auto_equip_unslotted()
	c.unequip_slot(false, 1)
	var atk := c.equipped_skills(false)
	assert_eq(atk.size(), 3, "the emptied slot is not offered in battle")
	for s in atk:
		assert_true(s != null, "no nulls reach the menu")

func test_level_up_auto_equips_into_a_free_slot() -> void:
	var c := _hero(2, 1)
	c.skills.append(_skill("Learned", false, 2))
	c.auto_equip_unslotted()
	c.experience_to_next = 10
	c.gain_experience(10)
	assert_eq(c.level, 2, "levelled")
	var names: Array[String] = []
	for s in c.equipped_skills(false):
		names.append(s.skill_name)
	assert_true(names.has("Learned"), "a newly learned move claims a free slot automatically")

func test_level_up_with_full_slots_leaves_the_move_in_the_pool() -> void:
	var c := _hero(4, 1)
	c.skills.append(_skill("Extra", false, 2))
	c.auto_equip_unslotted()          # all four attack slots taken
	c.experience_to_next = 10
	c.gain_experience(10)
	var names: Array[String] = []
	for s in c.equipped_skills(false):
		names.append(s.skill_name)
	assert_false(names.has("Extra"), "no slot is stolen from the player's chosen loadout")
	assert_true(c.is_skill_known(c.skills.size() - 1), "but the move is learned and swappable")

# ------------------------------------------------------------------ repair

func test_prune_drops_slots_that_are_no_longer_valid() -> void:
	var c := _hero(4, 4)
	c.auto_equip_unslotted()
	# Simulate a stale save: a slot pointing past the pool, and one at a move
	# the character has not reached the level for.
	c.skills[1].unlock_level = 99
	c.equipped_attacks[3] = 999
	c.prune_equipped()
	assert_eq(c.equipped_attacks[3], -1, "out-of-range slot cleared")
	for slot in Character.EQUIP_SLOTS:
		var s := c.equipped_skill(false, slot)
		if s != null:
			assert_ne(s.skill_name, "Atk1", "the now-locked move is no longer equipped")

func test_prune_rejects_a_category_mismatch() -> void:
	var c := _hero(4, 4)
	c.equipped_attacks[0] = 5          # index 5 is a special
	c.prune_equipped()
	assert_eq(c.equipped_attacks[0], -1, "a special sitting in an attack slot is cleared")

# ------------------------------------------------------------------ real party

func test_default_party_has_a_pool_bigger_than_its_slots() -> void:
	for hero in PartyFactory.create_default_party():
		assert_eq(hero.skills.size(), 12, "%s defines 12 moves" % hero.character_name)
		assert_true(hero.skills.size() <= Character.MAX_SKILLS, "within the 20 cap")
		var atk := 0
		var spc := 0
		for s in hero.skills:
			if s.is_special_category():
				spc += 1
			else:
				atk += 1
		assert_eq(atk, 6, "%s has six attacks, more than the four slots" % hero.character_name)
		assert_eq(spc, 6, "%s has six specials" % hero.character_name)

func test_default_party_starts_with_a_usable_loadout() -> void:
	for hero in PartyFactory.create_default_party():
		assert_true(hero.equipped_skills(false).size() >= 1,
			"%s starts with an attack equipped" % hero.character_name)
		assert_true(hero.equipped_skills(true).size() >= 1,
			"%s starts with a special equipped" % hero.character_name)

func test_curve_and_category_tables_line_up() -> void:
	assert_eq(PartyFactory.SKILL_UNLOCK_LEVELS.size(), PartyFactory.SKILL_CATEGORIES.size(),
		"one category per unlock entry")
	for hero in PartyFactory.create_default_party():
		for i in hero.skills.size():
			assert_eq(hero.skills[i].category, PartyFactory.SKILL_CATEGORIES[i],
				"%s slot %d category matches the table" % [hero.character_name, i])

# ------------------------------------------------------------------ persistence

func test_loadout_survives_a_save_round_trip() -> void:
	var c := _hero(6, 6)
	c.auto_equip_unslotted()
	c.equip_skill(false, 0, 4)        # a deliberate non-default choice
	c.unequip_slot(true, 3)
	var before_atk: Array[String] = []
	for s in c.equipped_skills(false):
		before_atk.append(s.skill_name)

	var back := SaveSerializer.deserialize_character(SaveSerializer.serialize_character(c))
	var after_atk: Array[String] = []
	for s in back.equipped_skills(false):
		after_atk.append(s.skill_name)
	assert_eq(after_atk, before_atk, "the chosen attack loadout is restored exactly")
	assert_eq(back.skills.size(), 12, "the whole pool round-trips, not just equipped moves")

func test_skill_category_survives_a_save_round_trip() -> void:
	var c := _hero(2, 2)
	var back := SaveSerializer.deserialize_character(SaveSerializer.serialize_character(c))
	assert_true(back.skills[0].is_attack_category(), "attack stays an attack")
	assert_true(back.skills[2].is_special_category(), "special stays a special")

func test_pre_moveset_save_still_loads_playable() -> void:
	# An older save has no equipped_* keys at all; the loader must not leave the
	# hero with an empty battle menu.
	var c := _hero(4, 4)
	c.auto_equip_unslotted()
	var d := SaveSerializer.serialize_character(c)
	d.erase("equipped_attacks")
	d.erase("equipped_specials")
	var back := SaveSerializer.deserialize_character(d)
	assert_true(back.equipped_skills(false).size() >= 1, "attacks were auto-equipped on load")
	assert_true(back.equipped_skills(true).size() >= 1, "specials were auto-equipped on load")
