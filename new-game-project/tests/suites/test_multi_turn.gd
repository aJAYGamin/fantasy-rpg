extends TestSuite

## Spec C: moves that play out over more than one turn — charge-ups, delayed
## strikes, recharge and timed buffs/debuffs. The manager is unpaced (a bare
## BattleManager), so every wait returns at once and a whole sequence of turns,
## enemy turns included, runs synchronously inside one call.
##
## Units have 5000 HP so nobody is downed by accident: defeating an ENEMY
## reports quest progress to the live GameManager. Enemies get their own
## species, so Memory Echo dodge never fires.

func suite_name() -> String:
	return "MultiTurn"

func _unit(name: String, hero: bool, speed := 10) -> Character:
	var c: Character = Character.new() if hero else Enemy.new()
	if not hero:
		(c as Enemy).species = "MultiTurnTestDummy"
	c.character_name = name
	c.base_hp = 5000
	c.base_mp = 500
	c.base_attack = 20
	c.base_magic = 20
	c.base_defense = 0
	c.base_arcane = 0
	c.base_speed = speed
	c.level = 1
	c.current_hp = c.max_hp()
	c.current_mp = c.max_mp()
	return c

func _skill(target: Skill.TargetType = Skill.TargetType.SINGLE_ENEMY) -> Skill:
	var s := Skill.new()
	s.skill_name = "Probe"
	s.target_type = target
	s.power = 1.0
	return s

## A harmless move: raises the user's own ARC (no damage, no randomness). ARC,
## so it never cancels a DEF/ATK debuff a test is watching.
func _tap() -> Skill:
	var s := Skill.new()
	s.skill_name = "Tap"
	s.skill_type = Skill.SkillType.STATUS
	s.status_type = Skill.StatusType.BUFF
	s.target_type = Skill.TargetType.SELF
	s.status_to_apply = "arcane_buff"
	return s

## A foe whose only move is `move` (so the AI always picks it). Slow by
## default, so it acts after the heroes each round.
func _foe(move: Skill = null, speed := 0) -> Character:
	var e := _unit("Foe", false, speed)
	e.skills = [move if move != null else _tap()] as Array[Skill]
	return e

func _battle(heroes: Array, foes: Array) -> BattleManager:
	var bm := BattleManager.new()
	var p: Array[Character] = []
	for h in heroes:
		p.append(h)
	var e: Array[Character] = []
	for f in foes:
		e.append(f)
	bm.start_battle(p, e)
	return bm

## The type of every status event, in order.
func _events(bm: BattleManager) -> Array:
	var out := []
	bm.status_effect_triggered.connect(func(_c, r): out.append(r.get("type", "")))
	return out

## Every action result and status event, in one ordered list.
func _log(bm: BattleManager) -> Array:
	var out := []
	bm.action_performed.connect(func(r): out.append(r.get("action", "")))
	bm.status_effect_triggered.connect(func(_c, r): out.append(r.get("type", "")))
	return out

## Every action result, in order.
func _hits(bm: BattleManager) -> Array:
	var out := []
	bm.action_performed.connect(func(r): out.append(r))
	return out

# --------------------------------------------------- Pacing

func test_a_bare_manager_never_waits() -> void:
	var bm := BattleManager.new()
	assert_false(bm.paced, "pacing is off until the battle scene turns it on")
	bm.free()

func test_an_enemy_turn_runs_to_the_next_hero_turn_at_once() -> void:
	# Enemy turns used to await real timers, so no test could drive one.
	var hero := _unit("Hero", true, 50)
	var foe := _foe()
	var bm := _battle([hero], [foe])
	assert_eq(bm.current_actor, hero, "the faster hero goes first")
	bm.player_use_skill(hero, _tap(), [hero])
	assert_true(foe.buffs.get("arcane", false), "the foe took its turn (Tap raised its ARC)")
	assert_eq(bm.current_actor, hero, "and the next round's turn is the hero's")
	assert_eq(bm.state, BattleManager.BattleState.CHOOSING_ACTION, "waiting for the hero again")
	bm.free()

