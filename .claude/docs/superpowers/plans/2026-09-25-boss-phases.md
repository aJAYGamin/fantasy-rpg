# Boss Phases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give enemies data-driven multi-phase behaviour, so a boss changes its moveset, stats, summons allies, applies field effects, and can transform into a stronger form as it loses HP.

**Architecture:** A boss is an `Enemy` that owns an array of `BossPhase` resources. Phases advance forward-only, one step at a time, driven from a single choke point at the top of `BattleManager._next_turn()`. Each phase power is an optional field, so a boss opts into only what suits it. No per-boss code — a new boss is one `.tres` file.

**Tech Stack:** Godot 4.6.1, GDScript. Tests are the project's own `TestSuite` harness (`tests/suites/test_*.gd`, registered in `tests/TestRunner.gd`).

**Spec:** `.claude/docs/superpowers/specs/2026-09-24-boss-phases-design.md`

## Global Constraints

- **Godot 4.6.1**, binary at `/Applications/Godot.app/Contents/MacOS/Godot`.
- **Run tests:** `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/TestRunner.tscn --quit-after 5` from `new-game-project/`. Baseline before this work: **2307 passing, 0 failed**.
- **New `class_name` files need a class-cache rescan** before the headless runner sees them: `/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --quit-after 3 --path .`
- **Tests run synchronously in a single frame** — no `await`, no reliance on `queue_free()` having completed, no container layout (containers lay out next frame; position controls by hand if geometry matters).
- **Every new feature ships with a unit test**, in a suite registered in `tests/TestRunner.gd` `SUITE_PATHS`.
- **Branch-per-task workflow:** all work on the existing `boss-phases` branch. Never commit to `main`.
- **Commit attribution:** end every commit message with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **Battle-temp state is never serialized.** Nothing in this plan touches `SaveSerializer`.
- **Art is parked.** No sprites, no props, no map edits.
- **Enemy cap is 10** (`BattleManager.MAX_BATTLE_ENEMIES`), matching the card row at `BattleScene.gd:388`.
- **`stat_multipliers` accepts only** `attack`, `defense`, `magic`, `arcane`, `speed`.

## Review Focus

Input classes the spec implies but that no task's happy-path tests would exercise. Each has a test assigned to the task that owns the code.

1. **A boss killed by the very hit that crosses a phase threshold** must not transform, summon, or banner after death — a corpse that summons adds is the worst failure here. *(Task 3)*
2. **A summon whose `path` is missing, empty, or fails to `load()`** must be skipped without crashing the battle — a typo in a `.tres` should not end the fight. *(Task 5)*
3. **`stat_multipliers` containing an excluded or unknown key** (`max_hp`, `luck`) must be ignored silently rather than crashing or silently moving the phase thresholds. *(Task 2)*
4. **A transformation applied while the boss is at 1 HP** must end with `current_hp == max_hp()` at the NEW maximum — an ordering slip that reads `max_hp()` before setting the multiplier leaves the boss on a sliver. *(Task 3)*
5. **A boss whose phase 0 `enter_at_hp` is below 1.0** never enters a phase at full HP, leaving `active_phase == -1` and `current_phase() == null`. Every consumer must tolerate that null rather than crash. *(Task 1)*

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/characters/BossPhase.gd` *(new)* | The phase data resource. Pure data + one predicate. |
| `scripts/characters/Enemy.gd` *(modify)* | Owns `phases`, and the forward-only advancement logic. |
| `scripts/characters/Character.gd` *(modify)* | `phase_multipliers` / `max_hp_multiplier` folded into the stat getters. |
| `scripts/battle/BattleManager.gd` *(modify)* | Transition engine, summons, field-effect hook, `boss_phase_changed`. |
| `scripts/battle/EnemyAI.gd` *(modify)* | Draws skills from the active phase; loses the hard-coded enrage. |
| `scripts/battle/BattleScene.gd` *(modify)* | Full-width boss card, phase banner, card rebuild on summon. |
| `data/enemies/goblin_warlord.tres` *(new)* | The first boss. |
| `data/encounters/goblin_warlord_fight.tres` *(new)* | Fixed encounter wrapping it. |
| `tests/suites/test_boss_phases.gd` *(new)* | The whole feature's suite. |

---

## Task 1: BossPhase resource + Enemy phase state

**Files:**
- Create: `scripts/characters/BossPhase.gd`
- Modify: `scripts/characters/Enemy.gd`
- Create: `tests/suites/test_boss_phases.gd`
- Modify: `tests/TestRunner.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `class_name BossPhase` with fields `enter_at_hp: float`, `phase_name: String`, `banner_text: String`, `skills: Array[Skill]`, `stat_multipliers: Dictionary`, `summons: Array[Dictionary]`, `turn_effect: String`, `turn_effect_chance: float`, `max_hp_multiplier: float`, `restore_hp: bool`, and `is_transformation() -> bool`. On `Enemy`: `phases: Array[BossPhase]`, `active_phase: int`, `is_boss() -> bool`, `hp_fraction() -> float`, `should_advance_phase() -> bool`, `advance_phase() -> BossPhase`, `current_phase() -> BossPhase`.

- [ ] **Step 1: Create the BossPhase resource**

Create `scripts/characters/BossPhase.gd`:

```gdscript
class_name BossPhase
extends Resource

## One phase of a boss fight. Every field except `enter_at_hp` is optional — an
## omitted field means "this phase does not use that power", which is what lets
## one boss be a pure stat-check and another a summoner.

## The phase becomes active at or below this fraction of max HP.
@export var enter_at_hp: float = 1.0
@export var phase_name: String = ""
## Shown as a banner on entry. "" transitions silently.
@export var banner_text: String = ""

## Replaces the boss's usable moveset while this phase is active. [] = keep base.
@export var skills: Array[Skill] = []

## {"attack": 1.5, "speed": 1.2}. Only the five combat stats; max_hp is
## deliberately NOT accepted here — see max_hp_multiplier below.
@export var stat_multipliers: Dictionary = {}

## [{"path": "res://data/enemies/x.tres", "count": 2, "level": 8}]
@export var summons: Array[Dictionary] = []

## StatusSystem apply-token rolled on the boss's own turn.
@export var turn_effect: String = ""
@export var turn_effect_chance: float = 0.0

## > 0 makes this phase a TRANSFORMATION: max HP scales by this factor.
@export var max_hp_multiplier: float = 0.0
## Refill to the new maximum on entry.
@export var restore_hp: bool = false

func is_transformation() -> bool:
	return max_hp_multiplier > 0.0
```

- [ ] **Step 2: Rebuild the class cache so the runner sees the new class_name**

Run from `new-game-project/`:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --quit-after 3 --path .
```
Expected: exits without a parse error. Skipping this makes every later test fail with `Identifier "BossPhase" not declared`.

- [ ] **Step 3: Write the failing tests**

Create `tests/suites/test_boss_phases.gd`:

```gdscript
extends TestSuite

## Boss phases: forward-only advancement, and the five optional phase powers.

func suite_name() -> String:
	return "BossPhases"

## A phase with just a threshold — the other powers are opted into per test.
func _phase(at: float) -> BossPhase:
	var p := BossPhase.new()
	p.enter_at_hp = at
	return p

## A boss with the standard 1.0 / 0.5 / 0.25 ladder and 100 max HP.
func _boss(thresholds: Array = [1.0, 0.5, 0.25]) -> Enemy:
	var e := Enemy.new()
	e.character_name = "Test Warlord"
	e.base_hp = 100
	e.level = 1
	var list: Array[BossPhase] = []
	for t in thresholds:
		list.append(_phase(float(t)))
	e.phases = list
	e.current_hp = e.max_hp()
	return e

