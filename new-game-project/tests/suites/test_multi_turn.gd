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
