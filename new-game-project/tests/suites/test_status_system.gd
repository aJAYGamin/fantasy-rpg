extends TestSuite

func suite_name() -> String:
	return "StatusSystem"

func _make(level: int = 1) -> Character:
	var c = Character.new()
	c.base_hp = 100
	c.base_mp = 50
	c.base_attack = 20
	c.base_defense = 10
	c.base_magic = 20
	c.base_arcane = 10
	c.base_speed = 20
	c.level = level
	c.current_hp = c.max_hp()
	c.current_mp = c.max_mp()
	return c

# --- Buff / Debuff math ---

func test_buff_doubles_stat() -> void:
	var c = _make()
	assert_eq(c.magic_power(), 20, "Lv1 base magic = 20")
	c.apply_buff(StatusSystem.STAT_MAG)
	assert_eq(c.magic_power(), 40, "MAG buff -> x2.0 -> 40")

func test_debuff_halves_stat() -> void:
	var c = _make()
	c.apply_debuff(StatusSystem.STAT_ATK)
	assert_eq(c.attack_power(), 10, "ATK debuff -> x0.5 -> 10")

func test_buff_and_debuff_cancel() -> void:
	var c = _make()
	c.apply_buff(StatusSystem.STAT_ATK)
	assert_eq(c.attack_power(), 40, "buff alone -> 40")
	# Re-applying a debuff to an already-buffed stat removes the buff (cancel).
	c.apply_debuff(StatusSystem.STAT_ATK)
	assert_eq(c.attack_power(), 20, "buff+debuff cancel -> back to base 20")
	assert_false(StatusSystem.is_effectively_buffed(c, StatusSystem.STAT_ATK), "no buff chip")
	assert_false(StatusSystem.is_effectively_debuffed(c, StatusSystem.STAT_ATK), "no debuff chip")

func test_debuff_then_buff_cancels() -> void:
	var c = _make()
	c.apply_debuff(StatusSystem.STAT_DEF)
	assert_eq(c.defense_power(), 5, "debuff -> x0.5")
	c.apply_buff(StatusSystem.STAT_DEF)
	assert_eq(c.defense_power(), 10, "buff cancels prior debuff -> base")

func test_re_applying_same_buff_is_noop() -> void:
	var c = _make()
	c.apply_buff(StatusSystem.STAT_SPD)
	c.apply_buff(StatusSystem.STAT_SPD)
	assert_eq(c.speed(), 40, "second buff does not stack -> still x2.0")

# --- Status stat penalties ---

func test_scorched_halves_attack() -> void:
	var c = _make()
	c.add_status(StatusSystem.SCORCHED)
	assert_eq(c.attack_power(), 10, "Scorched -> ATK x0.5")
	# MAG unaffected.
	assert_eq(c.magic_power(), 20, "Scorched does not touch MAG")

func test_frostbite_halves_magic() -> void:
	var c = _make()
	c.add_status(StatusSystem.FROSTBITE)
	assert_eq(c.magic_power(), 10, "Frostbite -> MAG x0.5")
	# ATK unaffected.
	assert_eq(c.attack_power(), 20, "Frostbite does not touch ATK")

func test_paralysis_quarters_speed() -> void:
	var c = _make()
	c.add_status(StatusSystem.PARALYSIS)
	assert_eq(c.speed(), 15, "Paralysis -> SPD x0.75 -> 15")

# --- Aria's worked example: status × debuff × (buff cancels) ---

func test_aria_example_frostbite_debuff_then_buff() -> void:
	var aria = _make()
	aria.base_magic = 100  # match user's example exactly
	assert_eq(aria.magic_power(), 100, "base MAG = 100")
	# Apply Frostbite + MAG debuff -> 100 * 0.5 * 0.5 = 25
	aria.add_status(StatusSystem.FROSTBITE)
	aria.apply_debuff(StatusSystem.STAT_MAG)
	assert_eq(aria.magic_power(), 25, "Frostbite + MAG debuff -> 25")
	# Apply MAG buff -> buff and debuff cancel; Frostbite remains -> 100 * 1.0 * 0.5 = 50
	aria.apply_buff(StatusSystem.STAT_MAG)
	assert_eq(aria.magic_power(), 50, "Buff cancels debuff, Frostbite stays -> 50")