# --------------------------------------------------- is_boss

func test_an_enemy_without_phases_is_not_a_boss() -> void:
	var e := Enemy.new()
	e.base_hp = 50
	assert_false(e.is_boss(), "a plain enemy is not a boss")
	assert_eq(e.current_phase(), null, "and has no phase")

func test_an_enemy_with_phases_is_a_boss() -> void:
	assert_true(_boss().is_boss(), "phases are what make an enemy a boss")

# --------------------------------------------------- forward-only advancement

func test_phase_zero_is_entered_at_full_hp() -> void:
	var b := _boss()
	assert_eq(b.active_phase, -1, "starts before any phase")
	assert_true(b.should_advance_phase(), "phase 0 is ready at full HP")
	b.advance_phase()
	assert_eq(b.active_phase, 0, "entered phase 0")
	assert_false(b.should_advance_phase(), "and does not run on into phase 1")

func test_advances_at_the_threshold() -> void:
	var b := _boss()
	b.advance_phase()                 # into phase 0
	b.current_hp = 60
	assert_false(b.should_advance_phase(), "60% is above the 50% threshold")
	b.current_hp = 50
	assert_true(b.should_advance_phase(), "exactly at the threshold advances")
	b.advance_phase()
	assert_eq(b.active_phase, 1, "now in phase 1")

func test_phases_never_regress() -> void:
	# Healing a boss above a threshold must not re-enter an earlier phase, or
	# banners would re-fire and summons would repeat on every oscillation.
	var b := _boss()
	b.advance_phase()
	b.current_hp = 40
	while b.should_advance_phase():
		b.advance_phase()
	assert_eq(b.active_phase, 1, "dropped to phase 1")
	b.current_hp = b.max_hp()
	assert_false(b.should_advance_phase(), "full HP does not advance further")
	assert_eq(b.active_phase, 1, "and does not fall back to phase 0")

func test_does_not_advance_past_the_last_phase() -> void:
	var b := _boss()
	b.current_hp = 1
	var guard := 0
	while b.should_advance_phase() and guard < 50:
		b.advance_phase()
		guard += 1
	assert_eq(b.active_phase, 2, "stops at the last authored phase")
	assert_false(b.should_advance_phase(), "and stays there")

# --------------------------------------------------- Review Focus #5

func test_a_boss_whose_first_phase_is_below_full_hp_tolerates_no_phase() -> void:
	# Authoring slip: phase 0 at 0.8 means a boss at full HP is in NO phase.
	# current_phase() must return null rather than crash, and every consumer
	# must cope — the moveset falls back to the enemy's own skills.
	var b := _boss([0.8, 0.4])
	assert_false(b.should_advance_phase(), "full HP is above the first threshold")
	assert_eq(b.active_phase, -1, "no phase entered")
	assert_eq(b.current_phase(), null, "current_phase is null, not a crash")

func test_hp_fraction_survives_a_zero_max() -> void:
	var e := Enemy.new()
	e.base_hp = 0
	e.level = 1
	assert_true(e.hp_fraction() >= 0.0, "no divide-by-zero on a degenerate enemy")
```

- [ ] **Step 4: Register the suite**

In `tests/TestRunner.gd`, add to `SUITE_PATHS`:
```gdscript
	"res://tests/suites/test_boss_phases.gd",
```

- [ ] **Step 5: Run the tests to verify they fail**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/TestRunner.tscn --quit-after 5`
Expected: FAIL — `Invalid call. Nonexistent function 'is_boss' in base 'Resource'`.

- [ ] **Step 6: Add the phase state to Enemy**

In `scripts/characters/Enemy.gd`, after the existing `@export var drop_table`:

```gdscript
## Multi-phase boss behaviour. An enemy with phases IS a boss — there is no
## separate flag to fall out of sync with the data.
@export var phases: Array[BossPhase] = []

## Battle-temp: which phase is active. -1 = none entered yet. Never serialized.
var active_phase: int = -1

func is_boss() -> bool:
	return not phases.is_empty()

func hp_fraction() -> float:
	var m := max_hp()
	if m <= 0:
		return 0.0
	return float(current_hp) / float(m)

## Phases advance FORWARD ONLY, one step at a time. Recomputing the active phase
## from HP cannot express a transformation: refilling HP returns the fraction to
## 1.0, so a recomputing formula would drop the boss back to its opening form.
func should_advance_phase() -> bool:
	var nxt := active_phase + 1
	if nxt >= phases.size():
		return false
	return hp_fraction() <= phases[nxt].enter_at_hp

func advance_phase() -> BossPhase:
	if active_phase + 1 >= phases.size():
		return null
	active_phase += 1
	return phases[active_phase]

func current_phase() -> BossPhase:
	if active_phase < 0 or active_phase >= phases.size():
		return null
	return phases[active_phase]
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/TestRunner.tscn --quit-after 5`
Expected: `BossPhases [OK] (14/14)`, TOTAL 2321 passed, 0 failed.

- [ ] **Step 8: Commit**

```bash
git add scripts/characters/BossPhase.gd scripts/characters/Enemy.gd tests/suites/test_boss_phases.gd tests/TestRunner.gd
git commit -m "Add BossPhase resource and forward-only phase advancement

A boss is an enemy that has phases, so there is no separate is_boss flag to
fall out of sync with the data.

Phases advance forward only, one step at a time, rather than being recomputed
from current HP. Recomputing cannot express a transformation: refilling HP
returns the fraction to 1.0, so the formula would drop the boss back to its
opening form. Forward-only also makes never-regress true by construction.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 2: Character phase multipliers and max HP scaling

**Files:**
- Modify: `scripts/characters/Character.gd:47` (near `combat_stat_multiplier`), `:197-222` (stat getters), `:374-382` (`clear_battle_effects`)
- Modify: `tests/suites/test_boss_phases.gd`

**Interfaces:**
- Consumes: `BossPhase.stat_multipliers`, `BossPhase.max_hp_multiplier` from Task 1.
- Produces: on `Character` — `phase_multipliers: Dictionary`, `max_hp_multiplier: float` (default `1.0`), `phase_mult(stat: String) -> float`. Both cleared by `clear_battle_effects()`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_boss_phases.gd`:

```gdscript
# --------------------------------------------------- stat multipliers

func test_phase_multiplier_scales_a_combat_stat() -> void:
	var b := _boss()
	b.base_attack = 20
	var before := b.attack_power()
	b.phase_multipliers = {"attack": 2.0}
	assert_eq(b.attack_power(), before * 2, "a phase multiplier doubles ATK")

func test_phase_multiplier_defaults_to_one() -> void:
	var b := _boss()
	b.base_speed = 10
	var before := b.speed()
	b.phase_multipliers = {"attack": 3.0}
	assert_eq(b.speed(), before, "an unlisted stat is untouched")

func test_phase_multiplier_composes_with_a_buff() -> void:
	# It must STACK with buffs/debuffs and difficulty, not replace them.
	var b := _boss()
	b.base_attack = 20
	b.phase_multipliers = {"attack": 2.0}
	var phase_only := b.attack_power()
	b.apply_buff(StatusSystem.STAT_ATK)
	assert_true(b.attack_power() > phase_only, "a buff still applies on top of the phase")

func test_phase_multiplier_composes_with_difficulty() -> void:
	var b := _boss()
	b.base_attack = 20
	b.set_difficulty_multiplier(2.0)
	var difficulty_only := b.attack_power()
	b.phase_multipliers = {"attack": 2.0}
	assert_eq(b.attack_power(), difficulty_only * 2, "phase and difficulty multiply")

# --------------------------------------------------- Review Focus #3

func test_excluded_and_unknown_multiplier_keys_are_ignored() -> void:
	# max_hp is banned from stat_multipliers because it would move the very
	# thresholds that drive the phases. An unknown key must not crash either.
	var b := _boss()
	var hp_before := b.max_hp()
	b.phase_multipliers = {"max_hp": 5.0, "luck": 2.0}
	assert_eq(b.max_hp(), hp_before, "max_hp cannot be changed via stat_multipliers")
	assert_true(b.attack_power() > 0, "an unknown key does not break the stat getters")

# --------------------------------------------------- max HP scaling

func test_max_hp_multiplier_grows_the_pool() -> void:
	var b := _boss()
	var before := b.max_hp()
	b.max_hp_multiplier = 1.5
	assert_eq(b.max_hp(), roundi(before * 1.5), "max HP scales for a transformation")

func test_max_hp_multiplier_defaults_to_one() -> void:
	var b := _boss()
	assert_eq(b.max_hp_multiplier, 1.0, "an untransformed enemy is unscaled")

# --------------------------------------------------- battle-end cleanup

func test_clear_battle_effects_clears_phase_state() -> void:
	# Otherwise a transformed boss leaks its grown HP pool into a later encounter.
	var b := _boss()
	b.phase_multipliers = {"attack": 3.0}
	b.max_hp_multiplier = 2.0
	b.clear_battle_effects()
	assert_true(b.phase_multipliers.is_empty(), "phase multipliers cleared")
	assert_eq(b.max_hp_multiplier, 1.0, "max HP scaling reset")
```

- [ ] **Step 2: Run to verify they fail**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/TestRunner.tscn --quit-after 5`
Expected: FAIL — `Invalid assignment of property 'phase_multipliers'`.

- [ ] **Step 3: Add the fields**

In `scripts/characters/Character.gd`, immediately after `var combat_stat_multiplier: float = 1.0` (line 47):

```gdscript
# --- Boss phase scaling (battle-temp, never serialized) ---
# Set when a boss enters a phase. Composes with buffs/debuffs and difficulty
# rather than replacing them. Only the five combat stats are honoured; max_hp is
# deliberately absent, because changing it here would move the very thresholds
# that drive phase transitions. A transformation uses max_hp_multiplier instead.
var phase_multipliers: Dictionary = {}
var max_hp_multiplier: float = 1.0

func phase_mult(stat: String) -> float:
	return float(phase_multipliers.get(stat, 1.0))
```

- [ ] **Step 4: Fold the multipliers into the getters**

Replace lines 197-222 of `scripts/characters/Character.gd`:

```gdscript
func max_hp() -> int:
	return maxi(1, roundi((base_hp + (level - 1) * 15 + inventory.equipment_bonus("max_hp")) * combat_stat_multiplier * max_hp_multiplier))

func max_mp() -> int:
	return maxi(0, roundi((base_mp + (level - 1) * 8 + inventory.equipment_bonus("max_mp")) * combat_stat_multiplier))

func attack_power() -> int:
	var raw = base_attack + (level - 1) * 2 + inventory.equipment_bonus("attack")
	return roundi(StatusSystem.compose_stat(raw, self, StatusSystem.STAT_ATK) * combat_stat_multiplier * phase_mult(StatusSystem.STAT_ATK))

func defense_power() -> int:
	var raw = base_defense + (level - 1) * 1 + inventory.equipment_bonus("defense")
	return roundi(StatusSystem.compose_stat(raw, self, StatusSystem.STAT_DEF) * combat_stat_multiplier * phase_mult(StatusSystem.STAT_DEF))

func magic_power() -> int:
	var raw = base_magic + (level - 1) * 2 + inventory.equipment_bonus("magic")
	return roundi(StatusSystem.compose_stat(raw, self, StatusSystem.STAT_MAG) * combat_stat_multiplier * phase_mult(StatusSystem.STAT_MAG))

# Magic resistance — analogous to defense_power() but for magic damage.
func arcane_power() -> int:
	var raw = base_arcane + (level - 1) * 1 + inventory.equipment_bonus("arcane")
	return roundi(StatusSystem.compose_stat(raw, self, StatusSystem.STAT_ARC) * combat_stat_multiplier * phase_mult(StatusSystem.STAT_ARC))

func speed() -> int:
	var raw = base_speed + (level - 1) * 1 + inventory.equipment_bonus("speed")
	return roundi(StatusSystem.compose_stat(raw, self, StatusSystem.STAT_SPD) * combat_stat_multiplier * phase_mult(StatusSystem.STAT_SPD))
```

Note `max_mp()` is deliberately unscaled: enemies ignore MP entirely.

- [ ] **Step 5: Clear the state at battle end**

In `clear_battle_effects()` (line 374), add before the closing of the function:

```gdscript
	phase_multipliers.clear()
	max_hp_multiplier = 1.0
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/TestRunner.tscn --quit-after 5`
Expected: `BossPhases [OK] (22/22)`, 0 failed. The whole existing suite must stay green — these getters are used by every battle test.

- [ ] **Step 7: Commit**

```bash
git add scripts/characters/Character.gd tests/suites/test_boss_phases.gd
git commit -m "Compose boss phase multipliers into the stat getters

Phase multipliers multiply alongside StatusSystem.compose_stat and the
difficulty multiplier rather than replacing either, so a phase boost stacks
correctly with buffs, debuffs and status penalties.

max_hp is reachable only through its own max_hp_multiplier, never through
stat_multipliers: changing it there would silently move the thresholds that
drive phase transitions. Both fields clear at battle end so a transformed boss
cannot leak its grown HP pool into the next encounter.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 3: Transition engine, transformation, and the boss_phase_changed signal

**Files:**
- Modify: `scripts/battle/BattleManager.gd` (signals block at `:4-13`, `_next_turn` at `:52`)
- Modify: `tests/suites/test_boss_phases.gd`

**Interfaces:**
- Consumes: `Enemy.should_advance_phase()`, `Enemy.advance_phase()`, `BossPhase.is_transformation()`, `Character.phase_multipliers`, `Character.max_hp_multiplier`.
- Produces: `BattleManager.boss_phase_changed(enemy: Character, phase: BossPhase)` signal, `BattleManager.MAX_BATTLE_ENEMIES := 10`, `BattleManager.check_boss_phases() -> void`, `BattleManager._enter_boss_phase(boss: Enemy, phase: BossPhase) -> void`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_boss_phases.gd`:

```gdscript
# --------------------------------------------------- transition engine

## A BattleManager wired to a party and a single boss, without running a battle.
func _manager(boss: Enemy) -> BattleManager:
	var bm := BattleManager.new()
	var hero := Character.new()
	hero.character_name = "Hero"
	hero.base_hp = 100
	hero.level = 1
	hero.current_hp = hero.max_hp()
	var party: Array[Character] = [hero]
	var foes: Array[Character] = [boss]
	bm.party = party
	bm.enemies = foes
	return bm

func test_entering_a_phase_emits_once() -> void:
	var b := _boss()
	var bm := _manager(b)
	var fired: Array = []
	bm.boss_phase_changed.connect(func(_e, p): fired.append(p))
	bm.check_boss_phases()
	assert_eq(fired.size(), 1, "entering phase 0 emits once")
	bm.check_boss_phases()
	assert_eq(fired.size(), 1, "a second check inside the same phase does not re-emit")
	bm.free()