func test_every_turn_loop_wait_goes_through_the_pacing_switch() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/battle/BattleManager.gd")
	assert_eq(src.count("create_timer("), 1, "only _pause() starts a timer")
	assert_false(src.contains("var hit_pause"), "Spec B's separate pause variables are gone")

# --------------------------------------------------- Timed buffs and debuffs

func test_a_timed_buff_lasts_its_owners_next_turns() -> void:
	var c := _unit("Timed", true)
	c.apply_buff("attack", 3)
	for t in 3:
		assert_false(c.tick_stat_timers(), "turn %d: nothing wore off" % (t + 1))
		assert_true(StatusSystem.is_effectively_buffed(c, "attack"), "turn %d: still buffed" % (t + 1))
	assert_true(c.tick_stat_timers(), "the 4th turn begins: it wears off")
	assert_false(StatusSystem.is_effectively_buffed(c, "attack"), "gone")

func test_an_effect_with_no_duration_lasts_the_battle() -> void:
	var c := _unit("Forever", true)
	c.apply_debuff("defense")
	for t in 10:
		c.tick_stat_timers()
	assert_true(StatusSystem.is_effectively_debuffed(c, "defense"), "every existing effect is untouched")

func test_a_permanent_effect_wins_either_way() -> void:
	var c := _unit("PermFirst", true)
	c.apply_buff("attack")
	c.apply_buff("attack", 2)
	for t in 5:
		c.tick_stat_timers()
	assert_true(StatusSystem.is_effectively_buffed(c, "attack"), "timed on top of permanent changes nothing")
	var d := _unit("TimedFirst", true)
	d.apply_buff("attack", 1)
	d.apply_buff("attack")
	for t in 5:
		d.tick_stat_timers()
	assert_true(StatusSystem.is_effectively_buffed(d, "attack"), "permanent on top of timed makes it permanent")

func test_re_applying_a_timed_effect_keeps_the_longer() -> void:
	var c := _unit("Refresh", true)
	c.apply_buff("speed", 1)
	c.apply_buff("speed", 3)
	for t in 3:
		c.tick_stat_timers()
	assert_true(StatusSystem.is_effectively_buffed(c, "speed"), "the longer duration holds")
	assert_true(c.tick_stat_timers(), "and ends after it")
	var d := _unit("NoShorten", true)
	d.apply_buff("speed", 3)
	d.apply_buff("speed", 1)
	for t in 3:
		d.tick_stat_timers()
	assert_true(StatusSystem.is_effectively_buffed(d, "speed"), "a shorter one never cuts it short")

func test_cancelling_a_timed_effect_clears_its_countdown() -> void:
	var c := _unit("Cancel", true)
	c.apply_debuff("defense", 2)
	c.apply_buff("defense")
	assert_false(c.debuff_turns.has("defense"), "the countdown goes with the cancelled debuff")
	c.apply_debuff("defense")
	for t in 5:
		c.tick_stat_timers()
	assert_true(StatusSystem.is_effectively_debuffed(c, "defense"), "a later permanent debuff is not cut short by it")

func test_the_chip_matches_the_multiplier_through_timed_and_permanent() -> void:
	# Review focus 4: whatever the order, the chip and the maths agree.
	var c := _unit("Chip", true)
	c.apply_buff("magic", 1)
	c.apply_buff("magic")
	assert_true(StatusSystem.is_effectively_buffed(c, "magic"), "buffed chip")
	assert_eq(StatusSystem.get_buff_multiplier(c, "magic"), 2.0, "x2 behind it")
	c.apply_debuff("magic", 2)
	assert_false(StatusSystem.is_effectively_buffed(c, "magic"), "the debuff cancelled the buff: no chip")
	assert_false(StatusSystem.is_effectively_debuffed(c, "magic"), "and no debuff chip either")
	assert_eq(StatusSystem.get_buff_multiplier(c, "magic"), 1.0, "x1 behind it")
	for t in 5:
		c.tick_stat_timers()
	assert_eq(StatusSystem.get_buff_multiplier(c, "magic"), 1.0, "no stale countdown brings anything back")

