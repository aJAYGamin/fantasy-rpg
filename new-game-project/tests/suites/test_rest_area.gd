extends TestSuite

## Rest areas: the top-up they give, and the swap allowance that gates loadout
## edits there (2 per rest, refilling every 5 battles). Town NPCs are
## unrestricted and so aren't gated by any of this.
##
## Touches GameManager, so every test snapshots and restores global state.

func suite_name() -> String:
	return "RestArea"

func _snapshot() -> Dictionary:
	return {
		"party": GameManager.party,
		"swaps": GameManager.rest_swaps_remaining,
		"battles": GameManager.battles_since_rest_refresh,
		"avail": GameManager.rest_available,
		"minutes": GameManager.clock.minutes,
	}

func _restore(s: Dictionary) -> void:
	GameManager.party = s["party"]
	GameManager.rest_swaps_remaining = s["swaps"]
	GameManager.battles_since_rest_refresh = s["battles"]
	GameManager.rest_available = s["avail"]
	GameManager.clock.set_minutes(s["minutes"])

func _hero(hp: int, mp: int) -> Character:
	var c := Character.new()
	c.character_name = "Tester"
	c.base_hp = 200
	c.base_mp = 100
	c.current_hp = hp
	c.current_mp = mp
	c.resonance_meter = 0.0
	return c

# ------------------------------------------------------------------- the heal

func test_rest_restores_a_quarter_of_max() -> void:
	var snap := _snapshot()
	var h := _hero(10, 5)
	GameManager.party = [h]
	var max_hp := h.max_hp()
	var max_mp := h.max_mp()
	GameManager.rest_at_camp()
	assert_eq(h.current_hp, 10 + int(round(max_hp * 0.25)), "a quarter of MAX hp is added")
	assert_eq(h.current_mp, 5 + int(round(max_mp * 0.25)), "a quarter of MAX mp is added")
	assert_near(h.resonance_meter, 10.0, 0.01, "resonance gains a flat 10")
	_restore(snap)

func test_rest_is_a_top_up_not_a_full_heal() -> void:
	# The distinction that matters: a badly hurt hero is not brought to full.
	var snap := _snapshot()
	var h := _hero(1, 0)
	GameManager.party = [h]
	GameManager.rest_at_camp()
	assert_true(h.current_hp < h.max_hp(), "still wounded after one rest")
	assert_true(h.current_hp > 1, "but better off than before")
	_restore(snap)

func test_rest_never_overshoots_the_maximum() -> void:
	var snap := _snapshot()
	var h := _hero(1, 1)
	h.current_hp = h.max_hp()
	h.current_mp = h.max_mp()
	h.resonance_meter = 96.0
	GameManager.party = [h]
	GameManager.rest_at_camp()
	assert_eq(h.current_hp, h.max_hp(), "hp clamped at max")
	assert_eq(h.current_mp, h.max_mp(), "mp clamped at max")
	assert_near(h.resonance_meter, 100.0, 0.01, "resonance clamped at 100")
	_restore(snap)

func test_rest_does_not_revive_the_downed() -> void:
	var snap := _snapshot()
	var down := _hero(0, 0)
	var up := _hero(10, 10)
	GameManager.party = [down, up]
	var healed: Dictionary = GameManager.rest_at_camp()["healed"]
	assert_eq(down.current_hp, 0, "a downed hero stays down — a rest is not a revive")
	assert_true(up.current_hp > 10, "the living are still healed")
	assert_false(healed.has(down.character_name) and healed.size() == 2,
		"the report covers only those actually healed")
	_restore(snap)

func test_rest_reports_what_it_restored() -> void:
	var snap := _snapshot()
	var h := _hero(10, 5)
	h.character_name = "Aria"
	GameManager.party = [h]
	var healed: Dictionary = GameManager.rest_at_camp()["healed"]
	assert_true(healed.has("Aria"), "the hero is reported by name")
	assert_true(int(healed["Aria"]["hp"]) > 0, "hp restored is reported")
	assert_true(int(healed["Aria"]["mp"]) > 0, "mp restored is reported")
	_restore(snap)

# -------------------------------------------------------------- swap allowance