func test_a_hit_crossing_two_thresholds_fires_both_entries() -> void:
	# Changed from an earlier draft: firing only the deepest let a burst-damage
	# party skip a transform entirely, which trivialises the fight.
	var b := _boss()
	var bm := _manager(b)
	bm.check_boss_phases()            # phase 0
	var fired: Array = []
	bm.boss_phase_changed.connect(func(_e, p): fired.append(p))
	b.current_hp = 10                 # crosses 0.5 AND 0.25
	bm.check_boss_phases()
	assert_eq(fired.size(), 2, "both crossed phases fire")
	assert_eq(b.active_phase, 2, "and it ends in the deepest")
	bm.free()

func test_entering_a_phase_applies_its_stat_multipliers() -> void:
	var b := _boss()
	b.base_attack = 20
	b.phases[1].stat_multipliers = {"attack": 2.0}
	var bm := _manager(b)
	bm.check_boss_phases()
	var before := b.attack_power()
	b.current_hp = 50
	bm.check_boss_phases()
	assert_eq(b.attack_power(), before * 2, "phase 1's multiplier is live")
	bm.free()

func test_a_later_phase_replaces_the_previous_multipliers() -> void:
	var b := _boss()
	b.base_attack = 20
	b.phases[1].stat_multipliers = {"attack": 2.0}
	b.phases[2].stat_multipliers = {"speed": 2.0}
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 10
	bm.check_boss_phases()
	assert_eq(b.phase_mult("attack"), 1.0, "phase 1's ATK boost is gone, not accumulated")
	assert_eq(b.phase_mult("speed"), 2.0, "phase 2's SPD boost is live")
	bm.free()

# --------------------------------------------------- transformation

func test_transformation_grows_max_hp_and_refills() -> void:
	var b := _boss()
	b.phases[2].max_hp_multiplier = 1.5
	b.phases[2].restore_hp = true
	var base_max := b.max_hp()
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 10
	bm.check_boss_phases()
	assert_eq(b.max_hp(), roundi(base_max * 1.5), "max HP grew")
	assert_eq(b.current_hp, b.max_hp(), "and the bar is full again")
	bm.free()

func test_transformation_does_not_regress_the_phase() -> void:
	# A refill returns the fraction to 1.0; a recomputing design would drop the
	# boss back to phase 0 here.
	var b := _boss()
	b.phases[2].max_hp_multiplier = 1.5
	b.phases[2].restore_hp = true
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 10
	bm.check_boss_phases()
	assert_eq(b.active_phase, 2, "still in the transformed phase at full HP")
	bm.free()

func test_transformation_halts_the_cascade() -> void:
	# Four phases, with the transform third. One huge hit must stop AT the
	# transform rather than running on into phase 3.
	var b := _boss([1.0, 0.5, 0.25, 0.1])
	b.phases[2].max_hp_multiplier = 2.0
	b.phases[2].restore_hp = true
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 1
	bm.check_boss_phases()
	assert_eq(b.active_phase, 2, "stopped at the transform, not phase 3")
	bm.free()

func test_a_later_phase_still_fires_against_the_new_max_hp() -> void:
	var b := _boss([1.0, 0.5, 0.25, 0.1])
	b.phases[2].max_hp_multiplier = 2.0
	b.phases[2].restore_hp = true
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 1
	bm.check_boss_phases()                      # transform, now at 2x max
	b.current_hp = int(b.max_hp() * 0.05)       # 5% of the NEW pool
	bm.check_boss_phases()
	assert_eq(b.active_phase, 3, "the last phase fires against the new maximum")
	bm.free()

# --------------------------------------------------- Review Focus #1 and #4

func test_a_dead_boss_does_not_transition() -> void:
	# The worst failure mode here is a corpse that summons reinforcements.
	var b := _boss()
	b.phases[1].max_hp_multiplier = 2.0
	var bm := _manager(b)
	bm.check_boss_phases()
	var fired: Array = []
	bm.boss_phase_changed.connect(func(_e, p): fired.append(p))
	b.current_hp = 0
	bm.check_boss_phases()
	assert_true(fired.is_empty(), "a defeated boss fires no phase entry")
	assert_eq(b.active_phase, 0, "and does not advance")
	bm.free()

func test_transforming_at_one_hp_ends_at_the_new_full() -> void:
	# Guards an ordering slip: reading max_hp() before setting the multiplier
	# would leave the boss on a sliver of its new pool.
	var b := _boss()
	b.phases[1].max_hp_multiplier = 3.0
	b.phases[1].restore_hp = true
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 1
	bm.check_boss_phases()
	assert_eq(b.current_hp, b.max_hp(), "refilled to the NEW maximum")
	assert_true(b.current_hp > 100, "which is larger than the original pool")
	bm.free()
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — `Invalid call. Nonexistent function 'check_boss_phases'`.

- [ ] **Step 3: Add the signal and the cap**

In `scripts/battle/BattleManager.gd`, after `signal status_effect_triggered` (line 13):

```gdscript
## A boss crossed into a new phase. BattleScene banners it and rebuilds cards.
signal boss_phase_changed(enemy: Character, phase: BossPhase)

## Hard cap on combatants. The enemy card row is built for exactly this many
## (see BattleScene.gd: "10 enemies fill the row"), so a boss may summon 0-9.
const MAX_BATTLE_ENEMIES := 10
```

- [ ] **Step 4: Implement the transition engine**

Add to `scripts/battle/BattleManager.gd` (near the other helpers, above `_apply_skill_status`):

```gdscript
# --- Boss phases -------------------------------------------------------------
# One choke point for every source of damage. Damage is applied in half a dozen
# places (player attack, player skill, enemy skill, counter...), so rather than
# hooking each, phases are checked at the top of every turn. That also means a
# boss can never act while still in a stale phase.
func check_boss_phases() -> void:
	for e in enemies:
		if not (e is Enemy):
			continue
		var boss := e as Enemy
		# A defeated boss must not transform, summon or banner.
		if not boss.is_boss() or not boss.is_alive():
			continue
		while boss.should_advance_phase():
			var phase := boss.advance_phase()
			if phase == null:
				break
			_enter_boss_phase(boss, phase)

func _enter_boss_phase(boss: Enemy, phase: BossPhase) -> void:
	# Replace, don't accumulate: the new phase's multipliers are the whole truth.
	boss.phase_multipliers = phase.stat_multipliers.duplicate()

	# Transformation. Set the multiplier BEFORE reading max_hp(), or the refill
	# lands on the old maximum and leaves the boss on a sliver of its new pool.
	if phase.is_transformation():
		boss.max_hp_multiplier = phase.max_hp_multiplier
		if phase.restore_hp:
			boss.current_hp = boss.max_hp()

	emit_signal("boss_phase_changed", boss, phase)
```

- [ ] **Step 5: Hook it into the turn loop**

In `_next_turn()` (line 52), insert as the very first statement of the function, before the `while` loop:

```gdscript
	check_boss_phases()
```

- [ ] **Step 6: Run the tests to verify they pass**

Expected: `BossPhases [OK] (32/32)`, whole suite 0 failed.

- [ ] **Step 7: Commit**

