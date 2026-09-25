# Boss Phases — Design

**Status:** approved in chat, awaiting written review
**Track:** B (systems breadth), item 1 of 3
**Date:** 2026-09-24

## Intent

Give The Amethyst Requiem real boss fights: enemies whose behaviour changes as
they are worn down, so a climactic battle reads differently from a roadside
scrap. The Goblin Castle exists as a scene but has nothing in it worth the trip.

A boss must be authorable **entirely as data in one `.tres` file**. Adding a
second or third boss should cost no code. Every phase power is **optional**, so
each boss opts into only the ones that suit it — the user was explicit that not
all bosses should do all five things.

### Success criteria

- A Goblin Warlord fight exists in the Goblin Castle that visibly changes
  behaviour twice as it loses HP.
- A new boss can be added by writing a `.tres` alone.
- The five phase powers (moveset, stats, summons, field effects, transformation) each work
  independently and can be combined.
- Nothing regresses: the existing 2307 tests stay green.

### Non-goals

- **Per-boss behaviour scripts.** Data-only for now. The `BossPhase` resource is
  the documented extension point if a future boss needs bespoke logic.
- **Save serialization.** Enemies are battle-temp and never serialized; phase
  state dies with the battle, like `status_effects` and `buffs`.
- **Boss-specific rewards plumbing.** `base_exp_reward` / `base_gold_reward` /
  `rarity` already scale rewards per enemy; a boss just uses bigger numbers.
- **New battle backgrounds or music.** Out of scope.

## Data model

### `BossPhase` — new Resource, `scripts/characters/BossPhase.gd`

```gdscript
class_name BossPhase
extends Resource

@export var enter_at_hp: float = 1.0        # active at/below this HP fraction
@export var phase_name: String = ""
@export var banner_text: String = ""         # "" = transition silently
@export var skills: Array[Skill] = []        # [] = keep the enemy's base skills
@export var stat_multipliers: Dictionary = {}    # {"attack": 1.5, "speed": 1.2}
@export var summons: Array[Dictionary] = []      # [{path, count, level}]
@export var turn_effect: String = ""         # StatusSystem apply-token
@export var turn_effect_chance: float = 0.0  # 0..1, rolled on the boss's turn
@export var max_hp_multiplier: float = 0.0   # >0 = TRANSFORM into a stronger form
@export var restore_hp: bool = false         # refill to the new max on entry
```

Every field except `enter_at_hp` is optional. An omitted field means "this phase
does not use that power", which is what lets one boss be a pure stat-check and
another a summoner.

### `Enemy` additions

```gdscript
@export var phases: Array[BossPhase] = []
func is_boss() -> bool: return not phases.is_empty()
```

A boss **is** an enemy with phases — there is no separate `is_boss` flag to fall
out of sync with the data. Battle-temp state (not serialized): `active_phase`,
defaulting to `-1` meaning "not yet entered any phase".

### `Character` addition

`phase_multipliers: Dictionary` and `max_hp_multiplier: float` — both
battle-temp, cleared by `clear_battle_effects()` alongside `buffs`/`debuffs`.
`max_hp()` folds in `max_hp_multiplier`; the five power getters fold in
`phase_multipliers`.

## Behaviour

### Phase selection — forward-only

`Enemy.should_advance(fraction: float) -> bool` and `advance_phase()` are pure and
testable with no battle running.

Phases advance **one step at a time, forward only**: the boss enters the next
phase when `hp_fraction <= phases[active + 1].enter_at_hp`. `active_phase` starts
at `-1`, and phase 0 is authored at `enter_at_hp = 1.0` so it is entered on the
first check.

| phases | HP 1.0 | 0.6 | 0.5 | 0.3 | 0.25 | 0.1 |
|---|---|---|---|---|---|---|
| `[1.0, 0.5, 0.25]` | 0 | 0 | 1 | 1 | 2 | 2 |

