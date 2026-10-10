# Multi-Turn Moves — Design (Spec C)

**Status:** approved in chat, awaiting written review
**Track:** B (systems breadth), item 3 — part C of three
**Date:** 2026-10-10
**Builds on:** Spec A (`2026-09-26-move-library-and-unified-resolver-design.md`) and
Spec B (`2026-10-03-skill-mechanics-design.md`)

## Intent

Moves that play out over more than one turn. Spec A put every move in its own
file and every skill through one resolver; Spec B added plain move options and
paced the resolver into visible beats. Spec C adds four multi-turn shapes, each
a plain option on a move, shown off by new hero and enemy moves:

1. **Charge-up** — gather power for a turn, release a big hit on the next.
2. **Delayed strike** — cast now, land at the end of a later round.
3. **Recharge** — a huge move now, then the user rests a turn.
4. **Timed buffs / debuffs** — they wear off after a few turns.

The user expects more multi-turn shapes later, so the design has one place a
future "fire later" shape plugs into (the scheduled-move list) and one pattern
for future per-character countdowns.

### Decisions made with the user

| Topic | Decision |
|---|---|
| Shapes | All four above. More may follow later — keep it extensible. |
| Where they appear | **New hero moves** and **enemy / boss moves**. No existing move changes. |
| Architecture | **Approach A**: one scheduled-move list in BattleManager (charge-ups and delayed strikes) plus per-character countdowns (recharge, timed stats). Not a generic effect framework; not statuses. |
| Charge interrupt | **Turn-skipping statuses** (stun, sleep, a paralysis skip) break a charge. Same for heroes and enemies. |
| Charge release | **Automatic** on the charger's next turn — no menu, no AI decision. |
| Charge feedback | A banner when charging starts. **No "Charging" chip.** Enemies show the move name under their card as usual. |
| Delayed strike feedback | **No indicator, no countdown.** It lands at the **end of the round** (after every hero and enemy has acted): banner text announcing it → pause → damage → the action pause → next turn. |
| Delayed strike counterplay | **Cannot be prevented** — not by downing the caster, not by anything. When it lands it **can miss or be dodged** like any attack. |
| Timed chips | The ordinary stat chip, **no number, no banner** — it just disappears. |
| Recharge | The next turn is skipped with a banner ("Kael is recovering!"), like a stun skip. |

### Success criteria

- Each of the four shapes works for heroes and enemies, through the one resolver.
- Every new option defaults to "off": every existing move behaves exactly as
  before, and existing buffs/debuffs still last the whole battle.
- A charging boss can be stunned out of its attack; a delayed strike lands even
  after its caster falls.
- Hero pools grow to 18; the four enemy moves are in play (the Warlord's in his
  final phase).
- Every multi-turn sequence is unit-tested synchronously — including the enemy
  turn loop, which cannot be tested today.
- An older save loads with the new moves added and its loadout untouched.

### Non-goals

- Changing any existing move, or making existing buffs timed.
- A visible countdown for delayed strikes or timed effects.
- Channelled moves, counters/stances, or anything else not listed above.
- Saving mid-battle state (charges, delayed strikes and countdowns are battle-only).

## Part 1 — The move options

Plain fields on `Skill`, grouped in the Inspector, all defaulting to "off".
Read-only at runtime, like every Spec B option (enemies share the library's
cached `Skill` objects).

| Field | Default | Meaning |
|---|---|---|
| `charge_turns: int` | `0` | `1` = the user spends this turn gathering power and releases on their next turn. |
| `delay_rounds: int` | `0` | `1` = the move lands at the end of the current round; `2` = the end of the next round. |
| `recharge_turns: int` | `0` | After the move is used, the user skips this many of their own turns. |
| `effect_turns: int` | `0` | The stat buffs/debuffs this move applies last this many of the **affected** character's turns. `0` = the rest of the battle (today's behaviour). |

`effect_turns` covers every stat buff/debuff a move applies: a `_buff` /
`_debuff` token (as a STATUS move's effect or a damage move's rider),
`target_buff` and `self_debuff`. It does not touch the six mutex statuses or the
`regenerate` token, which keep their own rules.

A move may combine shapes. A charge-up with `recharge_turns` releases, then
the user rests.

### Generated effect tags

`Skill.effect_tags()` gains, in this order after the Spec B tags:

| Option | Tag |
|---|---|
| `charge_turns = 1` | `Charges 1 turn` |
| `delay_rounds = 1` | `Lands at round end` |
| `delay_rounds = N > 1` | `Lands in N rounds` |
| `recharge_turns = N` | `Rests N turn` / `Rests N turns` |
| `effect_turns = N` (and the move applies a stat buff/debuff) | `Lasts N turns` |

## Part 2 — How it resolves

### The scheduled-move list

