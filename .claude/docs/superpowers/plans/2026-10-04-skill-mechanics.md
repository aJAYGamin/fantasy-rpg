# Skill Mechanics (Spec B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make five moves do what their descriptions promise, and add HP/resonance costs, multi-hit, pierce, ally heal, conditional power (incl. element override), scaling and trade-offs as move-file options, shown off by nine new hero moves and two enemy moves.

**Architecture:** Every mechanic is a plain `@export` option on `Skill` (default "off"), read by the single resolver `BattleManager.resolve_skill`. Pure maths lives on `Skill` (costs, scaling, condition) and in the damage functions (`Character._take_hit` with pierce + element override). Menus get costs and an auto-generated effect line from `Skill.cost_parts()` / `effect_tags()`. Saves carry the new fields; `PartyFactory.top_up_pool` gives old saves the new moves.

**Tech Stack:** Godot 4.6.1, GDScript, the project's own `TestSuite` harness.

**Spec:** `.claude/docs/superpowers/specs/2026-10-03-skill-mechanics-design.md`

## Global Constraints

- **Godot 4.6.1**, binary `/Applications/Godot.app/Contents/MacOS/Godot`. All paths below are relative to `new-game-project/` unless they start with `.claude/`.
- **Run tests** from `new-game-project/`: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/TestRunner.tscn --quit-after 5`. **Baseline: 3443 passed, 0 failed.** Never let it drop. A GDScript parse error silently drops a whole suite — if a suite's assertion count does not go UP after adding tests, look for a parse error in the output.
- **Branch `skill-mechanics`** — already created with the spec committed. Never commit to `main`; never create git worktrees.
- **Commit with `git commit -F <file>`** (write the message to a file first). Backticks inside a shell heredoc or `-m` are executed as commands and corrupt the message. End each message with the Co-Authored-By trailer your own instructions specify.
- **Tests run synchronously in one frame.** No `await`.
- **Never kill an ENEMY in a test** unless defeat is what the test is about: `BattleManager.handle_defeat` reports quest progress (`defeat:any`) to the live `GameManager`. Kill a hero instead when a defeat is needed.
- **Skills are read-only at runtime.** No code may write to a `Skill` during battle — enemies share the library's cached objects. Per-use state lives on the `Character` or in `BattleManager`.
- **Every new option defaults to "off"**, so the 81 existing moves not touched here behave exactly as before.
- **Never run** `tools/capture_move_baseline` or `tools/extract_move_library`. A deliberate change to a baselined move is recorded by hand: hero moves in `MERGE_DELTAS` (`tests/suites/test_move_library.gd`), enemy moves by editing `tests/fixtures/move_library_baseline.json`.
- **Enemies** pay HP costs and ignore MP and resonance costs.
- **Dodge rule:** a target on the user's OPPONENT side can miss (the move's `miss_chance`) or dodge; a target on the user's own side never rolls either.
- **Constants:** `LOW_HP_THRESHOLD = 0.3`, `SCALE_MIN = 0.75`, `SCALE_MAX = 1.5`. New pool slots 13–15 (indices 12–14): unlock levels `3, 9, 14`, categories `ATTACK, SPECIAL, SPECIAL`.
- **No new `class_name`.** One new test suite file (`test_skill_options.gd`) — register it in `tests/TestRunner.gd` `SUITE_PATHS`, then run the editor rescan once so Godot writes its `.uid`, and commit that `.uid`: `/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --quit-after 3 --path .`

## Review Focus

1. **A resonance cost exactly equal to the meter** — usable, and the meter ends at exactly 0 (Task 3 test `test_a_resonance_cost_equal_to_the_meter_is_spent_to_zero`).
2. **A move that misses every target** — no rider, no target buff, no recoil (Task 4 test `test_a_move_that_misses_everyone_has_no_after_effects`).
3. **Recoil when a hit finishes off its target** — counts only the HP the target actually had, not the overkill (Task 4 test `test_recoil_counts_only_hp_actually_lost`).
4. **An old save with a customised loadout** — top-up adds the new moves without moving the player's equipped choices (Task 7 test `test_top_up_keeps_the_players_loadout`).
5. **An enemy whose only moves are unaffordable HP-cost moves** — it falls back to its basic attack instead of stalling (Task 3 test `test_an_enemy_never_picks_an_hp_cost_it_cannot_pay`).

---

### Task 1: Move options on `Skill`

**Files:**
- Modify: `scripts/characters/Skill.gd`
- Create: `tests/suites/test_skill_options.gd`
- Modify: `tests/TestRunner.gd` (register the suite)

**Interfaces:**
- Produces (on `Skill`): enums `BonusCondition { NONE, TARGET_AFFLICTED, USER_HP_LOW }`, `ScaleWith { NONE, HP, MP, RESONANCE }`; constants `LOW_HP_THRESHOLD`, `SCALE_MIN`, `SCALE_MAX`; fields `hp_cost_percent: float`, `resonance_cost: float`, `hit_count: int`, `pierce: float`, `ally_heal_power: float`, `bonus_condition`, `bonus_multiplier: float`, `override_element: ElementalSystem.Element`, `override_super: bool`, `scale_with`, `scale_more_is_stronger: bool`, `self_debuff: String`, `recoil_percent: float`, `miss_chance: float`, `target_buff: String`; methods `hp_cost(user: Character) -> int`, `scale_factor(user: Character) -> float`, `condition_multiplier(user_hp_fraction: float, target: Character) -> float`, `static is_afflicted(c: Character) -> bool`, `override_multiplier() -> float`. `can_use` and `get_resonance_gain` gain the cost rules.

- [ ] **Step 1: Write the failing tests**

Create `tests/suites/test_skill_options.gd`:

```gdscript
extends TestSuite

## Spec B's move options on Skill: every one defaults to "off", and the pure
## maths behind costs, scaling and conditions. The resolver that uses them is
## tested in test_skill_resolver.gd.

func suite_name() -> String:
	return "SkillOptions"

func _hero(hp := 100, mp := 50) -> Character:
	var c := Character.new()
	c.character_name = "OptionsHero"
	c.base_hp = hp
	c.base_mp = mp
	c.level = 1
	c.current_hp = c.max_hp()
	c.current_mp = c.max_mp()
	return c

func _enemy(hp := 100) -> Enemy:
	var e := Enemy.new()
	e.character_name = "OptionsFoe"
	e.base_hp = hp
	e.level = 1
	e.current_hp = e.max_hp()
	return e

func test_every_option_defaults_to_off() -> void:
	var s := Skill.new()
	assert_eq(s.hp_cost_percent, 0.0, "no HP cost")
	assert_eq(s.resonance_cost, 0.0, "no resonance cost")
	assert_eq(s.hit_count, 1, "one hit")
	assert_eq(s.pierce, 0.0, "no pierce")
	assert_eq(s.ally_heal_power, 0.0, "no ally heal")
	assert_eq(int(s.bonus_condition), int(Skill.BonusCondition.NONE), "no condition")
	assert_eq(int(s.override_element), int(ElementalSystem.Element.NORMAL), "no element override")
	assert_eq(int(s.scale_with), int(Skill.ScaleWith.NONE), "no scaling")
	assert_eq(s.self_debuff, "", "no self-debuff")
	assert_eq(s.recoil_percent, 0.0, "no recoil")
	assert_eq(s.miss_chance, 0.0, "no miss chance")
	assert_eq(s.target_buff, "", "no target buff")

func test_hp_cost_is_a_rounded_up_share_of_max_hp() -> void:
	var s := Skill.new()
	s.hp_cost_percent = 12.5
	assert_eq(s.hp_cost(_hero(100)), 13, "12.5% of 100 rounds up to 13")
	s.hp_cost_percent = 0.0
	assert_eq(s.hp_cost(_hero(100)), 0, "no cost, no HP")

func test_an_hp_cost_can_never_knock_the_user_out() -> void:
	var s := Skill.new()
	s.hp_cost_percent = 12.0
	var h := _hero(100)
	h.current_hp = 12
	assert_false(s.can_use(h), "paying 12 would leave 0 HP: greyed out")
	h.current_hp = 13
	assert_true(s.can_use(h), "13 HP leaves 1 after paying: usable")

func test_enemies_pay_hp_but_ignore_mp_and_resonance() -> void:
	var s := Skill.new()
	s.mp_cost = 99
	s.resonance_cost = 99.0
	var e := _enemy(100)
	assert_true(s.can_use(e), "an enemy has no MP or resonance pool to pay from")
	s.hp_cost_percent = 50.0
	e.current_hp = 50
	assert_false(s.can_use(e), "but it does have HP, and may not KO itself")

func test_a_resonance_cost_needs_that_much_meter() -> void:
	var s := Skill.new()
	s.resonance_cost = 30.0
	var h := _hero()
	h.resonance_meter = 29.0
	assert_false(s.can_use(h), "29 is not enough for 30")
	h.resonance_meter = 30.0
	assert_true(s.can_use(h), "exactly 30 is enough")

func test_a_resonance_cost_move_builds_no_resonance() -> void:
	var s := Skill.new()
	assert_eq(s.get_resonance_gain(), 10.0, "an ordinary damage move builds 10")
	s.resonance_cost = 30.0
	assert_eq(s.get_resonance_gain(), 0.0, "spending resonance never refunds itself")
	s.resonance_gain_override = 25.0
	assert_eq(s.get_resonance_gain(), 0.0, "not even with an override")

func test_scaling_runs_from_min_to_max_on_the_users_own_pool() -> void:
	var s := Skill.new()
	var h := _hero(100, 50)
	assert_eq(s.scale_factor(h), 1.0, "no scaling is 1x")
	s.scale_with = Skill.ScaleWith.HP
	assert_true(is_equal_approx(s.scale_factor(h), Skill.SCALE_MAX), "full HP, more is stronger: max")
	h.current_hp = 50
	assert_true(is_equal_approx(s.scale_factor(h), lerpf(Skill.SCALE_MIN, Skill.SCALE_MAX, 0.5)), "half HP: halfway")
	s.scale_more_is_stronger = false
	h.current_hp = 100
	assert_true(is_equal_approx(s.scale_factor(h), Skill.SCALE_MIN), "full HP, less is stronger: min")
	s.scale_with = Skill.ScaleWith.RESONANCE
	s.scale_more_is_stronger = true
	h.resonance_meter = 100.0
	assert_true(is_equal_approx(s.scale_factor(h), Skill.SCALE_MAX), "a full meter: max")
	s.scale_with = Skill.ScaleWith.MP
	h.current_mp = 0
	assert_true(is_equal_approx(s.scale_factor(h), Skill.SCALE_MIN), "empty MP: min")

func test_scaling_on_a_pool_an_enemy_lacks_is_neutral() -> void:
	var s := Skill.new()
	var e := _enemy()
	s.scale_with = Skill.ScaleWith.MP
	assert_eq(s.scale_factor(e), 1.0, "enemies have no MP pool")
	s.scale_with = Skill.ScaleWith.RESONANCE
	assert_eq(s.scale_factor(e), 1.0, "or resonance meter")

func test_target_afflicted_condition() -> void:
	var s := Skill.new()
	s.bonus_condition = Skill.BonusCondition.TARGET_AFFLICTED
	s.bonus_multiplier = 1.5
	var t := _hero()
	assert_eq(s.condition_multiplier(1.0, t), 1.0, "a clean target gets no bonus")
	t.add_status(StatusSystem.POISON)
	assert_eq(s.condition_multiplier(1.0, t), 1.5, "a poisoned target does")
	var d := _hero()
	d.apply_debuff("defense")
	assert_eq(s.condition_multiplier(1.0, d), 1.5, "so does a debuffed one")

func test_user_hp_low_condition_is_strictly_below_thirty_percent() -> void:
	var s := Skill.new()
	s.bonus_condition = Skill.BonusCondition.USER_HP_LOW
	s.bonus_multiplier = 1.75
	assert_eq(s.condition_multiplier(0.29, _hero()), 1.75, "below 30%")
	assert_eq(s.condition_multiplier(0.30, _hero()), 1.0, "exactly 30% is not low")

func test_override_multiplier_is_effective_or_super_effective() -> void:
	var s := Skill.new()
	assert_eq(s.override_multiplier(), 1.0, "effective by default")
	s.override_super = true
	assert_eq(s.override_multiplier(), ElementalSystem.WEAKNESS_MULTIPLIER, "super-effective")
```

Register it in `tests/TestRunner.gd`: after the line `"res://tests/suites/test_meter_bars.gd",` add:

```gdscript
	"res://tests/suites/test_skill_options.gd",
```

- [ ] **Step 2: Run to verify they fail**

Expected: the new suite fails to parse (`Cannot find member "hp_cost_percent"` / `Static function "is_afflicted"` not found) — the SkillOptions line is missing or shows errors.

- [ ] **Step 3: Add the options**

In `scripts/characters/Skill.gd`, directly after the `source_path` declaration (`@export var source_path: String = ""`), add:

```gdscript

# --- Spec B: move options ----------------------------------------------------
# Every option below defaults to "off", so a move that does not set it behaves
# exactly as before. These DESCRIBE a move; the resolver keeps all per-use
# state on the Character / BattleManager — a Skill is read-only at runtime
# (enemies share the library's cached objects).

enum BonusCondition { NONE, TARGET_AFFLICTED, USER_HP_LOW }
enum ScaleWith { NONE, HP, MP, RESONANCE }

## USER_HP_LOW holds while the user's HP fraction is strictly below this.
const LOW_HP_THRESHOLD := 0.3
## Scaling runs between these multipliers.
const SCALE_MIN := 0.75
const SCALE_MAX := 1.5