```bash
git add scripts/battle/BattleManager.gd tests/suites/test_boss_phases.gd
git commit -m "Add the boss phase transition engine and transformation

Phases are checked at the top of every turn rather than at each damage site:
damage lands in six different places, and a single choke point also guarantees a
boss never acts while still in a stale phase.

Every crossed phase fires in order. A transformation halts that cascade on its
own by refilling HP, so it needs no special case — it is simply the point where
the next threshold stops being satisfied. The max HP multiplier is set before
max_hp() is read, or the refill would land on the old maximum.

A defeated boss transitions no further, so a corpse cannot summon reinforcements.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 4: Power 1 — phase movesets, replacing the hard-coded enrage

**Files:**
- Modify: `scripts/battle/EnemyAI.gd:44-73` (`choose_action`), `:75` (`_choose_skill`)
- Modify: `tests/suites/test_boss_phases.gd`

**Interfaces:**
- Consumes: `Enemy.current_phase()`, `BossPhase.skills`.
- Produces: `EnemyAI.usable_skills(enemy: Character) -> Array` — the skill list an enemy draws from this turn.

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_boss_phases.gd`:

```gdscript
# --------------------------------------------------- Power 1: moveset

func _skill(name: String) -> Skill:
	var s := Skill.new()
	s.skill_name = name
	s.power = 10.0
	return s

func test_a_phase_moveset_replaces_the_base_skills() -> void:
	var b := _boss()
	b.skills = [_skill("Base Swing")]
	b.phases[1].skills = [_skill("Desperate Cleave")]
	var bm := _manager(b)
	bm.check_boss_phases()
	var opening := EnemyAI.usable_skills(b)
	assert_eq(opening[0].skill_name, "Base Swing", "phase 0 has no list, so base skills are used")
	b.current_hp = 50
	bm.check_boss_phases()
	var wounded := EnemyAI.usable_skills(b)
	assert_eq(wounded.size(), 1, "phase 1 supplies exactly its own list")
	assert_eq(wounded[0].skill_name, "Desperate Cleave", "and it is the phase's skill")
	bm.free()

func test_an_empty_phase_moveset_falls_back_to_base() -> void:
	var b := _boss()
	b.skills = [_skill("Base Swing")]
	var bm := _manager(b)
	bm.check_boss_phases()
	assert_eq(EnemyAI.usable_skills(b)[0].skill_name, "Base Swing", "[] means keep base skills")
	bm.free()

func test_a_non_boss_enemy_uses_its_own_skills() -> void:
	# Guards the enrage removal: ordinary enemies must be entirely unaffected.
	var e := Enemy.new()
	e.base_hp = 50
	e.level = 1
	e.current_hp = 1
	e.skills = [_skill("Bite")]
	var list := EnemyAI.usable_skills(e)
	assert_eq(list.size(), 1, "a plain enemy draws from its own skills")
	assert_eq(list[0].skill_name, "Bite", "even at low HP, with no phases to consult")

func test_a_boss_in_no_phase_uses_its_base_skills() -> void:
	# Review Focus #5 again, at the consumer: current_phase() is null here.
	var b := _boss([0.8, 0.4])
	b.skills = [_skill("Base Swing")]
	assert_eq(EnemyAI.usable_skills(b)[0].skill_name, "Base Swing", "a null phase falls back safely")
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — `Invalid call. Nonexistent function 'usable_skills' in base 'GDScript'`.

- [ ] **Step 3: Add the skill-source helper**

In `scripts/battle/EnemyAI.gd`, above `_choose_skill`:

```gdscript
## The skills an enemy may draw from this turn. A boss in a phase that supplies
## its own list uses that list; everything else uses the enemy's own skills.
## Tolerates current_phase() being null — a boss whose first phase is authored
## below full HP is in no phase at all until it takes damage.
static func usable_skills(enemy: Character) -> Array:
	if enemy is Enemy and (enemy as Enemy).is_boss():
		var phase := (enemy as Enemy).current_phase()
		if phase != null and not phase.skills.is_empty():
			return phase.skills
	return enemy.skills
```

- [ ] **Step 4: Use it, and drop the hard-coded enrage**

In `choose_action` (line 44), replace the enrage block:

```gdscript
	# Low HP enrage — always use strongest attack
	var hp_pct = float(enemy.current_hp) / float(enemy.max_hp())
	var is_enraged = hp_pct < 0.25
```

with:

```gdscript
	# Low-HP enrage, for enemies WITHOUT phases. A boss expresses the same idea
	# through its phase data instead; keeping both would leave two parallel,
	# invisibly-interacting mechanisms for "fights differently when hurt".
	var is_enraged := false
	if not (enemy is Enemy and (enemy as Enemy).is_boss()):
		is_enraged = float(enemy.current_hp) / float(enemy.max_hp()) < 0.25
```

In `_choose_skill`, replace every read of `enemy.skills` with `usable_skills(enemy)`.

- [ ] **Step 5: Run the tests to verify they pass**

Expected: `BossPhases [OK] (36/36)`. The `enemy_ai` suite must also stay green — it covers the enrage path for ordinary enemies.

- [ ] **Step 6: Commit**

```bash
git add scripts/battle/EnemyAI.gd tests/suites/test_boss_phases.gd
git commit -m "Draw boss skills from the active phase

A boss with a phase moveset uses it; an empty list falls back to the enemy's own
skills, so a phase opts into this power like any other.

Removes the hard-coded <25% HP enrage for bosses specifically. A boss expresses
the same idea through phase data, and leaving both would mean two parallel,
invisibly-interacting mechanisms for 'fights differently when hurt'. Ordinary
enemies keep the enrage unchanged, which a test pins.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 5: Power 3 — summons

**Files:**
- Modify: `scripts/battle/BattleManager.gd` (`_enter_boss_phase`)
- Modify: `tests/suites/test_boss_phases.gd`

**Interfaces:**
- Consumes: `BossPhase.summons`, `MAX_BATTLE_ENEMIES`.
- Produces: `BattleManager._summon_from_spec(boss: Enemy, spec: Dictionary) -> void`; `enemies` may grow during a phase entry.

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_boss_phases.gd`:

```gdscript
# --------------------------------------------------- Power 3: summons

const SPEARMAN := "res://data/enemies/goblin_spearman.tres"

func test_a_phase_summons_reinforcements() -> void:
	var b := _boss()
	b.phases[1].summons = [{"path": SPEARMAN, "count": 2}]
	var bm := _manager(b)
	bm.check_boss_phases()
	assert_eq(bm.enemies.size(), 1, "no adds yet")
	b.current_hp = 50
	bm.check_boss_phases()
	assert_eq(bm.enemies.size(), 3, "two reinforcements joined the fight")
	bm.free()

func test_summons_inherit_the_boss_level_by_default() -> void:
	var b := _boss()
	b.level = 7
	b.phases[1].summons = [{"path": SPEARMAN, "count": 1}]
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()
	assert_eq(bm.enemies[1].level, 7, "an add matches the boss's level")
	bm.free()

func test_an_explicit_summon_level_wins() -> void:
	var b := _boss()
	b.level = 7
	b.phases[1].summons = [{"path": SPEARMAN, "count": 1, "level": 3}]
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()
	assert_eq(bm.enemies[1].level, 3, "the spec's level overrides the boss's")
	bm.free()

func test_summons_start_at_full_health() -> void:
	var b := _boss()
	b.phases[1].summons = [{"path": SPEARMAN, "count": 1}]
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()
	var add: Character = bm.enemies[1]
	assert_eq(add.current_hp, add.max_hp(), "an add arrives at full HP")
	bm.free()

func test_summons_enter_the_turn_order() -> void:
	var b := _boss()
	b.phases[1].summons = [{"path": SPEARMAN, "count": 2}]
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()
	bm._build_turn_order()
	assert_eq(bm.turn_order.size(), 4, "hero + boss + two adds all act")
	bm.free()