func test_a_battle_end_clears_every_countdown() -> void:
	var c := _unit("Done", true)
	c.apply_buff("attack", 3)
	c.apply_debuff("speed", 2)
	c.clear_battle_effects()
	assert_true(c.buff_turns.is_empty() and c.debuff_turns.is_empty(), "nothing carries into the next battle")

func test_a_timed_debuff_from_a_move_wears_off_on_the_targets_turns() -> void:
	var hero := _unit("Hero", true, 50)
	var foe := _foe()
	var bm := _battle([hero], [foe])
	var events := _events(bm)
	var s := _skill()
	s.power = 0.1
	s.status_to_apply = "defense_debuff"
	s.status_chance = 1.0
	s.effect_turns = 1
	bm.player_use_skill(hero, s, [foe])
	assert_true(StatusSystem.is_effectively_debuffed(foe, "defense"), "on through the foe's 1 turn")
	assert_false(events.has(StatusSystem.STATS_EXPIRED), "not worn off yet")
	bm.player_use_skill(hero, _tap(), [hero])
	assert_false(StatusSystem.is_effectively_debuffed(foe, "defense"), "gone when the foe's 2nd turn began")
	assert_true(events.has(StatusSystem.STATS_EXPIRED), "with a quiet refresh event")
	bm.free()

func test_a_target_buff_and_a_self_debuff_follow_the_moves_duration() -> void:
	var hero := _unit("Hero", true, 50)
	var foe := _foe()
	var bm := _battle([hero], [foe])
	var s := _skill()
	s.power = 0.1
	s.target_buff = "speed"
	s.self_debuff = "defense"
	s.effect_turns = 2
	bm.player_use_skill(hero, s, [foe])
	# Control returns at the hero's round-2 turn: the foe's turn and the hero's
	# own turn have each begun once since, so each countdown has ticked once.
	assert_eq(int(foe.buff_turns.get("speed", 0)), 1, "the foe's SPD buff is timed")
	assert_eq(int(hero.debuff_turns.get("defense", 0)), 1, "the hero's own DEF debuff is timed")
	bm.free()

# --------------------------------------------------- Recharge

func _status_move(token: String, target: Skill.TargetType) -> Skill:
	var s := Skill.new()
	s.skill_name = "Inflict"
	s.skill_type = Skill.SkillType.STATUS
	s.status_type = Skill.StatusType.DEBUFF
	s.target_type = target
	s.status_to_apply = token
	return s

func test_a_recharge_move_rests_the_users_next_turn() -> void:
	var hero := _unit("Kael", true, 50)
	var foe := _foe()
	var bm := _battle([hero], [foe])
	var events := _events(bm)
	var offered := []
	bm.turn_ready_for_action.connect(func(c): offered.append(c))
	var s := _skill()
	s.recharge_turns = 1
	bm.player_use_skill(hero, s, [foe])
	assert_eq(events.count(StatusSystem.RECHARGING), 1, "one rest, with its banner event")
	assert_eq(offered.filter(func(c): return c == hero).size(), 1, "round 2 was the rest; round 3 is offered")
	assert_eq(hero.recharge_turns_left, 0, "the rest is over")
	assert_eq(bm.current_actor, hero, "the hero chooses again")
	bm.free()

func test_a_stun_on_a_rest_turn_is_used_up_by_it() -> void:
	var a := _unit("A", true, 50)
	var b := _unit("B", true, 40)
	var foe := _foe()
	var bm := _battle([a, b], [foe])
	var s := _skill()
	s.recharge_turns = 1
	bm.player_use_skill(a, s, [foe])
	a.add_status(StatusSystem.STUN)
	bm.player_use_skill(b, _tap(), [b])
	assert_eq(bm.current_actor, b, "round 2: A rested, B is offered")
	assert_false(a.is_status(StatusSystem.STUN), "the stun went with the rest turn")
	bm.player_use_skill(b, _tap(), [b])
	assert_eq(bm.current_actor, a, "round 3: A acts — one turn lost, not two")
	bm.free()