@export_group("Costs")
## The user pays this % of their MAX HP, rounded up. It can never knock them
## out — the move is unusable instead. Enemies pay it too.
@export var hp_cost_percent: float = 0.0
## Heroes spend this much of the 0–100 resonance meter. Enemies ignore it.
@export var resonance_cost: float = 0.0

@export_group("Hits")
## Damage moves strike each target this many times.
@export var hit_count: int = 1
## Fraction (0–1) of the target's DEF (physical) or ARC (magic) ignored.
@export var pierce: float = 0.0

@export_group("Extra")
## After the hits, heals every living member of the user's side by MAG × this.
@export var ally_heal_power: float = 0.0

@export_group("Conditional")
@export var bonus_condition: BonusCondition = BonusCondition.NONE
## Damage multiplier while bonus_condition holds.
@export var bonus_multiplier: float = 1.5
## The one defender element this move treats differently. NORMAL = no override
## (the codebase's existing "not set" convention for elements).
@export var override_element: ElementalSystem.Element = ElementalSystem.Element.NORMAL
## false: effective (1x) against override_element. true: super-effective (2x).
@export var override_super: bool = false

@export_group("Scaling")
## The user's own pool this move's damage scales with.
@export var scale_with: ScaleWith = ScaleWith.NONE
## true: a fuller pool hits harder. false: an emptier pool hits harder.
@export var scale_more_is_stronger: bool = true

@export_group("Trade-offs")
## A stat ("attack"/"defense"/"magic"/"arcane"/"speed") lowered on the user
## after the move.
@export var self_debuff: String = ""
## The user takes this % of the damage the move dealt. Never knocks them out.
@export var recoil_percent: float = 0.0
## The move's own chance (0–1) to miss each opponent, separate from dodging.
@export var miss_chance: float = 0.0
## A stat raised on every target the move hit.
@export var target_buff: String = ""
@export_group("")
```

Replace the whole of `func can_use(user: Character) -> bool:` with:

```gdscript
## HP this move costs `user`, rounded up; 0 when it has no HP cost.
func hp_cost(user: Character) -> int:
	if hp_cost_percent <= 0.0:
		return 0
	return ceili(user.max_hp() * hp_cost_percent / 100.0)

func can_use(user: Character) -> bool:
	if user.is_status("stun"):
		return false
	# An HP cost may never knock the user out — on either side, since enemies
	# have HP too. The move greys out instead.
	if hp_cost_percent > 0.0 and user.current_hp <= hp_cost(user):
		return false
	# Enemies ignore MP and resonance costs entirely — they have neither pool —
	# and may use any skill they own. Only heroes pay MP and resonance.
	if user is Enemy:
		return true
	if resonance_cost > 0.0 and user.resonance_meter < resonance_cost:
		return false
	return user.current_mp >= mp_cost
```

Replace the whole of `func get_resonance_gain() -> float:` with:

```gdscript
func get_resonance_gain() -> float:
	# A move that SPENDS resonance builds none, or it would refund its own cost.
	if resonance_cost > 0.0:
		return 0.0
	if resonance_gain_override >= 0.0:
		return resonance_gain_override
	if skill_type == SkillType.DAMAGE:
		return 10.0
	return 0.0
```

Append to the end of the file:

```gdscript

# --- Spec B: maths for the resolver -------------------------------------------

## The damage multiplier from this move's scaling, read from the user's OWN
## pool: SCALE_MIN at one end, SCALE_MAX at the other. A pool the user lacks
## (an enemy's MP or resonance) gives 1x.
func scale_factor(user: Character) -> float:
	var fill := 0.0
	match scale_with:
		ScaleWith.NONE:
			return 1.0
		ScaleWith.HP:
			fill = float(user.current_hp) / float(maxi(1, user.max_hp()))
		ScaleWith.MP:
			if user is Enemy or user.max_mp() <= 0:
				return 1.0
			fill = float(user.current_mp) / float(user.max_mp())
		ScaleWith.RESONANCE:
			if user is Enemy:
				return 1.0
			fill = user.resonance_meter / 100.0
	fill = clampf(fill, 0.0, 1.0)
	if not scale_more_is_stronger:
		fill = 1.0 - fill
	return lerpf(SCALE_MIN, SCALE_MAX, fill)

## The damage multiplier from this move's condition against `target`.
## `user_hp_fraction` is measured before the move's costs are paid.
func condition_multiplier(user_hp_fraction: float, target: Character) -> float:
	match bonus_condition:
		BonusCondition.TARGET_AFFLICTED:
			return bonus_multiplier if is_afflicted(target) else 1.0
		BonusCondition.USER_HP_LOW:
			return bonus_multiplier if user_hp_fraction < LOW_HP_THRESHOLD else 1.0
	return 1.0

## True when `c` has an active status (poison, stun, …) or any stat debuff.
static func is_afflicted(c: Character) -> bool:
	if StatusSystem.get_active_mutex_status(c) != "":
		return true
	for stat in StatusSystem.BUFFABLE_STATS:
		if StatusSystem.is_effectively_debuffed(c, stat):
			return true
	return false

## The multiplier the element override uses for its one pairing.
func override_multiplier() -> float:
	return ElementalSystem.WEAKNESS_MULTIPLIER if override_super else 1.0
```

- [ ] **Step 4: Run the tests**

Expected: `SkillOptions [OK]`, `TOTAL: … 0 failed`. `Skill` and `SkillResolver` stay green.

- [ ] **Step 5: Rescan and commit**

Run the editor rescan (Global Constraints) so `tests/suites/test_skill_options.gd.uid` is written. Commit `scripts/characters/Skill.gd`, `tests/suites/test_skill_options.gd`, its `.uid`, and `tests/TestRunner.gd` with message `Add Spec B move options to Skill`.

---

### Task 2: Pierce and element override in the damage functions

**Files:**
- Modify: `scripts/characters/ElementalSystem.gd` (`get_combined_multiplier`)
- Modify: `scripts/characters/Character.gd` (`take_damage`, `take_magic_damage`)
- Test: `tests/suites/test_elemental.gd`, `tests/suites/test_character.gd`

**Interfaces:**
- Produces: `ElementalSystem.get_combined_multiplier(atk_primary, atk_secondary, def_primary, def_secondary, override_def: Element = NORMAL, override_mult: float = 1.0) -> float`; `Character.take_damage(amount, attack_element = NORMAL, attack_secondary_element = NORMAL, pierce: float = 0.0, override_element = NORMAL, override_mult: float = 1.0) -> Dictionary` and the same signature for `take_magic_damage`. Defaults reproduce today's behaviour exactly.

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_elemental.gd`:

```gdscript
# --------------------------------------------------- Spec B: element override

func test_an_override_replaces_exactly_one_pairing() -> void:
	var W := ElementalSystem.Element.WATER
	var N := ElementalSystem.Element.NORMAL
	assert_eq(ElementalSystem.get_combined_multiplier(W, N, W, N), 0.5, "water normally resists water")
	assert_eq(ElementalSystem.get_combined_multiplier(W, N, W, N, W, 2.0), 2.0, "the override makes it super-effective")
	assert_eq(ElementalSystem.get_combined_multiplier(W, N, W, N, W, 1.0), 1.0, "or merely effective")

func test_an_override_turns_an_immunity_into_a_hit() -> void:
	var W := ElementalSystem.Element.WATER
	var N := ElementalSystem.Element.NORMAL
	var NAT := ElementalSystem.Element.NATURE
	assert_eq(ElementalSystem.get_combined_multiplier(W, N, NAT, N), 0.0, "nature is immune to water")
	assert_eq(ElementalSystem.get_combined_multiplier(W, N, NAT, N, NAT, 1.0), 1.0, "an override can lift an immunity")

func test_a_dual_typed_defenders_other_element_still_counts() -> void:
	var W := ElementalSystem.Element.WATER
	var F := ElementalSystem.Element.FIRE
	var N := ElementalSystem.Element.NORMAL
	# Water vs Water (overridden to 2.0) x Water vs Fire (chart 2.0) = 4.0
	assert_eq(ElementalSystem.get_combined_multiplier(W, N, W, F, W, 2.0), 4.0, "only the named pairing changes")

func test_no_override_when_unset() -> void:
	var W := ElementalSystem.Element.WATER
	var N := ElementalSystem.Element.NORMAL
	assert_eq(ElementalSystem.get_combined_multiplier(W, N, W, N, N, 2.0), 0.5, "NORMAL means no override")
```

Append to `tests/suites/test_character.gd`:

```gdscript
# --------------------------------------------------- Spec B: pierce and override

func test_full_pierce_ignores_defence() -> void:
	var c = _make()
	c.base_defense = 6
	assert_eq(c.take_damage(30)["damage"], 24, "30 - DEF 6")
	c.current_hp = c.max_hp()
	assert_eq(c.take_damage(30, ElementalSystem.Element.NORMAL, ElementalSystem.Element.NORMAL, 1.0)["damage"], 30, "pierce 1.0 ignores all DEF")

func test_half_pierce_ignores_half_of_defence() -> void:
	var c = _make()
	c.base_defense = 6
	assert_eq(c.take_damage(30, ElementalSystem.Element.NORMAL, ElementalSystem.Element.NORMAL, 0.5)["damage"], 27, "30 - (6 x 0.5)")

func test_magic_pierce_ignores_arcane() -> void:
	var c = _make()
	c.base_arcane = 4
	assert_eq(c.take_magic_damage(30, ElementalSystem.Element.NORMAL, ElementalSystem.Element.NORMAL, 1.0)["damage"], 30, "pierce 1.0 ignores all ARC")

func test_the_override_reaches_the_damage_maths() -> void:
	var c = _make()
	c.base_defense = 0
	c.element = ElementalSystem.Element.WATER
	var plain = c.take_damage(20, ElementalSystem.Element.WATER)
	assert_eq(plain["multiplier"], 0.5, "water resists water")
	c.current_hp = c.max_hp()
	var over = c.take_damage(20, ElementalSystem.Element.WATER, ElementalSystem.Element.NORMAL, 0.0,
			ElementalSystem.Element.WATER, 2.0)
	assert_eq(over["multiplier"], 2.0, "the override is super-effective")
	assert_eq(over["damage"], 40, "and the damage follows")
```

- [ ] **Step 2: Run to verify they fail**

Expected: parse errors / FAIL — "Too many arguments" for `get_combined_multiplier` and `take_damage`.

- [ ] **Step 3: Implement**

In `scripts/characters/ElementalSystem.gd`, replace the whole of `static func get_combined_multiplier(...)` with:

```gdscript
static func get_combined_multiplier(
		atk_primary: Element, atk_secondary: Element,
		def_primary: Element, def_secondary: Element,
		override_def: Element = Element.NORMAL, override_mult: float = 1.0) -> float:
	var attackers: Array = [atk_primary]
	if atk_secondary != Element.NORMAL and atk_secondary != atk_primary:
		attackers.append(atk_secondary)
	var defenders: Array = [def_primary]
	if def_secondary != Element.NORMAL and def_secondary != def_primary:
		defenders.append(def_secondary)

	var result: float = 1.0
	for a in attackers:
		for d in defenders:
			# A move's element override replaces exactly ONE pairing — its own
			# primary element against the named defender element — instead of
			# stacking onto the chart value (Spec B, Part 3). NORMAL = unset.
			if override_def != Element.NORMAL and a == atk_primary and d == override_def:
				result *= override_mult
			else:
				result *= get_multiplier(a, d)
	return result
```