# --- Mutex statuses replace each other ---

func test_mutex_status_blocks_new_when_existing() -> void:
	# First mutex status wins — new applications are rejected while one is
	# already active. Gives the player a chance to cleanse before pile-on.
	var c = _make()
	c.add_status(StatusSystem.POISON)
	assert_true(c.is_status(StatusSystem.POISON), "poison applied")
	c.add_status(StatusSystem.SCORCHED)
	assert_false(c.is_status(StatusSystem.SCORCHED), "scorched REJECTED while poisoned")
	assert_true(c.is_status(StatusSystem.POISON), "poison still active")
	# After cleansing poison, the next mutex status CAN apply.
	c.remove_status(StatusSystem.POISON)
	c.add_status(StatusSystem.SCORCHED)
	assert_true(c.is_status(StatusSystem.SCORCHED), "scorched applies after poison cleared")

func test_regenerate_coexists_with_mutex() -> void:
	# Regenerate is intentionally NOT in the mutex pool so positive effects
	# can stack with negative status. Poison + regenerate is a valid state.
	var c = _make()
	c.add_status(StatusSystem.POISON)
	c.add_status(StatusSystem.REGENERATE)
	assert_true(c.is_status(StatusSystem.POISON), "poison still active")
	assert_true(c.is_status(StatusSystem.REGENERATE), "regenerate coexists")

# --- Tick damage ---

func test_poison_tick_is_one_tenth_max_hp() -> void:
	var c = _make()
	c.add_status(StatusSystem.POISON)
	# Lv1 base 100 -> max_hp 100 -> 10/turn
	assert_eq(StatusSystem.get_tick_damage(c), 10, "poison tick = max_hp/10")
	var results = c.process_status_effects()
	assert_eq(results[0]["type"], "poison", "result.type = poison")
	assert_eq(results[0]["value"], 10, "result.value = 10")
	assert_eq(c.current_hp, 90, "HP reduced by 10")

func test_scorched_and_frostbite_tick_one_twentieth() -> void:
	var c = _make()
	c.add_status(StatusSystem.SCORCHED)
	assert_eq(StatusSystem.get_tick_damage(c), 5, "scorched tick = max_hp/20")
	# Replace with frostbite (mutex), tick should switch
	c.add_status(StatusSystem.FROSTBITE)
	assert_eq(StatusSystem.get_tick_damage(c), 5, "frostbite tick = max_hp/20")

func test_no_tick_when_no_dot_status() -> void:
	var c = _make()
	c.add_status(StatusSystem.STUN)
	assert_eq(StatusSystem.get_tick_damage(c), 0, "stun does no tick damage")
	c.add_status(StatusSystem.PARALYSIS)
	assert_eq(StatusSystem.get_tick_damage(c), 0, "paralysis does no tick damage")

# --- Skip-turn resolver ---

func test_stun_skips_and_auto_clears() -> void:
	var c = _make()
	c.add_status(StatusSystem.STUN)
	var r = StatusSystem.resolve_turn_skip(c)
	assert_eq(r["skip"], "stun", "stun causes skip")
	assert_false(r["woke_up"], "woke_up false when stunned")
	assert_false(c.is_status(StatusSystem.STUN), "stun auto-clears after consumed")

func test_sleep_eventually_wakes() -> void:
	# By turn 4 (sleep_turn = 4) the wake chance is 100% — deterministic.
	var c = _make()
	c.add_status(StatusSystem.SLEEP)
	# Force the counter past the random range so the test is deterministic.
	c.sleep_turn = 4
	var r = StatusSystem.resolve_turn_skip(c)
	assert_eq(r["skip"], "", "sleep_turn=4 -> guaranteed wake (no skip)")
	assert_true(r["woke_up"], "woke_up flag set so UI can banner it")
	assert_false(c.is_status(StatusSystem.SLEEP), "sleep cleared on wake")
	assert_eq(c.sleep_turn, 0, "sleep_turn reset")