func test_a_rest_turn_that_is_also_a_sleep_turn_costs_one_turn() -> void:
	# Review focus 5.
	var a := _unit("A", true, 50)
	var b := _unit("B", true, 40)
	var foe := _foe()
	var bm := _battle([a, b], [foe])
	var s := _skill()
	s.recharge_turns = 1
	bm.player_use_skill(a, s, [foe])
	a.add_status(StatusSystem.SLEEP)
	a.sleep_turn = 0
	bm.player_use_skill(b, _tap(), [b])
	assert_eq(a.recharge_turns_left, 0, "the rest happened")
	assert_eq(a.sleep_turn, 1, "and the sleep counter advanced on that same turn")
	bm.free()

func test_a_battle_end_clears_the_rest() -> void:
	var c := _unit("Tired", true)
	c.recharge_turns_left = 1
	c.clear_battle_effects()
	assert_eq(c.recharge_turns_left, 0, "no rest carries into the next battle")

func test_a_heros_recharge_skip_reads_as_recovering() -> void:
	assert_eq(StatusSystem.skipped_phrase("Kael", StatusSystem.RECHARGING), "Kael is recovering!", "banner text")

# --------------------------------------------------- Charge-ups

func _charge(target: Skill.TargetType = Skill.TargetType.SINGLE_ENEMY) -> Skill:
	var s := _skill(target)
	s.skill_name = "Gather"
	s.charge_turns = 1
	return s

func test_a_charge_up_hits_on_the_users_next_turn() -> void:
	var hero := _unit("Kael", true, 50)
	var foe := _foe()
	var bm := _battle([hero], [foe])
	var seen := _log(bm)
	var before := foe.current_hp
	bm.player_use_skill(hero, _charge(), [foe])
	# Round 1: the charge (banner only) and the foe's Tap. Round 2: the release,
	# then the foe's Tap. Round 3: the hero chooses again.
	assert_eq(seen, [StatusSystem.CHARGING, "buff", "skill_physical", "buff"], "nothing hits until the release")
	assert_true(foe.current_hp < before, "the release hit")
	assert_eq(bm.current_actor, hero, "then the hero chooses again")
	assert_true(bm.scheduled.is_empty(), "the charge is spent")
	bm.free()

func test_charging_pays_its_costs_once() -> void:
	var hero := _unit("Kael", true, 50)
	var foe := _foe()
	var bm := _battle([hero], [foe])
	var s := _charge()
	s.mp_cost = 10
	var mp := hero.current_mp
	bm.player_use_skill(hero, s, [foe])
	assert_eq(hero.current_mp, mp - 10, "paid when charging, not again on release")
	bm.free()

func test_a_release_is_measured_when_it_fires() -> void:
	# An ally's ATK buff on a charging hero makes the release hit harder.
	var a := _unit("A", true, 50)
	var b := _unit("B", true, 40)
	var foe := _foe()
	var bm := _battle([a, b], [foe])
	var hits := _hits(bm)
	var s := _charge()
	bm.player_use_skill(a, s, [foe])
	a.apply_buff("attack")
	var expected := s.calculate_value(a)
	bm.player_use_skill(b, _tap(), [b])
	var release := hits.filter(func(r): return r["action"] == "skill_physical")
	assert_eq(release.size(), 1, "one release")
	assert_eq(int(release[0]["value"]), expected, "with the buffed ATK (foe DEF is 0)")
	bm.free()