In `scripts/characters/Character.gd`, replace both `func take_damage(...)` and `func take_magic_damage(...)` (from `func take_damage(amount: int, ...` through the end of `take_magic_damage`'s `return { ... }`) with:

```gdscript
func take_damage(amount: int, attack_element: ElementalSystem.Element = ElementalSystem.Element.NORMAL,
		attack_secondary_element: ElementalSystem.Element = ElementalSystem.Element.NORMAL,
		pierce: float = 0.0,
		override_element: ElementalSystem.Element = ElementalSystem.Element.NORMAL,
		override_mult: float = 1.0) -> Dictionary:
	return _take_hit(amount, defense_power(), attack_element, attack_secondary_element,
			pierce, override_element, override_mult)

# Mirror physical damage: the defender's arcane (magic resistance) is what is
# subtracted before the element multiplier.
func take_magic_damage(amount: int, attack_element: ElementalSystem.Element = ElementalSystem.Element.NORMAL,
		attack_secondary_element: ElementalSystem.Element = ElementalSystem.Element.NORMAL,
		pierce: float = 0.0,
		override_element: ElementalSystem.Element = ElementalSystem.Element.NORMAL,
		override_mult: float = 1.0) -> Dictionary:
	return _take_hit(amount, arcane_power(), attack_element, attack_secondary_element,
			pierce, override_element, override_mult)

## Shared by both damage functions. `mitigation` is DEF or ARC; `pierce`
## (0–1) ignores that share of it; the element override replaces one pairing
## of the type chart (see ElementalSystem.get_combined_multiplier).
func _take_hit(amount: int, mitigation: int, attack_element: ElementalSystem.Element,
		attack_secondary_element: ElementalSystem.Element, pierce: float,
		override_element: ElementalSystem.Element, override_mult: float) -> Dictionary:
	var multiplier = ElementalSystem.get_combined_multiplier(
		attack_element, attack_secondary_element, element, secondary_element,
		override_element, override_mult)

	if extra_weakness != ElementalSystem.Element.NORMAL and attack_element == extra_weakness:
		multiplier *= 1.5
	if extra_resistance != ElementalSystem.Element.NORMAL and attack_element == extra_resistance:
		multiplier *= 0.6

	var mitigated := int(round(mitigation * (1.0 - clampf(pierce, 0.0, 1.0))))
	var base_damage = max(1, amount - mitigated)
	var final_damage = max(1, int(base_damage * multiplier))
	if is_defending:
		final_damage = max(1, int(final_damage * DEFEND_DAMAGE_MULT))
	current_hp = max(0, current_hp - final_damage)

	return {
		"damage": final_damage,
		"multiplier": multiplier,
		"effectiveness": ElementalSystem.get_effectiveness_text(multiplier),
		"effectiveness_color": ElementalSystem.get_effectiveness_color(multiplier)
	}
```

Keep the existing comment block that sits above `take_damage` ("Both functions accept an optional `attack_secondary_element`…").

- [ ] **Step 4: Run the tests**

Expected: `Elemental [OK]`, `Character [OK]`, TOTAL 0 failed. Every other suite (battle, boss, resolver) stays green — the defaults reproduce the old maths.

- [ ] **Step 5: Commit**

Message: `Add pierce and a one-pairing element override to the damage maths`.

---

### Task 3: Resolver — costs, hits, misses, conditions and scaling

**Files:**
- Modify: `scripts/battle/BattleManager.gd` (`resolve_skill`; add `_pay_costs`, `_resolve_hit`, `_unlanded`, `_after_target`, `_emit_extra`)
- Test: `tests/suites/test_skill_resolver.gd`

**Interfaces:**
- Consumes: Task 1 (`hp_cost`, `scale_factor`, `condition_multiplier`, `override_multiplier`, `miss_chance`, `hit_count`, `pierce`, `resonance_cost`), Task 2 (damage-function parameters).
- Produces: results now carry `"is_first_hit": bool` (true on the first LANDED hit on that target this action). New result actions `"miss"` and `"hp_cost"`. `_after_target(skill, target)` (rolled once per target that took a landed hit) and `_emit_extra(user, target, skill, action, value)` — Task 4 extends both.

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_skill_resolver.gd`:

```gdscript
# --------------------------------------------------- Spec B: costs and hits

func _actions(hits: Array) -> Array:
	return hits.map(func(r): return r["action"])

func test_an_hp_cost_is_paid_and_reported() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.hp_cost_percent = 10.0
	var hero := bm.party[0]
	var before := hero.current_hp
	var hits := _capture(bm)
	bm.resolve_skill(hero, s, [bm.enemies[0]])
	assert_eq(hero.current_hp, before - s.hp_cost(hero), "the hero paid 10% of max HP")
	var paid := hits.filter(func(r): return r["action"] == "hp_cost")
	assert_eq(paid.size(), 1, "one hp_cost result")
	assert_false(paid[0]["is_first_target"], "the cost never takes the first-target resonance flag")
	bm.free()

func test_an_unaffordable_hp_cost_does_nothing() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.hp_cost_percent = 10.0
	var hero := bm.party[0]
	hero.current_hp = s.hp_cost(hero)   # paying would leave 0
	var foe_hp := bm.enemies[0].current_hp
	var hits := _capture(bm)
	bm.resolve_skill(hero, s, [bm.enemies[0]])
	assert_eq(hero.current_hp, s.hp_cost(hero), "never knocked out by its own cost")
	assert_eq(bm.enemies[0].current_hp, foe_hp, "and the move does not happen")
	assert_true(hits.is_empty(), "no results at all")
	bm.free()

func test_enemies_pay_hp_costs() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.hp_cost_percent = 10.0
	var foe := bm.enemies[0]
	var before := foe.current_hp
	bm.resolve_skill(foe, s, [bm.party[0]])
	assert_eq(foe.current_hp, before - s.hp_cost(foe), "enemies have HP, so they pay")
	bm.free()

func test_a_resonance_cost_equal_to_the_meter_is_spent_to_zero() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.resonance_cost = 30.0
	var hero := bm.party[0]
	hero.resonance_meter = 30.0
	var hits := _capture(bm)
	bm.resolve_skill(hero, s, [bm.enemies[0]])
	assert_eq(hero.resonance_meter, 0.0, "exactly enough is enough, and it is all spent")
	assert_true(_actions(hits).has("skill_physical"), "and the move happened")
	bm.free()

func test_two_hits_land_two_results_and_resonance_once() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.hit_count = 2
	var foe := bm.enemies[0]
	var before := foe.current_hp
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], s, [foe])
	var dmg := hits.filter(func(r): return r["action"] == "skill_physical")
	assert_eq(dmg.size(), 2, "two hits, two results")
	assert_eq(hits.filter(func(r): return r.get("is_first_target", false)).size(), 1, "skill resonance once per action")
	assert_eq(before - foe.current_hp, int(dmg[0]["value"]) + int(dmg[1]["value"]), "both hits dealt their damage")
	bm.free()

func test_took_damage_resonance_is_once_per_target() -> void:
	var bm := _manager(2, 1)
	var s := _skill(Skill.TargetType.ALL_ENEMIES)
	s.hit_count = 3
	var hits := _capture(bm)
	bm.resolve_skill(bm.enemies[0], s, [])
	for hero in bm.party:
		var firsts := hits.filter(func(r): return r["target"] == hero and r.get("is_first_hit", false))
		assert_eq(firsts.size(), 1, "%s: exactly one first hit of three" % hero.character_name)
	bm.free()

func test_a_target_killed_by_the_first_hit_takes_no_second() -> void:
	# The victim is a HERO: defeating an enemy would report quest progress.
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.hit_count = 2
	var hero := bm.party[0]
	hero.current_hp = 1
	var defeated := []
	bm.character_defeated.connect(func(c): defeated.append(c))
	var hits := _capture(bm)
	bm.resolve_skill(bm.enemies[0], s, [hero])
	assert_eq(hits.filter(func(r): return r["target"] == hero).size(), 1, "one hit, then it stops")
	assert_eq(defeated.size(), 1, "defeat handled once")
	bm.free()

func test_a_miss_is_its_own_result_and_deals_nothing() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.miss_chance = 1.0
	var foe := bm.enemies[0]
	var before := foe.current_hp
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], s, [foe])
	assert_eq(_actions(hits), ["miss"], "a miss, not a dodge")
	assert_eq(foe.current_hp, before, "and no damage")
	bm.free()

func test_a_miss_chance_never_applies_to_allies() -> void:
	var bm := _manager(3, 1)
	var s := _skill(Skill.TargetType.ALL_ALLIES, Skill.SkillType.STATUS)
	s.status_type = Skill.StatusType.BUFF
	s.status_to_apply = "defense_buff"
	s.miss_chance = 1.0
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], s, [])
	assert_false(_actions(hits).has("miss"), "moves on your own side always land")
	for h in bm.party:
		assert_true(StatusSystem.is_effectively_buffed(h, "defense"), "%s buffed" % h.character_name)
	bm.free()

func test_pierce_reaches_the_target() -> void:
	var bm := _manager(1, 1)
	var foe := bm.enemies[0]
	foe.base_defense = 10
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], s, [foe])
	s.pierce = 1.0
	bm.resolve_skill(bm.party[0], s, [foe])
	assert_eq(int(hits[0]["value"]), 10, "20 ATK - 10 DEF")
	assert_eq(int(hits[1]["value"]), 20, "pierce 1.0 ignores the DEF")
	bm.free()

func test_the_element_override_reaches_the_target() -> void:
	var bm := _manager(1, 1)
	var foe := bm.enemies[0]
	foe.element = ElementalSystem.Element.WATER
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.element = ElementalSystem.Element.WATER
	s.override_element = ElementalSystem.Element.WATER
	s.override_super = true
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], s, [foe])
	assert_eq(hits[0]["multiplier"], 2.0, "water made super-effective against water")
	assert_eq(int(hits[0]["value"]), 40, "20 x 2")
	bm.free()

func test_a_target_afflicted_bonus() -> void:
	var bm := _manager(1, 2)
	var s := _skill(Skill.TargetType.ALL_ENEMIES)
	s.bonus_condition = Skill.BonusCondition.TARGET_AFFLICTED
	s.bonus_multiplier = 1.5
	bm.enemies[1].add_status(StatusSystem.POISON)
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], s, [])
	assert_eq(int(hits[0]["value"]), 20, "a clean enemy takes the plain 20")
	assert_eq(int(hits[1]["value"]), 30, "a poisoned one takes 20 x 1.5")
	bm.free()

func test_a_low_hp_user_bonus() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.bonus_condition = Skill.BonusCondition.USER_HP_LOW
	s.bonus_multiplier = 1.75
	var hero := bm.party[0]
	hero.current_hp = int(hero.max_hp() * 0.2)
	var hits := _capture(bm)
	bm.resolve_skill(hero, s, [bm.enemies[0]])
	assert_eq(int(hits[0]["value"]), 35, "20 x 1.75 below 30% HP")
	bm.free()

func test_scaling_is_measured_before_costs_are_paid() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.hp_cost_percent = 50.0
	s.scale_with = Skill.ScaleWith.HP
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], s, [bm.enemies[0]])
	var dmg := hits.filter(func(r): return r["action"] == "skill_physical")
	assert_eq(int(dmg[0]["value"]), 30, "full HP when the move began: 20 x 1.5, not weakened by its own cost")
	bm.free()

func test_a_status_rider_is_on_the_target_before_its_results_reach_the_ui() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.hit_count = 3
	s.status_to_apply = "attack_debuff"
	s.status_chance = 1.0
	var foe := bm.enemies[0]
	var seen := []
	bm.action_performed.connect(func(_r): seen.append(StatusSystem.is_effectively_debuffed(foe, "attack")))
	bm.resolve_skill(bm.party[0], s, [foe])
	assert_eq(seen, [true, true, true], "rolled after the hits, applied before they are shown")
	bm.free()

func test_a_status_rider_rolls_once_per_target_not_per_hit() -> void:
	# Per hit, three 25% rolls would land ~58% of the time; once per target, 25%.
	seed(20261004)
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.hit_count = 3
	s.status_to_apply = "attack_debuff"
	s.status_chance = 0.25
	var foe := bm.enemies[0]
	var landed := 0
	for i in 400:
		foe.debuffs.clear()
		foe.current_hp = foe.max_hp()
		bm.resolve_skill(bm.party[0], s, [foe])
		if StatusSystem.is_effectively_debuffed(foe, "attack"):
			landed += 1
	assert_true(landed < 160, "about 100 of 400, far below the ~232 a per-hit roll gives (got %d)" % landed)
	assert_true(landed > 50, "and the rider still lands (got %d)" % landed)
	bm.free()

func test_an_enemy_never_picks_an_hp_cost_it_cannot_pay() -> void:
	var bm := _manager(1, 1)
	var foe := bm.enemies[0]
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.hp_cost_percent = 50.0
	foe.skills = [s] as Array[Skill]
	foe.current_hp = s.hp_cost(foe)
	var decision := EnemyAI.choose_action(foe, bm.party, bm.enemies)
	assert_eq(decision.get("skill"), null, "it falls back to its basic attack")
	bm.free()
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — HP/resonance not paid, one hit instead of two, no `"miss"`, no `is_first_hit`, damage ignores pierce/override/conditions/scaling.

- [ ] **Step 3: Rewrite `resolve_skill`**

In `scripts/battle/BattleManager.gd`, replace the whole of `func resolve_skill(...)` (from its signature through the line `handle_defeat(target)` that ends it) with:

```gdscript
func resolve_skill(user: Character, skill: Skill, chosen: Array[Character]) -> void:
	if not skill.can_use(user):
		return
	var targets := expand_targets(user, skill, chosen)
	# Measured BEFORE costs are paid, so an HP-cost move is not weakened by its
	# own cost (Spec B, Part 2, step 2).
	var scale := skill.scale_factor(user)
	var user_hp_fraction := float(user.current_hp) / float(maxi(1, user.max_hp()))
	_pay_costs(user, skill)

	var first := true
	for target in targets:
		if not target.is_alive():
			continue
		# Results are collected and emitted together once this target is done,
		# so effects rolled once per target (the status rider) are already on
		# it when the UI refreshes for these results. Emission is synchronous
		# either way, so nothing is shown any later.
		var results: Array[Dictionary] = []
		var landed := 0
		var hits := maxi(1, skill.hit_count) if skill.skill_type == Skill.SkillType.DAMAGE else 1
		for _h in hits:
			if not target.is_alive():
				break   # a target killed mid-sequence takes no further hits
			var result := {"actor": user, "target": target, "skill": skill,
					"is_first_target": first, "is_first_hit": false}
			first = false
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
			# "Took damage" resonance is granted once per target per action — on
			# the first hit that actually lands.
			result["is_first_hit"] = landed == 0
			landed += 1
			_resolve_hit(user, skill, target, result, scale, user_hp_fraction)
			result["target_alive"] = target.is_alive()
			results.append(result)
		if landed > 0:
			_after_target(skill, target)
		for r in results:
			emit_signal("action_performed", r)
		if not target.is_alive():
			handle_defeat(target)

## Pays MP, then resonance (heroes only — enemies have neither pool), then HP
## (both sides). Skill.can_use has already guaranteed every cost is affordable
## and that the HP cost leaves at least 1 HP.
func _pay_costs(user: Character, skill: Skill) -> void:
	if not (user is Enemy):
		user.use_mp(skill.mp_cost)
		if skill.resonance_cost > 0.0:
			user.resonance_meter = maxf(0.0, user.resonance_meter - skill.resonance_cost)
	var cost := skill.hp_cost(user)
	if cost > 0:
		user.current_hp = maxi(1, user.current_hp - cost)
		_emit_extra(user, user, skill, "hp_cost", cost)

## One landed hit of `skill` on `target`, written into `result`.
func _resolve_hit(user: Character, skill: Skill, target: Character, result: Dictionary,
		scale: float, user_hp_fraction: float) -> void:
	if skill.skill_type == Skill.SkillType.DAMAGE:
		var value := int(skill.calculate_value(user) * skill.condition_multiplier(user_hp_fraction, target) * scale)
		match skill.attack_type:
			Skill.AttackType.STRIKE, Skill.AttackType.RANGED:
				_record_damage(result, target.take_damage(value, skill.element, skill.secondary_element,
						skill.pierce, skill.override_element, skill.override_multiplier()))
				# "skill_physical", never "attack": for a HERO, "attack" routes to
				# on_attack instead of on_skill_used and grants different resonance.
				result["action"] = "skill_physical"
			Skill.AttackType.MAGIC:
				_record_damage(result, target.take_magic_damage(value, skill.element, skill.secondary_element,
						skill.pierce, skill.override_element, skill.override_multiplier()))
				result["action"] = "skill_magic"
	elif skill.skill_type == Skill.SkillType.STATUS:
		var value := skill.calculate_value(user)
		match skill.status_type:
			Skill.StatusType.HEAL:
				result["action"] = "heal"
				result["value"] = target.heal(value)
			Skill.StatusType.BUFF:
				# The token may be a stat buff ("attack_buff"), a stat debuff
				# ("magic_debuff") or a legacy named status ("regenerate").
				var token: String = skill.status_to_apply if skill.status_to_apply != "" else StatusSystem.REGENERATE
				_apply_skill_status(target, token)
				result["action"] = "buff"
				result["value"] = 0
			Skill.StatusType.DEBUFF:
				if skill.status_to_apply != "":
					_apply_skill_status(target, skill.status_to_apply)
				result["action"] = "debuff"
				result["value"] = 0

func _unlanded(result: Dictionary, action: String, target: Character) -> Dictionary:
	result["action"] = action
	result["value"] = 0
	result["target_alive"] = target.is_alive()
	return result

## Effects rolled ONCE per target that took at least one landed hit.
func _after_target(skill: Skill, target: Character) -> void:
	# A damage skill's status rider rolls once per target, not once per hit.
	if skill.skill_type == Skill.SkillType.DAMAGE and skill.status_to_apply != "" \
			and randf() < skill.status_chance:
		_apply_skill_status(target, skill.status_to_apply)

## A result that is not a hit: the HP cost, an ally heal, recoil, a self-debuff.
## Never carries the first-target or first-hit flags, so it cannot take the
## action's resonance.
func _emit_extra(user: Character, target: Character, skill: Skill, action: String, value: int) -> void:
	emit_signal("action_performed", {"actor": user, "target": target, "skill": skill,
			"action": action, "value": value, "is_first_target": false,
			"is_first_hit": false, "target_alive": target.is_alive()})
```

Do not change `_record_damage`, `expand_targets`, the wrappers, or `_execute_enemy_turn`. The structural test that reads `resolve_skill`'s source for `try_dodge` must keep passing.

- [ ] **Step 4: Run the tests**

Expected: `SkillResolver [OK]`, TOTAL 0 failed. `BossPhases`, `EnemyAI`, `StatusSystem` and `Resonance` stay green.

- [ ] **Step 5: Commit**

Message: `Resolve costs, multi-hit, misses, conditions and scaling`.

---

### Task 4: Resolver — after-effects

**Files:**
- Modify: `scripts/battle/BattleManager.gd` (`resolve_skill`, `_resolve_hit`, `_after_target`; add `_after_action`, `_apply_stat`)
- Test: `tests/suites/test_skill_resolver.gd`

**Interfaces:**
- Consumes: Task 3's `resolve_skill`, `_after_target`, `_emit_extra`.
- Produces: new result actions `"recoil"` and `"self_debuff"`; ally heals emit `"heal"`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_skill_resolver.gd`:

```gdscript
# --------------------------------------------------- Spec B: after-effects

func test_a_heal_applies_its_attached_effect() -> void:
	# Restoring Breeze: heal, then regenerate.
	var bm := _manager(2, 1)
	var s := _skill(Skill.TargetType.SINGLE_ALLY, Skill.SkillType.STATUS)
	s.status_type = Skill.StatusType.HEAL
	s.status_to_apply = StatusSystem.REGENERATE
	var ally := bm.party[1]
	ally.current_hp = 100
	bm.resolve_skill(bm.party[0], s, [ally])
	assert_true(ally.current_hp > 100, "healed")
	assert_eq(ally.regen_turns, BattleManager.REGEN_TURNS, "and regenerating")
	bm.free()

func test_a_target_buff_lands_only_on_targets_hit() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.target_buff = "attack"
	var foe := bm.enemies[0]
	bm.resolve_skill(bm.party[0], s, [foe])
	assert_true(StatusSystem.is_effectively_buffed(foe, "attack"), "the struck enemy is enraged")
	bm.free()

func test_a_move_that_misses_everyone_has_no_after_effects() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.miss_chance = 1.0
	s.target_buff = "attack"
	s.status_to_apply = "defense_debuff"
	s.status_chance = 1.0
	s.recoil_percent = 50.0
	var hero := bm.party[0]
	var foe := bm.enemies[0]
	var hp := hero.current_hp
	var hits := _capture(bm)
	bm.resolve_skill(hero, s, [foe])
	assert_false(StatusSystem.is_effectively_buffed(foe, "attack"), "no buff")
	assert_false(StatusSystem.is_effectively_debuffed(foe, "defense"), "no rider")
	assert_eq(hero.current_hp, hp, "no recoil")
	assert_false(_actions(hits).has("recoil"), "no recoil result")
	bm.free()

func test_the_ally_heal_heals_the_users_whole_side() -> void:
	var bm := _manager(3, 2)
	for h in bm.party:
		h.current_hp -= 100
	var s := _skill(Skill.TargetType.ALL_ENEMIES)
	s.ally_heal_power = 1.0
	var foe_hp := bm.enemies.map(func(e): return e.current_hp)
	bm.resolve_skill(bm.party[0], s, [])
	for h in bm.party:
		assert_eq(h.current_hp, h.max_hp() - 100 + 20, "%s healed by MAG 20 x 1.0" % h.character_name)
	for i in bm.enemies.size():
		assert_true(bm.enemies[i].current_hp < foe_hp[i], "enemies are damaged, never healed")
	bm.free()

func test_an_enemys_ally_heal_heals_enemies() -> void:
	var bm := _manager(1, 2)
	for e in bm.enemies:
		e.current_hp -= 100
	var hero_hp := bm.party[0].max_hp() - 50
	bm.party[0].current_hp = hero_hp
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.ally_heal_power = 1.0
	bm.resolve_skill(bm.enemies[0], s, [bm.party[0]])
	for e in bm.enemies:
		assert_eq(e.current_hp, e.max_hp() - 80, "%s healed by 20" % e.character_name)
	assert_true(bm.party[0].current_hp < hero_hp, "the hero was hit, not healed")
	bm.free()

func test_recoil_is_a_share_of_the_damage_dealt() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.recoil_percent = 25.0
	var hero := bm.party[0]
	var hp := hero.current_hp
	var hits := _capture(bm)
	bm.resolve_skill(hero, s, [bm.enemies[0]])
	assert_eq(hero.current_hp, hp - 5, "25% of the 20 dealt")
	var r := hits.filter(func(x): return x["action"] == "recoil")
	assert_eq(r.size(), 1, "one recoil result")
	assert_eq(int(r[0]["value"]), 5, "worth 5")
	bm.free()

func test_recoil_never_knocks_the_user_out() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.recoil_percent = 25.0
	var hero := bm.party[0]
	hero.current_hp = 3
	bm.resolve_skill(hero, s, [bm.enemies[0]])
	assert_eq(hero.current_hp, 1, "recoil of 5 stops at 1 HP")
	bm.free()

func test_recoil_counts_only_hp_actually_lost() -> void:
	# The enemy hits a HERO with 8 HP for 20: only 8 was dealt. (A hero is the
	# victim so no quest progress is reported.)
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.recoil_percent = 25.0
	var foe := bm.enemies[0]
	var hp := foe.current_hp
	bm.party[0].current_hp = 8
	bm.resolve_skill(foe, s, [bm.party[0]])
	assert_eq(foe.current_hp, hp - 2, "25% of 8, not of 20")
	bm.free()

func test_a_self_debuff_lands_on_the_user_after_the_hits() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.self_debuff = "defense"
	var hero := bm.party[0]
	var hits := _capture(bm)
	bm.resolve_skill(hero, s, [bm.enemies[0]])
	assert_true(StatusSystem.is_effectively_debuffed(hero, "defense"), "the user's DEF is lowered")
	assert_eq(_actions(hits), ["skill_physical", "self_debuff"], "after the hit")
	bm.free()

func test_after_effects_run_heal_then_recoil_then_self_debuff() -> void:
	var bm := _manager(2, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.ally_heal_power = 1.0
	s.recoil_percent = 25.0
	s.self_debuff = "speed"
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], s, [bm.enemies[0]])
	assert_eq(_actions(hits), ["skill_physical", "heal", "heal", "recoil", "self_debuff"], "the spec's order")
	bm.free()

func test_an_unknown_stat_name_changes_nothing() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.self_debuff = "burn"
	s.target_buff = "burn"
	var hero := bm.party[0]
	var hits := _capture(bm)
	bm.resolve_skill(hero, s, [bm.enemies[0]])
	assert_false(_actions(hits).has("self_debuff"), "no self-debuff result")
	assert_true(hero.debuffs.is_empty(), "no debuff invented")
	assert_true(bm.enemies[0].buffs.is_empty(), "no buff invented")
	bm.free()
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — no regen on heal, no target buff, no ally heal, no recoil, no self-debuff.

- [ ] **Step 3: Implement**

In `resolve_skill`, add a running total of damage dealt. Change these lines:

```gdscript
	var first := true
	for target in targets:
```

to:

```gdscript
	var first := true
	var dealt := 0   # HP actually removed by this action's hits, for recoil
	for target in targets:
```

and change:

```gdscript
			_resolve_hit(user, skill, target, result, scale, user_hp_fraction)
			result["target_alive"] = target.is_alive()
```

to:

```gdscript
			var hp_before := target.current_hp
			_resolve_hit(user, skill, target, result, scale, user_hp_fraction)
			if skill.skill_type == Skill.SkillType.DAMAGE:
				dealt += maxi(0, hp_before - target.current_hp)
			result["target_alive"] = target.is_alive()
```