func test_sleep_first_turn_always_sleeps() -> void:
	# sleep_turn = 0 -> 100% sleep chance; randf() < 1.0 is always true.
	var c = _make()
	c.add_status(StatusSystem.SLEEP)
	var r = StatusSystem.resolve_turn_skip(c)
	assert_eq(r["skip"], "sleep", "first turn of sleep always skips")
	assert_false(r["woke_up"], "still asleep -> woke_up stays false")
	assert_eq(c.sleep_turn, 1, "sleep_turn advanced")
	assert_true(c.is_status(StatusSystem.SLEEP), "still asleep")

# --- Apply-token parsing ---

func test_parse_buff_debuff_tokens() -> void:
	var p1 = StatusSystem.parse_apply_token("attack_buff")
	assert_eq(p1["kind"], "buff", "attack_buff -> buff")
	assert_eq(p1["value"], "attack", "stat extracted")
	var p2 = StatusSystem.parse_apply_token("magic_debuff")
	assert_eq(p2["kind"], "debuff", "magic_debuff -> debuff")
	assert_eq(p2["value"], "magic", "stat extracted")
	# Unknown stat falls through to "status" so a typo doesn't silently buff.
	var p3 = StatusSystem.parse_apply_token("bogus_buff")
	assert_eq(p3["kind"], "status", "unknown stat name treated as status")
	var p4 = StatusSystem.parse_apply_token("poison")
	assert_eq(p4["kind"], "status", "bare name -> status")
	assert_eq(p4["value"], "poison", "value preserved")

# --- Banner phrases ---

func test_applied_phrase() -> void:
	assert_eq(StatusSystem.applied_phrase("Aria", StatusSystem.POISON),
			"Aria was Poisoned!", "poison applied phrasing")
	assert_eq(StatusSystem.applied_phrase("Kael", StatusSystem.SLEEP),
			"Kael fell Asleep!", "sleep applied phrasing")
	assert_eq(StatusSystem.applied_phrase("Lyra", StatusSystem.FROSTBITE),
			"Lyra was Frostbitten!", "frostbite applied phrasing")
	assert_eq(StatusSystem.applied_phrase("Storm Eagle", StatusSystem.STUN),
			"Storm Eagle was Stunned!", "stun applied phrasing")
	assert_eq(StatusSystem.applied_phrase("Void Shade", StatusSystem.PARALYSIS),
			"Void Shade was Paralyzed!", "paralysis applied phrasing")

func test_skipped_phrase_stun_is_reoriented() -> void:
	# Per design: stun's skip banner is softer because the actor recovers.
	assert_eq(StatusSystem.skipped_phrase("Aria", StatusSystem.STUN),
			"Aria reoriented themself", "stun skip phrasing")
	assert_eq(StatusSystem.skipped_phrase("Kael", StatusSystem.SLEEP),
			"Kael is Asleep!", "sleep skip phrasing")
	assert_eq(StatusSystem.skipped_phrase("Lyra", StatusSystem.PARALYSIS),
			"Lyra is Paralyzed!", "paralysis skip phrasing")

func test_woke_phrase() -> void:
	assert_eq(StatusSystem.woke_phrase("Aria"), "Aria woke up!", "wake phrasing")

# --- clear_battle_effects ---

func test_clear_battle_effects_wipes_everything() -> void:
	var c = _make()
	c.add_status(StatusSystem.POISON)
	c.apply_buff(StatusSystem.STAT_ATK)
	c.apply_debuff(StatusSystem.STAT_DEF)
	c.sleep_turn = 3
	c.clear_battle_effects()
	assert_eq(c.status_effects.size(), 0, "all statuses cleared")
	assert_eq(c.buffs.size(), 0, "buffs cleared")
	assert_eq(c.debuffs.size(), 0, "debuffs cleared")
	assert_eq(c.sleep_turn, 0, "sleep counter cleared")
	assert_eq(c.attack_power(), 20, "stats back to base after clear")
