extends TestSuite

## Permission rules for changing a moveset across the three surfaces that allow
## it: the pause page (rearrange only), a campfire (budgeted equips) and a town
## trainer (unlimited).

func suite_name() -> String:
	return "LoadoutEditor"

func _snapshot() -> Dictionary:
	return {"swaps": GameManager.rest_swaps_remaining}

func _restore(s: Dictionary) -> void:
	GameManager.rest_swaps_remaining = s["swaps"]

func _hero() -> Character:
	var c := Character.new()
	c.character_name = "Tester"
	c.base_hp = 100
	c.level = 1
	var pool: Array[Skill] = []
	for i in 6:
		var s := Skill.new()
		s.skill_name = "Atk%d" % i
		s.category = Skill.SkillCategory.ATTACK
		pool.append(s)
	for i in 6:
		var s := Skill.new()
		s.skill_name = "Spc%d" % i
		s.category = Skill.SkillCategory.SPECIAL
		pool.append(s)
	c.skills = pool
	c.auto_equip_unslotted()
	return c

## First pool attack that isn't currently in a slot.
func _spare_attack(c: Character) -> int:
	for i in c.learned_pool_indices(false):
		if not c.is_equipped(i):
			return i
	return -1

# --------------------------------------------------------------- pause page

func test_pause_allows_rearranging_only() -> void:
	var ed := LoadoutEditor.new(LoadoutEditor.Mode.PAUSE)
	assert_true(ed.can_rearrange(), "reordering is allowed in the pause menu")
	assert_false(ed.can_equip(), "but not swapping a move in")
	assert_false(ed.can_clear(), "and not clearing a slot")

func test_pause_rearrange_actually_works() -> void:
	var c := _hero()
	var ed := LoadoutEditor.new(LoadoutEditor.Mode.PAUSE)
	var first := c.equipped_skill(false, 0).skill_name
	var second := c.equipped_skill(false, 1).skill_name
	assert_true(ed.rearrange(c, false, 0, 1), "slots reordered")
	assert_eq(c.equipped_skill(false, 0).skill_name, second, "they swapped places")
	assert_eq(c.equipped_skill(false, 1).skill_name, first, "both ways")

func test_pause_equip_is_refused_and_costs_nothing() -> void:
	var snap := _snapshot()
	var c := _hero()
	var ed := LoadoutEditor.new(LoadoutEditor.Mode.PAUSE)
	GameManager.rest_swaps_remaining = 2
	var spare := _spare_attack(c)
	assert_false(ed.equip(c, false, 0, spare), "equipping refused in the pause menu")
	assert_eq(GameManager.rest_swaps_remaining, 2, "and no allowance was spent")
	assert_false(ed.equip_blocked_reason().is_empty(), "the screen is told why")
	_restore(snap)

# ----------------------------------------------------------------- campfire

func test_campfire_equip_spends_an_allowance() -> void:
	var snap := _snapshot()
	var c := _hero()
	var ed := LoadoutEditor.new(LoadoutEditor.Mode.CAMPFIRE)
	GameManager.rest_swaps_remaining = 2
	var spare := _spare_attack(c)
	assert_true(ed.equip(c, false, 0, spare), "first swap allowed")
	assert_eq(GameManager.rest_swaps_remaining, 1, "one allowance spent")
	assert_eq(c.equipped_skill(false, 0).skill_name, c.skills[spare].skill_name,
		"and the move is actually equipped")
	_restore(snap)

func test_campfire_runs_out_of_swaps() -> void:
	var snap := _snapshot()
	var c := _hero()
	var ed := LoadoutEditor.new(LoadoutEditor.Mode.CAMPFIRE)
	GameManager.rest_swaps_remaining = 1
	assert_true(ed.equip(c, false, 0, _spare_attack(c)), "the last swap works")
	assert_false(ed.can_equip(), "now exhausted")
	var spare := _spare_attack(c)
	if spare >= 0:
		assert_false(ed.equip(c, false, 1, spare), "a further swap is refused")
	assert_false(ed.equip_blocked_reason().is_empty(), "with a reason to show")
	assert_eq(GameManager.rest_swaps_remaining, 0, "never goes negative")
	_restore(snap)