`BattleManager` keeps one list of moves that will resolve later. Each entry is
a small inner-class record:

- `user`, `skill`, `chosen` (the targets picked when the move was used)
- `when`: `CASTER_TURN` (a charge-up) or `ROUND_END` (a delayed strike)
- `rounds_left` (delayed strikes)
- `measured`: the cast-time measurements of a delayed strike — the caster's
  `Skill.calculate_value`, `scale_factor`, and HP fraction

A future "fire later" shape is a new `when`.

### Using a move — `resolve_skill`

The resolver splits into **use** and **strike**:

1. **Check** `can_use` (unchanged).
2. **Charge-up** (`charge_turns > 0`): pay the costs, add a `CASTER_TURN` entry,
   emit the "gathering power" banner. Nothing else happens this turn.
3. **Delayed strike** (`delay_rounds > 0`): measure, pay the costs, add a
   `ROUND_END` entry with `rounds_left = delay_rounds`. **Nothing visible
   happens.** If the move has `recharge_turns`, the rest starts now (the cast is
   the effort).
4. **Otherwise**: measure, pay, and **strike** now — Spec B's paced beats,
   per-target effects and after-action effects, unchanged.
5. **Recharge**: after a strike (an immediate one or a charge release), the user
   gets `recharge_turns_left = recharge_turns`.

**Strike** is today's beat loop taking already-measured values. It is what a
charge release and a delayed landing call.

### Charge-up release

On the charger's next turn, after the skip check (Part 3):

- **Targets**: the `chosen` target; if it has fallen, a random living character
  on the same side. An area move hits whoever stands.
- **Measured at release** (the charger is acting now), so an ally's ATK buff on a
  charging Kael makes the release hit harder.
- **Costs are not paid again** and `can_use` is not re-checked.
- A charger who is **downed** loses the entry.

### Delayed strike landing

At the **end of the round** — after the last actor of the round, before the next
round's turn order is built — each due `ROUND_END` entry lands, one at a time,
**in the order cast**:

1. `rounds_left` counts down; at 0 the entry lands and leaves the list.
2. If nobody is standing on the target side, nothing happens.
3. Banner: **"<Move> strikes!"** (e.g. "Deluge strikes!"), then a pause.
4. **Strike** with the cast-time `measured` values (the caster's strength is
   fixed when cast; the target's defence, element and dodge are checked now).
   Miss and dodge roll as for any attack aimed at the opponents. A single target
   that has fallen is replaced by a random living one on its side.
5. If the **caster is down**, only the hits land: no ally heal, recoil,
   self-debuff, or resonance.
6. The action pause, then the battle-end check. If the battle ended, any later
   entries are dropped.

### Timed buffs and debuffs

`Character.apply_buff(stat, turns := 0)` and `apply_debuff(stat, turns := 0)`
gain an optional duration. Each character keeps a countdown per timed stat
(battle-only, cleared by `clear_battle_effects`, never saved):

- **Counting**: the affected character's own turns. A 3-turn buff is active for
  their next 3 turns (the turn it was applied in does not count) and is gone
  when their 4th turn begins. A skipped turn still counts.
- **Permanent wins**: a permanent buff on a timed-buffed stat makes it
  permanent; a timed buff on a permanently buffed stat changes nothing.
- **Refresh**: a timed buff on an already timed-buffed stat keeps the longer
  of the two remaining durations.
- **Cancelling** is unchanged: a debuff on a buffed stat (or the reverse)
  cancels it, and the cancelled side's countdown goes with it.
- Stats still never stack — a stat is buffed or not.
- An expiry emits a quiet event so the chips refresh, **with no banner**.

### Recharge

`Character.recharge_turns_left` (battle-only). See the turn order below.

### Resonance

A charge-up grants its skill resonance on its release's first landed hit; a
delayed strike on its landing's first landed hit, and only if the caster is
standing. "Took damage" resonance is unchanged.

## Part 3 — The turn

### Start of an actor's turn (`_next_turn`)

Steps marked **new**; the rest is today's order.

1. Boss phase check, skip the downed, boss field effect, clear defend.
2. Status damage and regen.
3. **New — timed stats count down**; expired ones are removed.
4. `turn_started`.
5. **New — recharging?** `recharge_turns_left` counts down and the turn is
   skipped with **"<Name> is recovering!"**. `StatusSystem.resolve_turn_skip`
   still runs on this turn, so a stun is used up by it and a sleep counter
   advances — one skipped turn, not two.
6. Status skip / wake (today's). If the turn is skipped **and the actor has a
   charge-up**, the entry is dropped and **"<Name>'s focus was broken!"** plays
   first, then the skip banner. A sleeper who wakes and acts keeps their charge.
7. **New — charging?** The charge releases (Part 2): no menu for a hero, no AI
   choice for an enemy (an enemy shows the move name under its card first). The
   manager is `EXECUTING_ACTION` throughout, so the action menu stays hidden.
   Then the action pause and the next turn.
8. Otherwise `turn_ready_for_action`, as today.

### End of the round

When the last actor of the round has finished: land due delayed strikes
(Part 2), then build the next round's turn order.

### Pacing

Spec B's pauses become one switch. `BattleManager.paced` (false on a bare
manager; `BattleScene` sets it true) makes `_pause(seconds)` wait; unpaced, it
returns at once. **Every** wait in the turn loop goes through it — the new
banners and the existing hard-coded ones:

| Constant | Seconds | Used for |
|---|---|---|
| `HIT_PAUSE` | 0.8 | between beats (Spec B) |
| `ACTION_PAUSE` | 1.0 | after every action and every delayed landing (Spec B) |
| `THINK_PAUSE` | 0.4 | an enemy's turn before it shows its move (today's 0.4) |
| `PREVIEW_PAUSE` | 1.0 | an enemy's move name under its card (today's 1.0) |
| `WAKE_PAUSE` | 1.75 | the wake-up banner (today's 1.75) |
| `SKIP_PAUSE` | 1.9 | skip banners, including "recovering" (today's 1.9) |
| `BANNER_PAUSE` | 1.75 | "gathering power", "focus broken", "<Move> strikes!" |

The real game's timings do not change. Tests drive whole multi-turn sequences —
enemy turns included — synchronously. Spec B's `hit_pause` / `action_pause`
variables are replaced by the switch.

### Banners

The new banners go through `status_effect_triggered` like stun and sleep, with
new event types (`charging`, `focus_broken`, `recharging`, `strike_landing`)
and `BattleScene` phrasing them. "Recovering" is a skip banner (the action menu
gating already treats skips).

Starting a charge and casting a delayed strike spend costs without a hit, and
the panels only refresh on events. Starting a charge refreshes through its
banner event; casting a delayed strike emits a quiet `strike_scheduled` event
(no banner, no text) so the spent MP shows — nothing about the strike itself
is shown.

## Part 4 — The moves

### Heroes — pool slots 16–18

Pools grow from 15 to 18 (`MAX_SKILLS` is 20). New slots, the same for all three
heroes: unlock levels **6, 11, 16**; categories **ATTACK, SPECIAL, SPECIAL**.

| Hero | Slot | Move (`file`) | Shape | Data |
|---|---|---|---|---|
| Aria | 16 | **Undertow** (`undertow.tres`) | Timed debuff | Water, magic, one enemy, power 1.4, 12 MP; `defense_debuff` at 100%, `effect_turns 3` |
| Aria | 17 | **Deluge** (`deluge.tres`) | Delayed | Water, magic, all enemies, power 3.4, 28 MP; `delay_rounds 2` |
| Aria | 18 | **Tsunami** (`tsunami.tres`) | Charge-up | Water, magic, all enemies, power 5.5, 40 MP; `charge_turns 1` |
| Kael | 16 | **Sunforge Strike** (`sunforge_strike.tres`) | Charge-up | Fire, strike, one enemy, power 4.0, 14 MP; `charge_turns 1` |
| Kael | 17 | **Searing Brand** (`searing_brand.tres`) | Timed debuff | Fire, strike, one enemy, power 1.8, 12 MP; `attack_debuff` at 100%, `effect_turns 3` |
| Kael | 18 | **Eruption** (`eruption.tres`) | Recharge | Fire, strike, all enemies, power 5.0, 35 MP; `recharge_turns 1` |
| Lyra | 16 | **Gathering Squall** (`gathering_squall.tres`) | Delayed | Wind, magic, one enemy, power 2.0, 10 MP; `delay_rounds 1` |
| Lyra | 17 | **Windrunner's Blessing** (`windrunners_blessing.tres`) | Timed buff | Wind, STATUS buff, all allies, `speed_buff`, 8 MP; `effect_turns 3` |
| Lyra | 18 | **Dawnsong** (`dawnsong.tres`) | Recharge | Light, STATUS heal, all allies, power 3.0, 30 MP; `recharge_turns 1` |

Balance, against existing moves of similar cost or role: charge-ups and
recharges ~1.4–2× an instant equivalent (they cost a turn, and a charge can be
broken) — Tsunami 5.5 vs Tidal Requiem 3.5 (40 MP), Sunforge 4.0 vs Molten
Blade 2.8, Eruption 5.0 vs Phoenix Fury 4.0 (45 MP), Dawnsong 3.0 vs Grand Mend
1.5 (30 MP). Delayed strikes get a smaller bonus — Deluge 3.4 vs Maelstrom 3.0
(35 MP); Gathering Squall 2.0 vs Resonant Gale 2.0 (16 MP). Timed effects are
cheaper or more certain than their permanent cousins — Windrunner's Blessing
8 MP vs Tailwind 22 MP; Undertow / Searing Brand land 100% vs Guard Crush's 45%.

### Enemies

| Enemy | Move (`file`) | Shape | Data |
|---|---|---|---|
| Goblin Warlord | **Earthsplitter** (`earthsplitter.tres`) | Charge-up | Normal, strike, whole party, power 2.6; `charge_turns 1`. Added to his **final phase's** moveset (the phase with Ruinous Sweep and Executioner's Drop). |
| Void Shade | **Doom Sigil** (`doom_sigil.tres`) | Delayed | Psychic, magic, one hero, power 2.4; `delay_rounds 2` |
| Earth Golem | **Tectonic Slam** (`tectonic_slam.tres`) | Recharge | Earth, strike, whole party, power 1.8; `recharge_turns 1` |
| Dark Wraith | **Withering Hex** (`withering_hex.tres`) | Timed debuff | Dark, magic, whole party, power 0.6; `attack_debuff` at 100%, `effect_turns 3` |

Enemies choose these like any other move (`EnemyAI` needs no change). The
three base-moveset additions and the Warlord's phase addition are recorded in
`tests/fixtures/move_library_baseline.json` by appending entries, as Spec B did.

## Part 5 — Saves

- `SaveSerializer` writes and reads the four new options, defaulting to "off".
- Charges, delayed strikes, recharge and timed countdowns are battle-only and
  never saved.
- `PartyFactory.POOLS`, `SKILL_UNLOCK_LEVELS` and `SKILL_CATEGORIES` grow to 18;
  `top_up_party` (Spec B) adds the three new moves to an older save's heroes on
  load, without touching the loadout.

## Part 6 — Edge cases

- A charger downed before releasing loses the charge.
- The battle ending, or the party fleeing, drops every scheduled entry and
  clears every countdown (`clear_battle_effects` and a fresh list per battle).
- A delayed strike whose side has nobody standing does nothing.
- A landing that downs the last enemy or hero ends the battle after the action
  pause; later due entries are dropped.
- A landing that pushes a boss past a threshold changes phase at the start of
  the next turn, as for any damage.
- An area delayed strike hits whoever stands when it lands, summons included.
- Paralysis breaks a charge only on a turn it actually skips (its 25% roll);
  poison, scorched and frostbite do not.
- A recharging actor who is also stunned or asleep loses one turn for both.

## Part 7 — Testing

One new suite, **`test_multi_turn.gd`** (registered; `.uid` committed), plus
additions to `test_skill_options`, `test_save_serializer`, `test_party_factory`,
`test_move_library`, `test_skill_learning`, `test_moveset` and
`test_status_system`. All synchronous (the manager unpaced).

- **Options**: defaults off; effect tags.
- **Charge-up**: costs paid on charging; nothing hits that turn; the release on
  the next turn hits; release measured at release; a fallen target is replaced;
  stun, sleep and a paralysis skip break the charge (with the banner event);
  a woken sleeper keeps it; a downed charger loses it; an enemy charge breaks the
  same way (through the real enemy turn loop).
- **Delayed strike**: nothing visible on cast; lands at the end of the round
  `delay_rounds` rounds later; in cast order; can miss and be dodged; lands after
  the caster falls with only its hits; cast-time strength; a fallen single
  target is replaced; nothing on an empty side; a landing that ends the battle
  drops later entries.
- **Recharge**: the next turn is skipped with the banner event; a stun is used
  up on the same turn; charge + recharge releases, then rests.
- **Timed stats**: the expiry turn; permanent wins; refresh keeps the longer;
  cancelling clears the countdown; existing moves stay permanent; an expiry
  emits the quiet refresh event.
- **Pacing**: a bare manager is unpaced; every turn-loop wait goes through
  `_pause`.
- **Data**: the nine hero moves in slots 16–18; the four enemy moves wired
  (the Warlord's in his final phase); pools 18 (8 attacks, 10 specials).
- **Saves**: the four options round-trip; an older save gets the new moves.
- Before hand-off, a probe battle checks the banners and pacing in a window.

## Review focus

1. **An enemy's charge through the real turn loop** — the enemy turn awaits
   timers today and has never been unit-tested; a release that skips the AI must
   not also run the AI's own action (two actions in one turn).
2. **A delayed strike that ends the battle** mid-way through several due
   landings — later landings must not run against a finished battle (rewards
   computed twice, a second victory screen).
3. **Fleeing with a delayed strike scheduled** — nothing may land in the next
   battle or in the overworld.
4. **Timed and permanent on the same stat**, applied in both orders and
   cancelled by the opposite effect — the chip must match the multiplier.
5. **A recharging hero whose next turn is also a sleep turn** — exactly one
   turn lost, and the sleep counter still advances.