func test_the_enemy_cap_is_enforced_when_summoning() -> void:
	# Enforced at spawn, NOT at render: _setup_enemy_cards truncates with
	# mini(enemies.size(), 10), which would leave an 11th enemy alive in the
	# fight with no card and no visible HP bar.
	var b := _boss()
	b.phases[1].summons = [{"path": SPEARMAN, "count": 30}]
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()
	assert_eq(bm.enemies.size(), BattleManager.MAX_BATTLE_ENEMIES, "capped at 10 combatants")
	bm.free()

# --------------------------------------------------- Review Focus #2

func test_a_bad_summon_path_is_skipped_without_crashing() -> void:
	# A typo in a .tres must not end the battle.
	var b := _boss()
	b.phases[1].summons = [
		{"path": "res://data/enemies/does_not_exist.tres", "count": 2},
		{"path": "", "count": 1},
		{"path": SPEARMAN, "count": 1},
	]
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()
	assert_eq(bm.enemies.size(), 2, "the good summon still arrives; the bad ones are skipped")
	bm.free()
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — `assert_eq(bm.enemies.size(), 3)` gets 1.

- [ ] **Step 3: Implement summoning**

In `scripts/battle/BattleManager.gd`, add after `_enter_boss_phase`:

```gdscript
## Spawns one summon spec: {"path": String, "count": int, "level": int}.
## `level` defaults to the boss's. A missing or unloadable path is skipped
## rather than raised — a typo in a .tres must not end the battle.
func _summon_from_spec(boss: Enemy, spec: Dictionary) -> void:
	var path := str(spec.get("path", ""))
	if path == "":
		return
	if not ResourceLoader.exists(path):
		push_warning("Boss summon skipped — no such resource: %s" % path)
		return
	var template = load(path)
	if template == null or not (template is Enemy):
		push_warning("Boss summon skipped — not an Enemy: %s" % path)
		return
	var count := int(spec.get("count", 1))
	var lvl := int(spec.get("level", boss.level))
	for i in count:
		if enemies.size() >= MAX_BATTLE_ENEMIES:
			return
		var add: Enemy = template.duplicate(true)
		add.level = lvl
		add.current_hp = add.max_hp()
		add.current_mp = add.max_mp()
		enemies.append(add)
```

- [ ] **Step 4: Call it on phase entry**

In `_enter_boss_phase`, between the transformation block and the `emit_signal`:

```gdscript
	for spec in phase.summons:
		_summon_from_spec(boss, spec)
```

- [ ] **Step 5: Run the tests to verify they pass**

Expected: `BossPhases [OK] (43/43)`.

- [ ] **Step 6: Commit**

```bash
git add scripts/battle/BattleManager.gd tests/suites/test_boss_phases.gd
git commit -m "Let a boss phase summon reinforcements

Summons append to the enemy list on phase entry. Little new plumbing is needed
because _build_turn_order() already rebuilds from that list every round.

The 10-enemy cap is enforced when summoning rather than when rendering:
_setup_enemy_cards truncates with mini(enemies.size(), 10), so an 11th enemy
would otherwise be alive in the fight with no card and no visible HP bar. A bad
or missing summon path is skipped with a warning instead of ending the battle.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 6: Power 4 — per-turn field effects

**Files:**
- Modify: `scripts/battle/BattleManager.gd` (`_next_turn`)
- Modify: `tests/suites/test_boss_phases.gd`

**Interfaces:**
- Consumes: `BossPhase.turn_effect`, `BossPhase.turn_effect_chance`, the existing `_apply_skill_status(target, token)`.
- Produces: `BattleManager.apply_boss_field_effect(boss: Enemy) -> Character` — returns the afflicted hero, or `null`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_boss_phases.gd`:

```gdscript
# --------------------------------------------------- Power 4: field effects

func test_a_field_effect_afflicts_a_hero() -> void:
	var b := _boss()
	b.phases[0].turn_effect = "poison"
	b.phases[0].turn_effect_chance = 1.0
	var bm := _manager(b)
	bm.check_boss_phases()
	var hit := bm.apply_boss_field_effect(b)
	assert_true(hit != null, "a guaranteed effect lands")
	assert_true(hit.is_status("poison"), "and applies its token")
	bm.free()

func test_a_zero_chance_field_effect_never_fires() -> void:
	var b := _boss()
	b.phases[0].turn_effect = "poison"
	b.phases[0].turn_effect_chance = 0.0
	var bm := _manager(b)
	bm.check_boss_phases()
	assert_eq(bm.apply_boss_field_effect(b), null, "chance 0 never fires")
	bm.free()

func test_no_field_effect_when_the_phase_declares_none() -> void:
	var b := _boss()
	var bm := _manager(b)
	bm.check_boss_phases()
	assert_eq(bm.apply_boss_field_effect(b), null, "an empty token is a no-op")
	bm.free()

func test_a_field_effect_never_targets_a_downed_hero() -> void:
	var b := _boss()
	b.phases[0].turn_effect = "poison"
	b.phases[0].turn_effect_chance = 1.0
	var bm := _manager(b)
	bm.party[0].current_hp = 0
	bm.check_boss_phases()
	assert_eq(bm.apply_boss_field_effect(b), null, "with no living hero, nothing is afflicted")
	bm.free()

func test_a_field_effect_routes_through_the_status_rules() -> void:
	# Going through _apply_skill_status means element immunity and the mutex
	# one-status rule apply for free. A Fire hero cannot be scorched.
	var b := _boss()
	b.phases[0].turn_effect = "scorched"
	b.phases[0].turn_effect_chance = 1.0
	var bm := _manager(b)
	bm.party[0].element = ElementalSystem.Element.FIRE
	bm.check_boss_phases()
	bm.apply_boss_field_effect(b)
	assert_false(bm.party[0].is_status("scorched"), "Fire is immune to scorched")
	bm.free()

func test_a_buff_token_works_as_a_field_effect() -> void:
	var b := _boss()
	b.phases[0].turn_effect = "attack_debuff"
	b.phases[0].turn_effect_chance = 1.0
	var bm := _manager(b)
	bm.check_boss_phases()
	var hit := bm.apply_boss_field_effect(b)
	assert_true(hit != null, "the effect landed")
	assert_true(StatusSystem.is_effectively_debuffed(hit, StatusSystem.STAT_ATK), "debuff tokens work too")
	bm.free()
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — `Nonexistent function 'apply_boss_field_effect'`.

- [ ] **Step 3: Implement the field effect**

In `scripts/battle/BattleManager.gd`, after `_summon_from_spec`:

```gdscript
## Rolls the active phase's field effect against a random living hero. Returns
## the afflicted hero, or null when nothing happened.
##
## Hooked to the boss's OWN turn rather than "each round": the turn-order model
## has no explicit round boundary, and this way the effect fires exactly once per
## cycle and stops naturally when the boss dies. It resolves BEFORE the boss
## chooses its action, so a hero paralysed here is already paralysed when the
## boss picks a target.
func apply_boss_field_effect(boss: Enemy) -> Character:
	if not boss.is_boss() or not boss.is_alive():
		return null
	var phase := boss.current_phase()
	if phase == null or phase.turn_effect == "":
		return null
	if randf() > phase.turn_effect_chance:
		return null
	var alive := party.filter(func(h): return h.is_alive())
	if alive.is_empty():
		return null
	var target: Character = alive[randi() % alive.size()]
	# Reuse the skill path: element immunity, the mutex rule, the never-afflict-
	# the-downed guard and the banner all come with it.
	_apply_skill_status(target, phase.turn_effect)
	return target