func test_allowance_starts_full_and_spends_down() -> void:
	var snap := _snapshot()
	GameManager.rest_swaps_remaining = GameManager.REST_SWAP_ALLOWANCE
	assert_eq(GameManager.REST_SWAP_ALLOWANCE, 2, "two swaps per rest")
	assert_true(GameManager.can_spend_rest_swap(), "can swap at first")
	assert_true(GameManager.spend_rest_swap(), "first swap allowed")
	assert_true(GameManager.spend_rest_swap(), "second swap allowed")
	assert_false(GameManager.can_spend_rest_swap(), "allowance exhausted")
	assert_false(GameManager.spend_rest_swap(), "a third swap is refused")
	assert_eq(GameManager.rest_swaps_remaining, 0, "never goes negative")
	_restore(snap)

func test_allowance_refills_after_five_battles() -> void:
	var snap := _snapshot()
	GameManager.rest_swaps_remaining = 0
	GameManager.battles_since_rest_refresh = 0
	for i in range(GameManager.REST_REFRESH_BATTLES - 1):
		GameManager.register_battle_completed()
		assert_eq(GameManager.rest_swaps_remaining, 0,
			"still empty after %d battles" % (i + 1))
	GameManager.register_battle_completed()
	assert_eq(GameManager.rest_swaps_remaining, GameManager.REST_SWAP_ALLOWANCE,
		"refilled on the fifth battle")
	assert_eq(GameManager.battles_since_rest_refresh, 0, "counter resets after refilling")
	_restore(snap)

func test_battles_until_refresh_counts_down() -> void:
	var snap := _snapshot()
	GameManager.battles_since_rest_refresh = 0
	assert_eq(GameManager.battles_until_rest_refresh(), GameManager.REST_REFRESH_BATTLES,
		"full wait at the start")
	GameManager.register_battle_completed()
	assert_eq(GameManager.battles_until_rest_refresh(), GameManager.REST_REFRESH_BATTLES - 1,
		"one battle closer")
	_restore(snap)

func test_refill_is_idempotent() -> void:
	var snap := _snapshot()
	GameManager.rest_swaps_remaining = GameManager.REST_SWAP_ALLOWANCE
	GameManager.refill_rest_swaps()
	assert_eq(GameManager.rest_swaps_remaining, GameManager.REST_SWAP_ALLOWANCE,
		"refilling a full allowance changes nothing")
	_restore(snap)

func test_resting_does_not_itself_refill_swaps() -> void:
	# The allowance is tied to battles fought, not to visiting a campfire —
	# otherwise walking out and back in would farm free swaps.
	var snap := _snapshot()
	GameManager.party = [_hero(10, 10)]
	GameManager.rest_swaps_remaining = 0
	GameManager.rest_at_camp()
	assert_eq(GameManager.rest_swaps_remaining, 0, "a rest alone grants no swaps")
	_restore(snap)

# ------------------------------------------------------------------ free edits

func test_delete_and_rearrange_cost_nothing() -> void:
	# Only equipping is budgeted; the loadout screen must not spend an allowance
	# for clearing a slot or reordering.
	var snap := _snapshot()
	var c := Character.new()
	c.base_hp = 100
	var pool: Array[Skill] = []
	for i in 4:
		var s := Skill.new()
		s.skill_name = "Atk%d" % i
		pool.append(s)
	c.skills = pool
	c.auto_equip_unslotted()

	GameManager.rest_swaps_remaining = 0        # no allowance at all
	assert_true(c.unequip_slot(false, 0), "clearing a slot works with no allowance")
	assert_true(c.swap_slots(false, 1, 2), "rearranging works with no allowance")
	assert_eq(GameManager.rest_swaps_remaining, 0, "and neither spent anything")
	_restore(snap)

# ----------------------------------------------------------------- persistence

func test_rest_state_round_trips_through_a_save() -> void:
	var snap := _snapshot()
	GameManager.rest_swaps_remaining = 1
	GameManager.battles_since_rest_refresh = 3
	var data := {
		"rest_swaps_remaining": GameManager.rest_swaps_remaining,
		"battles_since_rest_refresh": GameManager.battles_since_rest_refresh,
	}
	GameManager.rest_swaps_remaining = 0
	GameManager.battles_since_rest_refresh = 0
	GameManager.rest_swaps_remaining = clampi(int(data.get("rest_swaps_remaining", 2)), 0, GameManager.REST_SWAP_ALLOWANCE)
	GameManager.battles_since_rest_refresh = maxi(0, int(data.get("battles_since_rest_refresh", 0)))
	assert_eq(GameManager.rest_swaps_remaining, 1, "allowance restored")
	assert_eq(GameManager.battles_since_rest_refresh, 3, "battle counter restored")
	_restore(snap)

