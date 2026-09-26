# Move Library + Unified Skill Resolver — Design (Spec A)

**Status:** approved in chat, awaiting written review
**Track:** B (systems breadth), item 3 — part A of three
**Date:** 2026-09-26

## Intent

Two foundations for the new skill mechanics the user asked for, built before
any of those mechanics so they land once, in the right place:

1. **Every move is its own file**, so one move can be given to any number of
   heroes and enemies. The user's stated goal: "the moves [should] be in their
   own files so that multiple enemies or heroes can have the same move."
2. **One skill resolver for both sides.** Hero and enemy skills currently
   resolve through two near-identical ~50-line functions that have already
   drifted apart, and the drift has produced a live bug (below). Every new
   mechanic in Spec B would otherwise have to be written twice.

This spec adds **no new skill mechanics**. After it lands the game plays
exactly as before except that enemy area attacks work.

### Decomposition

| Spec | Contents |
|---|---|
| **A (this)** | Move library, per-hero copies, save-by-reference, unified resolver, the enemy-AoE fix |
| B | New mechanics: HP/resonance costs, multi-hit, pierce, damage+heal, conditional power, self trade-offs, and the four "honest skill" fixes — authored in the library files |
| C | Multi-turn effects (charge-up / delayed skills) — needs state that survives across turns |

### Success criteria

- Every hero and enemy move lives in `data/skills/`; none are inline in an
  enemy `.tres` and none are built in code.
- Aria and Lyra share **one** `mend.tres` and **one** `grand_mend.tres`, each
  learning them at their own level, with no interference.
- Editing a move file changes that move in **existing saves**, not only new
  games.
- A save never breaks because a move file was renamed or deleted.
- An enemy's area attack hits the whole party.
- The existing 2498 tests stay green.

### Non-goals

- **Any new skill mechanic.** That is Spec B.
- **A `SkillSlot` wrapper type.** Considered and rejected — see Part 1.
- **Changing basic attacks.** `player_attack` and the enemy's no-skill attack
  are not skills and keep their current paths.
- **Rebalancing.** The AoE fix raises difficulty; tuning in response is
  separate work.

## The bug this fixes

**Every enemy area attack in the game hits exactly one hero.** Expanding
`TargetType.ALL_ENEMIES` into a full target list exists only in
`AttackMenu.gd` — the player's menu. `BattleManager._execute_enemy_turn`
always calls `enemy_use_skill(enemy, skill, [target])` with one target, and
`enemy_use_skill` expands nothing except `SELF`.

Nine enemies have area skills this silently shrinks: dark wraith, earth golem,
fire drake, sea serpent, storm eagle, light golem, wind sprite, void shade and
the Goblin Warlord.

**This is a deliberate difficulty increase.** Those encounters have been
balanced, by accident, around area attacks hitting one hero. The user accepted
the change.

## Part 1 — The move library

### Layout

- One `.tres` per move, **flat** in `data/skills/`, named in snake_case after
  the move: `data/skills/cyclone.tres`.
- Flat rather than split into `hero/` and `enemy/` because sharing across
  heroes *and* enemies is the point; a split would work against it.
- **85 files**: 51 enemy moves (all names already distinct) and 34 hero moves
  (36 definitions, less the merged Mend and Grand Mend).
- If a hero move and an enemy move share a name but differ in data, both keep
  a file and the enemy's gains an owner prefix (`void_shade_null_strike.tres`).
  Identical definitions collapse to one file.
- The existing `Skill_blizzard.tres` is renamed `blizzard.tres`; its two
  references (ice golem, frost wyrm) are updated.

### Per-hero data: copies, not a wrapper

`unlock_level` and `category` are **per hero**, not per move. Aria learns Mend
at level 7 as an attack; Lyra learns it at level 1. They are stamped onto the
`Skill` by `PartyFactory._apply_skill_tables`.

A shared file is shared **by reference**. If both heroes held the same
`mend.tres` object, whichever hero was built second would overwrite the
first's unlock level for both.

**Resolution: each hero receives its own `.duplicate()` of the file**, and the
per-hero fields are stamped on that copy. The file is the single definition of
what the move does; each runtime object belongs to one hero.

**Why not a `SkillSlot` wrapper** holding `{skill, unlock_level, category}`:
it would change the type of every character's pool, and **7 scripts and 8 test
files** read that pool as `Skill` objects, as do `Character`'s own loadout
methods (`equipped_skill` and friends). A large ripple for no player-visible
difference. The copy approach changes **no consumer**.

### `Skill.source_path`

A duplicated resource loses its `resource_path`, so the copy must remember
where it came from:

```gdscript
## The library file this move was loaded from ("" for a move with no file).
## Set when a hero's copy is made; read by SaveSerializer to save the move by
## reference, so an edited move file reaches existing saves.
@export var source_path: String = ""
```

### Mend and Grand Mend merge

Today they are two different moves with the same name — Aria's are Light,
Lyra's are Wind. For a heal, element is cosmetic: it sets the icon and colour
and does not change the amount healed. The user chose to merge them into one
**Light** `mend.tres` and one **Light** `grand_mend.tres`. Lyra's heals will
show a Light icon; nothing about their numbers changes.

### PartyFactory

- `_make_skill` and `_make_status_skill` are removed.
- Each hero's pool is built by loading library files in pool order and taking
  a copy of each:

```gdscript
static func _move(path: String) -> Skill:
	var template: Skill = load(path)
	var copy: Skill = template.duplicate(true)
	copy.source_path = path
	return copy
```

- `_apply_skill_tables` is unchanged — it now stamps each hero's own copies.
- **Pool order must be preserved exactly.** `equipped_attacks` and
  `equipped_specials` store indices into the pool, and
  `SKILL_UNLOCK_LEVELS` / `SKILL_CATEGORIES` are positional.

### Enemies

Each enemy `.tres` replaces its inline `[sub_resource]` skills with
`[ext_resource]` references to library files, the pattern `blizzard.tres`
already uses. Enemies need no per-enemy fields on a move, so they reference
the files directly. Battle copies are already `.duplicate(true)`'d per fight,
so nothing at runtime can write back to a file.

## Part 2 — The unified resolver

### Signature

```gdscript
func resolve_skill(user: Character, skill: Skill, targets: Array[Character]) -> void
```

`player_use_skill` and `enemy_use_skill` become thin wrappers:

- `player_use_skill` keeps its `state` check, calls `resolve_skill`, then
  `end_player_turn()`.
- `enemy_use_skill` just calls `resolve_skill`.

### Steps, in order

1. **`skill.can_use(user)`** — return if false.
2. **Expand targets by `target_type`, relative to the user's side:**

   | `target_type` | Hero user | Enemy user |
   |---|---|---|
   | `SINGLE_ENEMY` / `SINGLE_ALLY` | the passed target | the passed target |
   | `ALL_ENEMIES` | every living enemy | **every living hero** |
   | `ALL_ALLIES` | every living hero | every living enemy |
   | `SELF` | `[user]` | `[user]` |

   "Enemies" and "allies" mean *the user's* opponents and allies. Helpers
   `_opponents_of(user)` and `_allies_of(user)` decide side by membership in
   `party` / `enemies`. **This is the AoE fix**, and it is the only place
   target expansion happens. `SELF` now works for heroes too — previously only
   the enemy path supported it.
3. **Pay the cost** — `user.use_mp(skill.mp_cost)`. Enemies pay nothing,
   unchanged: `Skill.can_use` already exempts them and `use_mp` must not be
   called for them.
4. **For each target:** skip if downed → **dodge roll** → value → damage or
   status effect → rider → emit `action_performed` → `handle_defeat` if downed.

### Dodge moves inside, per target

Today the enemy turn rolls **one** dodge *before* calling the skill
(`_execute_enemy_turn`), so an area attack shared a single roll, while the
player side rolls per target inside its resolver. The resolver rolls
`EnemyAI.try_dodge(target)` **per target**, for both sides.

**The outer dodge roll in `_execute_enemy_turn` must be removed for skills**,
or every enemy skill rolls dodge twice. The enemy's basic attack (no skill)
keeps its existing outer roll.

### Action names

The action name is not cosmetic. For **heroes**, `BattleScene` routes
`"attack"` to `resonance_system.on_attack` and `"skill_physical"` /
`"skill_magic"` to `on_skill_used`, which grant **different** resonance.

Today the enemy side emits `"attack"` for a strike skill and the player side
emits `"skill_physical"`. The resolver emits **`"skill_physical"` for
`STRIKE`/`RANGED` and `"skill_magic"` for `MAGIC` on both sides**. This is:

- **required** for heroes — `"attack"` would change their resonance gain;
- **safe** for enemies — damage numbers and `on_damage_taken` accept all three
  names, and the resonance hook skips non-heroes.

Status results keep `"heal"`, `"buff"`, `"debuff"` and `"dodge"`.

### Resonance: once per action

`BattleScene` grants skill resonance only when `result["is_first_target"]` is
true, so an area attack does not multiply it. The resolver sets
`is_first_target` true on **the first emission of the action only**. Spec B's
multi-hit depends on this staying true across hits.

## Part 3 — Saves

### Format

A hero's pool is saved as an array of the **existing** `serialize_skill`
dictionaries — which already carry every move field plus `unlock_level` and
`category` — with **one key added**:

```json
{"source_path": "res://data/skills/cyclone.tres", "skill_name": "Cyclone",
 "power": 2.2, "unlock_level": 10, "category": 1, "...": "..."}
```

The dictionary *is* the snapshot. No separate wrapper.

### Loading each pool entry

1. `source_path` non-empty **and** `ResourceLoader.exists(source_path)` →
   load the file, `duplicate(true)`, set `source_path`, then stamp
   `unlock_level` and `category` **from the saved dictionary**. The move's
   behaviour comes from the file (current balance); when this hero learns it
   comes from the save.
2. Otherwise → `deserialize_skill(dict)`, exactly as today. **A missing file
   never breaks a save.**

### Saves made before this change

They have no `source_path`. Each entry is **re-linked by `skill_name`** to the
library file whose move has that name, then loaded as in step 1 — so the
user's existing saves pick up new balance too. This is what lands Lyra's old
Wind Mend on the shared Light `mend.tres`. No name match → snapshot.

The name index is built once per load from the library files, not per entry.

### Order

Entries load **in saved order**. `equipped_attacks` / `equipped_specials` are
indices into this array; reordering it would silently re-equip different
moves.

Enemies are battle-temp and never serialized; unaffected.

## Migration

Hand-editing 14 enemy files and moving 36 hero definitions is where a silent
break hides — a wrong path fails at load, a wrong field fails as wrong
behaviour. So:

- **Generate** the library files with a one-off script
  (`tools/extract_move_library.gd`, headless), which reads every current move
  from the live data and code and writes it out. Do not hand-write 85 files.
- **Verify** after generation: every enemy `.tres` loads; every move it
  references resolves; every hero's pool loads with the same names, in the
  same order, with the same per-move data as before the migration. The
  comparison is automated, not eyeballed.
- The extraction script is committed alongside, so the migration can be
  re-run or audited.

## Testing

A new suite `tests/suites/test_move_library.gd`, plus additions to existing
suites where the behaviour belongs:

**Library**
- Every hero move and every enemy move resolves to a file in `data/skills/`.
  No enemy `.tres` still holds an inline skill sub-resource.
- Every file in `data/skills/` loads as a `Skill`.
- **The motivating regression:** Aria and Lyra both hold Mend, with different
  unlock levels (7 and 1); changing one hero's copy changes neither the other
  hero's nor the file.
- Every hero pool matches its pre-migration snapshot: same names, same order,
  same power / cost / element / type / target / rider.

**Saves**
- Round-trip by reference: `source_path` survives, and the loaded move comes
  from the file.
- An edited file reaches an existing save: save, change the move's `power` in
  memory on the template, load, see the new value. **The test must restore
  the original `power` afterwards** — `load()` returns Godot's *cached*
  instance, so an unrestored edit leaks into every later test that loads the
  same move, creating a silent dependency on test order.
- A save whose `source_path` no longer exists loads from its snapshot.
- A legacy save with no `source_path` re-links by name.
- A legacy save whose name matches nothing loads from its snapshot.
- Pool order is preserved and the equipped loadout still points at the same
  moves.

**Resolver**
- **An enemy area attack hits every living hero.**
- A hero area attack hits every living enemy (unchanged).
- `SELF` targets the user, for a hero and for an enemy.
- `ALL_ALLIES` from an enemy targets its fellow enemies, not the party.
- Dodge is rolled per target, and an enemy skill is not dodge-rolled twice.
- A hero's strike skill emits `"skill_physical"`, never `"attack"`.
- Resonance is granted once per action (`is_first_target` true exactly once).
- Enemies never pay MP.
- Downed targets are skipped.

## Risks

- **The migration.** Every enemy file changes. Mitigated by generating, then
  verifying against a pre-migration snapshot, in tests.
- **The difficulty jump** from the AoE fix. Accepted; tuning is separate.
- **Saves referencing moved or renamed files.** Mitigated by the snapshot
  fallback; a save degrades to frozen balance rather than failing.
- **A move file edited into an invalid state** now affects every hero and
  enemy using it, and every existing save. That is the intended trade for
  single-point editing; the "every file loads" test guards the invalid case.
- **Renaming `Skill_blizzard.tres` is not a plain file rename.** Its two
  referencing `ext_resource` lines carry both a `uid` and a `path`, and uids
  resolve through `.godot`'s uid cache, which goes stale when a file is moved
  outside the editor. Update both references' `path`, keep the file's own
  `uid`, then run the headless editor rescan
  (`--headless --editor --quit-after 3`) before trusting the result. The
  generated library files get fresh uids the same way.
- **Class cache.** No new `class_name` is introduced, so no rescan is needed
  for that reason — but see the rename above.