and after the `for target in targets:` loop ends (after its final `handle_defeat(target)` line, at the function's top indentation level) add:

```gdscript
	_after_action(user, skill, dealt)
```

In `_resolve_hit`, change the HEAL case:

```gdscript
			Skill.StatusType.HEAL:
				result["action"] = "heal"
				result["value"] = target.heal(value)
```

to:

```gdscript
			Skill.StatusType.HEAL:
				result["action"] = "heal"
				result["value"] = target.heal(value)
				# A heal's attached effect applies too (Restoring Breeze's regen).
				if skill.status_to_apply != "":
					_apply_skill_status(target, skill.status_to_apply)
```

Replace the whole of `_after_target` with:

```gdscript
## Effects rolled ONCE per target that took at least one landed hit.
func _after_target(skill: Skill, target: Character) -> void:
	# A damage skill's status rider rolls once per target, not once per hit.
	if skill.skill_type == Skill.SkillType.DAMAGE and skill.status_to_apply != "" \
			and randf() < skill.status_chance:
		_apply_skill_status(target, skill.status_to_apply)
	if skill.target_buff != "" and target.is_alive():
		_apply_stat(target, skill.target_buff, true)
```

Add after `_emit_extra`:

```gdscript
## Effects that happen once, after every target, in this order: the ally heal,
## recoil, the self-debuff (Spec B, Part 2, step 7).
func _after_action(user: Character, skill: Skill, dealt: int) -> void:
	if skill.ally_heal_power > 0.0:
		var amount := int(user.magic_power() * skill.ally_heal_power)
		for ally in _allies_of(user):
			if ally.is_alive():
				_emit_extra(user, ally, skill, "heal", ally.heal(amount))
	if skill.recoil_percent > 0.0 and dealt > 0:
		# Recoil never knocks the user out.
		var recoil := mini(int(dealt * skill.recoil_percent / 100.0), user.current_hp - 1)
		if recoil > 0:
			user.current_hp -= recoil
			_emit_extra(user, user, skill, "recoil", recoil)
	if skill.self_debuff != "" and _apply_stat(user, skill.self_debuff, false):
		_emit_extra(user, user, skill, "self_debuff", 0)

## Raises (buff) or lowers a stat by name. An unknown name is a data error in a
## move file: it warns and changes nothing, rather than inventing a status the
## way the phantom "burn" once did.
func _apply_stat(c: Character, stat: String, buff: bool) -> bool:
	var r: Dictionary = c.apply_buff(stat) if buff else c.apply_debuff(stat)
	if r.get("action", "") == "invalid":
		push_warning("Skill stat '%s' is not one of %s — ignored" % [stat, StatusSystem.BUFFABLE_STATS])
		return false
	return true
```

- [ ] **Step 4: Run the tests**

Expected: `SkillResolver [OK]`, TOTAL 0 failed. (The `burn` test prints a warning — expected.)

- [ ] **Step 5: Commit**

Message: `Add the ally heal, recoil, self-debuff, target buff and heal effects`.

---

### Task 5: Battle feedback

**Files:**
- Modify: `scripts/battle/DamageNumber.gd` (add `setup_miss`)
- Modify: `scripts/battle/BattleScene.gd` (`_on_action_performed`; add `_spawn_miss_text`, `grants_damage_resonance`)
- Test: `tests/suites/test_skill_resolver.gd`

**Interfaces:**
- Consumes: Task 3/4 result actions (`miss`, `hp_cost`, `recoil`, `self_debuff`) and the `is_first_hit` flag.
- Produces: `static BattleScene.grants_damage_resonance(result: Dictionary) -> bool`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_skill_resolver.gd`:

```gdscript
# --------------------------------------------------- Spec B: battle feedback

func test_took_damage_resonance_follows_the_first_hit_flag() -> void:
	assert_true(BattleScene.grants_damage_resonance({"action": "skill_physical", "is_first_hit": true}), "first landed hit")
	assert_false(BattleScene.grants_damage_resonance({"action": "skill_physical", "is_first_hit": false}), "a later hit")
	assert_true(BattleScene.grants_damage_resonance({"action": "attack"}), "a basic attack carries no flag and counts")
	assert_false(BattleScene.grants_damage_resonance({"action": "recoil", "is_first_hit": false}), "recoil is self-inflicted")
	assert_false(BattleScene.grants_damage_resonance({"action": "hp_cost", "is_first_hit": false}), "so is an HP cost")
	assert_false(BattleScene.grants_damage_resonance({"action": "miss", "is_first_hit": false}), "a miss deals nothing")
```

- [ ] **Step 2: Run to verify it fails**

Expected: parse error — `grants_damage_resonance` not found in `BattleScene`.

- [ ] **Step 3: Implement**

In `scripts/battle/DamageNumber.gd`, after `func setup_dodge():` (and its body), add:

```gdscript
## The move's OWN miss chance came up — distinct from the target dodging.
func setup_miss():
	var cinzel = load("res://fonts/Cinzel-Regular.ttf")
	if cinzel:
		add_theme_font_override("font", cinzel)
	add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	add_theme_constant_override("shadow_offset_x", 2)
	add_theme_constant_override("shadow_offset_y", 2)
	add_theme_constant_override("shadow_outline_size", 4)
	text = "Miss!"
	add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	add_theme_font_size_override("font_size", 14)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_animate()
```

In `scripts/battle/BattleScene.gd`, in `_on_action_performed`, change:

```gdscript
			"dodge":
				_spawn_dodge_text(spawn_pos)
```

to:

```gdscript
			"dodge":
				_spawn_dodge_text(spawn_pos)
			"miss":
				_spawn_miss_text(spawn_pos)
			"hp_cost", "recoil":
				# Self-inflicted: a plain number over the user.
				_spawn_damage_number(int(result.get("value", 0)), spawn_pos)
```

and change:

```gdscript
	# Taking damage builds resonance for heroes on receiving end (once per hit)
	if result.has("target") and battle_manager.party.has(result["target"]):
		if result.get("action") in ["attack", "skill_magic", "skill_physical"]:
			resonance_system.on_damage_taken(result["target"])
```

to:

```gdscript
	# Taking damage builds resonance for heroes on the receiving end — once per
	# target per action, so a multi-hit move does not multiply it.
	if result.has("target") and battle_manager.party.has(result["target"]) \
			and grants_damage_resonance(result):
		resonance_system.on_damage_taken(result["target"])
```

After `func _spawn_dodge_text(...)` add:

```gdscript
func _spawn_miss_text(pos: Vector2):
	var label = Label.new()
	add_child(label)
	label.set_script(load("res://scripts/battle/DamageNumber.gd"))
	label.position = pos + Vector2(randf_range(-20, 20), 0)
	label.call("setup_miss")

## True for a result that builds "took damage" resonance: a damaging action, on
## the first hit that LANDED on that target this action. Results from paths that
## predate multi-hit (basic attacks) carry no flag and count. HP costs and recoil
## are self-inflicted and never count.
static func grants_damage_resonance(result: Dictionary) -> bool:
	return result.get("action") in ["attack", "skill_magic", "skill_physical"] \
		and result.get("is_first_hit", true)
```

- [ ] **Step 4: Run the tests**

Expected: `SkillResolver [OK]`, TOTAL 0 failed.

- [ ] **Step 5: Commit**

Message: `Show misses, HP costs and recoil; damage resonance once per target`.

---

### Task 6: Costs and effect tags in the menus

**Files:**
- Modify: `scripts/characters/Skill.gd` (add `cost_parts`, `cost_text`, `effect_tags`, `effect_text`, `_num`, `_effect_phrase`)
- Modify: `scripts/ui/BattleUITheme.gd` (add `COST_COLORS`, `cost_color`)
- Modify: `scripts/battle/AttackMenu.gd` (cost column, description panel)
- Modify: `scripts/ui/StatsScreen.gd` (`_skill_view_model`, the move card)
- Modify: `scripts/ui/LoadoutScreen.gd` (`_pool_row`, `_detail_panel`)
- Test: `tests/suites/test_skill_options.gd`, `tests/suites/test_stats_screen.gd`

**Interfaces:**
- Produces: `Skill.cost_parts() -> Array[Dictionary]` (each `{"kind": "mp"|"hp"|"resonance", "text": String}`), `Skill.cost_text() -> String`, `Skill.effect_tags() -> Array[String]`, `Skill.effect_text() -> String`, `BattleUITheme.cost_color(kind: String) -> Color`. The Stats view model gains `"costs"` and `"tags"` (keeps `"mp_cost"`).

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_skill_options.gd`:

```gdscript
# --------------------------------------------------- costs and tags in menus

func test_cost_parts_list_every_cost() -> void:
	var s := Skill.new()
	assert_true(s.cost_parts().is_empty(), "a free move has no costs")
	assert_eq(s.cost_text(), "", "and no cost text")
	s.mp_cost = 12
	s.hp_cost_percent = 15.0
	s.resonance_cost = 30.0
	var parts := s.cost_parts()
	assert_eq(parts.map(func(p): return p["kind"]), ["mp", "hp", "resonance"], "in MP, HP, resonance order")
	assert_eq(s.cost_text(), "12 MP · 15% HP · 30 ✦", "joined for single-label menus")

func test_effect_tags_describe_the_options() -> void:
	var s := Skill.new()
	s.attack_type = Skill.AttackType.MAGIC
	assert_true(s.effect_tags().is_empty(), "a plain move has no tags")
	s.hit_count = 2
	s.pierce = 1.0
	assert_eq(s.effect_tags(), ["2 hits", "Ignores ARC"] as Array[String], "hits and pierce")
	s.hit_count = 1
	s.pierce = 0.5
	s.attack_type = Skill.AttackType.STRIKE
	assert_eq(s.effect_tags(), ["Ignores 50% DEF"] as Array[String], "partial physical pierce")

func test_effect_tags_cover_riders_and_heal_effects() -> void:
	var s := Skill.new()
	s.status_to_apply = "speed_debuff"
	s.status_chance = 0.4
	assert_eq(s.effect_tags(), ["40% chance: Lowers SPD"] as Array[String], "a damage rider")
	var h := Skill.new()
	h.skill_type = Skill.SkillType.STATUS
	h.status_type = Skill.StatusType.HEAL
	h.status_to_apply = StatusSystem.REGENERATE
	assert_eq(h.effect_tags(), ["Regenerates"] as Array[String], "a heal's attached effect")

func test_effect_tags_cover_conditions_override_and_scaling() -> void:
	var s := Skill.new()
	s.bonus_condition = Skill.BonusCondition.TARGET_AFFLICTED
	assert_eq(s.effect_tags(), ["×1.5 vs afflicted"] as Array[String], "afflicted bonus")
	s.bonus_condition = Skill.BonusCondition.USER_HP_LOW
	s.bonus_multiplier = 1.75
	assert_eq(s.effect_tags(), ["×1.75 below 30% HP"] as Array[String], "low-HP bonus")
	s.bonus_condition = Skill.BonusCondition.NONE
	s.override_element = ElementalSystem.Element.WATER
	s.override_super = true
	assert_eq(s.effect_tags(), ["Super-effective vs Water"] as Array[String], "element override")
	s.override_element = ElementalSystem.Element.NORMAL
	s.scale_with = Skill.ScaleWith.MP
	assert_eq(s.effect_tags(), ["Stronger with more MP"] as Array[String], "scaling")
	s.scale_more_is_stronger = false
	s.scale_with = Skill.ScaleWith.HP
	assert_eq(s.effect_tags(), ["Stronger with less HP"] as Array[String], "inverse scaling")

func test_effect_tags_cover_trade_offs_and_ally_heal() -> void:
	var s := Skill.new()
	s.ally_heal_power = 1.0
	s.recoil_percent = 25.0
	s.miss_chance = 0.3
	s.self_debuff = "defense"
	s.target_buff = "attack"
	assert_eq(s.effect_tags(), ["Heals allies", "25% recoil", "30% miss chance",
			"Lowers your DEF", "Raises target's ATK"] as Array[String], "every trade-off")
	assert_eq(s.effect_text(), "Heals allies · 25% recoil · 30% miss chance · Lowers your DEF · Raises target's ATK", "joined")

func test_each_cost_kind_has_its_own_colour() -> void:
	var mp := BattleUITheme.cost_color("mp")
	var hp := BattleUITheme.cost_color("hp")
	var res := BattleUITheme.cost_color("resonance")
	assert_ne(mp, hp, "MP and HP differ")
	assert_ne(hp, res, "HP and resonance differ")
	assert_ne(mp, res, "MP and resonance differ")
```

Append to `tests/suites/test_stats_screen.gd`:

```gdscript
func test_skill_view_model_carries_costs_and_tags() -> void:
	var vm := StatsScreen.build_hero_view_model(_aria())
	var frost: Dictionary = vm["attacks"][1]  # Frost Bolt
	assert_eq(frost["costs"], [{"kind": "mp", "text": "12 MP"}], "its costs, ready for the card")
	assert_true(frost.has("tags"), "and its generated effect line")
```

- [ ] **Step 2: Run to verify they fail**

Expected: parse errors — `cost_parts`, `effect_tags`, `cost_color` not found; the view model lacks `costs`.

- [ ] **Step 3: Implement**

Append to `scripts/characters/Skill.gd`:

```gdscript

# --- Spec B: what menus show ------------------------------------------------------

## The move's costs as labelled pieces for the menus, in MP, HP, resonance
## order — e.g. [{"kind": "mp", "text": "12 MP"}]. A free move returns [].
func cost_parts() -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	if mp_cost > 0:
		parts.append({"kind": "mp", "text": "%d MP" % mp_cost})
	if hp_cost_percent > 0.0:
		parts.append({"kind": "hp", "text": "%s%% HP" % _num(hp_cost_percent)})
	if resonance_cost > 0.0:
		parts.append({"kind": "resonance", "text": "%s ✦" % _num(resonance_cost)})
	return parts

## The costs joined for menus that show one label ("12 MP · 15% HP").
func cost_text() -> String:
	var texts: Array[String] = []
	for p in cost_parts():
		texts.append(p["text"])
	return " · ".join(texts)

## A short line generated from the move's options — e.g. "2 hits · Ignores
## ARC". Generated from data, so it can never promise what the move does not
## do (hand-written descriptions drifting from the data is how the five
## "honest skill" gaps happened).
func effect_tags() -> Array[String]:
	var tags: Array[String] = []
	var def_name := "ARC" if attack_type == AttackType.MAGIC else "DEF"
	if skill_type == SkillType.DAMAGE and hit_count > 1:
		tags.append("%d hits" % hit_count)
	if pierce >= 1.0:
		tags.append("Ignores %s" % def_name)
	elif pierce > 0.0:
		tags.append("Ignores %d%% %s" % [int(round(pierce * 100.0)), def_name])
	if skill_type == SkillType.DAMAGE and status_to_apply != "" and status_chance > 0.0:
		tags.append("%d%% chance: %s" % [int(round(status_chance * 100.0)), _effect_phrase(status_to_apply)])
	if skill_type == SkillType.STATUS and status_type == StatusType.HEAL and status_to_apply != "":
		tags.append(_effect_phrase(status_to_apply))
	if ally_heal_power > 0.0:
		tags.append("Heals allies")
	match bonus_condition:
		BonusCondition.TARGET_AFFLICTED:
			tags.append("×%s vs afflicted" % _num(bonus_multiplier))
		BonusCondition.USER_HP_LOW:
			tags.append("×%s below %d%% HP" % [_num(bonus_multiplier), int(round(LOW_HP_THRESHOLD * 100.0))])
	if override_element != ElementalSystem.Element.NORMAL:
		tags.append("%s vs %s" % ["Super-effective" if override_super else "Effective",
				ElementalSystem.get_element_name(override_element)])
	if scale_with != ScaleWith.NONE:
		var pool: String = {ScaleWith.HP: "HP", ScaleWith.MP: "MP", ScaleWith.RESONANCE: "resonance"}[scale_with]
		tags.append("Stronger with %s %s" % ["more" if scale_more_is_stronger else "less", pool])
	if recoil_percent > 0.0:
		tags.append("%s%% recoil" % _num(recoil_percent))
	if miss_chance > 0.0:
		tags.append("%d%% miss chance" % int(round(miss_chance * 100.0)))
	if self_debuff != "":
		tags.append("Lowers your %s" % StatusSystem.STAT_SHORT.get(self_debuff, self_debuff.to_upper()))
	if target_buff != "":
		tags.append("Raises target's %s" % StatusSystem.STAT_SHORT.get(target_buff, target_buff.to_upper()))
	return tags

## The tags joined for display.
func effect_text() -> String:
	return " · ".join(effect_tags())

## 12.0 -> "12", 12.5 -> "12.5", 1.75 -> "1.75" (up to two decimals, no
## trailing zeros).
static func _num(v: float) -> String:
	return String.num(v, 2)

## "Lowers SPD", "Raises ATK", "Regenerates", or a status name ("Scorched").
static func _effect_phrase(token: String) -> String:
	if token == StatusSystem.REGENERATE:
		return "Regenerates"
	for stat in StatusSystem.BUFFABLE_STATS:
		if token == stat + "_debuff":
			return "Lowers %s" % StatusSystem.STAT_SHORT[stat]
		if token == stat + "_buff":
			return "Raises %s" % StatusSystem.STAT_SHORT[stat]
	return StatusSystem.STATUS_LABELS.get(token, token.capitalize())
```

Append to `scripts/ui/BattleUITheme.gd`:

```gdscript

# --- Move costs ----------------------------------------------------------------
# One colour per kind of cost, shared by every menu that lists moves.
const COST_COLORS := {
	"mp": Color(0.50, 0.70, 1.00),
	"hp": Color(1.00, 0.45, 0.45),
	"resonance": Color(0.72, 0.55, 1.00),
}

static func cost_color(kind: String) -> Color:
	return COST_COLORS.get(kind, TEXT_PRIMARY)
```

In `scripts/battle/AttackMenu.gd`, replace the whole "Column 3: MP cost" block:

```gdscript
	# Column 3: MP cost
	var mp_lbl = Label.new()
	mp_lbl.text = "%d MP" % skill.mp_cost if skill.mp_cost > 0 else ""
	mp_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if cinzel: mp_lbl.add_theme_font_override("font", cinzel)
	mp_lbl.add_theme_font_size_override("font_size", 9)
	mp_lbl.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
	info_grid.add_child(mp_lbl)
```

with:

```gdscript
	# Column 3: cost — MP, HP and/or resonance, each in its own colour.
	var cost_box := HBoxContainer.new()
	cost_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_box.alignment = BoxContainer.ALIGNMENT_END
	cost_box.add_theme_constant_override("separation", 4)
	cost_box.mouse_filter = Control.MOUSE_FILTER_IGNORE   # clicks reach the move
	for part in skill.cost_parts():
		var cost_lbl := Label.new()
		cost_lbl.text = part["text"]
		if cinzel: cost_lbl.add_theme_font_override("font", cinzel)
		cost_lbl.add_theme_font_size_override("font_size", 9)
		cost_lbl.add_theme_color_override("font_color", BattleUITheme.cost_color(part["kind"]))
		cost_box.add_child(cost_lbl)
	info_grid.add_child(cost_box)
```

In `_show_description_above`, change:

```gdscript
	var new_text = "%s — %s" % [skill.skill_name, skill.description if skill.description != "" else "No description."]
```

to:

```gdscript
	var new_text = "%s — %s" % [skill.skill_name, skill.description if skill.description != "" else "No description."]
	if skill.effect_text() != "":
		new_text += "\n" + skill.effect_text()
```

In `scripts/ui/StatsScreen.gd` `_skill_view_model`, after the line `"mp_cost": s.mp_cost,` add:

```gdscript
		"costs": s.cost_parts(),
		"tags": s.effect_text(),
```

In the move card, replace:

```gdscript
	if int(s["mp_cost"]) > 0:
		top.add_child(_label("MP %d" % int(s["mp_cost"]), BattleUITheme.font_bold(), 12, Color(0.50, 0.70, 1.0), HORIZONTAL_ALIGNMENT_RIGHT))
```

with:

```gdscript
	for part in s["costs"]:
		top.add_child(_label(part["text"], BattleUITheme.font_bold(), 12,
				BattleUITheme.cost_color(part["kind"]), HORIZONTAL_ALIGNMENT_RIGHT))
```

and directly after the block that ends `v.add_child(desc)` (the `if str(s["description"]) != "":` block), add:

```gdscript
	if str(s["tags"]) != "":
		var tags := _label(s["tags"], BattleUITheme.font_regular(), 10, BattleUITheme.TEXT_SUBTITLE)
		tags.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tags.custom_minimum_size = Vector2(0, 0)
		v.add_child(tags)
```

In `scripts/ui/LoadoutScreen.gd` `_pool_row`, replace:

```gdscript
	if s.mp_cost > 0:
		label += "   MP %d" % s.mp_cost
```

with:

```gdscript
	if s.cost_text() != "":
		label += "   " + s.cost_text()
```

In `_detail_panel`, replace:

```gdscript
	var cost_text := "Cost:  %d MP" % s.mp_cost if s.mp_cost > 0 else "Cost:  Free"
	v.add_child(_label(cost_text, BattleUITheme.font_bold(), 11, Color(0.50, 0.70, 1.0)))
```

with:

```gdscript
	var cost_row := HBoxContainer.new()
	cost_row.add_theme_constant_override("separation", 6)
	cost_row.add_child(_label("Cost:", BattleUITheme.font_bold(), 11, BattleUITheme.TEXT_SUBTITLE))
	var parts := s.cost_parts()
	if parts.is_empty():
		cost_row.add_child(_label("Free", BattleUITheme.font_bold(), 11, BattleUITheme.cost_color("mp")))
	for part in parts:
		cost_row.add_child(_label(part["text"], BattleUITheme.font_bold(), 11, BattleUITheme.cost_color(part["kind"])))
	v.add_child(cost_row)
	if s.effect_text() != "":
		var tags := _label(s.effect_text(), BattleUITheme.font_regular(), 11, BattleUITheme.TEXT_SUBTITLE)
		tags.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(tags)
```

- [ ] **Step 4: Run the tests**

Expected: `SkillOptions [OK]`, `StatsScreen [OK]`, TOTAL 0 failed.

- [ ] **Step 5: Commit**

Message: `Show every move cost and a generated effect line in the menus`.

---

### Task 7: Saves and pool top-up

**Files:**
- Modify: `scripts/save/SaveSerializer.gd` (`serialize_skill`, `deserialize_skill`)
- Modify: `scripts/PartyFactory.gd` (add `POOLS`, `_pool`, `_stamp_slot`, `top_up_pool`, `top_up_party`; `_create_*` and `_apply_skill_tables` use them)
- Modify: `scripts/GameManager.gd` (`load_from_slot`)
- Test: `tests/suites/test_save_serializer.gd`, `tests/suites/test_party_factory.gd`

**Interfaces:**
- Produces: `PartyFactory.POOLS: Dictionary` (hero name → ordered Array of library file names), `PartyFactory.top_up_pool(hero: Character) -> int` (moves added), `PartyFactory.top_up_party(party: Array) -> void`. Task 9 extends `POOLS`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_save_serializer.gd`:

```gdscript
# --------------------------------------------------- Spec B options in saves

func test_every_spec_b_option_round_trips() -> void:
	var s := Skill.new()
	s.skill_name = "Everything"
	s.hp_cost_percent = 12.0
	s.resonance_cost = 30.0
	s.hit_count = 3
	s.pierce = 0.5
	s.ally_heal_power = 1.25
	s.bonus_condition = Skill.BonusCondition.USER_HP_LOW
	s.bonus_multiplier = 1.75
	s.override_element = ElementalSystem.Element.WATER
	s.override_super = true
	s.scale_with = Skill.ScaleWith.RESONANCE
	s.scale_more_is_stronger = false
	s.self_debuff = "defense"
	s.recoil_percent = 25.0
	s.miss_chance = 0.3
	s.target_buff = "attack"
	var b := SaveSerializer.deserialize_skill(JSON.parse_string(JSON.stringify(SaveSerializer.serialize_skill(s))))
	assert_eq(b.hp_cost_percent, 12.0, "hp cost")
	assert_eq(b.resonance_cost, 30.0, "resonance cost")
	assert_eq(b.hit_count, 3, "hits")
	assert_eq(b.pierce, 0.5, "pierce")
	assert_eq(b.ally_heal_power, 1.25, "ally heal")
	assert_eq(int(b.bonus_condition), int(Skill.BonusCondition.USER_HP_LOW), "condition")
	assert_eq(b.bonus_multiplier, 1.75, "bonus")
	assert_eq(int(b.override_element), int(ElementalSystem.Element.WATER), "override element")
	assert_true(b.override_super, "override strength")
	assert_eq(int(b.scale_with), int(Skill.ScaleWith.RESONANCE), "scaling pool")
	assert_false(b.scale_more_is_stronger, "scaling direction")
	assert_eq(b.self_debuff, "defense", "self-debuff")
	assert_eq(b.recoil_percent, 25.0, "recoil")
	assert_eq(b.miss_chance, 0.3, "miss chance")
	assert_eq(b.target_buff, "attack", "target buff")

func test_a_save_without_spec_b_fields_loads_with_everything_off() -> void:
	var b := SaveSerializer.deserialize_skill({"skill_name": "Old"})
	assert_eq(b.hit_count, 1, "one hit")
	assert_eq(b.hp_cost_percent, 0.0, "no HP cost")
	assert_eq(int(b.scale_with), int(Skill.ScaleWith.NONE), "no scaling")
	assert_true(b.scale_more_is_stronger, "default direction")
	assert_eq(b.bonus_multiplier, 1.5, "default bonus")
```

Append to `tests/suites/test_party_factory.gd`:

```gdscript
# --------------------------------------------------- Spec B: pool top-up

## A hero as an older save would load it: missing the last `n` moves of its
## factory pool.
func _older_save(hero: Character, n: int) -> Character:
	hero.skills.resize(hero.skills.size() - n)
	hero.prune_equipped()
	return SaveSerializer.deserialize_character(SaveSerializer.serialize_character(hero))

func test_top_up_restores_moves_a_save_is_missing() -> void:
	for hero in PartyFactory.create_default_party():
		var full := hero.skills.size()
		var back := _older_save(hero, 3)
		assert_eq(PartyFactory.top_up_pool(back), 3, "%s gains its three missing moves" % back.character_name)
		assert_eq(back.skills.size(), full, "back to the whole pool")
		for slot in range(full - 3, full):
			var want := 1 if PartyFactory.TEST_UNLOCK_ALL_SKILLS else PartyFactory.SKILL_UNLOCK_LEVELS[slot]
			assert_eq(back.skills[slot].unlock_level, want, "%s slot %d unlock level" % [back.character_name, slot])
			assert_eq(int(back.skills[slot].category), PartyFactory.SKILL_CATEGORIES[slot], "%s slot %d category" % [back.character_name, slot])
			assert_eq(back.skills[slot].source_path, PartyFactory.MOVES + PartyFactory.POOLS[back.character_name][slot], "the right file")

func test_top_up_is_a_no_op_on_a_full_pool() -> void:
	for hero in PartyFactory.create_default_party():
		assert_eq(PartyFactory.top_up_pool(hero), 0, "%s already has everything" % hero.character_name)

func test_top_up_matches_a_legacy_move_by_name() -> void:
	var hero: Character = PartyFactory.create_default_party()[0]
	hero.skills[0].source_path = ""   # a move saved before moves had files
	assert_eq(PartyFactory.top_up_pool(hero), 0, "matched by name, not added twice")

func test_top_up_leaves_unknown_heroes_alone() -> void:
	var stranger := Character.new()
	stranger.character_name = "Stranger"
	assert_eq(PartyFactory.top_up_pool(stranger), 0, "no pool to top up from")

func test_top_up_keeps_the_players_loadout() -> void:
	var hero: Character = PartyFactory.create_default_party()[0]
	var back := _older_save(hero, 3)
	var before_atk := back.equipped_attacks.duplicate()
	var before_spc := back.equipped_specials.duplicate()
	PartyFactory.top_up_party([back])
	for slot in before_atk.size():
		if before_atk[slot] != -1:
			assert_eq(back.equipped_attacks[slot], before_atk[slot], "attack slot %d keeps the player's choice" % slot)
	for slot in before_spc.size():
		if before_spc[slot] != -1:
			assert_eq(back.equipped_specials[slot], before_spc[slot], "special slot %d keeps the player's choice" % slot)
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL / parse errors — the new fields are not saved; `PartyFactory.POOLS` and `top_up_pool` do not exist.

- [ ] **Step 3: Implement saves**

In `scripts/save/SaveSerializer.gd` `serialize_skill`, after `"source_path": s.source_path,` add:

```gdscript
		"hp_cost_percent": s.hp_cost_percent,
		"resonance_cost": s.resonance_cost,
		"hit_count": s.hit_count,
		"pierce": s.pierce,
		"ally_heal_power": s.ally_heal_power,
		"bonus_condition": int(s.bonus_condition),
		"bonus_multiplier": s.bonus_multiplier,
		"override_element": int(s.override_element),
		"override_super": s.override_super,
		"scale_with": int(s.scale_with),
		"scale_more_is_stronger": s.scale_more_is_stronger,
		"self_debuff": s.self_debuff,
		"recoil_percent": s.recoil_percent,
		"miss_chance": s.miss_chance,
		"target_buff": s.target_buff,
```

In `deserialize_skill`, before `return s`, add:

```gdscript
	# Spec B options. Every default means "off", so a save written before they
	# existed loads each move exactly as it was.
	s.hp_cost_percent = float(d.get("hp_cost_percent", 0.0))
	s.resonance_cost = float(d.get("resonance_cost", 0.0))
	s.hit_count = int(d.get("hit_count", 1))
	s.pierce = float(d.get("pierce", 0.0))
	s.ally_heal_power = float(d.get("ally_heal_power", 0.0))
	s.bonus_condition = int(d.get("bonus_condition", Skill.BonusCondition.NONE))
	s.bonus_multiplier = float(d.get("bonus_multiplier", 1.5))
	s.override_element = int(d.get("override_element", ElementalSystem.Element.NORMAL))
	s.override_super = bool(d.get("override_super", false))
	s.scale_with = int(d.get("scale_with", Skill.ScaleWith.NONE))
	s.scale_more_is_stronger = bool(d.get("scale_more_is_stronger", true))
	s.self_debuff = String(d.get("self_debuff", ""))
	s.recoil_percent = float(d.get("recoil_percent", 0.0))
	s.miss_chance = float(d.get("miss_chance", 0.0))
	s.target_buff = String(d.get("target_buff", ""))
```

- [ ] **Step 4: Implement the pool table and top-up**

In `scripts/PartyFactory.gd`, after `const MOVES := "res://data/skills/"`, add:

```gdscript

## Each hero's pool, in slot order. The order is load-bearing:
## SKILL_UNLOCK_LEVELS, SKILL_CATEGORIES and the equipped loadout are positional.
const POOLS := {
	"Aria": [
		"aqua_slash.tres", "frost_bolt.tres", "tide_pulse.tres", "mend.tres",
		"tidal_requiem.tres", "hydro_pierce.tres", "tidal_barrier.tres", "grand_mend.tres",
		"riptide_lash.tres", "glacial_shard.tres", "abyssal_veil.tres", "maelstrom.tres",
	],
	"Kael": [
		"flame_strike.tres", "shield_bash.tres", "war_cry.tres", "inferno.tres",
		"phoenix_fury.tres", "molten_blade.tres", "iron_will.tres", "flame_wall.tres",
		"cinder_cleave.tres", "guard_crush.tres", "ember_ward.tres", "scorched_earth.tres",
	],
	"Lyra": [
		"wind_slash.tres", "mend.tres", "gust.tres", "wind_barrier.tres",
		"gale_requiem.tres", "cyclone.tres", "grand_mend.tres", "tailwind.tres",
		"zephyr_cut.tres", "feather_volley.tres", "restoring_breeze.tres", "sanctuary.tres",
	],
}

## A hero's whole pool as their own copies, in slot order.
static func _pool(hero_name: String) -> Array[Skill]:
	var out: Array[Skill] = []
	for f in POOLS[hero_name]:
		out.append(_move(f))
	return out

## Stamps the curve and category for pool slot `slot` onto a hero's copy.
static func _stamp_slot(skill: Skill, slot: int) -> void:
	if slot < SKILL_UNLOCK_LEVELS.size():
		skill.unlock_level = 1 if TEST_UNLOCK_ALL_SKILLS else SKILL_UNLOCK_LEVELS[slot]
	elif TEST_UNLOCK_ALL_SKILLS:
		skill.unlock_level = 1
	if slot < SKILL_CATEGORIES.size():
		skill.category = SKILL_CATEGORIES[slot]

## Appends, at the end of the pool, a copy of every move in this hero's factory
## pool that `hero` lacks — matched by file, or by name for a move saved before
## moves had files — stamped with that move's OWN slot's unlock level and
## category. A save keeps a pool exactly as written, so without this a save
## from before a pool grew would never gain the new moves. Returns how many
## were added; an unknown hero is left alone.
static func top_up_pool(hero: Character) -> int:
	if not POOLS.has(hero.character_name):
		return 0
	var have_paths := {}
	var have_names := {}
	for s in hero.skills:
		if s == null:
			continue
		if s.source_path != "":
			have_paths[s.source_path] = true
		have_names[s.skill_name] = true
	var files: Array = POOLS[hero.character_name]
	var added := 0
	for slot in files.size():
		var path: String = MOVES + files[slot]
		var template: Skill = load(path)
		if have_paths.has(path) or have_names.has(template.skill_name):
			continue
		if hero.skills.size() >= Character.MAX_SKILLS:
			break
		var copy := _move(files[slot])
		_stamp_slot(copy, slot)
		hero.skills.append(copy)
		added += 1
	return added

## After a save loads: give every hero the moves added to their pool since it
## was written, then fill any EMPTY loadout slots (the player's choices stay).
static func top_up_party(party: Array) -> void:
	for hero in party:
		if top_up_pool(hero) > 0:
			hero.auto_equip_unslotted()
```

Replace the whole of `_apply_skill_tables` with:

```gdscript
## Stamps the curve and category onto a hero's pool. Slots beyond the tables keep
## their Skill defaults (level 1, ATTACK) rather than becoming unreachable.
static func _apply_skill_tables(hero: Character) -> void:
	for i in hero.skills.size():
		if hero.skills[i] != null:
			_stamp_slot(hero.skills[i], i)
```

In each of `_create_aria`, `_create_kael`, `_create_lyra`, replace the whole `hero.skills = [ ... ] as Array[Skill]` statement with `hero.skills = _pool("Aria")` (respectively `"Kael"`, `"Lyra"`).

- [ ] **Step 5: Top up on load**

In `scripts/GameManager.gd` `load_from_slot`, after the line `party = SaveSerializer.deserialize_party(data.get("party", []))`, add:

```gdscript
	# A save keeps each hero's pool exactly as it was written; moves added to
	# the game since then are appended here (Spec B, Part 7).
	PartyFactory.top_up_party(party)
```

- [ ] **Step 6: Run the tests**

Expected: `SaveSerializer [OK]`, `PartyFactory [OK]`, `MoveLibrary [OK]` (pools unchanged — still the same 12 files), TOTAL 0 failed.

- [ ] **Step 7: Commit**

Message: `Save the new move options and top up old saves' pools`.

---

### Task 8: The honest fixes

**Files:**
- Modify: `data/skills/cyclone.tres`, `data/skills/hydro_pierce.tres`, `data/skills/gale_requiem.tres`, `data/skills/frost_bolt.tres`, `data/skills/restoring_breeze.tres`
- Modify: `tests/suites/test_move_library.gd` (`MERGE_DELTAS`, the delta comparison; add honest-skill tests)
- Test: `tests/suites/test_move_library.gd`, `tests/suites/test_skill_resolver.gd`

**Interfaces:**
- Consumes: Tasks 1–6 (the options and their resolver behaviour).

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_move_library.gd`:

```gdscript
# --------------------------------------------------- Spec B: honest skills

## Each move now does what its description promises, and its generated tags say so.
func test_cyclone_hits_twice() -> void:
	var s: Skill = load(LIB + "cyclone.tres")
	assert_eq(s.hit_count, 2, "two hits")
	assert_true(is_equal_approx(s.power, 1.2), "at 1.2 each")
	assert_true(s.effect_tags().has("2 hits"), "and says so")

func test_hydro_pierce_pierces() -> void:
	var s: Skill = load(LIB + "hydro_pierce.tres")
	assert_eq(s.pierce, 1.0, "ignores all ARC")
	assert_true(is_equal_approx(s.power, 2.4), "at 2.4")
	assert_true(s.effect_tags().has("Ignores ARC"), "and says so")

func test_gale_requiem_heals_the_party() -> void:
	var s: Skill = load(LIB + "gale_requiem.tres")
	assert_eq(s.ally_heal_power, 1.0, "heals allies by MAG x 1.0")
	assert_true(is_equal_approx(s.power, 2.5), "damage 2.5")
	assert_true(s.effect_tags().has("Heals allies"), "and says so")

func test_frost_bolt_can_slow() -> void:
	var s: Skill = load(LIB + "frost_bolt.tres")
	assert_eq(s.status_to_apply, "speed_debuff", "lowers SPD")
	assert_true(is_equal_approx(s.status_chance, 0.4), "40% of the time")
	assert_true(is_equal_approx(s.power, 1.4), "at 1.4")
	assert_true(s.effect_tags().has("40% chance: Lowers SPD"), "and says so")

func test_restoring_breeze_regenerates() -> void:
	var s: Skill = load(LIB + "restoring_breeze.tres")
	assert_eq(s.status_to_apply, StatusSystem.REGENERATE, "regenerates")
	assert_true(is_equal_approx(s.power, 0.5), "after a smaller heal of 0.5")
	assert_true(s.effect_tags().has("Regenerates"), "and says so")
```

Append to `tests/suites/test_skill_resolver.gd`:

```gdscript
# --------------------------------------------------- Spec B: honest skills in battle

func test_the_real_cyclone_strikes_every_enemy_twice() -> void:
	var bm := _manager(1, 2)
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], load("res://data/skills/cyclone.tres"), [])
	for foe in bm.enemies:
		var on_foe := hits.filter(func(r): return r["target"] == foe and r["action"] == "skill_magic")
		assert_eq(on_foe.size(), 2, "%s hit twice" % foe.character_name)
	bm.free()

