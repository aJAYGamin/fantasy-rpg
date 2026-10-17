# Multi-Turn Moves Implementation Plan (Spec C)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four multi-turn move shapes — charge-up, delayed strike, recharge, timed buffs/debuffs — as plain move options resolved by the one battle resolver, shown off by nine new hero moves and four enemy moves.

**Architecture:** One scheduled-move list in `BattleManager` holds charge-ups (fire on the user's next turn) and delayed strikes (fire at the end of a round); per-character countdowns hold recharge and timed stats. The resolver splits into *use* (check, measure, pay, maybe schedule) and *strike* (Spec B's paced beats). Every wait in the turn loop goes through one pacing switch, so whole multi-turn sequences — enemy turns included — run synchronously in tests.

**Tech Stack:** Godot 4.6.1, GDScript, the project's own headless `TestSuite` runner.

**Spec:** `.claude/docs/superpowers/specs/2026-10-10-multi-turn-moves-design.md`

## Global Constraints

- **Godot 4.6.1**, binary `/Applications/Godot.app/Contents/MacOS/Godot`. All paths below are relative to `new-game-project/` unless they start with `.claude/`.
- **Run tests** from `new-game-project/`: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/TestRunner.tscn --quit-after 5`. **Baseline: 3896 passed, 0 failed.** Never let it drop. A GDScript parse error silently drops a whole suite — if a suite's assertion count does not go UP after adding tests, look for a parse error in the output.
- **Known warning set** in a full run (not yours): invalid save slot 99 / -1, QuestFactory unknown quest, Boss summon / BossPhase warnings, ItemFactory / EquipmentFactory unknown-name warnings, two `Skill stat 'burn'` warnings, Godot exit leaks. Anything else is new and must be fixed or reported.
- **Branch `multi-turn-moves`** — already created with the spec committed. Never commit to `main`; never create git worktrees.
- **Commit with `git commit -F <file>`**: subject line, a **blank line**, then the Co-Authored-By trailer your own instructions specify. Stage files by name; never stage `.DS_Store`.
- **Tests run synchronously in one frame.** No `await` in tests.
- **Never kill an ENEMY in a test** unless defeat is what the test is about: `BattleManager.handle_defeat` reports quest progress to the live `GameManager`. Downing a HERO is fine.
- **Skills are read-only at runtime.** No code may write to a `Skill` during battle — enemies share the library's cached objects. Per-use state lives on the `Character` or in `BattleManager`.
- **Every new option defaults to "off"**, and every existing buff/debuff keeps lasting the whole battle.
- **Never run** `tools/capture_move_baseline` or `tools/extract_move_library`. Adding a move to a baselined enemy is recorded by appending an entry to `tests/fixtures/move_library_baseline.json` with the **Edit tool** (python3 is not on this project's allowlist).
- **Play-test flags stay at shipping values in every commit**: `PartyFactory.TEST_UNLOCK_ALL_SKILLS := false`, `GameManager.REST_REFRESH_BATTLES := 5`, `BattleScene.TEST_SHOW_ENEMY_HP := false`.
- **No new `class_name`.** One new suite file, `tests/suites/test_multi_turn.gd`: register it in `tests/TestRunner.gd` `SUITE_PATHS`, run the editor rescan once (`/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --quit-after 3 --path .`) so Godot writes its `.uid`, and commit that `.uid`.
- **Pacing constants** (BattleManager): `HIT_PAUSE 0.8`, `ACTION_PAUSE 1.0`, `THINK_PAUSE 0.4`, `PREVIEW_PAUSE 1.0`, `WAKE_PAUSE 1.75`, `SKIP_PAUSE 1.9`, `BANNER_PAUSE 1.75`.
- **Exact banner text**: `"<Name> is gathering power!"`, `"<Name>'s focus was broken!"`, `"<Name> is recovering!"`, `"<Move> strikes!"`.
- **Exact effect tags**: `Charges 1 turn`, `Lands at round end`, `Lands in N rounds`, `Rests 1 turn` / `Rests N turns`, `Lasts 1 turn` / `Lasts N turns`.
- **New hero pool slots 16–18** (indices 15–17): unlock levels `6, 11, 16`; categories `ATTACK, SPECIAL, SPECIAL`.

## Review Focus

1. **An enemy's charge through the real turn loop** — a release must not also run the enemy AI (two actions in one turn). Pinned by Task 5 `test_an_enemy_charge_releases_without_the_ai_acting_again`.
2. **A delayed strike that ends the battle** while more are due — later landings must not run against a finished battle (rewards twice, a second end screen). Pinned by Task 6 `test_a_landing_that_ends_the_battle_drops_the_rest`.
3. **Fleeing with a delayed strike scheduled** — nothing may carry into the next battle. Pinned by Task 6 `test_a_new_battle_starts_with_nothing_scheduled` and Task 4 `test_a_battle_end_clears_the_rest`.
4. **Timed and permanent on the same stat**, both orders, then cancelled — the chip must match the multiplier. Pinned by Task 3 `test_the_chip_matches_the_multiplier_through_timed_and_permanent`.
5. **A recharging hero whose rest turn is also a sleep turn** — one turn lost, sleep counter advanced. Pinned by Task 4 `test_a_rest_turn_that_is_also_a_sleep_turn_costs_one_turn`.

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `scripts/battle/BattleManager.gd` | pacing switch, `_end_turn`, use/strike split, scheduled list, turn-start and round-end hooks | 1, 3, 4, 5, 6 |
| `scripts/battle/BattleScene.gd` | turns pacing on; phrases the charge / landing banners | 1, 5 |
| `scripts/characters/Skill.gd` | the four options, `applies_stat_effect`, effect tags | 2 |
| `scripts/save/SaveSerializer.gd` | saves the four options | 2 |
| `scripts/characters/Character.gd` | timed buff/debuff countdowns, `recharge_turns_left` | 3, 4 |
| `scripts/characters/StatusSystem.gd` | event-type constants, colours, phrases | 3, 4, 5, 6 |
| `data/skills/*.tres` (13 new) | the moves | 7, 8 |
| `scripts/PartyFactory.gd` | pools 15 → 18 | 7 |
| `data/enemies/{void_shade,earth_golem,dark_wraith,goblin_warlord}.tres` | enemy wiring | 8 |
| `tests/fixtures/move_library_baseline.json` | records the four enemy additions | 8 |
| `tests/suites/test_multi_turn.gd` (new) | every multi-turn rule | 1, 3, 4, 5, 6 |
| `CLAUDE.md` | documents the system | 9 |

---

### Task 1: One pacing switch, and enemy turns a test can run

**Files:**
- Modify: `scripts/battle/BattleManager.gd` (constants block ~lines 48–59, `_next_turn`, `resolve_skill`'s beat pause, `end_player_turn`, `_execute_enemy_turn`, `_pause`)
- Modify: `scripts/battle/BattleScene.gd` (`_ready`, the two `battle_manager.hit_pause` / `action_pause` lines)
- Modify: `tests/suites/test_skill_resolver.gd` (`test_pacing_is_off_unless_the_battle_scene_turns_it_on`)
- Create: `tests/suites/test_multi_turn.gd`; Modify: `tests/TestRunner.gd` (`SUITE_PATHS`)

**Interfaces:**
- Produces: `BattleManager.paced: bool` (false by default); constants `THINK_PAUSE`, `PREVIEW_PAUSE`, `WAKE_PAUSE`, `SKIP_PAUSE` (plus existing `HIT_PAUSE`, `ACTION_PAUSE`); `_pause(seconds: float) -> void` (waits only when paced); `_end_turn() -> void` (the shared end of any actor's turn: `IDLE`, `ACTION_PAUSE`, battle-end check, next actor). `hit_pause` / `action_pause` variables are **removed**.
- Produces (test helpers in `test_multi_turn.gd`, used by Tasks 3–6): `_unit(name, hero, speed := 10)`, `_skill(target := SINGLE_ENEMY)`, `_tap()`, `_foe(move := null, speed := 0)`, `_battle(heroes, foes)`, `_events(bm)`, `_log(bm)`, `_hits(bm)`.

- [ ] **Step 1: Write the failing tests**

Create `tests/suites/test_multi_turn.gd`:

```gdscript
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
```

Register it — in `tests/TestRunner.gd`, after `"res://tests/suites/test_scrollbars.gd",` add:

```gdscript
	"res://tests/suites/test_multi_turn.gd",
```

Then run the editor rescan once: `/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --quit-after 3 --path .` (writes `tests/suites/test_multi_turn.gd.uid`).

In `tests/suites/test_skill_resolver.gd`, replace `test_pacing_is_off_unless_the_battle_scene_turns_it_on` with:

```gdscript
func test_pacing_is_off_unless_the_battle_scene_turns_it_on() -> void:
	var bm := BattleManager.new()
	assert_false(bm.paced, "a bare manager never waits (tests)")
	assert_eq(BattleManager.HIT_PAUSE, 0.8, "the battle's pause between hits (user's choice)")
	assert_eq(BattleManager.ACTION_PAUSE, 1.0, "and after every action, before the next turn")
	bm.free()
```

- [ ] **Step 2: Run to verify they fail**

Expected: parse errors for `paced` first; once it exists, `MultiTurn` fails `the foe took its turn` (the enemy turn hits `get_tree()` on a manager outside the tree and stops) and the `create_timer(` count is 6, not 1.

- [ ] **Step 3: Implement**

In `scripts/battle/BattleManager.gd`, replace the two lines

```gdscript
## The pauses in effect. 0 by default, so a bare manager (every test) resolves
## synchronously; BattleScene sets them to HIT_PAUSE / ACTION_PAUSE.
var hit_pause := 0.0
var action_pause := 0.0
```

with

```gdscript
## An enemy's turn before it shows its move, and how long its move name shows
## under its card before it acts.
const THINK_PAUSE := 0.4
const PREVIEW_PAUSE := 1.0
## Banner waits: each banner's time on screen plus a small buffer, so nothing
## moves on mid-fade (BattleScene.BANNER_DURATION_WAKE / BANNER_DURATION_SKIP).
const WAKE_PAUSE := 1.75
const SKIP_PAUSE := 1.9
## Off on a bare manager, so every wait returns at once and a whole sequence of
## turns — enemy turns included — runs synchronously in a test. BattleScene
## turns it on. Every wait in the turn loop goes through _pause().
var paced := false
```

Replace `_pause`:

```gdscript
## Waits `seconds` — only while paced (the real battle). A bare manager (every
## test) is outside the scene tree and never waits.
func _pause(seconds: float) -> void:
	if paced and seconds > 0.0:
		await get_tree().create_timer(seconds).timeout
```

In `_next_turn`, replace

```gdscript
	var boss_pause: float = check_boss_phases()
	if boss_pause > 0.0:
		await get_tree().create_timer(boss_pause).timeout
```

with

```gdscript
	await _pause(check_boss_phases())
```

and replace `await get_tree().create_timer(1.75).timeout` with `await _pause(WAKE_PAUSE)`, and `await get_tree().create_timer(1.90).timeout` with `await _pause(SKIP_PAUSE)`.

In `resolve_skill`, replace `await _pause(hit_pause)` with `await _pause(HIT_PAUSE)`.

Replace `end_player_turn` with:

```gdscript
func end_player_turn():
	await _end_turn()

## The end of ANY actor's turn: the bars finish dropping, then the battle-end
## check, then the next actor.
func _end_turn() -> void:
	state = BattleState.IDLE
	await _pause(ACTION_PAUSE)
	if check_battle_end():
		return
	current_turn_index += 1
	_next_turn()
```

In `_execute_enemy_turn`, replace `await get_tree().create_timer(0.4).timeout` with `await _pause(THINK_PAUSE)`, `await get_tree().create_timer(1.0).timeout` with `await _pause(PREVIEW_PAUSE)`, and the tail

```gdscript
	# As after a hero's action: the bars finish before the next turn begins.
	await _pause(action_pause)
	if check_battle_end():
		return
	current_turn_index += 1
	_next_turn()
```

with

```gdscript
	# As after a hero's action: the bars finish before the next turn begins.
	_end_turn()
```

In `scripts/battle/BattleScene.gd` `_ready`, replace

```gdscript
	# The real battle is paced so each hit, and each action, is seen landing.
	battle_manager.hit_pause = BattleManager.HIT_PAUSE
	battle_manager.action_pause = BattleManager.ACTION_PAUSE
```

with

```gdscript
	# The real battle is paced, so each hit, action and banner is seen.
	battle_manager.paced = true
```

- [ ] **Step 4: Run the tests**

Expected: `MultiTurn [OK]`, `SkillResolver [OK]`, TOTAL 0 failed, warning set unchanged.

- [ ] **Step 5: Commit**

Stage `scripts/battle/BattleManager.gd`, `scripts/battle/BattleScene.gd`, `tests/suites/test_multi_turn.gd`, `tests/suites/test_multi_turn.gd.uid`, `tests/TestRunner.gd`, `tests/suites/test_skill_resolver.gd`. Message: `Route every battle wait through one pacing switch`.

---

### Task 2: The four move options, their tags, and saves

**Files:**
- Modify: `scripts/characters/Skill.gd` (new `@export_group("Multi-turn")` before the closing `@export_group("")`; `effect_tags`; new `applies_stat_effect`, `_turns`)
- Modify: `scripts/save/SaveSerializer.gd` (`serialize_skill`, `deserialize_skill`)
- Test: `tests/suites/test_skill_options.gd`, `tests/suites/test_save_serializer.gd`

**Interfaces:**
- Produces: `Skill.charge_turns: int`, `Skill.delay_rounds: int`, `Skill.recharge_turns: int`, `Skill.effect_turns: int` (all default 0); `Skill.applies_stat_effect() -> bool`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_skill_options.gd`:

```gdscript
# --------------------------------------------------- Spec C: multi-turn options

func test_multi_turn_options_default_to_off() -> void:
	var s := Skill.new()
	assert_eq(s.charge_turns, 0, "no charge-up")
	assert_eq(s.delay_rounds, 0, "lands at once")
	assert_eq(s.recharge_turns, 0, "no rest after")
	assert_eq(s.effect_turns, 0, "buffs and debuffs last the battle")

func test_multi_turn_effect_tags() -> void:
	var s := Skill.new()
	s.charge_turns = 1
	assert_true(s.effect_tags().has("Charges 1 turn"), "charge-up")
	s = Skill.new()
	s.delay_rounds = 1
	assert_true(s.effect_tags().has("Lands at round end"), "a one-round delay")
	s.delay_rounds = 2
	assert_true(s.effect_tags().has("Lands in 2 rounds"), "a two-round delay")
	s = Skill.new()
	s.recharge_turns = 1
	assert_true(s.effect_tags().has("Rests 1 turn"), "recharge")
	s.recharge_turns = 2
	assert_true(s.effect_tags().has("Rests 2 turns"), "plural")

func test_a_duration_is_tagged_only_on_a_move_with_a_stat_effect() -> void:
	var rider := Skill.new()
	rider.status_to_apply = "defense_debuff"
	rider.status_chance = 1.0
	rider.effect_turns = 3
	assert_true(rider.effect_tags().has("Lasts 3 turns"), "a timed debuff rider")
	var blessing := Skill.new()
	blessing.skill_type = Skill.SkillType.STATUS
	blessing.status_type = Skill.StatusType.BUFF
	blessing.status_to_apply = "speed_buff"
	blessing.effect_turns = 1
	assert_true(blessing.effect_tags().has("Lasts 1 turn"), "singular, on a status buff")
	var plain := Skill.new()
	plain.effect_turns = 3
	assert_false(plain.effect_tags().has("Lasts 3 turns"), "a move with no stat effect says nothing")
	var poison := Skill.new()
	poison.status_to_apply = "poison"
	poison.status_chance = 1.0
	poison.effect_turns = 3
	assert_false(poison.applies_stat_effect(), "a mutex status is not a stat effect")
```

Append to `tests/suites/test_save_serializer.gd`:

```gdscript
func test_every_spec_c_option_round_trips() -> void:
	var s := Skill.new()
	s.skill_name = "Later"
	s.charge_turns = 1
	s.delay_rounds = 2
	s.recharge_turns = 1
	s.effect_turns = 3
	var b := SaveSerializer.deserialize_skill(JSON.parse_string(JSON.stringify(SaveSerializer.serialize_skill(s))))
	assert_eq(b.charge_turns, 1, "charge")
	assert_eq(b.delay_rounds, 2, "delay")
	assert_eq(b.recharge_turns, 1, "recharge")
	assert_eq(b.effect_turns, 3, "duration")

func test_a_save_without_spec_c_fields_loads_with_everything_off() -> void:
	var b := SaveSerializer.deserialize_skill({"skill_name": "Old"})
	assert_eq(b.charge_turns, 0, "no charge")
	assert_eq(b.delay_rounds, 0, "no delay")
	assert_eq(b.recharge_turns, 0, "no recharge")
	assert_eq(b.effect_turns, 0, "permanent effects")
```

- [ ] **Step 2: Run to verify they fail**

Expected: parse errors (`charge_turns` not found) — the two suites drop out.

- [ ] **Step 3: Implement**

In `scripts/characters/Skill.gd`, replace

```gdscript
## A stat raised on every target the move hit.
@export var target_buff: String = ""
@export_group("")
```

with

```gdscript
## A stat raised on every target the move hit.
@export var target_buff: String = ""

# --- Spec C: multi-turn options ----------------------------------------------
@export_group("Multi-turn")
## 1 = the user spends this turn gathering power and releases on their next
## turn. A stun, sleep or paralysis skip on that turn breaks the charge.
@export var charge_turns: int = 0
## 1 = the move lands at the end of this round; 2 = the end of the next round.
@export var delay_rounds: int = 0
## After the move is used, the user skips this many of their own turns.
@export var recharge_turns: int = 0
## The stat buffs/debuffs this move applies last this many of the AFFECTED
## character's turns. 0 = the rest of the battle (every move before Spec C).
@export var effect_turns: int = 0
@export_group("")
```

In `effect_tags()`, replace the final `return tags` with:

```gdscript
	# Spec C — multi-turn shapes.
	if charge_turns > 0:
		tags.append("Charges %s" % _turns(charge_turns))
	if delay_rounds == 1:
		tags.append("Lands at round end")
	elif delay_rounds > 1:
		tags.append("Lands in %d rounds" % delay_rounds)
	if recharge_turns > 0:
		tags.append("Rests %s" % _turns(recharge_turns))
	if effect_turns > 0 and applies_stat_effect():
		tags.append("Lasts %s" % _turns(effect_turns))
	return tags

## True if the move raises or lowers a stat — a "_buff"/"_debuff" token (as a
## status move's effect or a damage move's rider), a target buff or a
## self-debuff. These are what effect_turns times; mutex statuses and
## regenerate keep their own rules.
func applies_stat_effect() -> bool:
	var kind: String = StatusSystem.parse_apply_token(status_to_apply)["kind"]
	return kind == "buff" or kind == "debuff" or target_buff != "" or self_debuff != ""

## "1 turn" / "3 turns".
static func _turns(n: int) -> String:
	return "%d turn%s" % [n, "" if n == 1 else "s"]
```

In `scripts/save/SaveSerializer.gd` `serialize_skill`, after `"target_buff": s.target_buff,` add:

```gdscript
		"charge_turns": s.charge_turns,
		"delay_rounds": s.delay_rounds,
		"recharge_turns": s.recharge_turns,
		"effect_turns": s.effect_turns,
```

In `deserialize_skill`, after `s.target_buff = String(d.get("target_buff", ""))` add:

```gdscript
	# Spec C options — the same "off" defaults for a save written before them.
	s.charge_turns = int(d.get("charge_turns", 0))
	s.delay_rounds = int(d.get("delay_rounds", 0))
	s.recharge_turns = int(d.get("recharge_turns", 0))
	s.effect_turns = int(d.get("effect_turns", 0))
```

- [ ] **Step 4: Run the tests** — `SkillOptions [OK]`, `SaveSerializer [OK]`, TOTAL 0 failed.

- [ ] **Step 5: Commit** — stage the two scripts and two test files. Message: `Add the multi-turn move options, their tags and saves`.

---

### Task 3: Timed buffs and debuffs

**Files:**
- Modify: `scripts/characters/Character.gd` (new `buff_turns` / `debuff_turns` beside `buffs` / `debuffs`; `apply_buff`, `apply_debuff`, new `_merge_timer`, `tick_stat_timers`, `_tick`; `clear_battle_effects`)
- Modify: `scripts/characters/StatusSystem.gd` (new constant `STATS_EXPIRED`)
- Modify: `scripts/battle/BattleManager.gd` (`_apply_skill_status`, `_resolve_hit` BUFF/DEBUFF branches, `_after_target`, `_apply_stat`, `_after_action`, `_next_turn`)
- Test: `tests/suites/test_multi_turn.gd`

**Interfaces:**
- Consumes: `Skill.effect_turns`, `Skill.applies_stat_effect()` (Task 2).
- Produces: `Character.apply_buff(stat: String, turns: int = 0) -> Dictionary`, `Character.apply_debuff(stat: String, turns: int = 0) -> Dictionary`, `Character.tick_stat_timers() -> bool`, `Character.buff_turns: Dictionary`, `Character.debuff_turns: Dictionary`; `StatusSystem.STATS_EXPIRED := "stats_expired"`; `BattleManager._apply_skill_status(target, token, regen_amount := -1, turns := 0)`, `_apply_stat(c, stat, buff, turns := 0) -> bool`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_multi_turn.gd`:

```gdscript
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
```

- [ ] **Step 2: Run to verify they fail**

Expected: parse errors (`apply_buff` takes 1 argument; `STATS_EXPIRED` missing).

- [ ] **Step 3: Implement**

`scripts/characters/StatusSystem.gd` — after `const DEFENDING := "defending"` add:

```gdscript
## Spec C event types (status_effect_triggered). STATS_EXPIRED is quiet: it
## only refreshes the chips when a timed buff/debuff wears off.
const STATS_EXPIRED := "stats_expired"
```

`scripts/characters/Character.gd` — after `var debuffs: Dictionary = {}` add:

```gdscript
## Turns left on a TIMED buff / debuff, per stat (Spec C). A buffed or
## debuffed stat with no entry here lasts the whole battle, as every effect
## did before. Battle-only: cleared by clear_battle_effects, never saved.
var buff_turns: Dictionary = {}
var debuff_turns: Dictionary = {}
```

Replace `apply_buff` and `apply_debuff` with:

```gdscript
# turns > 0 makes the effect TIMED (Spec C): it lasts that many of this
# character's own turns (see tick_stat_timers); 0 = the rest of the battle.
# A permanent effect always wins: timed on top of permanent changes nothing,
# permanent on top of timed makes it permanent; timed on timed keeps the longer.
func apply_buff(stat: String, turns: int = 0) -> Dictionary:
	if not (stat in StatusSystem.BUFFABLE_STATS):
		return {"action": "invalid", "stat": stat}
	if debuffs.get(stat, false):
		debuffs[stat] = false
		debuff_turns.erase(stat)
		return {"action": "cancelled_debuff", "stat": stat}
	if buffs.get(stat, false):
		_merge_timer(buff_turns, stat, turns)
		return {"action": "noop", "stat": stat}
	buffs[stat] = true
	if turns > 0:
		buff_turns[stat] = turns
	return {"action": "buffed", "stat": stat}

func apply_debuff(stat: String, turns: int = 0) -> Dictionary:
	if not (stat in StatusSystem.BUFFABLE_STATS):
		return {"action": "invalid", "stat": stat}
	if buffs.get(stat, false):
		buffs[stat] = false
		buff_turns.erase(stat)
		return {"action": "cancelled_buff", "stat": stat}
	if debuffs.get(stat, false):
		_merge_timer(debuff_turns, stat, turns)
		return {"action": "noop", "stat": stat}
	debuffs[stat] = true
	if turns > 0:
		debuff_turns[stat] = turns
	return {"action": "debuffed", "stat": stat}

## Re-applying an effect a stat already has. A permanent one (no entry) stays
## permanent; a timed one turns permanent if the new one is, else keeps the
## longer time.
static func _merge_timer(timers: Dictionary, stat: String, turns: int) -> void:
	if not timers.has(stat):
		return
	if turns <= 0:
		timers.erase(stat)
	else:
		timers[stat] = maxi(int(timers[stat]), turns)

## Counts down this character's timed buffs and debuffs at the start of their
## turn. A 3-turn effect is active for their next 3 turns and is gone when the
## 4th begins (the turn it was applied in does not count; a skipped turn
## does). Returns true if any wore off, so the UI can refresh its chips.
func tick_stat_timers() -> bool:
	var from_buffs := _tick(buff_turns, buffs)
	var from_debuffs := _tick(debuff_turns, debuffs)
	return from_buffs or from_debuffs

static func _tick(timers: Dictionary, flags: Dictionary) -> bool:
	var expired := false
	for stat in timers.keys():
		if int(timers[stat]) <= 0:
			timers.erase(stat)
			flags[stat] = false
			expired = true
		else:
			timers[stat] = int(timers[stat]) - 1
	return expired
```

In `clear_battle_effects`, after `debuffs.clear()` add:

```gdscript
	buff_turns.clear()
	debuff_turns.clear()
```

`scripts/battle/BattleManager.gd`:

- `_apply_skill_status` signature → `func _apply_skill_status(target: Character, token: String, regen_amount: int = -1, turns: int = 0):` and its two branches → `target.apply_buff(parsed["value"], turns)` / `target.apply_debuff(parsed["value"], turns)`.
- In `_resolve_hit`, the BUFF branch's `_apply_skill_status(target, token)` → `_apply_skill_status(target, token, -1, skill.effect_turns)`; the DEBUFF branch's `_apply_skill_status(target, skill.status_to_apply)` → `_apply_skill_status(target, skill.status_to_apply, -1, skill.effect_turns)`.
- In `_after_target`: the rider → `_apply_skill_status(target, skill.status_to_apply, -1, skill.effect_turns)`; the target buff → `_apply_stat(target, skill.target_buff, true, skill.effect_turns)`.
- `_apply_stat` → `func _apply_stat(c: Character, stat: String, buff: bool, turns: int = 0) -> bool:` with `var r: Dictionary = c.apply_buff(stat, turns) if buff else c.apply_debuff(stat, turns)`.
- In `_after_action`: `_apply_stat(user, skill.self_debuff, false)` → `_apply_stat(user, skill.self_debuff, false, skill.effect_turns)`.
- In `_next_turn`, immediately before `emit_signal("turn_started", current_actor)` add:

```gdscript
	# Spec C: timed buffs / debuffs count down on their owner's turns. Quiet —
	# the event only refreshes the chips.
	if current_actor.tick_stat_timers():
		emit_signal("status_effect_triggered", current_actor, {"type": StatusSystem.STATS_EXPIRED, "value": 0})
```

(The boss self-buffs and field effects keep calling with no duration, so they stay permanent.)

- [ ] **Step 4: Run the tests** — `MultiTurn [OK]`, `StatusSystem [OK]`, `SkillResolver [OK]`, TOTAL 0 failed.

- [ ] **Step 5: Commit** — stage `Character.gd`, `StatusSystem.gd`, `BattleManager.gd`, `test_multi_turn.gd`. Message: `Let moves apply buffs and debuffs that wear off`.

---

### Task 4: Split the resolver into use and strike; recharge

**Files:**
- Modify: `scripts/battle/BattleManager.gd` (`resolve_skill` → `resolve_skill` + `_measure` + `_strike` + `_start_recharge`; `_resolve_hit` gains `base_value`; `_next_turn` recharge step)
- Modify: `scripts/characters/Character.gd` (`recharge_turns_left`; `clear_battle_effects`)
- Modify: `scripts/characters/StatusSystem.gd` (`RECHARGING`, its colour, `skipped_phrase`)
- Modify: `tests/suites/test_skill_resolver.gd` (`test_an_enemy_skill_is_dodge_rolled_once_not_twice` looks for dodge in `_strike` now)
- Test: `tests/suites/test_multi_turn.gd`

**Interfaces:**
- Consumes: `Skill.recharge_turns` (Task 2), `_end_turn` (Task 1).
- Produces: `BattleManager._measure(user, skill) -> Dictionary` (`"scale"`, `"hp_fraction"`); `BattleManager._strike(user: Character, skill: Skill, targets: Array[Character], m: Dictionary, caster_standing: bool = true) -> void` (`m` may also hold `"value"`, a cast-time `Skill.calculate_value`); `BattleManager._start_recharge(user, skill) -> void`; `_resolve_hit(..., base_value: int = -1)`; `Character.recharge_turns_left: int`; `StatusSystem.RECHARGING := "recharging"`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_multi_turn.gd`:

```gdscript
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
```

In `tests/suites/test_skill_resolver.gd` `test_an_enemy_skill_is_dodge_rolled_once_not_twice`, replace the line

```gdscript
	assert_true(_function_body(src, "resolve_skill").contains("try_dodge"), "the resolver rolls dodge")
```

with

```gdscript
	assert_true(_function_body(src, "_strike").contains("try_dodge"), "the strike rolls dodge")
```

- [ ] **Step 2: Run to verify they fail** — parse errors (`recharge_turns_left`, `RECHARGING`), then `SkillResolver` fails the `_strike` assertion.

- [ ] **Step 3: Implement**

`scripts/characters/StatusSystem.gd` — after `const STATS_EXPIRED := "stats_expired"` add:

```gdscript
## A turn lost resting after a recharge move. Routed as a skip banner.
const RECHARGING := "recharging"
```

In `STATUS_COLORS`, after the `DEFENDING:` line add `RECHARGING: Color(0.70, 0.62, 0.85),  # spent lilac`. In `skipped_phrase`, after the `PARALYSIS:` case add `RECHARGING: return "%s is recovering!" % character_name`.

`scripts/characters/Character.gd` — after `var regen_amount: int = 0` add:

```gdscript
## Turns left resting after a recharge move (Spec C). Battle-only.
var recharge_turns_left: int = 0
```

and in `clear_battle_effects` after `regen_amount = 0` add `recharge_turns_left = 0`.

`scripts/battle/BattleManager.gd` — replace the whole of `resolve_skill` (from its `##` doc comment through the line `_after_action(user, skill, dealt)` that ends it) with:

```gdscript
## The single skill resolver for heroes AND enemies. There used to be two
## ~50-line near-copies that had already drifted: SELF targeting existed on one
## side only, dodge was rolled in different places, and the same outcome
## emitted different action names. Every skill mechanic lands here, once.
##
## USING a move — check, measure, pay — is separate from STRIKING with it, so a
## move that fires later (Spec C) strikes through the same code.
func resolve_skill(user: Character, skill: Skill, chosen: Array[Character]) -> void:
	if not skill.can_use(user):
		return
	var m := _measure(user, skill)
	_pay_costs(user, skill)
	await _strike(user, skill, expand_targets(user, skill, chosen), m)
	_start_recharge(user, skill)

## What a strike needs from the moment a move is measured — BEFORE its costs
## are paid, so an HP-cost move is not weakened by its own cost (Spec B).
func _measure(user: Character, skill: Skill) -> Dictionary:
	return {"scale": skill.scale_factor(user),
			"hp_fraction": float(user.current_hp) / float(maxi(1, user.max_hp()))}

## The hits of a move: Spec B's paced beats, per-target effects and
## after-action effects. `m` comes from _measure; a delayed strike adds its
## caster's cast-time "value". A fallen caster's strike lands only its hits —
## no result takes the action's resonance, and there are no after-effects.
func _strike(user: Character, skill: Skill, targets: Array[Character], m: Dictionary,
		caster_standing: bool = true) -> void:
	var scale: float = m["scale"]
	var user_hp_fraction: float = m["hp_fraction"]
	var base_value: int = int(m.get("value", -1))
	var first := caster_standing
	var dealt := 0       # HP actually removed by this action's hits, for recoil
	var landed := {}     # target -> hits that landed on it
	var hits := maxi(1, skill.hit_count) if skill.skill_type == Skill.SkillType.DAMAGE else 1
	# One BEAT per hit: beat N is hit N on every target still standing, shown
	# together, then a pause before the next beat — so each hit visibly drops
	# the bars. A target downed in a beat falls at its end and takes no more.
	for h in hits:
		var standing: Array[Character] = []
		for t in targets:
			if t.is_alive():
				standing.append(t)
		if standing.is_empty():
			break
		if h > 0:
			await _pause(HIT_PAUSE)
		var results: Array[Dictionary] = []
		for target in standing:
			var result := {"actor": user, "target": target, "skill": skill,
					"is_first_target": false, "is_first_hit": false}
			# Dodge depends on WHO the skill lands on, not what kind of skill it
			# is: anything aimed at the user's opponents can miss (the move's own
			# chance) or be dodged; the user's own side never rolls either.
			if _opponents_of(user).has(target):
				if skill.miss_chance > 0.0 and randf() < skill.miss_chance:
					results.append(_unlanded(result, "miss", target))
					continue
				if EnemyAI.try_dodge(target):
					results.append(_unlanded(result, "dodge", target))
					continue
			# Resonance rides on hits that actually land. "Took damage" resonance
			# is once per target per action (the first landed hit on that target);
			# the action's skill resonance is once per action, on its first
			# LANDED hit — never on a miss or a dodge.
			result["is_first_hit"] = landed.get(target, 0) == 0
			result["is_first_target"] = first
			first = false
			landed[target] = landed.get(target, 0) + 1
			var hp_before := target.current_hp
			_resolve_hit(user, skill, target, result, scale, user_hp_fraction, base_value)
			if skill.skill_type == Skill.SkillType.DAMAGE:
				dealt += maxi(0, hp_before - target.current_hp)
			result["target_alive"] = target.is_alive()
			results.append(result)
		# Effects rolled once per target (the status rider, the target buff)
		# go on before the LAST beat is shown, so their chips appear with it.
		if h == hits - 1 or not targets.any(func(t): return t.is_alive()):
			for target in targets:
				if landed.get(target, 0) > 0:
					_after_target(skill, target)
		for r in results:
			emit_signal("action_performed", r)
		for target in standing:
			if not target.is_alive():
				handle_defeat(target)
	if caster_standing:
		_after_action(user, skill, dealt)

## Spec C recharge: the user rests their next `recharge_turns` turns.
func _start_recharge(user: Character, skill: Skill) -> void:
	if skill.recharge_turns > 0:
		user.recharge_turns_left = skill.recharge_turns
```

Change `_resolve_hit`'s signature to

```gdscript
func _resolve_hit(user: Character, skill: Skill, target: Character, result: Dictionary,
		scale: float, user_hp_fraction: float, base_value: int = -1) -> void:
	# The move's raw strength: measured now, or carried from the cast (Spec C).
	var raw: int = base_value if base_value >= 0 else skill.calculate_value(user)
```

and in its body replace `skill.calculate_value(user) * skill.condition_multiplier(...)` with `raw * skill.condition_multiplier(...)` (DAMAGE branch), and the STATUS branch's `var value := skill.calculate_value(user)` with `var value := raw`.

In `_next_turn`, immediately after `emit_signal("turn_started", current_actor)` add:

```gdscript
	# Spec C: resting after a recharge move. The status skip still resolves on
	# this same turn, so a stun is used up by it and a sleep counter advances —
	# one lost turn, not two.
	if current_actor.recharge_turns_left > 0:
		current_actor.recharge_turns_left -= 1
		StatusSystem.resolve_turn_skip(current_actor)
		emit_signal("status_effect_triggered", current_actor, {
			"type": StatusSystem.RECHARGING,
			"value": 0,
			"skipped": true,
			"name": current_actor.character_name,
		})
		await _pause(SKIP_PAUSE)
		current_turn_index += 1
		_next_turn()
		return
```

(`BattleScene._on_status_triggered` already routes any `skipped` event to `skipped_phrase` and `STATUS_COLORS` — no scene change.)

- [ ] **Step 4: Run the tests** — every existing `SkillResolver` test still passes (the refactor changes no behaviour), `MultiTurn [OK]`, TOTAL 0 failed.

- [ ] **Step 5: Commit** — stage `BattleManager.gd`, `Character.gd`, `StatusSystem.gd`, `test_multi_turn.gd`, `test_skill_resolver.gd`. Message: `Split using a move from striking with it; add recharge`.

---

### Task 5: Charge-ups

**Files:**
- Modify: `scripts/battle/BattleManager.gd` (`BANNER_PAUSE`; inner class `Scheduled`; `scheduled` list; charge branch in `resolve_skill`; `_charge_of`, `_strike_targets`, `_release_charge`; `_next_turn` skip and release steps; `handle_defeat`; `check_battle_end`)
- Modify: `scripts/characters/StatusSystem.gd` (`CHARGING`, `FOCUS_BROKEN`, colours, `multi_turn_phrase`)
- Modify: `scripts/battle/BattleScene.gd` (`_on_status_triggered` banner branch)
- Test: `tests/suites/test_multi_turn.gd`

**Interfaces:**
- Consumes: `_measure`, `_strike`, `_start_recharge` (Task 4); `_end_turn` (Task 1); `Skill.charge_turns` (Task 2).
- Produces: `BattleManager.BANNER_PAUSE := 1.75`; `class Scheduled` with `enum When { CASTER_TURN, ROUND_END }`, fields `user`, `skill`, `chosen: Array[Character]`, `when`, `rounds_left: int`, `measured: Dictionary`, and `_init(u: Character, s: Skill, c: Array[Character], w: When)`; `BattleManager.scheduled: Array`; `_charge_of(user) -> Scheduled`; `_strike_targets(user, skill, chosen: Array[Character]) -> Array[Character]`; `StatusSystem.CHARGING`, `StatusSystem.FOCUS_BROKEN`, `StatusSystem.multi_turn_phrase(character_name: String, result: Dictionary) -> String`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_multi_turn.gd`:

```gdscript
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
```

- [ ] **Step 2: Run to verify they fail** — parse errors (`scheduled`, `CHARGING`, `_charge_of`, `_strike_targets`).

- [ ] **Step 3: Implement**

`scripts/characters/StatusSystem.gd` — after `const RECHARGING := "recharging"` add:

```gdscript
## A charge-up begins; a charge-up is broken by a skipped turn.
const CHARGING := "charging"
const FOCUS_BROKEN := "focus_broken"
```

In `STATUS_COLORS` add `CHARGING: Color(1.00, 0.72, 0.35),       # gathering gold` and `FOCUS_BROKEN: Color(0.75, 0.75, 0.85),   # spent grey-blue`. After `woke_phrase` add:

```gdscript
## Banner text for Spec C's multi-turn events that are not skips, or "" for a
## quiet event (one that only refreshes the UI).
static func multi_turn_phrase(character_name: String, result: Dictionary) -> String:
	match String(result.get("type", "")):
		CHARGING:
			return "%s is gathering power!" % character_name
		FOCUS_BROKEN:
			return "%s's focus was broken!" % character_name
		_:
			return ""
```

`scripts/battle/BattleScene.gd` `_on_status_triggered` — after the `elif result.get("applied", false):` block (end of the function) add:

```gdscript
	else:
		# Spec C: charge-up and delayed-strike banners ("" = a quiet event).
		var line := StatusSystem.multi_turn_phrase(nm, result)
		if line != "":
			_show_status_banner(line,
					StatusSystem.STATUS_COLORS.get(event_type, Color(0.85, 0.7, 1.0)),
					BANNER_DURATION_APPLIED)
```

`scripts/battle/BattleManager.gd`:

After `const SKIP_PAUSE := 1.9` add:

```gdscript
## The Spec C banners ("gathering power", "focus broken", "<Move> strikes!").
const BANNER_PAUSE := 1.75
```

After `var current_actor: Character` add:

```gdscript
## A move that resolves later (Spec C): a charge-up waiting for its user's next
## turn, or a delayed strike waiting for the end of a round. A future "fires
## later" shape is a new When.
class Scheduled:
	enum When { CASTER_TURN, ROUND_END }
	var user: Character
	var skill: Skill
	var chosen: Array[Character]
	var when: When
	## Delayed strikes only: rounds until it lands, and the cast-time
	## measurements (_measure plus the caster's "value").
	var rounds_left := 0
	var measured: Dictionary = {}

	func _init(u: Character, s: Skill, c: Array[Character], w: When) -> void:
		user = u
		skill = s
		chosen = c.duplicate()
		when = w

## Every move waiting to resolve, in the order it was used. A fresh list per
## battle (a fresh manager), cleared when the battle ends.
var scheduled: Array = []
```

In `resolve_skill`, after the `can_use` check add:

```gdscript
	if skill.charge_turns > 0:
		# Spec C charge-up: pay now, gather power this turn, release on the
		# user's next turn (_release_charge) — measured then, not now.
		_pay_costs(user, skill)
		scheduled.append(Scheduled.new(user, skill, chosen, Scheduled.When.CASTER_TURN))
		emit_signal("status_effect_triggered", user, {"type": StatusSystem.CHARGING,
				"value": 0, "name": user.character_name})
		await _pause(BANNER_PAUSE)
		return
```

After `_start_recharge` add:

```gdscript
## The user's waiting charge-up, or null.
func _charge_of(user: Character) -> Scheduled:
	for e in scheduled:
		if e.user == user and e.when == Scheduled.When.CASTER_TURN:
			return e
	return null

## A later strike's targets. Area moves hit whoever stands now; a single
## target that has fallen is replaced by a random living character on its
## side, so a charge or delayed strike is never spent on the fallen. Nobody
## standing: an empty list.
func _strike_targets(user: Character, skill: Skill, chosen: Array[Character]) -> Array[Character]:
	var pick: Array[Character] = []
	for c in chosen:
		if c.is_alive():
			pick.append(c)
	var single := skill.target_type == Skill.TargetType.SINGLE_ENEMY \
			or skill.target_type == Skill.TargetType.SINGLE_ALLY
	if pick.is_empty() and single:
		var side: Array[Character] = _opponents_of(user) \
				if skill.target_type == Skill.TargetType.SINGLE_ENEMY else _allies_of(user)
		var living: Array[Character] = []
		for c in side:
			if c.is_alive():
				living.append(c)
		if not living.is_empty():
			pick.append(living[randi() % living.size()])
	var out: Array[Character] = []
	for t in expand_targets(user, skill, pick):
		if t.is_alive():
			out.append(t)
	return out

## A charge-up firing on its user's turn: no menu, no AI choice. Measured now —
## the charger is acting — so a buff landed on them while charging counts.
func _release_charge(entry: Scheduled) -> void:
	scheduled.erase(entry)
	var user := entry.user
	if enemies.has(user):
		emit_signal("enemy_move_preview", user, entry.skill.skill_name)
		await _pause(PREVIEW_PAUSE)
		emit_signal("enemy_move_preview", user, "")
	var targets := _strike_targets(user, entry.skill, entry.chosen)
	if not targets.is_empty():
		await _strike(user, entry.skill, targets, _measure(user, entry.skill))
	_start_recharge(user, entry.skill)
```

In `_next_turn`, inside `if skip_status != "":`, before its `emit_signal("status_effect_triggered", current_actor, {` add:

```gdscript
		# Spec C: a skipped turn breaks a charge-up; its costs stay spent.
		var broken := _charge_of(current_actor)
		if broken != null:
			scheduled.erase(broken)
			emit_signal("status_effect_triggered", current_actor, {"type": StatusSystem.FOCUS_BROKEN,
					"value": 0, "name": current_actor.character_name})
			await _pause(BANNER_PAUSE)
```

and immediately before `# Actor is ready — UI shows action menu / starts enemy AI.` add:

```gdscript
	# Spec C: a charge-up releases on its user's turn — no menu, no AI choice.
	var charge := _charge_of(current_actor)
	if charge != null:
		state = BattleState.EXECUTING_ACTION
		await _release_charge(charge)
		_end_turn()
		return
```

At the top of `handle_defeat` add:

```gdscript
	# Spec C: a downed charger loses its charge (a delayed strike still lands).
	var lost := _charge_of(character)
	if lost != null:
		scheduled.erase(lost)
```

In `check_battle_end`, add `scheduled.clear()` as the first line of BOTH the victory and the defeat branch (before `state = BattleState.BATTLE_OVER`).

- [ ] **Step 4: Run the tests** — `MultiTurn [OK]`, TOTAL 0 failed, warning set unchanged.

- [ ] **Step 5: Commit** — stage `BattleManager.gd`, `StatusSystem.gd`, `BattleScene.gd`, `test_multi_turn.gd`. Message: `Add charge-up moves that a skipped turn can break`.

---

### Task 6: Delayed strikes

**Files:**
- Modify: `scripts/battle/BattleManager.gd` (delayed branch in `resolve_skill`; `_land_delayed_strikes`; round end in `_next_turn`)
- Modify: `scripts/characters/StatusSystem.gd` (`STRIKE_SCHEDULED`, `STRIKE_LANDING`, colour, `multi_turn_phrase` case)
- Test: `tests/suites/test_multi_turn.gd`

**Interfaces:**
- Consumes: `Scheduled`, `scheduled`, `_strike_targets`, `BANNER_PAUSE` (Task 5); `_measure`, `_strike`, `_start_recharge` (Task 4).
- Produces: `StatusSystem.STRIKE_SCHEDULED := "strike_scheduled"` (quiet), `StatusSystem.STRIKE_LANDING := "strike_landing"` (its event carries `"move"`); `BattleManager._land_delayed_strikes() -> void`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_multi_turn.gd`:

```gdscript
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
```

- [ ] **Step 2: Run to verify they fail** — parse errors (`STRIKE_SCHEDULED`, `STRIKE_LANDING`).

- [ ] **Step 3: Implement**

`scripts/characters/StatusSystem.gd` — after `const FOCUS_BROKEN := "focus_broken"` add:

```gdscript
## A delayed strike is cast (quiet: only refreshes the spent MP); one lands.
const STRIKE_SCHEDULED := "strike_scheduled"
const STRIKE_LANDING := "strike_landing"
```

In `STATUS_COLORS` add `STRIKE_LANDING: Color(0.85, 0.55, 1.00),  # amethyst`. In `multi_turn_phrase`, before the `_:` case add:

```gdscript
		STRIKE_LANDING:
			return "%s strikes!" % String(result.get("move", ""))
```

`scripts/battle/BattleManager.gd` — in `resolve_skill`, after the charge-up block add:

```gdscript
	if skill.delay_rounds > 0:
		# Spec C delayed strike: measured and paid now, lands at the end of a
		# later round (_land_delayed_strikes). Nothing about it is shown — the
		# quiet event only refreshes the panels so the spent MP shows.
		var entry := Scheduled.new(user, skill, chosen, Scheduled.When.ROUND_END)
		entry.rounds_left = skill.delay_rounds
		entry.measured = _measure(user, skill)
		entry.measured["value"] = skill.calculate_value(user)
		_pay_costs(user, skill)
		scheduled.append(entry)
		emit_signal("status_effect_triggered", user, {"type": StatusSystem.STRIKE_SCHEDULED, "value": 0})
		_start_recharge(user, skill)
		return
```

After `_release_charge` add:

```gdscript
## The end of a round: every delayed strike that is due lands, one at a time in
## the order cast — its banner, a pause, the hits (which can miss or be
## dodged), then the action pause. Nothing prevents one: a fallen caster's
## strike still lands, with only its hits. A landing that ends the battle drops
## the rest (check_battle_end clears the list).
func _land_delayed_strikes() -> void:
	for entry in scheduled.duplicate():
		if entry.when != Scheduled.When.ROUND_END:
			continue
		entry.rounds_left -= 1
		if entry.rounds_left > 0:
			continue
		scheduled.erase(entry)
		var targets := _strike_targets(entry.user, entry.skill, entry.chosen)
		if targets.is_empty():
			continue
		state = BattleState.EXECUTING_ACTION
		emit_signal("status_effect_triggered", entry.user, {"type": StatusSystem.STRIKE_LANDING,
				"value": 0, "move": entry.skill.skill_name})
		await _pause(BANNER_PAUSE)
		await _strike(entry.user, entry.skill, targets, entry.measured, entry.user.is_alive())
		await _pause(ACTION_PAUSE)
		if check_battle_end():
			return
```

In `_next_turn`, replace

```gdscript
	if current_turn_index >= turn_order.size():
		_start_new_round()
		return
```

with

```gdscript
	if current_turn_index >= turn_order.size():
		# Spec C: the round is over — due delayed strikes land before the next.
		await _land_delayed_strikes()
		if state == BattleState.BATTLE_OVER:
			return
		_start_new_round()
		return
```

- [ ] **Step 4: Run the tests** — `MultiTurn [OK]`, TOTAL 0 failed, warning set unchanged.

- [ ] **Step 5: Commit** — stage `BattleManager.gd`, `StatusSystem.gd`, `test_multi_turn.gd`. Message: `Add delayed strikes that land at the end of the round`.

---

### Task 7: The nine hero moves

**Files:**
- Create: `data/skills/undertow.tres`, `deluge.tres`, `tsunami.tres`, `sunforge_strike.tres`, `searing_brand.tres`, `eruption.tres`, `gathering_squall.tres`, `windrunners_blessing.tres`, `dawnsong.tres`
- Modify: `scripts/PartyFactory.gd` (`POOLS`, `SKILL_UNLOCK_LEVELS`, `SKILL_CATEGORIES`, the "15" / "seven attacks and eight specials" comments)
- Modify: `tests/suites/test_move_library.gd`, `test_party_factory.gd`, `test_skill_learning.gd`, `test_moveset.gd`

**Interfaces:**
- Consumes: the four options (Task 2) and their behaviour (Tasks 3–6).

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_move_library.gd`:

```gdscript
# --------------------------------------------------- Spec C: new moves

const SPEC_C_HERO_MOVES := {
	"Aria": ["undertow.tres", "deluge.tres", "tsunami.tres"],
	"Kael": ["sunforge_strike.tres", "searing_brand.tres", "eruption.tres"],
	"Lyra": ["gathering_squall.tres", "windrunners_blessing.tres", "dawnsong.tres"],
}

func test_each_hero_gains_three_moves_in_slots_16_to_18() -> void:
	for hero in PartyFactory.create_default_party():
		var want: Array = SPEC_C_HERO_MOVES[hero.character_name]
		for i in 3:
			assert_eq(hero.skills[15 + i].source_path, LIB + want[i], "%s slot %d" % [hero.character_name, 16 + i])

func test_every_spec_c_hero_move_is_described_and_tagged() -> void:
	for name in SPEC_C_HERO_MOVES:
		for f in SPEC_C_HERO_MOVES[name]:
			var s: Skill = load(LIB + f)
			assert_true(s.description != "", "%s has a description" % f)
			assert_false(s.effect_tags().is_empty(), "%s shows its multi-turn shape" % f)

func test_every_multi_turn_shape_is_used_by_some_move() -> void:
	var used := {}
	for f in _library_files():   # full res:// paths
		var s: Skill = load(f)
		if s.charge_turns > 0: used["charge"] = true
		if s.delay_rounds > 0: used["delay"] = true
		if s.recharge_turns > 0: used["recharge"] = true
		if s.effect_turns > 0 and s.applies_stat_effect(): used["timed"] = true
	for m in ["charge", "delay", "recharge", "timed"]:
		assert_true(used.has(m), "some move uses %s" % m)
```

In `tests/suites/test_party_factory.gd` `test_each_hero_has_eight_skills`, change `15` to `18` and the message to `"%s has an 18-move pool (8 attack + 10 special)"`.

In `tests/suites/test_skill_learning.gd`: in `test_party_curve_is_applied` change `assert_eq(hero.skills.size(), 15, …)` to `18`; in `test_curve_covers_every_slot_and_is_reachable` change `assert_eq(PartyFactory.SKILL_UNLOCK_LEVELS.size(), 15, …)` to `18`. (The `_hero([1, 2, 7, 15])` helpers elsewhere are synthetic and stay.)

In `tests/suites/test_moveset.gd` `test_default_party_has_a_pool_bigger_than_its_slots`: `assert_eq(hero.skills.size(), 15, "%s defines 15 moves" …)` → `18` / `"%s defines 18 moves"`; `assert_eq(atk, 7, "%s has seven attacks, …")` → `8` / `"%s has eight attacks, more than the four slots"`; `assert_eq(spc, 8, "%s has eight specials")` → `10` / `"%s has ten specials"`.

- [ ] **Step 2: Run to verify they fail** — the files and slots do not exist yet.

- [ ] **Step 3: Create the nine move files**

Each is a text resource of exactly this shape (no uid line). Enum ints: `attack_type` 2 = Magic (omitted = Strike); `target_type` 1 = all enemies, 3 = all allies (omitted = one enemy); `skill_type` 1 = Status; `status_type` 1 = Buff (omitted = Heal); `element` 1 Fire, 2 Water, 7 Wind, 13 Light.

`data/skills/undertow.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Undertow"
description = "A dragging current that leaves a foe's guard sodden for a few turns."
mp_cost = 12
attack_type = 2
power = 1.4
element = 2
status_to_apply = "defense_debuff"
status_chance = 1.0
effect_turns = 3
```

`data/skills/deluge.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Deluge"
description = "Calls a deluge that crashes onto every enemy at the end of the next round."
mp_cost = 28
attack_type = 2
target_type = 1
power = 3.4
element = 2
delay_rounds = 2
```

`data/skills/tsunami.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Tsunami"
description = "Draws the sea back for a turn, then breaks it over every enemy."
mp_cost = 40
attack_type = 2
target_type = 1
power = 5.5
element = 2
charge_turns = 1
```

`data/skills/sunforge_strike.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Sunforge Strike"
description = "Heats his blade white for a turn, then brings it down on one foe."
mp_cost = 14
power = 4.0
element = 1
charge_turns = 1
```

`data/skills/searing_brand.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Searing Brand"
description = "A burning cut that saps a foe's strength for a few turns."
mp_cost = 12
power = 1.8
element = 1
status_to_apply = "attack_debuff"
status_chance = 1.0
effect_turns = 3
```

`data/skills/eruption.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Eruption"
description = "Unleashes everything at once on every enemy — then he has to catch his breath."
mp_cost = 35
target_type = 1
power = 5.0
element = 1
recharge_turns = 1
```

`data/skills/gathering_squall.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Gathering Squall"
description = "A squall that gathers through the round and breaks on one foe at its end."
mp_cost = 10
attack_type = 2
power = 2.0
element = 7
delay_rounds = 1
```

`data/skills/windrunners_blessing.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Windrunner's Blessing"
description = "Quickens the whole party for a few turns."
mp_cost = 8
skill_type = 1
status_type = 1
target_type = 3
element = 7
status_to_apply = "speed_buff"
effect_turns = 3
```

`data/skills/dawnsong.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Dawnsong"
description = "A song that mends the whole party — and leaves her breathless for a turn."
mp_cost = 30
skill_type = 1
target_type = 3
power = 3.0
element = 13
recharge_turns = 1
```

- [ ] **Step 4: Grow the hero pools**

In `scripts/PartyFactory.gd`, append to each `POOLS` list, at the end, in this order:
- `"Aria"`: `"undertow.tres", "deluge.tres", "tsunami.tres",`
- `"Kael"`: `"sunforge_strike.tres", "searing_brand.tres", "eruption.tres",`
- `"Lyra"`: `"gathering_squall.tres", "windrunners_blessing.tres", "dawnsong.tres",`

In `SKILL_UNLOCK_LEVELS`, after the line `14,  # 14 special  (Spec B: Abyssal Tithe / Provoking Blow / Tempest Gamble)`, add:

```gdscript
	6,   # 15 attack   (Spec C: Undertow / Sunforge Strike / Gathering Squall)
	11,  # 16 special  (Spec C: Deluge / Searing Brand / Windrunner's Blessing)
	16,  # 17 special  (Spec C: Tsunami / Eruption / Dawnsong)
```

In `SKILL_CATEGORIES`, replace the last two entry lines

```gdscript
	Skill.SkillCategory.ATTACK,  Skill.SkillCategory.SPECIAL,
	Skill.SkillCategory.SPECIAL,
]
```

with

```gdscript
	Skill.SkillCategory.ATTACK,  Skill.SkillCategory.SPECIAL,
	Skill.SkillCategory.SPECIAL,
	Skill.SkillCategory.ATTACK,  Skill.SkillCategory.SPECIAL,   # Spec C: slots 16-18
	Skill.SkillCategory.SPECIAL,
]
```

Update the comments: line ~12 "Each hero currently defines 15: seven attacks and eight specials" → "Each hero currently defines 18: eight attacks and ten specials"; line ~37–38 "With seven attacks and eight specials" → "With eight attacks and ten specials"; the `TEST_UNLOCK_ALL_SKILLS` comment "its whole 15-move pool" → "its whole 18-move pool".

- [ ] **Step 5: Run the tests** — `MoveLibrary [OK]`, `PartyFactory [OK]`, `SkillLearning [OK]`, `Moveset [OK]`, `SaveSerializer [OK]`, TOTAL 0 failed. If the move index test fails, look for a typo'd `skill_name` collision.

- [ ] **Step 6: Commit** — stage the nine `.tres` files, `PartyFactory.gd` and the four test files. Message: `Add nine hero moves that charge, delay, recharge or time their effects`.

---

### Task 8: The four enemy moves

**Files:**
- Create: `data/skills/earthsplitter.tres`, `doom_sigil.tres`, `tectonic_slam.tres`, `withering_hex.tres`
- Modify: `data/enemies/void_shade.tres`, `earth_golem.tres`, `dark_wraith.tres`, `goblin_warlord.tres`
- Modify: `tests/fixtures/move_library_baseline.json` (append four entries, with the Edit tool)
- Modify: `tests/suites/test_move_library.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/suites/test_move_library.gd`:

```gdscript
func test_spec_c_enemies_carry_their_multi_turn_moves() -> void:
	var has := func(list: Array, n: String) -> bool:
		return list.map(func(s): return s.skill_name).has(n)
	assert_true(has.call(load("res://data/enemies/void_shade.tres").skills, "Doom Sigil"), "the Void Shade curses")
	assert_true(has.call(load("res://data/enemies/earth_golem.tres").skills, "Tectonic Slam"), "the Earth Golem slams")
	assert_true(has.call(load("res://data/enemies/dark_wraith.tres").skills, "Withering Hex"), "the Dark Wraith hexes")
	var warlord: Enemy = load("res://data/enemies/goblin_warlord.tres")
	var final_phase: BossPhase = warlord.phases[warlord.phases.size() - 1]
	assert_true(has.call(final_phase.skills, "Earthsplitter"), "the Warlord charges in his final phase")
	assert_false(has.call(warlord.skills, "Earthsplitter"), "and only there")
```

- [ ] **Step 2: Run to verify it fails.**

- [ ] **Step 3: Create the four move files** (same shape as Task 7; `target_type` 1 = the whole party when an enemy uses it; `element` 6 Earth, 9 Psychic, 14 Dark)

`data/skills/earthsplitter.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Earthsplitter"
description = "The Warlord heaves his axe skyward, gathering every ounce of strength for one ground-splitting blow."
target_type = 1
power = 2.6
charge_turns = 1
```

`data/skills/doom_sigil.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Doom Sigil"
description = "Etches a sigil on its victim that detonates when the next round ends."
attack_type = 2
power = 2.4
element = 9
delay_rounds = 2
```

`data/skills/tectonic_slam.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Tectonic Slam"
description = "Slams the earth so hard the whole party is thrown — and the golem must recover."
target_type = 1
power = 1.8
element = 6
recharge_turns = 1
```

`data/skills/withering_hex.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Withering Hex"
description = "A hex that saps every hero's strength for a few turns."
attack_type = 2
target_type = 1
power = 0.6
element = 14
status_to_apply = "attack_debuff"
status_chance = 1.0
effect_turns = 3
```

- [ ] **Step 4: Wire the enemies**

- `data/enemies/void_shade.tres`: after the line `[ext_resource type="Resource" path="res://data/skills/void_mend.tres" id="7_dg6hy"]` add `[ext_resource type="Resource" path="res://data/skills/doom_sigil.tres" id="8_doom"]`, and change its `skills = …` line to end `ExtResource("7_dg6hy"), ExtResource("8_doom")])`.
- `data/enemies/earth_golem.tres`: after `… earth_mend.tres" id="7_shw47"]` add `[ext_resource type="Resource" path="res://data/skills/tectonic_slam.tres" id="8_tectonic"]`; its `skills` line ends `ExtResource("7_shw47"), ExtResource("8_tectonic")])`.
- `data/enemies/dark_wraith.tres`: after `… void_shroud.tres" id="7_d2i2a"]` add `[ext_resource type="Resource" path="res://data/skills/withering_hex.tres" id="8_wither"]`; its `skills` line ends `ExtResource("7_d2i2a"), ExtResource("8_wither")])`.
- `data/enemies/goblin_warlord.tres`: after `… overreach.tres" id="8_overreach"]` add `[ext_resource type="Resource" path="res://data/skills/earthsplitter.tres" id="9_earthsplitter"]`; change the **fury phase's** line `skills = Array[ExtResource("1_skill")]([ExtResource("3_ro5fg"), ExtResource("4_q44ng")])` (inside `[sub_resource … id="Phase_fury"]`) to end `ExtResource("4_q44ng"), ExtResource("9_earthsplitter")])`. Do NOT change the base `[resource]` `skills` line.

- [ ] **Step 5: Record the additions in the baseline (Edit tool)**

In `tests/fixtures/move_library_baseline.json`, append one object to the END of each list below. Match the neighbouring entries exactly: keys in sorted order, tab indentation one level deeper than the list, the previous last entry gaining a trailing comma, and the file's missing final newline left as it is. Afterwards `git diff --stat tests/fixtures/move_library_baseline.json` must show insertions only.

- `"res://data/enemies/void_shade.tres"` → its `"skills"` list:
```json
{
	"attack_type": 2,
	"category": 0,
	"description": "Etches a sigil on its victim that detonates when the next round ends.",
	"element": 9,
	"mp_cost": 0,
	"power": 2.4,
	"resonance_gain_override": -1.0,
	"secondary_element": 0,
	"skill_name": "Doom Sigil",
	"skill_type": 0,
	"status_chance": 0.0,
	"status_to_apply": "",
	"status_type": 0,
	"target_type": 0,
	"unlock_level": 1
}
```
- `"res://data/enemies/earth_golem.tres"` → its `"skills"` list:
```json
{
	"attack_type": 0,
	"category": 0,
	"description": "Slams the earth so hard the whole party is thrown — and the golem must recover.",
	"element": 6,
	"mp_cost": 0,
	"power": 1.8,
	"resonance_gain_override": -1.0,
	"secondary_element": 0,
	"skill_name": "Tectonic Slam",
	"skill_type": 0,
	"status_chance": 0.0,
	"status_to_apply": "",
	"status_type": 0,
	"target_type": 1,
	"unlock_level": 1
}
```
- `"res://data/enemies/dark_wraith.tres"` → its `"skills"` list:
```json
{
	"attack_type": 2,
	"category": 0,
	"description": "A hex that saps every hero's strength for a few turns.",
	"element": 14,
	"mp_cost": 0,
	"power": 0.6,
	"resonance_gain_override": -1.0,
	"secondary_element": 0,
	"skill_name": "Withering Hex",
	"skill_type": 0,
	"status_chance": 1.0,
	"status_to_apply": "attack_debuff",
	"status_type": 0,
	"target_type": 1,
	"unlock_level": 1
}
```
- `"res://data/enemies/goblin_warlord.tres"` → `"phase_skills"`, the THIRD list (after Executioner's Drop):
```json
{
	"attack_type": 0,
	"category": 0,
	"description": "The Warlord heaves his axe skyward, gathering every ounce of strength for one ground-splitting blow.",
	"element": 0,
	"mp_cost": 0,
	"power": 2.6,
	"resonance_gain_override": -1.0,
	"secondary_element": 0,
	"skill_name": "Earthsplitter",
	"skill_type": 0,
	"status_chance": 0.0,
	"status_to_apply": "",
	"status_type": 0,
	"target_type": 1,
	"unlock_level": 1
}
```

- [ ] **Step 6: Run the tests** — `MoveLibrary [OK]`, `BossPhases [OK]`, TOTAL 0 failed.

- [ ] **Step 7: Commit** — stage the four `.tres` move files, the four enemy files, the fixture and `test_move_library.gd`. Message: `Give four enemies a charge, a delayed curse, a recharge slam and a timed hex`.

---

### Task 9: Document the system

**Files:**
- Modify: `CLAUDE.md` (the project's, at `new-game-project/CLAUDE.md`)

- [ ] **Step 1: Skill section** — under `### Skill (Resource)`, add a `**Spec C options**` sub-list: the four fields with one line each, that all default to "off", the four effect tags, and `applies_stat_effect()`.

- [ ] **Step 2: BattleManager section** — record:
  - **Pacing switch**: `paced` (false on a bare manager; `BattleScene` sets it) and `_pause()`; the seven constants; that Spec B's `hit_pause` / `action_pause` variables are gone; that every wait in the turn loop goes through `_pause` (pinned by a test), so tests drive enemy turns synchronously.
  - **Use vs strike**: `resolve_skill` checks, measures (`_measure`), pays, then strikes now or schedules; `_strike` is the beat loop; `_start_recharge`.
  - **The scheduled list**: `Scheduled` (`CASTER_TURN` / `ROUND_END`), `_charge_of`, `_strike_targets` (fallen single target → a random living one on its side), `_release_charge` (measured at release, enemies show the move name), `_land_delayed_strikes` (end of round, cast order, banner → pause → hits → action pause, fallen caster = hits only, battle end drops the rest); `check_battle_end` clears the list; `handle_defeat` drops a charger's charge.
  - **The turn-start order** (Spec C Part 3): ticks → timed stats → `turn_started` → recharge → status skip (breaking a charge first) → charge release → `turn_ready_for_action`.
  - The new event types (`StatusSystem.CHARGING`, `FOCUS_BROKEN`, `RECHARGING`, `STRIKE_SCHEDULED`, `STRIKE_LANDING`, `STATS_EXPIRED`) and which are quiet.

- [ ] **Step 3: Status section** — timed buffs/debuffs: `buff_turns` / `debuff_turns`, `apply_buff/apply_debuff(stat, turns)`, `tick_stat_timers` (expiry rule), the permanent-wins / longer-wins / cancel rules; `recharge_turns_left`; all battle-only.

- [ ] **Step 4: Pools, moves and counts** — hero pools are **18** (8 attack + 10 special); `SKILL_UNLOCK_LEVELS` gains `6, 11, 16`; list the nine hero moves and four enemy moves (Earthsplitter in the Warlord's final phase); the move library is **110** files (update every "97"); update every "15-move" / "7 + 8" mention; the play-test flag comment. Roadmap Track B item 3: Spec C done — Track B complete. Update both test-count references to the real numbers from a final run (`TOTAL` line and `SUITE_PATHS` entries — 49) and add `multi_turn` to the Testing Policy suite list.

- [ ] **Step 5: Run the full suite** — ALL TESTS PASSED, 0 failed.

- [ ] **Step 6: Commit** — stage `CLAUDE.md` only. Message: `Document Spec C: multi-turn moves`.

---

## Done criteria

- Charge-ups release on the user's next turn and are broken by a skipped turn; delayed strikes land at the end of the round in cast order and cannot be prevented; recharge rests the next turn; timed buffs/debuffs wear off on their owner's turns.
- Every new option defaults to "off"; existing buffs/debuffs still last the whole battle.
- Every wait in the turn loop goes through the pacing switch; enemy turns are unit-tested.
- Heroes have 18-move pools with the nine new moves; the four enemies carry theirs (Earthsplitter in the Warlord's final phase).
- Saves carry the four options; older saves gain the new moves.
- All five Review Focus cases pinned; the full suite green with no drop below 3896.
