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