func test_the_real_gale_requiem_heals_the_party() -> void:
	var bm := _manager(2, 1)
	bm.party[1].current_hp -= 100
	var hp := bm.party[1].current_hp
	bm.resolve_skill(bm.party[0], load("res://data/skills/gale_requiem.tres"), [])
	assert_true(bm.party[1].current_hp > hp, "the ally was healed")
	bm.free()
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — the five files still hold their old values.

- [ ] **Step 3: Edit the five move files**

Each file's `[resource]` section: change the existing `power` line and append the new lines at the end of the section. Leave every other line as it is.

`data/skills/cyclone.tres`: `power = 2.2` → `power = 1.2`; add `hit_count = 2`.

`data/skills/hydro_pierce.tres`: `power = 2.5` → `power = 2.4`; add `pierce = 1.0`.

`data/skills/gale_requiem.tres`: `power = 3.0` → `power = 2.5`; add `ally_heal_power = 1.0`.

`data/skills/frost_bolt.tres`: `power = 1.5` → `power = 1.4`; add:

```
status_to_apply = "speed_debuff"
status_chance = 0.4
```

`data/skills/restoring_breeze.tres`: `power = 1.2` → `power = 0.5` (its `status_to_apply = "regenerate"` stays).

- [ ] **Step 4: Record the deltas**