func test_a_stun_breaks_a_charge() -> void:
	var a := _unit("A", true, 50)
	var b := _unit("B", true, 40)
	var foe := _foe()
	var bm := _battle([a, b], [foe])
	var seen := _log(bm)
	var before := foe.current_hp
	bm.player_use_skill(a, _charge(), [foe])
	a.add_status(StatusSystem.STUN)
	bm.player_use_skill(b, _tap(), [b])
	assert_eq(foe.current_hp, before, "the charge never fired")
	assert_true(bm.scheduled.is_empty(), "and is gone")
	var broken := seen.find(StatusSystem.FOCUS_BROKEN)
	assert_true(broken >= 0, "the focus-broken banner event")
	assert_true(broken < seen.find(StatusSystem.STUN), "before the stun's skip banner")
	bm.free()

func test_sleep_breaks_a_charge() -> void:
	var a := _unit("A", true, 50)
	var b := _unit("B", true, 40)
	var foe := _foe()
	var bm := _battle([a, b], [foe])
	var before := foe.current_hp
	bm.player_use_skill(a, _charge(), [foe])
	a.add_status(StatusSystem.SLEEP)
	a.sleep_turn = 0   # the first sleep turn always skips
	bm.player_use_skill(b, _tap(), [b])
	assert_eq(foe.current_hp, before, "asleep: the charge never fired")
	assert_true(bm.scheduled.is_empty(), "and is gone")
	bm.free()

func test_a_sleeper_who_wakes_keeps_the_charge() -> void:
	var a := _unit("A", true, 50)
	var b := _unit("B", true, 40)
	var foe := _foe()
	var bm := _battle([a, b], [foe])
	var before := foe.current_hp
	bm.player_use_skill(a, _charge(), [foe])
	a.add_status(StatusSystem.SLEEP)
	a.sleep_turn = 4   # 0% to stay asleep: wakes and acts this turn
	bm.player_use_skill(b, _tap(), [b])
	assert_true(foe.current_hp < before, "woke and released")
	bm.free()

func test_a_downed_charger_loses_the_charge() -> void:
	var a := _unit("A", true, 50)
	var b := _unit("B", true, 40)
	var foe := _foe()
	var bm := _battle([a, b], [foe])
	bm.player_use_skill(a, _charge(), [foe])
	a.current_hp = 0
	bm.handle_defeat(a)
	assert_eq(bm._charge_of(a), null, "a downed charger's charge is dropped")
	bm.free()

func test_a_later_strike_replaces_a_fallen_single_target() -> void:
	var a := _unit("A", true)
	var b := _unit("B", true)
	var foe := _unit("Foe", false)
	var bm := BattleManager.new()
	bm.party = [a, b] as Array[Character]
	bm.enemies = [foe] as Array[Character]
	a.current_hp = 0
	var got := bm._strike_targets(foe, _skill(), [a] as Array[Character])
	assert_eq(got, [b] as Array[Character], "the only living hero takes it")
	var area := bm._strike_targets(foe, _skill(Skill.TargetType.ALL_ENEMIES), [] as Array[Character])
	assert_eq(area, [b] as Array[Character], "an area move hits whoever stands")
	b.current_hp = 0
	assert_true(bm._strike_targets(foe, _skill(), [a] as Array[Character]).is_empty(), "nobody standing: nothing")
	bm.free()

func test_an_enemy_charge_releases_without_the_ai_acting_again() -> void:
	# Review focus 1: the release IS the enemy's turn.
	var hero := _unit("Hero", true, 10)
	var foe := _foe(_charge(Skill.TargetType.ALL_ENEMIES), 50)
	var bm := _battle([hero], [foe])
	assert_eq(bm.scheduled.size(), 1, "round 1: the foe began charging")
	var previews := []
	bm.enemy_move_preview.connect(func(_e, m): previews.append(m))
	var hits := _hits(bm)
	var before := hero.current_hp
	bm.player_use_skill(hero, _tap(), [hero])
	var on_hero := hits.filter(func(r): return r["action"] == "skill_physical")
	assert_eq(on_hero.size(), 1, "round 2: one release")
	assert_true(hero.current_hp < before, "that hit the hero")
	assert_true(bm.scheduled.is_empty(), "and the AI did not start a new charge in the same turn")
	assert_true(previews.has("Gather"), "the move name showed under its card")
	bm.free()