func test_a_save_without_rest_keys_loads_with_a_full_allowance() -> void:
	# Pre-feature saves shouldn't start the player with zero swaps.
	var data := {}
	var swaps := clampi(int(data.get("rest_swaps_remaining", GameManager.REST_SWAP_ALLOWANCE)),
		0, GameManager.REST_SWAP_ALLOWANCE)
	assert_eq(swaps, GameManager.REST_SWAP_ALLOWANCE, "defaults to a full allowance")

func test_corrupt_allowance_is_clamped() -> void:
	var data := {"rest_swaps_remaining": 99}
	var swaps := clampi(int(data.get("rest_swaps_remaining", 2)), 0, GameManager.REST_SWAP_ALLOWANCE)
	assert_eq(swaps, GameManager.REST_SWAP_ALLOWANCE, "an out-of-range value is clamped")

# ------------------------------------------------------- campfire cooldown

func test_campfire_goes_on_cooldown_after_a_rest() -> void:
	# "Cannot rest now" until five more battles are fought.
	var snap := _snapshot()
	GameManager.party = [_hero(10, 10)]
	GameManager.rest_available = true
	assert_true(GameManager.can_rest(), "a fresh campfire is usable")
	GameManager.rest_at_camp(TimeOfDay.Phase.DAY)
	assert_false(GameManager.can_rest(), "used up straight after resting")
	for i in range(GameManager.REST_REFRESH_BATTLES - 1):
		GameManager.register_battle_completed()
		assert_false(GameManager.can_rest(), "still on cooldown after %d battles" % (i + 1))
	GameManager.register_battle_completed()
	assert_true(GameManager.can_rest(), "available again after five battles")
	_restore(snap)

func test_resting_refreshes_the_battle_counter() -> void:
	var snap := _snapshot()
	GameManager.party = [_hero(10, 10)]
	GameManager.battles_since_rest_refresh = 3
	GameManager.rest_available = true
	GameManager.rest_at_camp(TimeOfDay.Phase.DAY)
	assert_eq(GameManager.battles_since_rest_refresh, 0,
		"the five-battle wait starts from the rest, not from the last refill")
	_restore(snap)

func test_unavailable_prompt_text() -> void:
	assert_eq(GameManager.rest_unavailable_text(), "Cannot rest now",
		"the exact wording shown at a campfire on cooldown")

# ------------------------------------------------------- resting to a phase

func test_rest_advances_the_clock_to_the_chosen_phase() -> void:
	var snap := _snapshot()
	GameManager.party = [_hero(10, 10)]
	GameManager.rest_available = true
	GameManager.clock.set_minutes(600.0)                    # 10:00
	GameManager.rest_at_camp(TimeOfDay.Phase.NIGHT)
	assert_eq(GameManager.clock.phase(), TimeOfDay.Phase.NIGHT, "it is now night")
	assert_near(GameManager.clock.minutes, TimeOfDay.NIGHT_START, 0.01,
		"the clock sits exactly at the phase start")
	_restore(snap)

func test_resting_to_an_earlier_phase_rolls_into_tomorrow() -> void:
	# Resting until dawn at 10pm should reach the COMING dawn, not rewind.
	var snap := _snapshot()
	GameManager.party = [_hero(10, 10)]
	GameManager.rest_available = true
	GameManager.clock.set_minutes(1320.0)                   # 22:00
	var result := GameManager.rest_at_camp(TimeOfDay.Phase.DAWN)
	assert_eq(GameManager.clock.phase(), TimeOfDay.Phase.DAWN, "woke at dawn")
	assert_true(float(result["minutes_passed"]) > 0.0, "time moved forward, never backward")
	assert_near(float(result["minutes_passed"]), 420.0, 1.0, "22:00 to 05:00 is seven hours")
	_restore(snap)

func test_every_phase_is_a_valid_rest_target() -> void:
	for p in [TimeOfDay.Phase.DAWN, TimeOfDay.Phase.DAY, TimeOfDay.Phase.DUSK, TimeOfDay.Phase.NIGHT]:
		var t := TimeOfDay.new()
		t.set_minutes(0.0)
		t.advance_to_phase(p)
		assert_eq(t.phase(), p, "resting to phase %d lands in it" % p)
