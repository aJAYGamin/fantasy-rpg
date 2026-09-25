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
all bosses should do all four things.

### Success criteria

- A Goblin Warlord fight exists in the Goblin Castle that visibly changes
  behaviour twice as it loses HP.
- A new boss can be added by writing a `.tres` alone.
- The four phase powers (moveset, stats, summons, field effects) each work
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
@export var turn_effect_chance: float = 0.0  # 0..1, rolled each round
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

`phase_multipliers: Dictionary` — battle-temp, cleared by
`clear_battle_effects()` alongside `buffs`/`debuffs`.

## Behaviour

### Phase selection

`Enemy.phase_for_hp(fraction: float) -> int` is a **pure function** — no battle
required, so the interesting rules are testable directly.

The active phase is the **last** phase in the array whose
`enter_at_hp >= fraction`. Phases are authored in descending order, with the
first at `1.0`:

| phases | HP 1.0 | 0.6 | 0.5 | 0.3 | 0.25 | 0.1 |
|---|---|---|---|---|---|---|
| `[1.0, 0.5, 0.25]` | 0 | 0 | 1 | 1 | 2 | 2 |

At battle start `active_phase` is `-1`, so the first check enters phase 0 like any
other transition and applies its powers. Phase 0 is normally authored empty
(no banner, no summons, no multipliers), which makes that entry invisible — but a
boss that wants an opening line or an opening buff can simply fill phase 0 in.

Two rules that exist to prevent visible glitches:

1. **Phases never regress.** If a boss is healed back above a threshold it keeps
   its current phase. Without this, damage/heal oscillation around a boundary
   would re-fire banners and re-summon adds.
2. **A hit that crosses two thresholds lands on the deepest one and fires only
   that phase's entry.** A single huge hit from full HP to 10% enters phase 2 and
   shows phase 2's banner; it does not also run phase 1's summons. Skipping a
   phase's rewards-in-kind is the intended reading — the boss was overwhelmed.

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
changing max HP mid-fight would move the very thresholds that drive phases.

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

**Cap:** total living enemies is capped at `BattleManager.MAX_BATTLE_ENEMIES = 6`
(a new constant; the existing overworld `MAX_ROAMERS = 4` is unrelated). Summons
beyond the cap are silently skipped — the enemy card row and turn-order panel
are not built for unbounded combatants.

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
| 3 | 25% | `stat_multipliers` ATK ×1.5, SPD ×1.2 + a heavier moveset; banner. |

Chosen so the live fight exercises all four powers at least once.

## Testing

New suite `tests/suites/test_boss_phases.gd`, registered in `TestRunner.gd`:

- `phase_for_hp` at exact boundaries (1.0, 0.5, 0.25) and between them.
- An enemy with no phases is not a boss and is unaffected throughout.
- A transition fires **once** per entry, not on every hit within a phase.
- Healing back above a threshold does not regress the phase.
- A single hit crossing two thresholds lands on the deepest and fires one entry.
- Moveset swap: the AI draws from the phase's skills when present, base when not.
- Stat multipliers compose with buffs, debuffs and difficulty rather than
  replacing them; excluded stats (`max_hp`) are ignored.
- Summons append to the enemy list, respect the cap, and enter turn order.
- Field effects respect element immunity and the mutex rule, and never target a
  downed hero.
- `clear_battle_effects()` clears `phase_multipliers`.

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