**Why forward-only rather than recomputing from HP.** Recomputing ("the active
phase is the last one whose `enter_at_hp >= fraction`") cannot express
transformation. A transform refills HP, so the fraction returns to 1.0 and the
formula computes phase 0 — the boss reverts to its opening form, and if a
never-regress rule pins it instead, no later phase can ever fire and the boss is
frozen for the rest of the fight. Advancing forward from where the boss already
is has no such failure.

Two consequences, both improvements:

1. **Phases never regress, by construction.** Healing a boss above a threshold
   cannot re-fire banners or re-summon adds, and this needs no special case.
2. **Every crossed phase fires, in order.** A hit from 60% to 5% runs phase 1's
   entry and then phase 2's, rather than skipping to the deepest. This is a
   change from the first draft of this spec, and transformation is why: skipping
   meant bursting a boss past its transform threshold skipped the transform
   entirely, which trivialises the fight. Queued banners display sequentially
   through the existing status-banner pacing.

   A transform stops the cascade on its own: it refills HP, so the next phase's
   condition is immediately false. Transformation is a natural checkpoint rather
   than a special case in the code.

### Transition

`BattleManager` checks for a phase change **after damage resolves** and, on
entry, in this order:

1. Set `active_phase`.
2. Apply `stat_multipliers` into `Character.phase_multipliers` (replacing the
   previous phase's, not accumulating).
3. Queue `summons`.
4. Emit `boss_phase_changed(enemy, phase)`.

`BattleScene` renders `banner_text` through the existing `_show_status_banner`
path, so the pacing and styling match status banners already in the game.

### Power 1 — Moveset

`EnemyAI._choose_skill` uses the active phase's `skills` when that array is
non-empty, otherwise the enemy's own `skills`. Skills are not filtered by MP:
enemies bypass MP entirely (see `Skill.can_use`), which already holds today.

**This replaces the hard-coded enrage** at `EnemyAI.gd:54`
(`is_enraged = hp_pct < 0.25`). Leaving both would mean two parallel,
invisibly-interacting mechanisms for "boss acts differently when hurt". Non-boss
enemies keep the old behaviour unchanged; only enemies with phases use phases.

### Power 2 — Stats

`stat_multipliers` accepts the five combat stats only: `attack`, `defense`,
`magic`, `arcane`, `speed`. **`max_hp`/`max_mp` are deliberately excluded** —
changing max HP here would silently move the very thresholds that drive phases.
A boss that should grow its HP pool does so through **Power 5 —
Transformation**, which changes max HP and refills deliberately.

The multiplier composes in `Character`'s power getters alongside
`StatusSystem.compose_stat` and `combat_stat_multiplier`, so a phase boost stacks
correctly with buffs, debuffs, status penalties and the difficulty setting rather
than overriding them.

### Power 3 — Summons

On phase entry, each `{path, count, level}` entry loads the enemy `.tres`,
`.duplicate(true)`s it per the existing pattern, sets its level (defaulting to
the boss's level), and appends to `BattleManager.enemies`.

This works with little new plumbing because `_build_turn_order()` rebuilds from
`enemies` every round and `BattleScene._rebuild_enemy_cards()` already exists.

**Cap:** total enemies is capped at `BattleManager.MAX_BATTLE_ENEMIES = 10`, so a
boss can summon between 0 and 9. Ten is not an invented number — the enemy card
row is already built for exactly that (`BattleScene.gd:388`: *"10 enemies fill
the row"*, cards sized `10 x 124 + 9 x 2 = 1258` for the 1280-wide viewport).

The cap is enforced **when summoning**, not when rendering. `_setup_enemy_cards`
currently truncates with `mini(enemies.size(), 10)`, which would leave an 11th
enemy alive in the fight with no card and no visible HP — fixable only by never
creating it.

Summoned enemies are ordinary enemies: they can be killed, drop loot, and grant
EXP. They are added after the boss in turn order and act from the next round.

### Power 4 — Field effects

At the start of **the boss's own turn**, if the active phase has a `turn_effect`,
roll `turn_effect_chance`. On success, apply the token to a randomly chosen
living hero via `StatusSystem.parse_apply_token`.

"The boss's turn" rather than "each round" because the turn-order model has no
explicit round boundary to hook — `_build_turn_order()` simply rebuilds and
`_next_turn()` walks it. Tying the effect to the boss's own turn is unambiguous,
fires exactly once per cycle, and stops naturally when the boss dies. The effect
resolves **before** the boss chooses its action, so a hero paralysed by the field
effect is already paralysed when the boss picks a target.

Routing through `parse_apply_token` means element immunity, the mutex
one-status-at-a-time rule and the "never afflict a downed character" guard all
apply for free, with no duplicated logic.

### Power 5 — Transformation

A phase with `max_hp_multiplier > 0` is a **transformation**: the boss becomes a
stronger version of itself rather than merely escalating.

On entry:
1. `Character.max_hp_multiplier` (battle-temp) is set, scaling `max_hp()`.
2. If `restore_hp`, `current_hp` is set to the new `max_hp()`.

`max_hp` remains **excluded from `stat_multipliers`** — changing it there would
silently move the thresholds driving the phases. Transformation reaches it
through its own explicit field, so growing max HP is always a deliberate,
readable authoring decision rather than a side effect.

Transformation composes with the other powers: the same phase can also swap the
moveset, boost combat stats and summon, so "second form" is authored as one
phase rather than needing a parallel concept.

Because a transform restores HP, the boss returns to a full bar in its new form
and the phase cascade halts there — the fight visibly restarts, which is the
point.

## UI

- **Full-width boss card.** `BattleScene._create_enemy_card` uses
  `SIZE_EXPAND_FILL` for `is_boss()` enemies — the hook is already anticipated by
  the TODO at `BattleScene.gd:389`.
- **Phase banner** via the existing status-banner overlay.
- Boss card border keeps using `get_rarity_color()`; a boss is authored at a high
  rarity tier, so it already reads as special.

## First boss — Goblin Warlord

`data/enemies/goblin_warlord.tres`, reached through a fixed `EncounterGroup`
(`is_fixed = true`, which exists but has no users yet) in the Goblin Castle.

| Phase | Enters | Uses |
|---|---|---|
| 1 | 100% | Base moveset. Banner on battle start suppressed. |
| 2 | 50% | Summons 2× `goblin_spearman`; banner. |
| 3 | 25% | **Transformation** — max HP ×1.5, refill to full, ATK ×1.5 / SPD ×1.2, heavier moveset, banner. |

Chosen so the live fight exercises all five powers at least once, and so the
transform lands as the fight's climax: the party has the boss nearly dead, and it
stands back up bigger.

Phase 3's `enter_at_hp` is measured against the boss's ORIGINAL max HP; after the
transform its bar is full again at the new, larger maximum.

## Testing

New suite `tests/suites/test_boss_phases.gd`, registered in `TestRunner.gd`:

- `phase_for_hp` at exact boundaries (1.0, 0.5, 0.25) and between them.
- An enemy with no phases is not a boss and is unaffected throughout.
- A transition fires **once** per entry, not on every hit within a phase.
- Healing back above a threshold does not regress the phase.
- A single hit crossing two thresholds fires BOTH entries, in order.
- **Transformation:** max HP grows, HP refills to the new max, and the boss does
  NOT revert to an earlier phase now that its fraction is 1.0 again.
- **Transformation halts the cascade:** a hit that would otherwise cross a
  transform and the phase beyond it stops at the transform.
- A later phase still fires after a transform, once HP falls again against the
  NEW max HP.
- Moveset swap: the AI draws from the phase's skills when present, base when not.
- Stat multipliers compose with buffs, debuffs and difficulty rather than
  replacing them; excluded stats (`max_hp`) are ignored.
- Summons append to the enemy list, enter turn order, and **respect the cap at
  spawn time** — a boss that would exceed 10 enemies summons only up to the limit,
  so no combatant ever exists without a card.
- Field effects respect element immunity and the mutex rule, and never target a
  downed hero.
- `clear_battle_effects()` clears `phase_multipliers` AND `max_hp_multiplier`, so
  a transformed boss does not leak its grown HP pool into a later encounter.

Per the project Testing Policy, a regression test accompanies any bug found on
the way.

## Risks

- **Turn-order panel with summons.** `TurnOrderIndicator` builds per-actor slots;
  adding combatants mid-battle is new for it. Verify it rebuilds rather than
  showing stale slots.
- **The enrage replacement** changes behaviour for existing enemies if scoped
  wrongly. Guard: phases only apply to enemies that have them; a test asserts a
  phase-less enemy behaves exactly as before.
- **Class cache.** `BossPhase` is a new `class_name`, so the headless runner
  needs the documented `--editor --quit-after 3` rescan before tests see it.