In `tests/suites/test_move_library.gd`, replace the `MERGE_DELTAS` declaration and its doc comment with:

```gdscript
## The approved differences from the pre-migration baseline, keyed
## "<hero>:<slot>" -> {field: approved value}: the Mend / Grand Mend merge
## (Spec A) and the five honest-skill fixes (Spec B). Fields the baseline
## predates (hit_count, pierce, ally_heal_power, …) are not compared at all.
const MERGE_DELTAS := {
	"Aria:1": {"power": 1.4, "status_to_apply": "speed_debuff", "status_chance": 0.4},  # Frost Bolt
	"Aria:3": {"mp_cost": 12},                                                          # Mend
	"Aria:5": {"power": 2.4},                                                           # Hydro Pierce
	"Lyra:1": {"element": ElementalSystem.Element.LIGHT},                               # Mend
	"Lyra:4": {"power": 2.5},                                                           # Gale Requiem
	"Lyra:5": {"power": 1.2},                                                           # Cyclone
	"Lyra:6": {"element": ElementalSystem.Element.LIGHT},                               # Grand Mend
	"Lyra:10": {"power": 0.5},                                                          # Restoring Breeze
}

## Equal for a delta's purposes: floats approximately, everything else exactly.
func _same(a, b) -> bool:
	if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT:
		return is_equal_approx(float(a), float(b))
	return a == b
```

In `test_hero_pools_match_the_baseline`, replace:

```gdscript
			for field in allowed:
				assert_eq(int(got[field]), int(allowed[field]), "%s %s is the merged value" % [key, field])
```

with:

```gdscript
			for field in allowed:
				assert_true(_same(got[field], allowed[field]),
						"%s %s is the approved value (got %s)" % [key, field, str(got[field])])
```

- [ ] **Step 5: Run the tests**

Expected: `MoveLibrary [OK]`, `SkillResolver [OK]`, TOTAL 0 failed.

- [ ] **Step 6: Commit**

Message: `Make Cyclone, Hydro Pierce, Gale Requiem, Frost Bolt and Restoring Breeze honest`.

---

### Task 9: The new moves

**Files:**
- Create: `data/skills/brine_surge.tres`, `mana_surge.tres`, `abyssal_tithe.tres`, `bloodfire_edge.tres`, `last_stand.tres`, `provoking_blow.tres`, `opportune_gust.tres`, `resonant_gale.tres`, `tempest_gamble.tres`, `reckless_charge.tres`, `overreach.tres`
- Modify: `scripts/PartyFactory.gd` (`POOLS`, `SKILL_UNLOCK_LEVELS`, `SKILL_CATEGORIES`, the `TEST_UNLOCK_ALL_SKILLS` comment)
- Modify: `data/enemies/goblin_spearman.tres`, `data/enemies/goblin_warlord.tres`
- Modify: `tests/fixtures/move_library_baseline.json` (by hand, via the script below)
- Modify: `tests/suites/test_move_library.gd`, `test_party_factory.gd`, `test_skill_learning.gd`, `test_moveset.gd`

**Interfaces:**
- Consumes: Task 7's `POOLS`, every option from Task 1.

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_move_library.gd`:

```gdscript
# --------------------------------------------------- Spec B: new moves

const NEW_HERO_MOVES := {
	"Aria": ["brine_surge.tres", "mana_surge.tres", "abyssal_tithe.tres"],
	"Kael": ["bloodfire_edge.tres", "last_stand.tres", "provoking_blow.tres"],
	"Lyra": ["opportune_gust.tres", "resonant_gale.tres", "tempest_gamble.tres"],
}

func test_each_hero_gains_three_moves_in_slots_13_to_15() -> void:
	for hero in PartyFactory.create_default_party():
		var want: Array = NEW_HERO_MOVES[hero.character_name]
		for i in 3:
			assert_eq(hero.skills[12 + i].source_path, LIB + want[i], "%s slot %d" % [hero.character_name, 13 + i])

func test_every_new_move_is_described_and_tagged() -> void:
	var files: Array = []
	for name in NEW_HERO_MOVES:
		files.append_array(NEW_HERO_MOVES[name])
	files.append_array(["reckless_charge.tres", "overreach.tres"])
	for f in files:
		var s: Skill = load(LIB + f)
		assert_true(s.description != "", "%s has a description" % f)
		assert_false(s.effect_tags().is_empty(), "%s shows what makes it special" % f)