func test_stunning_a_charging_enemy_breaks_its_attack() -> void:
	var hero := _unit("Hero", true, 10)
	var foe := _foe(_charge(Skill.TargetType.ALL_ENEMIES), 50)
	var bm := _battle([hero], [foe])
	var events := _events(bm)
	var before := hero.current_hp
	bm.player_use_skill(hero, _status_move("stun", Skill.TargetType.SINGLE_ENEMY), [foe])
	assert_eq(hero.current_hp, before, "the charged attack never landed")
	assert_true(events.has(StatusSystem.FOCUS_BROKEN), "focus broken")
	assert_true(bm.scheduled.is_empty(), "and the stunned foe did not charge again")
	bm.free()

func test_charge_banner_text() -> void:
	assert_eq(StatusSystem.multi_turn_phrase("Kael", {"type": StatusSystem.CHARGING}), "Kael is gathering power!", "charging")
	assert_eq(StatusSystem.multi_turn_phrase("Kael", {"type": StatusSystem.FOCUS_BROKEN}), "Kael's focus was broken!", "broken")
	assert_eq(StatusSystem.multi_turn_phrase("Kael", {"type": StatusSystem.STATS_EXPIRED}), "", "a quiet event has no banner")

# --------------------------------------------------- Delayed strikes

func _delayed(rounds := 1, target: Skill.TargetType = Skill.TargetType.SINGLE_ENEMY) -> Skill:
	var s := _skill(target)
	s.skill_name = "Later"
	s.delay_rounds = rounds
	return s

func test_a_delayed_strike_shows_nothing_until_the_round_ends() -> void:
	var hero := _unit("Aria", true, 50)
	var foe := _foe()
	var bm := _battle([hero], [foe])
	var seen := _log(bm)
	bm.player_use_skill(hero, _delayed(), [foe])
	assert_eq(seen, [StatusSystem.STRIKE_SCHEDULED, "buff", StatusSystem.STRIKE_LANDING, "skill_physical"],
			"cast quietly; the foe acts; then at the round's end it lands")
	bm.free()

func test_a_two_round_delay_lands_at_the_end_of_the_next_round() -> void:
	var hero := _unit("Aria", true, 50)
	var foe := _foe()
	var bm := _battle([hero], [foe])
	var before := foe.current_hp
	bm.player_use_skill(hero, _delayed(2), [foe])
	assert_eq(foe.current_hp, before, "round 1 ended: not yet")
	assert_eq(bm.scheduled.size(), 1, "still waiting")
	bm.player_use_skill(hero, _tap(), [hero])
	assert_true(foe.current_hp < before, "round 2 ended: it landed")
	assert_true(bm.scheduled.is_empty(), "and left the list")
	bm.free()

func test_delayed_strikes_land_in_the_order_cast() -> void:
	var a := _unit("A", true, 50)
	var b := _unit("B", true, 40)
	var foe := _foe()
	var bm := _battle([a, b], [foe])
	var landed := []
	bm.status_effect_triggered.connect(func(_c, r):
		if r.get("type", "") == StatusSystem.STRIKE_LANDING:
			landed.append(r["move"]))
	var first := _delayed()
	first.skill_name = "First"
	var second := _delayed()
	second.skill_name = "Second"
	bm.player_use_skill(a, first, [foe])
	bm.player_use_skill(b, second, [foe])
	assert_eq(landed, ["First", "Second"], "one at a time, in cast order")
	bm.free()

func test_a_landing_can_miss() -> void:
	var hero := _unit("Aria", true, 50)
	var foe := _foe()
	var bm := _battle([hero], [foe])
	var hits := _hits(bm)
	var s := _delayed()
	s.miss_chance = 1.0
	bm.player_use_skill(hero, s, [foe])
	assert_eq(hits.map(func(r): return r["action"]).filter(func(a): return a == "miss").size(), 1,
			"it rolled its miss chance when it landed")
	bm.free()