func test_campfire_clear_and_rearrange_stay_free() -> void:
	# The whole point of the rule: running out of swaps must not lock the player
	# out of tidying their existing loadout.
	var snap := _snapshot()
	var c := _hero()
	var ed := LoadoutEditor.new(LoadoutEditor.Mode.CAMPFIRE)
	GameManager.rest_swaps_remaining = 0
	assert_true(ed.rearrange(c, false, 0, 2), "reordering still allowed")
	assert_true(ed.clear(c, false, 3), "clearing a slot still allowed")
	assert_eq(GameManager.rest_swaps_remaining, 0, "and neither cost anything")
	_restore(snap)

func test_campfire_reports_remaining_swaps() -> void:
	var snap := _snapshot()
	var ed := LoadoutEditor.new(LoadoutEditor.Mode.CAMPFIRE)
	GameManager.rest_swaps_remaining = 2
	assert_eq(ed.swaps_remaining(), 2, "the screen can show the budget")
	GameManager.spend_rest_swap()
	assert_eq(ed.swaps_remaining(), 1, "and it counts down")
	_restore(snap)

# ------------------------------------------------------------------ trainer

func test_trainer_is_unlimited() -> void:
	var snap := _snapshot()
	var c := _hero()
	var ed := LoadoutEditor.new(LoadoutEditor.Mode.TRAINER)
	GameManager.rest_swaps_remaining = 0        # campfire budget is irrelevant here
	assert_true(ed.can_equip(), "a trainer is never gated by the rest allowance")
	assert_eq(ed.swaps_remaining(), -1, "reported as unlimited")
	var spare := _spare_attack(c)
	assert_true(ed.equip(c, false, 0, spare), "swap allowed with zero rest swaps")
	assert_eq(GameManager.rest_swaps_remaining, 0, "and the rest budget is untouched")
	assert_true(ed.equip_blocked_reason().is_empty(), "nothing to explain")
	_restore(snap)

# ------------------------------------------------------------------- guards

func test_reequipping_the_same_move_is_free_and_refused() -> void:
	# A stray double-click on the move already in that slot must not burn a swap.
	var snap := _snapshot()
	var c := _hero()
	var ed := LoadoutEditor.new(LoadoutEditor.Mode.CAMPFIRE)
	GameManager.rest_swaps_remaining = 2
	var already: int = c.equipped_attacks[0]
	assert_false(ed.equip(c, false, 0, already), "no-op rejected")
	assert_eq(GameManager.rest_swaps_remaining, 2, "and charged nothing")
	_restore(snap)

func test_wrong_category_is_refused_without_charge() -> void:
	var snap := _snapshot()
	var c := _hero()
	var ed := LoadoutEditor.new(LoadoutEditor.Mode.CAMPFIRE)
	GameManager.rest_swaps_remaining = 2
	assert_false(ed.equip(c, false, 0, 6), "a special cannot go in an attack slot")
	assert_eq(GameManager.rest_swaps_remaining, 2, "a refused swap costs nothing")
	_restore(snap)

func test_bad_input_is_refused_without_charge() -> void:
	var snap := _snapshot()
	var c := _hero()
	var ed := LoadoutEditor.new(LoadoutEditor.Mode.CAMPFIRE)
	GameManager.rest_swaps_remaining = 2
	assert_false(ed.equip(c, false, 0, 99), "pool index out of range")
	assert_false(ed.equip(c, false, 99, 0), "slot out of range")
	assert_false(ed.equip(null, false, 0, 0), "null character")
	assert_eq(GameManager.rest_swaps_remaining, 2, "none of which cost a swap")
	_restore(snap)