func test_every_new_mechanic_is_used_by_some_move() -> void:
	var used := {}
	for f in _library_files():   # full res:// paths
		var s: Skill = load(f)
		if s.hp_cost_percent > 0.0: used["hp_cost"] = true
		if s.resonance_cost > 0.0: used["resonance_cost"] = true
		if s.hit_count > 1: used["multi_hit"] = true
		if s.pierce > 0.0: used["pierce"] = true
		if s.ally_heal_power > 0.0: used["ally_heal"] = true
		if s.bonus_condition == Skill.BonusCondition.TARGET_AFFLICTED: used["afflicted"] = true
		if s.bonus_condition == Skill.BonusCondition.USER_HP_LOW: used["low_hp"] = true
		if s.override_element != ElementalSystem.Element.NORMAL: used["override"] = true
		if s.scale_with != Skill.ScaleWith.NONE: used["scaling"] = true
		if s.self_debuff != "": used["self_debuff"] = true
		if s.recoil_percent > 0.0: used["recoil"] = true
		if s.miss_chance > 0.0: used["miss"] = true
		if s.target_buff != "": used["target_buff"] = true
	for m in ["hp_cost", "resonance_cost", "multi_hit", "pierce", "ally_heal", "afflicted",
			"low_hp", "override", "scaling", "self_debuff", "recoil", "miss", "target_buff"]:
		assert_true(used.has(m), "some move uses %s" % m)

func test_goblins_gain_their_trade_off_moves() -> void:
	var spear: Enemy = load("res://data/enemies/goblin_spearman.tres")
	var warlord: Enemy = load("res://data/enemies/goblin_warlord.tres")
	assert_true(spear.skills.map(func(s): return s.skill_name).has("Reckless Charge"), "the Spearman charges recklessly")
	assert_true(warlord.skills.map(func(s): return s.skill_name).has("Overreach"), "the Warlord overreaches")

func test_brine_surge_is_super_effective_against_water() -> void:
	var s: Skill = load(LIB + "brine_surge.tres")
	assert_eq(int(s.override_element), int(ElementalSystem.Element.WATER), "names Water")
	assert_true(s.override_super, "super-effective")
	assert_eq(int(s.element), int(ElementalSystem.Element.WATER), "a Water move")
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — the files and pool slots do not exist yet.

- [ ] **Step 3: Create the eleven move files**

Each is a text resource of this exact shape (no uid line; the editor may add one later). Create them with these contents:

`data/skills/brine_surge.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Brine Surge"
description = "A surge of heavy brine that overwhelms even creatures of the sea."
mp_cost = 12
attack_type = 2
power = 1.2
element = 2
override_element = 2
override_super = true
```

`data/skills/mana_surge.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Mana Surge"
description = "Pours raw mana into a torrent — the fuller her MP, the harder it hits."
mp_cost = 20
attack_type = 2
power = 2.2
element = 2
scale_with = 2
```

`data/skills/abyssal_tithe.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Abyssal Tithe"
description = "Pays the abyss in resonance to drown every enemy."
attack_type = 2
target_type = 1
power = 2.6
element = 2
resonance_cost = 30.0
```

`data/skills/bloodfire_edge.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Bloodfire Edge"
description = "Feeds his own blood to the flame for a searing cut."
power = 2.7
element = 1
hp_cost_percent = 12.0
```

`data/skills/last_stand.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Last Stand"
description = "A desperate blow that burns brightest when he is close to falling."
mp_cost = 10
power = 1.6
element = 1
bonus_condition = 2
bonus_multiplier = 1.75
```

`data/skills/provoking_blow.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Provoking Blow"
description = "A crushing strike that leaves the foe enraged."
mp_cost = 14
power = 2.6
element = 1
target_buff = "attack"
```

`data/skills/opportune_gust.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Opportune Gust"
description = "A cutting wind that finds every opening in a foe already suffering."
mp_cost = 10
attack_type = 2
power = 1.4
element = 7
bonus_condition = 1
bonus_multiplier = 1.5
```

`data/skills/resonant_gale.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Resonant Gale"
description = "A gale tuned to her resonance — the fuller it rings, the harder it hits."
mp_cost = 16
attack_type = 2
power = 2.0
element = 7
scale_with = 3
```

`data/skills/tempest_gamble.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Tempest Gamble"
description = "Unleashes a wild tempest on every enemy — but the winds may scatter."
mp_cost = 22
attack_type = 2
target_type = 1
power = 3.0
element = 7
miss_chance = 0.3
```

`data/skills/reckless_charge.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Reckless Charge"
description = "A heedless charge that jars the goblin as much as its target."
power = 1.6
recoil_percent = 25.0
```

`data/skills/overreach.tres`:
```
[gd_resource type="Resource" script_class="Skill" format=3]

[ext_resource type="Script" path="res://scripts/characters/Skill.gd" id="1_skill"]

[resource]
script = ExtResource("1_skill")
skill_name = "Overreach"
description = "A huge overhead swing that leaves the Warlord's guard wide open."
power = 2.0
self_debuff = "defense"
```

(Enum values: `attack_type` 0 = Strike, 2 = Magic; `target_type` 1 = all enemies; `element` 1 = Fire, 2 = Water, 7 = Wind; `bonus_condition` 1 = target afflicted, 2 = user HP low; `scale_with` 2 = MP, 3 = resonance. Omitted fields keep their defaults: single enemy, damage, Normal, 0 MP.)

- [ ] **Step 4: Grow the hero pools**

In `scripts/PartyFactory.gd`:

Append to each `POOLS` list, at the end, in this order:
- `"Aria"`: `"brine_surge.tres", "mana_surge.tres", "abyssal_tithe.tres",`
- `"Kael"`: `"bloodfire_edge.tres", "last_stand.tres", "provoking_blow.tres",`
- `"Lyra"`: `"opportune_gust.tres", "resonant_gale.tres", "tempest_gamble.tres",`

In `SKILL_UNLOCK_LEVELS`, after the line `18,  # 11 special`, add:

```gdscript
	3,   # 12 attack   (Spec B: Brine Surge / Bloodfire Edge / Opportune Gust)
	9,   # 13 special  (Spec B: Mana Surge / Last Stand / Resonant Gale)
	14,  # 14 special  (Spec B: Abyssal Tithe / Provoking Blow / Tempest Gamble)
```

In `SKILL_CATEGORIES`, after the last line `Skill.SkillCategory.SPECIAL, Skill.SkillCategory.SPECIAL,`, add:

```gdscript
	Skill.SkillCategory.ATTACK,  Skill.SkillCategory.SPECIAL,
	Skill.SkillCategory.SPECIAL,
```

In the `TEST_UNLOCK_ALL_SKILLS` comment, change "knows its whole 12-move pool" to "knows its whole 15-move pool".

- [ ] **Step 5: Give the goblins their moves**

`data/enemies/goblin_spearman.tres`: after the line
`[ext_resource type="Resource" path="res://data/skills/haft_bash.tres" id="6_opb3d"]` add:

```
[ext_resource type="Resource" path="res://data/skills/reckless_charge.tres" id="7_reckless"]
```

and change its `skills = Array[ExtResource("1_skill")]([ExtResource("4_5gm65"), ExtResource("5_shcj0"), ExtResource("6_opb3d")])` to end `ExtResource("6_opb3d"), ExtResource("7_reckless")])`.

`data/enemies/goblin_warlord.tres`: after the line
`[ext_resource type="Resource" path="res://data/skills/savage_bellow.tres" id="7_ouhqc"]` add:

```
[ext_resource type="Resource" path="res://data/skills/overreach.tres" id="8_overreach"]
```

and change the BASE moves line — the one in the `[resource]` section, `skills = Array[ExtResource("1_skill")]([ExtResource("6_g2gb1"), ExtResource("7_ouhqc")])` — to end `ExtResource("7_ouhqc"), ExtResource("8_overreach")])`. Do NOT change the fury phase's `skills` line (`ExtResource("3_ro5fg"), ExtResource("4_q44ng")`).

- [ ] **Step 6: Record the two enemy additions in the baseline (by hand)**

The baseline is a migration guard; adding a move to a baselined enemy is recorded by appending that move to the enemy's fixture entry. Run from `new-game-project/` (it preserves the file's exact formatting — tab indent, sorted keys, no ASCII escaping, no trailing newline):

```bash
python3 - <<'EOF'
import json
P = "tests/fixtures/move_library_baseline.json"
d = json.load(open(P, encoding="utf-8"))
def move(name, desc, power):
    return {"attack_type": 0, "category": 0, "description": desc, "element": 0,
            "mp_cost": 0, "power": power, "resonance_gain_override": -1.0,
            "secondary_element": 0, "skill_name": name, "skill_type": 0,
            "status_chance": 0.0, "status_to_apply": "", "status_type": 0,
            "target_type": 0, "unlock_level": 1}
e = d["enemies"]
e["res://data/enemies/goblin_spearman.tres"]["skills"].append(
    move("Reckless Charge", "A heedless charge that jars the goblin as much as its target.", 1.6))
e["res://data/enemies/goblin_warlord.tres"]["skills"].append(
    move("Overreach", "A huge overhead swing that leaves the Warlord's guard wide open.", 2.0))
open(P, "w", encoding="utf-8").write(json.dumps(d, indent="\t", sort_keys=True, ensure_ascii=False))
EOF
```

Then `git diff --stat tests/fixtures/move_library_baseline.json` must show only insertions.

- [ ] **Step 7: Let the pool tests see 15 moves**

In `tests/suites/test_move_library.gd` `test_hero_pools_match_the_baseline`, replace:

```gdscript
		assert_eq(hero.skills.size(), want.size(), "%s kept 12 moves" % hero.character_name)
```

with:

```gdscript
		# Pools may grow (Spec B added slots 13-15); every baselined slot must stay.
		assert_true(hero.skills.size() >= want.size(), "%s kept its %d baselined moves" % [hero.character_name, want.size()])
```

`tests/suites/test_party_factory.gd` (`test_each_hero_has_eight_skills`): change `12` to `15` and the message to `"%s has a 15-move pool (7 attack + 8 special)"`.

`tests/suites/test_skill_learning.gd`: in `test_party_curve_is_applied` change `assert_eq(hero.skills.size(), 12, …)` to `15`; in `test_curve_covers_every_slot_and_is_reachable` change `assert_eq(PartyFactory.SKILL_UNLOCK_LEVELS.size(), 12, …)` to `15`.

`tests/suites/test_moveset.gd` (`test_default_party_has_a_pool_bigger_than_its_slots`): change `assert_eq(hero.skills.size(), 12, "%s defines 12 moves" …)` to `15` / `"%s defines 15 moves"`, `assert_eq(atk, 6, …)` to `7` (message `"%s has seven attacks, more than the four slots"`), and `assert_eq(spc, 6, …)` to `8` (message `"%s has eight specials"`).

- [ ] **Step 8: Run the tests**

Expected: `MoveLibrary [OK]`, `PartyFactory [OK]`, `SkillLearning [OK]`, `Moveset [OK]`, `BossPhases [OK]`, TOTAL 0 failed. If `test_the_library_holds_every_move` or the index test fails, check for a typo'd `skill_name` collision.

- [ ] **Step 9: Commit**

Message: `Add nine hero moves and two goblin moves that use the new mechanics`.

---

### Task 10: Document the system

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Skill section**

Under `### Skill (Resource)`, add a `**Spec B options**` sub-list: every field from Task 1 with one line each, the constants, that all default to "off", the dodge/miss rule, that enemies pay HP but ignore MP/resonance, the element override's balance rules (one element per move, replaces one pairing, lower base power), and that `cost_parts()` / `effect_tags()` drive every menu (never format costs by hand).

- [ ] **Step 2: Resolver section**

Under `### BattleManager`, record the resolution order (check → measure → pay → per target per hit: miss, dodge, damage → once per target: rider, target buff → once per action: ally heal, recoil, self-debuff), the results-buffered-per-target rule, the new actions (`miss`, `hp_cost`, `recoil`, `self_debuff`), `is_first_hit` and `BattleScene.grants_damage_resonance`.

- [ ] **Step 3: Pools, saves and baseline**

- Hero pools are **15** moves (`PartyFactory.POOLS`); slots 13–15 unlock at 3 / 9 / 14 (Attack / Special / Special). Update every "12-move" mention.
- `PartyFactory.top_up_pool` / `top_up_party` and the `GameManager.load_from_slot` hook: old saves gain new pool moves; the player's loadout is kept.
- `MERGE_DELTAS` now records Spec A's Mend merge and Spec B's five honest fixes; the two goblin additions were recorded by appending to the fixture.

- [ ] **Step 4: Roadmap and counts**

Rewrite Track B item 3: Spec A and Spec B done; Spec C (multi-turn) remains. Update both test-count references to the real numbers from a final run (`TOTAL` line and the number of `SUITE_PATHS` entries), and add `skill_options` to the Testing Policy suite list.

- [ ] **Step 5: Run the full suite**

Expected: ALL TESTS PASSED, 0 failed.

- [ ] **Step 6: Commit**

Message: `Document Spec B: move options, resolution order, pools and saves`.

---

## Done criteria

- Cyclone, Hydro Pierce, Gale Requiem, Frost Bolt and Restoring Breeze do what their descriptions say, at about their old total strength.
- Every Spec B option exists on `Skill`, defaults to "off", and is resolved by `resolve_skill` in the spec's order.
- Every mechanic is used by at least one move in the library; heroes have 15-move pools; the Spearman and the Warlord carry their trade-off moves.
- Every menu shows every cost and a generated effect line.
- Saves carry every option; an older save gains the new moves without disturbing the loadout.
- All five Review Focus cases pinned; the full suite green with no drop below 3443.
