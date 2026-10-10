# Skill Mechanics — Design (Spec B)

**Status:** approved in chat, awaiting written review
**Track:** B (systems breadth), item 3 — part B of three
**Date:** 2026-10-03
**Builds on:** Spec A (`2026-09-26-move-library-and-unified-resolver-design.md`)

## Intent

Give moves more than "damage, heal, buff, debuff". Spec A put every move in its
own file and every skill through one resolver (`BattleManager.resolve_skill`),
so each mechanic here is written once, works for heroes and enemies alike, and
is authored by editing a move file.

Two goals, in the user's order:

1. **Honest skills.** Five moves promise something they do not do. Each is
   fixed to do what its description says.
2. **New mechanics**, each shown off by at least one real move: HP and
   resonance costs, conditional power, scaling, and trade-offs.

Multi-turn effects (charge-up, delayed hits) are **Spec C** and out of scope.

### Decisions made with the user

| Topic | Decision |
|---|---|
| Where mechanics appear | Fix the honest moves in place; add **new** moves to the pools for the rest. Existing moves keep their balance. |
| Architecture | Plain options on each move file (approach A), grouped in the Inspector. Not composable effect resources. |
| Conditional power | Target is afflicted (any status or debuff); user's HP is low; and the user's own addition — **element override** (a move becomes effective or super-effective against one element it normally isn't), balanced so it is not overpowered. |
| HP cost | A percentage of the user's **max** HP. Can never knock the user out — the move greys out instead. |
| Resonance cost | A fixed amount of the meter. |
| Scaling (user's addition) | A move can grow stronger or weaker with the **user's own** HP, MP or resonance, in either direction, within a capped range. |
| Trade-offs | Self-debuff, recoil, the move's own miss chance, and the user's addition — **buffing the target's stats**. |
| Honest fixes | Keep each move's total strength about the same; it just does what it says. |
| Dodge (from earlier) | Anything aimed at the user's opponents can be dodged; anything aimed at the user or its allies always lands. Unchanged here, and the miss chance follows the same rule. |

### Success criteria

- Cyclone hits twice, Hydro Pierce ignores magic defence, Gale Requiem heals the
  party, Frost Bolt can slow, Restoring Breeze regenerates — each at about its
  old total strength.
- Every new mechanic is used by at least one move a player can meet in battle.
- Every option defaults to "off", so the 81 existing moves left alone behave
  exactly as before.
- A move's cost and effects are visible in every menu that lists moves, and the
  effect line is generated from the move's data, so it cannot drift from what
  the move does.
- An existing save loads with the new moves added to each hero's pool.
- Skills stay read-only at runtime: no mechanic writes to a `Skill` (enemies
  share the library's objects — see Spec A's Part 1 correction).
- The existing ~3443 tests stay green apart from the deliberate, recorded
  baseline changes listed in Part 5.

### Non-goals

- **Multi-turn effects** (Spec C).
- **Rebalancing existing moves** beyond the five honest fixes.
- **Changing the type chart.** The element override is per move.
- **Enemy AI strategy.** Enemies may use the new moves; the AI is not taught to
  play around them (beyond never choosing a move it cannot pay for).
- **The pre-existing bugs** logged for follow-up (single-ally targeting always
  hitting the first hero; resonance ultimates being dodge-rollable).

---

## Part 1 — The move options

All new fields live on `Skill` (`scripts/characters/Skill.gd`), each with a
default that means "off", grouped with `@export_group` so the Inspector reads
cleanly.

| Group | Field | Type / default | Meaning |
|---|---|---|---|
| **Costs** | `hp_cost_percent` | float, `0.0` | The user pays this % of their max HP, rounded up. |
| | `resonance_cost` | float, `0.0` | The user spends this much of the 0–100 resonance meter. |
| **Hits** | `hit_count` | int, `1` | Damage moves strike each target this many times. |
| | `pierce` | float, `0.0` | Fraction (0–1) of the target's DEF (physical) or ARC (magic) ignored. |
| **Extra** | `ally_heal_power` | float, `0.0` | After the hits, heals every living member of the user's side by `MAG × this`. |
| **Conditional** | `bonus_condition` | `BonusCondition`, `NONE` | `NONE`, `TARGET_AFFLICTED`, `USER_HP_LOW`. |
| | `bonus_multiplier` | float, `1.5` | Damage multiplier while the condition holds. |
| | `override_element` | `Element`, `NORMAL` | The one defender element this move treats differently. `NORMAL` = no override (the codebase's existing "not set" convention for elements). |
| | `override_super` | bool, `false` | `false` = **effective** (1×) against that element; `true` = **super-effective** (2×). |
| **Scaling** | `scale_with` | `ScaleWith`, `NONE` | `NONE`, `HP`, `MP`, `RESONANCE` — the user's own pool. |
| | `scale_more_is_stronger` | bool, `true` | `true`: fuller pool = stronger. `false`: emptier pool = stronger. |
| **Trade-offs** | `self_debuff` | String, `""` | A stat (`attack`/`defense`/`magic`/`arcane`/`speed`) lowered on the user after the move. |
| | `recoil_percent` | float, `0.0` | The user takes this % of the damage the move dealt. |
| | `miss_chance` | float, `0.0` | The move's own chance (0–1) to miss each target, separate from dodging. |
| | `target_buff` | String, `""` | A stat raised on every target the move hit. |

Constants on `Skill`: `LOW_HP_THRESHOLD := 0.3`, `SCALE_MIN := 0.75`,
`SCALE_MAX := 1.5`.

`self_debuff` and `target_buff` must name one of `StatusSystem.BUFFABLE_STATS`.
An unknown name is ignored with a `push_warning`, never applied — the phantom
`burn` status showed what an unchecked string does.

## Part 2 — How a move resolves

`resolve_skill(user, skill, chosen)` stays the single resolver. Order:

1. **Check** (`Skill.can_use`): not stunned; MP (heroes); resonance (heroes:
   `resonance_meter >= resonance_cost`); HP (both sides:
   `current_hp > hp cost`, so paying always leaves at least 1).
2. **Measure** the scaling factor and the user-HP condition **before paying**,
   so an HP-cost move is not weakened by its own cost.
3. **Pay**, in order: MP (heroes), resonance (heroes; subtracted from
   `Character.resonance_meter`, the field `ResonanceSystem` reads), HP (both
   sides). An HP cost emits an `"hp_cost"` result on the user.
4. **For each living target, for each hit** (status moves always hit once):
   1. If the target is an **opponent** of the user: roll `miss_chance` → a
      `"miss"` result; otherwise roll the target's dodge → a `"dodge"` result.
      Targets on the user's own side are never rolled (the dodge rule).
   2. Damage moves: `value = calculate_value(user) × condition × scaling`, then
      the target's damage function applies `pierce` and the element override
      (Part 3). The result is `"skill_physical"` / `"skill_magic"` as today.
   3. A target that drops to 0 takes no further hits; `handle_defeat` runs once.
5. **Once per target that took at least one landed hit**: roll the status rider
   (`status_to_apply` / `status_chance`) once — not once per hit — then apply
   `target_buff`.
6. **Heal moves** now apply their `status_to_apply` after healing (this is the
   Restoring Breeze fix; it is the only heal move with a token, so no other
   move changes). A heal's regen heals `HEAL_REGEN_POWER` (0.25) × the caster's
   MAG per turn rather than `max_hp / 8`, and never weakens a regen already
   running.
7. **After all targets**, in order: the ally heal (`"heal"` results on each
   living ally that was actually healed — a full-HP ally reports nothing),
   recoil (`"recoil"` result: `recoil_percent` of the total damage
   dealt this action, never dropping the user below 1 HP), the self-debuff.

### Conditions and scaling

- `TARGET_AFFLICTED`: the target has an active mutex status or is effectively
  debuffed in any stat (`StatusSystem` helpers). Checked before each hit.
- `USER_HP_LOW`: the user's HP fraction is below `LOW_HP_THRESHOLD`, measured
  at step 2.
- Scaling: `f` is the pool's fill (`current_hp/max_hp`, `current_mp/max_mp`,
  `resonance_meter/100`), measured at step 2. The multiplier runs linearly from
  `SCALE_MIN` to `SCALE_MAX` as `f` goes 0→1 (or 1→0 when
  `scale_more_is_stronger` is false). A pool the user does not have — an
  enemy's MP or resonance — gives 1×.

### Resonance

- **Skill resonance stays once per action.** `is_first_target` is true on the
  first LANDED hit of the action (a miss or dodge result always carries false),
  so a two-hit move does not build double, and a move whose first target dodges
  still builds its resonance on a later landed hit.
- **"Took damage" resonance becomes once per target per action.** Results carry
  a new `is_first_hit` flag (true on the first LANDED hit on each target; a miss
  or dodge result always carries false); `BattleScene` grants `on_damage_taken`
  only when it is set (`BattleScene.grants_damage_resonance`). Single-hit moves
  are unaffected.
- A move with a `resonance_cost` builds **no** resonance
  (`get_resonance_gain()` returns 0), so it cannot refund itself.
- HP cost and recoil are self-inflicted and grant no "took damage" resonance.

### Enemies

Enemies pay HP costs (they have HP) and ignore MP and resonance costs (they
have neither pool), matching how MP already works. `EnemyAI._choose_skill`
already filters by `can_use`, so an enemy never picks an HP-cost move it
cannot afford. The AI's "prefer super-effective" check ignores element
overrides; acceptable for now.

## Part 3 — Damage functions

`Character.take_damage` and `take_magic_damage` gain two optional parameters,
defaulting to today's behaviour:

- `pierce: float = 0.0` — subtracts `defense × (1 − pierce)` (or arcane).
- `override_element` / `override_mult` — when the move has an override, the
  pairing `(move's primary element, override_element)` uses `override_mult`
  (1.0 or 2.0) instead of the chart value. Every other pairing — the move's
  secondary element, a dual-typed defender's other element — uses the chart.

Balance limits on the override (authoring rules, recorded in CLAUDE.md): one
element per move; it replaces one pairing, never stacks onto it; and moves that
use it carry lower base power than comparable moves.

## Part 4 — Menus and battle feedback

- **`Skill.cost_parts()`** returns the move's costs as labelled pieces —
  `12 MP` (blue), `15% HP` (red), `25 ✦` (amethyst) — and every menu that shows
  a cost uses it: the battle Attack menu (`AttackMenu.gd`), the Stats-screen
  move cards (`StatsScreen.gd`) and the Loadout screen (`LoadoutScreen.gd`).
  Multiple costs show together (`12 MP · 15% HP`). Greying out needs no new
  code: the Attack menu already greys moves with `can_use`.
- **`Skill.effect_tags()`** generates a short line from the move's options —
  e.g. *2 hits · Ignores ARC · ×1.5 vs afflicted · Lowers your DEF*. It shows
  under the hand-written description wherever descriptions appear. Generated
  from data, it cannot promise what the move does not do.
- **Battle text:** `"miss"` shows "Miss" (distinct from "Dodge"); `"hp_cost"`
  and `"recoil"` show a damage number over the user; the ally heal shows heal
  numbers for the allies it healed; self-debuffs and target buffs show as the existing stat chips.

## Part 5 — The honest fixes

Total strength kept about the same:

| Move | Today | After |
|---|---|---|
| Cyclone (Lyra) | 1 hit × 2.2, all enemies | `hit_count 2`, `power 1.2` — the extra 0.2 offsets the defence being subtracted twice |
| Hydro Pierce (Aria) | 2.5, no pierce | `power 2.4`, `pierce 1.0` (ignores all ARC) |
| Gale Requiem (Lyra) | 3.0 damage only | `power 2.5`, `ally_heal_power 1.0` |
| Frost Bolt (Aria) | 1.5, no slow | `power 1.4`, `status_to_apply "speed_debuff"`, `status_chance 0.4` |
| Restoring Breeze (Lyra) | heal 1.2 once | `power 0.5`, then its existing `regenerate` applies, scaled by the caster's MAG (Ruling 11): `HEAL_REGEN_POWER` 0.25 × MAG per turn for 3 turns, so `0.5 + 3 × 0.25 = 1.25 × MAG` against the old `1.2 × MAG`. The default `max_hp / 8` regen stays for BUFF moves like Iron Will, and a regen never weakens one already running (the larger per-turn amount is kept) |

**Baseline tests.** Spec A's move-library baseline is a migration guard. Each
change above is recorded the documented way: hero moves as `MERGE_DELTAS`
entries (`Aria:1`, `Aria:5`, `Lyra:4`, `Lyra:5`, `Lyra:10`). The hero-pool test
compares the baseline's slots and allows pools to grow. The two enemies that
gain a move (Part 6) have their fixture entries edited by hand in the same
commit. Fields the baseline predates are not compared, so the new options need
no entries.

## Part 6 — New moves

Nine hero moves, one mechanic each, in pool slots 13–15 (indices 12–14).
`PartyFactory.SKILL_UNLOCK_LEVELS` and `SKILL_CATEGORIES` grow by three
entries shared by all heroes: **slot 13 — Attack menu, level 3; slot 14 —
Special, level 9; slot 15 — Special, level 14.** Pools grow from 12 to 15
(`Character.MAX_SKILLS` is 20).

| Hero | Move (file) | Shape | Mechanic |
|---|---|---|---|
| Aria | **Brine Surge** (`brine_surge.tres`) | Water, magic, one enemy, 1.2, 12 MP | `override_element WATER`, `override_super true` — water normally resists water |
| Aria | **Mana Surge** (`mana_surge.tres`) | Water, magic, one enemy, 2.2, 20 MP | `scale_with MP`, more is stronger |
| Aria | **Abyssal Tithe** (`abyssal_tithe.tres`) | Water, magic, all enemies, 2.6, 0 MP | `resonance_cost 30` |
| Kael | **Bloodfire Edge** (`bloodfire_edge.tres`) | Fire, strike, one enemy, 2.7, 0 MP | `hp_cost_percent 12` |
| Kael | **Last Stand** (`last_stand.tres`) | Fire, strike, one enemy, 1.6, 10 MP | `USER_HP_LOW`, `bonus_multiplier 1.75` |
| Kael | **Provoking Blow** (`provoking_blow.tres`) | Fire, strike, one enemy, 2.6, 14 MP | `target_buff "attack"` |
| Lyra | **Opportune Gust** (`opportune_gust.tres`) | Wind, magic, one enemy, 1.4, 10 MP | `TARGET_AFFLICTED`, `bonus_multiplier 1.5` |
| Lyra | **Resonant Gale** (`resonant_gale.tres`) | Wind, magic, one enemy, 2.0, 16 MP | `scale_with RESONANCE`, more is stronger |
| Lyra | **Tempest Gamble** (`tempest_gamble.tres`) | Wind, magic, all enemies, 3.0, 22 MP | `miss_chance 0.3` |

Order in each pool: Brine Surge / Bloodfire Edge / Opportune Gust at slot 13;
Mana Surge / Last Stand / Resonant Gale at 14; Abyssal Tithe / Provoking Blow /
Tempest Gamble at 15.

Two enemy moves cover the mechanics no hero move uses:

| Enemy | Move (file) | Shape | Mechanic |
|---|---|---|---|
| Goblin Spearman | **Reckless Charge** (`reckless_charge.tres`) | Normal, strike, one hero, 1.6 | `recoil_percent 25` |
| Goblin Warlord | **Overreach** (`overreach.tres`) | Normal, strike, one hero, 2.0 | `self_debuff "defense"` — an opening for the player |

The Spearman appends Reckless Charge to its moves (the Warlord also summons
Spearmen, so it appears in the boss fight). Overreach joins the Warlord's base
moves; his fury-phase moveset is unchanged.

Hand-written descriptions for every new move are part of each file and must
match its mechanic.

The library grows from 86 to 97 files.

## Part 7 — Saves

- **New fields are saved.** `SaveSerializer.serialize_skill` /
  `deserialize_skill` carry every Part 1 field, read with its default when
  absent, so the snapshot fallback still rebuilds a move whose file is gone.
- **Pools are topped up on load.** Saves keep a hero's pool exactly as saved, so
  without this today's 12-move saves would never get the new moves.
  `PartyFactory.top_up_pool(hero)` appends, at the end of the pool, a copy of
  every move in that hero's factory pool the save lacks (matched by
  `source_path`, falling back to `skill_name`), stamped with that move's own
  slot's unlock level and category. `GameManager.load_from_slot` calls it after
  `SaveSerializer.deserialize_party` and then `auto_equip_unslotted()`.
  `SaveSerializer` stays free of any `PartyFactory` dependency, as the save
  design requires. An unknown hero name is left alone. This also covers any
  future pool growth.

## Part 8 — Testing

Each mechanic gets a direct test through `resolve_skill`, with HP, dodge
(`dodge_chance` meta 0 or 1) and miss chance pinned so results are
deterministic:

- Costs: HP and resonance paid; greyed out (`can_use` false) when unaffordable;
  HP cost never KOs; enemies pay HP and ignore MP/resonance; resonance-cost
  moves build no resonance.
- Hits: two hits land two results; resonance once per action; "took damage"
  once per target; a target killed by hit 1 takes no hit 2; the rider rolls
  once per target.
- Pierce: damage with `pierce 1.0` equals damage against zero defence.
- Ally heal: every living ally on the user's side healed, never the other side.
- Conditions: afflicted vs clean target; user above and below 30% HP.
- Override: effective and super-effective against the named element; a
  dual-typed defender's other element still applies; no effect when unset.
- Scaling: both ends (0.75× and 1.5×) and both directions; measured before
  costs; an enemy's missing pool gives 1×.
- Trade-offs: self-debuff once; recoil share and never below 1 HP; miss chance
  0/1 on opponents, ignored on allies; target buff only on targets hit.
- Order: rider and target buff after the hits; heal, recoil, self-debuff after
  all targets.
- Heal moves apply their token (Restoring Breeze regenerates for 0.25 × the
  caster's MAG per turn, about its old total; Iron Will keeps `max_hp / 8`; a
  running regen is never weakened); a full-HP ally gets no heal result.
- `cost_parts()` and `effect_tags()` for representative moves; an unknown stat
  name warns and does nothing.
- Saves: every new field round-trips; a 12-move hero pool loads as 15 with the
  right unlock levels and categories; top-up is a no-op on a full pool.
- Baseline: the five honest fixes are recorded deltas; everything else in the
  library is unchanged.
- Tests elsewhere that pin a hero pool at 12 moves (party factory, moveset,
  skill learning, stats screen) move to 15; that is the deliberate pool growth,
  not a regression.

## Review focus

1. **Multi-hit and defeat**: a target dying mid-sequence must not be hit again,
   handled twice, or counted toward recoil.
2. **"Can't KO" everywhere**: the HP cost and recoil both stop at 1 HP, on both
   sides.
3. **Measuring before paying**: scaling and the low-HP condition read the
   user's pools before costs are paid.
4. **Old saves**: a pre-Spec-B save gains its three moves with the right unlock
   levels, and its loadout stays valid.
5. **Nothing writes to a `Skill` at runtime** — all per-use state lives on the
   `Character` or in `BattleManager`.