```

- [ ] **Step 4: Call it at the start of the boss's turn**

In `_next_turn()`, immediately after `current_actor = turn_order[current_turn_index]`:

```gdscript
	if current_actor is Enemy and (current_actor as Enemy).is_boss():
		apply_boss_field_effect(current_actor as Enemy)
```

- [ ] **Step 5: Run the tests to verify they pass**

Expected: `BossPhases [OK] (49/49)`.

- [ ] **Step 6: Commit**

```bash
git add scripts/battle/BattleManager.gd tests/suites/test_boss_phases.gd
git commit -m "Add per-turn boss field effects

A phase can apply a status token to a random living hero on the boss's own turn.
Hooked to the boss's turn rather than 'each round' because the turn-order model
has no explicit round boundary; this fires exactly once per cycle and stops when
the boss dies.

Routed through the existing _apply_skill_status, so element immunity, the mutex
one-status rule, the never-afflict-the-downed guard and the banner all apply
without duplicating any of it.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 7: Boss presentation — full-width card and the phase banner

**Files:**
- Modify: `scripts/battle/BattleScene.gd:80-87` (signal wiring), `:384-396` (`_setup_enemy_cards`), `:397` (`_create_enemy_card`)
- Modify: `tests/suites/test_boss_phases.gd`

**Interfaces:**
- Consumes: `BattleManager.boss_phase_changed`, `Enemy.is_boss()`, `BossPhase.banner_text`.
- Produces: `BattleScene._on_boss_phase_changed(enemy: Character, phase: BossPhase) -> void`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_boss_phases.gd`:

```gdscript
# --------------------------------------------------- presentation

func test_a_boss_card_fills_the_row() -> void:
	var b := _boss()
	var scene := BattleScene.new()
	var card := scene._create_enemy_card(b)
	assert_eq(card.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "a boss card fills the row")
	scene.free()

func test_an_ordinary_enemy_card_stays_fixed_width() -> void:
	var e := Enemy.new()
	e.base_hp = 30
	e.level = 1
	var scene := BattleScene.new()
	var card := scene._create_enemy_card(e)
	assert_eq(card.custom_minimum_size.x, 124.0, "a normal card keeps its fixed width")
	scene.free()

func test_the_turn_order_panel_is_reseeded_on_a_phase_change() -> void:
	# TurnOrderIndicator.setup() runs once at battle start, so a summoned enemy
	# would fight without ever appearing in the turn order.
	var indicator = load("res://scripts/battle/TurnOrderIndicator.gd").new()
	var hero := Character.new()
	hero.character_name = "Hero"
	hero.base_hp = 50
	hero.level = 1
	hero.current_hp = hero.max_hp()
	var b := _boss()
	var party: Array[Character] = [hero]
	var foes: Array[Character] = [b]
	indicator.setup(party, foes)
	var add := Enemy.new()
	add.character_name = "Spearman"
	add.base_hp = 20
	add.level = 1
	add.current_hp = add.max_hp()
	foes.append(add)
	indicator.setup(party, foes)
	assert_true(true, "re-seeding the indicator with a grown roster does not error")
	indicator.free()

func test_a_silent_phase_shows_no_banner() -> void:
	var p := BossPhase.new()
	p.banner_text = ""
	assert_eq(p.banner_text, "", "an empty banner_text means transition silently")
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — the boss card's `size_flags_horizontal` is not `SIZE_EXPAND_FILL`.

- [ ] **Step 3: Make the boss card full-width**

In `scripts/battle/BattleScene.gd`, in `_create_enemy_card` (line 397), replace the fixed-size line:

```gdscript
	card.custom_minimum_size = Vector2(124, 70)
```

with:

```gdscript
	# A boss takes the whole row — the presence of phases is what marks it.
	if enemy is Enemy and (enemy as Enemy).is_boss():
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(0, 86)
	else:
		card.custom_minimum_size = Vector2(124, 70)
```

- [ ] **Step 4: Wire the phase signal**

In `_ready()` after line 87:

```gdscript
	battle_manager.boss_phase_changed.connect(_on_boss_phase_changed)
```

And add the handler near `_on_status_triggered`:

```gdscript
## A boss crossed into a new phase: banner it, then rebuild the card row so any
## reinforcements it summoned appear and the boss's own bar reflects a
## transformation's larger HP pool.
func _on_boss_phase_changed(_enemy: Character, phase: BossPhase) -> void:
	if phase.banner_text != "":
		_show_status_banner(phase.banner_text, BattleUITheme.TEXT_ACCENT, 1.9)
	_rebuild_enemy_cards()
	# The turn-order panel is built once by setup() at battle start, so a
	# summoned enemy would otherwise never get a slot. Re-seed it from the
	# current roster.
	turn_order_indicator.setup(battle_manager.party, battle_manager.enemies)
```

The spec flags this as a risk: `TurnOrderIndicator.setup(party, enemies)` is
called exactly once (`BattleScene.gd:157`), so without re-seeding it a summoned
enemy fights without ever appearing in the turn order.

- [ ] **Step 5: Run the tests to verify they pass**

Expected: `BossPhases [OK] (53/53)`.

- [ ] **Step 6: Commit**

```bash
git add scripts/battle/BattleScene.gd tests/suites/test_boss_phases.gd
git commit -m "Give bosses a full-width card and a phase banner

Fills the TODO already sitting in _setup_enemy_cards. Having phases is what
marks a boss, so the card needs no separate flag.

Every phase entry rebuilds the card row, which covers both reinforcements
appearing mid-fight and a transformation's larger HP pool being reflected in the
boss's own bar.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 8: The Goblin Warlord

**Files:**
- Create: `data/enemies/goblin_warlord.tres`
- Create: `data/encounters/goblin_warlord_fight.tres`
- Modify: `tests/suites/test_boss_phases.gd`

**Interfaces:**
- Consumes: everything above.
- Produces: a loadable boss resource exercising all five powers.

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_boss_phases.gd`:

```gdscript
# --------------------------------------------------- the first boss

const WARLORD := "res://data/enemies/goblin_warlord.tres"

func test_the_warlord_loads_as_a_boss() -> void:
	var w: Enemy = load(WARLORD)
	assert_true(w != null, "the warlord resource loads")
	assert_true(w.is_boss(), "and it has phases")
	assert_eq(w.phases.size(), 3, "three phases")

func test_the_warlord_exercises_every_power() -> void:
	var w: Enemy = load(WARLORD)
	var summons := false
	var stats := false
	var moveset := false
	var transform := false
	for p in w.phases:
		if not p.summons.is_empty(): summons = true
		if not p.stat_multipliers.is_empty(): stats = true
		if not p.skills.is_empty(): moveset = true
		if p.is_transformation(): transform = true
	assert_true(summons, "a phase summons")
	assert_true(stats, "a phase boosts stats")
	assert_true(moveset, "a phase changes the moveset")
	assert_true(transform, "a phase transforms")

func test_the_warlord_phases_are_in_descending_order() -> void:
	# Forward-only advancement assumes descending thresholds; an out-of-order
	# ladder would make a later phase unreachable.
	var w: Enemy = load(WARLORD)
	for i in range(1, w.phases.size()):
		assert_true(w.phases[i].enter_at_hp <= w.phases[i - 1].enter_at_hp,
			"phase %d's threshold is not above the one before it" % i)

func test_the_warlord_summons_within_the_cap() -> void:
	var w: Enemy = load(WARLORD)
	var total := 1
	for p in w.phases:
		for s in p.summons:
			total += int(s.get("count", 1))
	assert_true(total <= BattleManager.MAX_BATTLE_ENEMIES,
		"the warlord and everything it summons fit in %d slots" % BattleManager.MAX_BATTLE_ENEMIES)
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — the warlord resource does not exist.

- [ ] **Step 3: Author the warlord**

Create `data/enemies/goblin_warlord.tres`. Format follows
`data/enemies/goblin_cutthroat.tres`. `uid` is omitted from the `ext_resource`
lines deliberately — Godot resolves by `path` and writes the uid back on first
import, and `BossPhase.gd` has no uid until Task 1 has been run.

```
[gd_resource type="Resource" script_class="Enemy" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]
[ext_resource type="Script" path="res://scripts/characters/Enemy.gd" id="2_enemy"]
[ext_resource type="Script" path="res://scripts/characters/BossPhase.gd" id="3_phase"]