func test_a_delayed_strike_keeps_its_cast_time_strength() -> void:
	var hero := _unit("Aria", true, 50)
	var foe := _foe()
	var bm := _battle([hero], [foe])
	var hits := _hits(bm)
	var s := _delayed(2)
	var expected := s.calculate_value(hero)
	bm.player_use_skill(hero, s, [foe])
	hero.apply_debuff("attack")
	bm.player_use_skill(hero, _tap(), [hero])
	var landing := hits.filter(func(r): return r["action"] == "skill_physical")
	assert_eq(landing.size(), 1, "it landed")
	assert_eq(int(landing[0]["value"]), expected, "as strong as when cast, though the caster's ATK fell since")
	bm.free()

func test_a_fallen_casters_strike_lands_with_only_its_hits() -> void:
	# The caster is a HERO, downed by the foe before the round ends.
	var a := _unit("A", true, 50)
	var b := _unit("B", true, 40)
	var crush := _skill(Skill.TargetType.ALL_ENEMIES)
	crush.skill_name = "Crush"
	var foe := _foe(crush)
	var bm := _battle([a, b], [foe])
	var hits := _hits(bm)
	var s := _delayed()
	s.ally_heal_power = 1.0
	bm.player_use_skill(a, s, [foe])
	a.current_hp = 1   # the foe's Crush will down A before the round ends
	var foe_before := foe.current_hp
	bm.player_use_skill(b, _tap(), [b])
	assert_false(a.is_alive(), "the caster fell first")
	assert_true(foe.current_hp < foe_before, "the strike still landed")
	var from_a := hits.filter(func(r): return r["actor"] == a)
	assert_false(from_a.any(func(r): return r.get("is_first_target", false)), "no resonance for a fallen caster")
	assert_false(from_a.any(func(r): return r["action"] == "heal"), "and no ally heal")
	bm.free()

func test_a_landing_that_ends_the_battle_drops_the_rest() -> void:
	# Review focus 2. The hero is downed by the first landing (heroes may fall
	# in tests; enemies may not).
	var hero := _unit("Hero", true, 0)
	hero.current_hp = 1
	var foe1 := _foe(_delayed(1, Skill.TargetType.ALL_ENEMIES), 50)
	var foe2 := _foe(_delayed(1, Skill.TargetType.ALL_ENEMIES), 40)
	var bm := _battle([hero], [foe1, foe2])
	assert_eq(bm.scheduled.size(), 2, "both foes cast")
	var ended := []
	bm.battle_ended.connect(func(won, _r): ended.append(won))
	var events := _events(bm)
	bm.player_use_skill(hero, _tap(), [hero])
	assert_eq(ended, [false], "one defeat, once")
	assert_eq(events.count(StatusSystem.STRIKE_LANDING), 1, "the second strike never landed")
	assert_true(bm.scheduled.is_empty(), "and was dropped")
	assert_eq(bm.state, BattleManager.BattleState.BATTLE_OVER, "the battle is over")
	bm.free()

func test_a_new_battle_starts_with_nothing_scheduled() -> void:
	# Review focus 3: fleeing ends the scene and its manager; the next battle's
	# manager starts empty, and heroes' countdowns were cleared on the way out.
	var bm := BattleManager.new()
	assert_true(bm.scheduled.is_empty(), "nothing carried in")
	bm.free()

func test_landing_banner_text() -> void:
	assert_eq(StatusSystem.multi_turn_phrase("Aria", {"type": StatusSystem.STRIKE_LANDING, "move": "Deluge"}),
			"Deluge strikes!", "names the move")
	assert_eq(StatusSystem.multi_turn_phrase("Aria", {"type": StatusSystem.STRIKE_SCHEDULED}), "", "casting is quiet")