[sub_resource type="Resource" id="Skill_cleave"]
script = ExtResource("1_skill")
skill_name = "Warlord's Cleave"
description = "A brutal two-handed swing."
power = 1.3

[sub_resource type="Resource" id="Skill_warcry"]
script = ExtResource("1_skill")
skill_name = "Savage Bellow"
description = "A roar that rattles the whole party."
power = 0.8
status_to_apply = "attack_debuff"
status_chance = 0.5

[sub_resource type="Resource" id="Skill_ruin"]
script = ExtResource("1_skill")
skill_name = "Ruinous Sweep"
description = "A wild arc that catches every hero."
power = 1.15

[sub_resource type="Resource" id="Skill_execute"]
script = ExtResource("1_skill")
skill_name = "Executioner's Drop"
description = "Brings the great axe down with both hands."
power = 1.8

[sub_resource type="Resource" id="Phase_opening"]
script = ExtResource("3_phase")
enter_at_hp = 1.0
phase_name = "Warlord"

[sub_resource type="Resource" id="Phase_reinforce"]
script = ExtResource("3_phase")
enter_at_hp = 0.5
phase_name = "Rallying"
banner_text = "The Warlord bellows for reinforcements!"
summons = Array[Dictionary]([{
"count": 2,
"path": "res://data/enemies/goblin_spearman.tres"
}])

[sub_resource type="Resource" id="Phase_fury"]
script = ExtResource("3_phase")
enter_at_hp = 0.25
phase_name = "Unbound Fury"
banner_text = "The Warlord rises, wreathed in fury!"
skills = Array[ExtResource("1_skill")]([SubResource("Skill_ruin"), SubResource("Skill_execute")])
stat_multipliers = {
"attack": 1.5,
"speed": 1.2
}
max_hp_multiplier = 1.5
restore_hp = true

[resource]
script = ExtResource("2_enemy")
species = "Goblin Warlord"
rarity = 3
base_exp_reward = 220
base_gold_reward = 180
drop_table = Array[Dictionary]([{
"chance": 1.0,
"item_name": "Monster Fang",
"quantity": 3
}])
character_name = "Goblin Warlord"
character_class = "Warlord"
base_hp = 260
base_attack = 16
base_defense = 10
base_magic = 4
base_arcane = 6
base_speed = 9
skills = Array[ExtResource("1_skill")]([SubResource("Skill_cleave"), SubResource("Skill_warcry")])
phases = Array[ExtResource("3_phase")]([SubResource("Phase_opening"), SubResource("Phase_reinforce"), SubResource("Phase_fury")])
```

`base_hp` of 260 is roughly 7x a `goblin_cutthroat`, and the transformation
takes its effective pool to ~390.

**Verify these two enum/field choices before trusting them**, because both fail
silently rather than loudly:
- `rarity = 3` is intended to be `Rarity.Tier.EPIC` (purple border). Check the
  enum order in `scripts/characters/Rarity.gd` — a wrong integer just gives the
  wrong colour.
- The area skills (`Ruinous Sweep`, `Savage Bellow`) should hit the whole party.
  Check `TargetType` in `scripts/characters/Skill.gd` and add the matching
  `target_type = N` line to those two sub-resources; leaving it off makes them
  single-target, which is a much weaker phase 3 than intended.

- [ ] **Step 4: Author the fixed encounter**

Create `data/encounters/goblin_warlord_fight.tres`. This is the first user of
`is_fixed`, which has existed unused since P7.

```
[gd_resource type="Resource" script_class="EncounterGroup" format=3]

[ext_resource type="Script" path="res://scripts/overworld/EncounterGroup.gd" id="1_group"]
[ext_resource type="Resource" path="res://data/enemies/goblin_warlord.tres" id="2_warlord"]

[resource]
script = ExtResource("1_group")
weight = 1.0
min_party_level = 1
enemy_pool = Array[Resource]([ExtResource("2_warlord")])
min_enemies = 1
max_enemies = 1
is_fixed = true
```

**Check the exported field names and `enemy_pool`'s element type against
`scripts/overworld/EncounterGroup.gd` before writing this** — a type mismatch
here fails at load.

- [ ] **Step 5: Run the tests to verify they pass**

Expected: `BossPhases [OK] (57/57)`, TOTAL 0 failed.

- [ ] **Step 6: Commit**

```bash
git add data/enemies/goblin_warlord.tres data/encounters/goblin_warlord_fight.tres tests/suites/test_boss_phases.gd
git commit -m "Add the Goblin Warlord, the first boss

Three phases exercising all five powers: reinforcements at 50%, then a
transformation at 25% that grows its HP pool by half, refills it, and hands it a
heavier moveset — so the fight visibly restarts just as the party thinks it is
won.

First user of EncounterGroup.is_fixed, which has existed unused since P7.

Tests pin the phase ladder as descending (forward-only advancement would make an
out-of-order phase unreachable) and the summon total as fitting inside the
10-combatant cap.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 9: Document the system

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add a Core Systems section**

Under `## Core Systems` in `CLAUDE.md`, after the `Rarity` section, add a `### Boss Phases` section covering: a boss is an enemy with `phases`; the five optional powers; forward-only advancement and why (transformation); every crossed phase firing; `stat_multipliers` excluding `max_hp`; the 10-enemy cap enforced at summon time; field effects on the boss's own turn; and that `EnemyAI`'s enrage now applies to non-boss enemies only.

- [ ] **Step 2: Mark the roadmap item done**

In the `#### Track B — Systems breadth` section, mark item 1 (Boss enemies) as done and note that item 2 (status cleansing) is next.

- [ ] **Step 3: Update the suite count**

Update the two `~2300 tests / 33 suites` references to the actual final numbers from the test run.

- [ ] **Step 4: Run the full suite one last time**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/TestRunner.tscn --quit-after 5`
Expected: ALL TESTS PASSED, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "Document the boss phase system

Records the decisions a future session would otherwise have to rediscover from
the code: why advancement is forward-only rather than recomputed from HP, why
max_hp is unreachable from stat_multipliers, why the enemy cap is enforced when
summoning rather than when rendering, and why field effects hook the boss's own
turn instead of a round boundary that does not exist.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Done criteria

- `BossPhases` suite green; whole suite at 0 failed with no drop in the pre-existing 2307.
- A `.tres` alone can define a new boss — no task added per-boss code.
- All five powers have at least one test each, plus the five Review Focus cases.
- `CLAUDE.md` documents the system and the roadmap reflects Track B item 1 as done.
