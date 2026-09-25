# The Amethyst Requiem — Project Context for Claude Code

## Project Overview
**The Amethyst Requiem** — a turn-based JRPG built in **Godot 4 (GDScript)**, in active
development. Working title's payoff is the **AMETHYST** element + a triple-hero
"Amethyst Requiem" resonance (see ElementalSystem / ResonanceMenu).

**Completed (P1–P7 part 1, all merged to `main`):** core turn-based battle, 16-element
system with dual-typing, status effects (mutex + buff/debuff), 3-slot save system with
full serialization, auto-save on town entry, a heavily-themed amethyst battle UI, the
pause-menu Stats/Items/Equipment screens, a full Settings screen (audio/display/
performance/difficulty/input remapping) with complete keyboard+controller navigation,
a proper defeat→load game-over, and **visible roaming overworld enemies** (replacing
old random encounters).

Since then: the wider map set (Forest / Mountain Pass / Goblin Castle) with
map-to-map transitions, town + shop + inn interiors, dialogue **with a choice UI**,
quests, shops, time-of-day, per-device input profiles, 20-move pools with equipped
loadouts, campfire rest areas, and a full controller-navigation pass.

**Next up:** **Track B — systems breadth** (boss fights → status cleansing → new
skill shapes), then Track C hardening, then Track A story progression, with real
art LAST. See **Roadmap** near the bottom for the agreed order and its contents.

> **Aesthetic rule (applies to everything):** anything added to the UI must be
> visually appealing and match the game's amethyst aesthetic. Reuse
> `BattleUITheme` (panels/buttons/fonts/colors) and `HeroPalette` (per-hero
> accents); never ship default-themed Godot controls (plain dropdowns,
> scrollbars, sliders, popups, cursors). Style every new control to fit.

> **Art style (world/map/prop art):** **smooth hand-painted 2D illustration** —
> soft shading, fine clean linework, anti-aliased edges, vibrant saturated colors,
> top-down 3/4 overhead view (polished storybook / mobile-RPG look). **NOT pixel
> art** (an earlier note called it "32-bit pixel" — that was wrong; the actual
> generated maps are painted). Requirement: **individual objects must read clearly**
> — a player should never have to guess what a structure is because it's blurry, so
> generate at high enough resolution that small props (flowers, statues, ornaments)
> keep crisp definition, and downscale in Godot rather than upscaling. Use **Linear**
> texture filtering for this art (Nearest is only for genuine pixel-art assets like
> the time-of-day phase icons). Animated props are baked as sprite-sheet loops
> (SpriteFlow Sprite Motion) in the same painted style; see the animated-prop plan.

---

## Engine & Setup
- **Engine:** Godot 4.6.1 stable (binary on this machine: `/Applications/Godot.app/Contents/MacOS/Godot`)
- **Language:** GDScript
- **Autoload Singleton:** `GameManager` (`res://scripts/GameManager.gd`)
- **Main scenes:** `MainMenu.tscn`, `OverworldScene.tscn`, `BattleScene.tscn`
- **Fonts:** Cinzel-Regular.ttf, Cinzel-Bold.ttf (`res://fonts/`)
- **Run tests headless:** `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/TestRunner.tscn --quit-after 5` (currently **~2408 tests, 40 suites** — count varies slightly with how many save slots exist, since a few SaveSerializer tests skip to protect real saves)
- **Force class-cache rescan** (after adding a new `class_name` file): `… --headless --editor --quit-after 3 --path .`

---

## File Structure
```
scripts/
  GameManager.gd              # Autoload: party, gold, 3-slot saves, species memory, overworld↔battle handoff
  PartyFactory.gd             # Static: builds the default party (Aria/Kael/Lyra) with skills
  PauseMenu.gd                # Esc menu (Resume/Save/Stats/Items/Equipment/Settings/Quit)
  SaveSlotMenu.gd             # 3-slot save/load picker (New Game + Continue flows)
  ui/
    HeroPalette.gd            # class_name HeroPalette — per-hero accent palette (Aria blue / Kael red / Lyra green)
    BattleUITheme.gd          # class_name BattleUITheme — shared amethyst panel/button styles for battle UI
    StatsScreen.gd            # class_name StatsScreen — pause-menu per-hero stats page (P1)
    ItemsScreen.gd            # class_name ItemsScreen — pause-menu Items page, 4 tabs + field-use (P2)
    EquipmentScreen.gd        # class_name EquipmentScreen — pause-menu per-hero equip page, 5 slots (P3)
    SettingsScreen.gd         # class_name SettingsScreen — settings hub (Game/Controls/Audio/Display/Performance) (P4)
    FocusUtil.gd              # class_name FocusUtil — L1/R1 category-cycle detection + held-state queries (P4)
    HoldRepeat.gd             # class_name HoldRepeat — auto-repeat timing for held nav / category cycling
    SaveIndicator.gd          # class_name SaveIndicator — bottom-right auto-save status badge (P5)
  settings/
    SettingsModel.gd          # class_name SettingsModel — audio/display/perf/difficulty/sticks data + config + apply (P4)
    InputMapConfig.gd         # class_name InputMapConfig — named actions, defaults, remap, per-device reset, persistence (P4)
  overworld/
    OverworldScene.gd         # Free-roam controller; roaming-enemy spawner/manager; auto-save; pause host
    Player.gd                 # CharacterBody2D, 8-dir keyboard/controller movement (stick sensitivity)
    RoamingEnemy.gd           # class_name RoamingEnemy — visible overworld enemy: wander+chase in a territory (P7)
    MapArea.gd                # Resource: area metadata + encounter group list + safe_zones (town rects)
    EncounterGroup.gd         # Resource: weighted encounter (pool + count range + level gate)
  save/
    SaveSerializer.gd         # Pure static: Character/Skill/Item/Inventory ↔ Dictionary (full, option 1B)
    AutoSaveSystem.gd         # class_name AutoSaveSystem — pure safe-zone enter detection for auto-save (P5)
  battle/
    BattleScene.gd            # Main battle controller & UI wiring; status banners; hero panel theming
    BattleManager.gd          # Turn logic, state machine, action dispatch, status resolution
    AttackMenu.gd             # Attack/Special skill picker (2x2 grid, themed)
    ResonanceMenu.gd          # Resonance/ultimate picker (auto-grow PanelContainer, element-gradient text)
    ItemsMenu.gd              # In-battle item picker (themed, scrollable)
    StatusChipFactory.gd      # class_name StatusChipFactory — builds status/buff/debuff chips under HP bars
    VictoryScreen.gd          # Post-battle EXP/gold animation + level-up trigger (themed gold card)
    LevelUpScreen.gd          # Stat gain display per hero (hero-colored panels via HeroPalette)
    DefeatScreen.gd           # Continue / Quit Game (themed crimson card)
    TurnOrderIndicator.gd     # Side panel showing upcoming turn order (per-actor tinted slots)
    EnemyAI.gd                # Enemy decision-making + Memory Echo dodge logic
    ResonanceSystem.gd        # Resonance meter management (reads character.resonance_meter directly)
    EnemyCard.gd / HeroCard.gd# (legacy standalone card scripts; battle cards are built inline in BattleScene)
    DamageNumber.gd           # Floating damage number popup
  characters/
    Character.gd              # Base class (Resource) for heroes & enemies
    Enemy.gd                  # Extends Character; drops, EXP/gold rewards, Memory Echo, rarity color/name
    Skill.gd                  # Skill resource: damage/status, attack types, elements, status_to_apply token
    StatusSystem.gd           # class_name StatusSystem — mutex statuses + buff/debuff math + banner phrasing
    ElementalSystem.gd        # Element enum, weakness/resistance tables, colors, icons  (NOTE: in characters/, not systems/)
    Rarity.gd                 # Enemy rarity tiers (COMMON→CELESTIAL), multipliers, colors
  dialogue/
    DialogueManager.gd        # STUB — node dialogue + `choices_presented` signal; no choice UI yet (future P10)
  inventory/
    Inventory.gd              # Per-character item + equipment container (pool + equipped slots + equip/unequip)
    Item.gd                   # Item resource with use() logic + ItemCategory (GENERAL/HEALING/BATTLE/KEY)
    ItemFactory.gd            # class_name ItemFactory — named item defs + create() + roll_drops() (P2)
    Equipment.gd              # class_name Equipment — gear resource: slot/rarity/stat bonuses/class+element restriction (P3)
    EquipmentFactory.gd       # class_name EquipmentFactory — named gear defs + create() + roll_drops() (P3)
scenes/
  BattleScene.tscn
  MainMenu.tscn
  OverworldScene.tscn         # has a MapArea (Fallster Plains) assigned via @export
data/                         # data-driven content (.tres resources)
  enemies/                    # one .tres per enemy (10 enemies; stats + skills)
  skills/                     # shared skill .tres files
  encounters/                 # EncounterGroup .tres files
  maps/                       # MapArea .tres files (fallster_plains.tres)
tests/
  TestRunner.tscn/.gd         # run this scene (F6) to execute all suites; register suites in SUITE_PATHS
  TestSuite.gd                # base class with assert_* helpers
  suites/                     # one test_<feature>.gd per system (24 suites)
assets/  backgrounds/ characters/ enemies/ icons/ ui/
fonts/   music/
```

---

## Core Systems

### Character (Resource) — `scripts/characters/Character.gd`
Base class for all heroes and enemies.
- **Stats:** `base_hp`, `base_mp`, `base_attack`, `base_defense`, `base_magic`,
  `base_arcane` (magic resistance — mirrors `base_defense` but for magic damage),
  `base_speed`.
- **Scaled by level:** `max_hp()`, `max_mp()`, `attack_power()`, `defense_power()`,
  `magic_power()` (magic attack), `arcane_power()` (magic defense), `speed()`.
  **All five power/defense getters route through `StatusSystem.compose_stat()`** so
  buffs/debuffs/status penalties apply automatically.
- **Damage:** `take_damage` subtracts `defense_power()`, `take_magic_damage`
  subtracts `arcane_power()`, then applies the element multiplier. Both accept an
  optional `attack_secondary_element` for dual-typed attackers.
- **Elemental affinity:** `element`, `secondary_element`, `extra_weakness`, `extra_resistance`.
- **Runtime state (persists across battles):** `current_hp`, `current_mp`, `resonance_meter`.
- **Battle-temp state (NOT serialized; cleared at battle end):** `status_effects: Array[String]`,
  `buffs: Dictionary`, `debuffs: Dictionary`, `sleep_turn: int`.
- **Status API:** `add_status(name)` (enforces mutex — see StatusSystem), `remove_status`,
  `is_status`/`has_status`, `apply_buff(stat)`, `apply_debuff(stat)`, `clear_battle_effects()`.
- **MP:** heroes pay MP; **enemies ignore MP entirely** (no MP pool — see Skill.can_use).
- **Leveling:** `gain_experience(amount)` → `true` if leveled; level-up does NOT restore HP/MP.
- Inventory: per-character `Inventory` resource.

### Status Effect System — `scripts/characters/StatusSystem.gd` (`class_name StatusSystem`)
Central registry for the two parallel systems. **All cleared at battle end** and
on run-away (`BattleScene._on_run_pressed` + `_on_battle_ended` both call
`hero.clear_battle_effects()`).

**1) Mutex statuses** — a character can have **at most ONE** at a time. Applying a
new one while any is active is **rejected** (first-come-first-served; was previously
"replace", changed per design). Pool + behavior:
| Status | Tick dmg / turn | Stat penalty | Skip rule | Clears |
|---|---|---|---|---|
| `stun` | — | — | Skip 1 turn | auto after the skip |
| `poison` | 1/10 max HP | — | — | heal / KO |
| `paralysis` | — | SPD ×0.75 | 25% skip each turn | heal only (persists) |
| `sleep` | — | — | skip; wake chance 0%/25%/50%/75%/100% by turn | wakes (acts same turn) / heal |
| `scorched` | 1/20 max HP | ATK ×0.5 | — | heal / KO |
| `frostbite` | 1/20 max HP | MAG ×0.5 | — | heal / KO |
- Non-mutex positive statuses (`regenerate`, `defending`) can coexist with the mutex pool.
  These are transient combat effects, NOT real statuses: defending is a `Character.is_defending`
  bool (halves incoming damage until next turn, `DEFEND_DAMAGE_MULT`); regenerate is
  `Character.start_regen(turns)` (heal-over-time). Neither lives in `status_effects` (not mutex,
  never serialized) — they're kept as named constants only for chip rendering + as the default
  BUFF token. `_apply_skill_status` intercepts the `regenerate` token before `add_status`.
- **`add_status` guards (enforced at the single mutation point):** a defeated character
  (`not is_alive()`) is never afflicted — a killing blow that also inflicts a status leaves the
  downed character clean. **Element immunity** (`StatusSystem.ELEMENT_IMMUNITY` /
  `is_immune_to`): Fire can't be scorched, Metal poisoned, Lightning paralyzed, Ice frostbitten —
  checked against both primary and secondary element.
- Key API: `resolve_turn_skip(character)` → `{skip, woke_up}` (mutates: stun auto-clears,
  sleep counter advances or wakes); `get_tick_damage(character)`; `get_active_mutex_status`;
  `get_status_stat_multiplier`; phrasing helpers `applied_phrase`/`skipped_phrase`/`woke_phrase`
  (stun's skip reads "X reoriented themself").

**2) Buff / Debuff** — per stat (`attack`/`defense`/`magic`/`arcane`/`speed`), **no stacking**:
- **Buff = ×2.0**, **Debuff = ×0.5**. A stat with BOTH cancels to ×1.0 (no chip).
  Applying a buff to a debuffed stat removes the debuff (and vice versa).
- Composes multiplicatively with status penalties. Worked example: Aria MAG 100 +
  Frostbite (×0.5) + MAG debuff (×0.5) = 25; then a MAG buff cancels the debuff →
  100 × 1.0 × 0.5 (Frostbite) = 50.
- `StatusSystem.get_buff_multiplier`, `is_effectively_buffed/debuffed` (for chip rendering).

**Inflicting statuses:** `Skill.status_to_apply` is a token consumed by
`BattleManager._apply_skill_status`. Tokens: a mutex/legacy status name
(`"poison"`, `"regenerate"`), or `"<stat>_buff"` / `"<stat>_debuff"`
(e.g. `"attack_buff"`, `"magic_debuff"`). `StatusSystem.parse_apply_token` routes
it to `add_status` vs `apply_buff`/`apply_debuff`. A mutex status landing emits a
`status_effect_triggered` event with `applied: true` so the UI can banner it.

**UI for statuses:**
- **Chips** (`StatusChipFactory.populate_row`): one mutex-status chip + one chip per
  non-cancelled buffed/debuffed stat, rendered under the resonance bar (heroes) /
  HP bar (enemies). Rebuilt on every action/tick.
- **Banners** (`BattleScene._show_status_banner`): centered fade-in/out overlay on
  a `StatusBannerLayer` CanvasLayer. Fires on: status applied ("X was Poisoned!"),
  skip-turn ("X reoriented themself" / "X is Asleep!" / "X is Paralyzed!"),
  and wake ("X woke up!"). The skip/wake banners gate the action menu — see
  BattleManager turn flow below.

### Skill (Resource) — `scripts/characters/Skill.gd`
- `SkillType`: `DAMAGE`, `STATUS`  (⚠️ refactored — was `DAMAGE/HEAL/BUFF`)
- `StatusType`: `HEAL`, `BUFF`, `DEBUFF` — used when `skill_type == STATUS`
- `AttackType`: `STRIKE`, `RANGED`, `MAGIC`, `STATUS`
- `TargetType`: `SINGLE_ENEMY`, `ALL_ENEMIES`, `SINGLE_ALLY`, `ALL_ALLIES`, `SELF`
- `can_use(user)`: blocked by stun; **enemies bypass MP cost entirely**; heroes need MP.
- `status_to_apply` (token, see above) + `status_chance` (roll for DAMAGE skills).
- `calculate_value`, `is_heal/is_buff/is_debuff`, `is_physical/is_magic`, `get_resonance_gain`
  (default 10.0 for DAMAGE, 0 for STATUS; `resonance_gain_override` ≥ 0 to override).
- `skills` is `@export` on Character. Hero skills: indices 0–3 = attacks, 4–7 = specials.

### ElementalSystem — `scripts/characters/ElementalSystem.gd`
- Elements: `NORMAL, FIRE, WATER, NATURE, ICE, LIGHTNING, EARTH, WIND, SOUND,
  PSYCHIC, SPIRIT, DRAGON, METAL, LIGHT, DARK, AMETHYST`. `NORMAL` replaced `NONE`.
  **AMETHYST** is the signature element — super-effective (`WEAKNESS_MULTIPLIER = 2.0`)
  vs every other element; reserved for the triple-resonance "Amethyst Requiem".
- **Dual-element:** `Character.secondary_element` / `Skill.secondary_element`
  (`NORMAL` = single-typed). Dual enemies: Fire Drake (Fire/Dragon), Storm Eagle
  (Lightning/Wind), Void Shade (Psychic/Spirit), Dark Wraith (Dark/Spirit).
- **Damage formula:** `get_combined_multiplier` **multiplies every pairwise**
  `mult(atk_e, def_e)` across attacker × defender elements. Weaknesses AND
  resistances both stack.
- Multipliers: `WEAKNESS_MULTIPLIER = 2.0`, `RESISTANCE_MULTIPLIER = 0.5`,
  `IMMUNITY_MULTIPLIER = 0.0`. Compare against `WEAKNESS_MULTIPLIER`, not literal 2.0.
- `get_element_name/icon/color`.

### Rarity — `scripts/characters/Rarity.gd`
- Tiers (7): `COMMON, UNCOMMON, RARE, EPIC, MYTHIC, LEGENDARY, CELESTIAL`.
- Colors: Common=grey, Uncommon=green, Rare=blue, Epic=purple, Mythic=red,
  Legendary=gold, Celestial=white/silver. **Enemy card borders use this color.**
- `get_color(tier)`, **`tier_name(tier)`** (⚠️ not `get_name` — that collided with
  a built-in), `get_exp_multiplier`, `get_loot_multiplier`.

### Boss Phases — `scripts/characters/BossPhase.gd`, `Enemy.phases`
- A boss is just an `Enemy` with `phases: Array[BossPhase]` populated.
  `is_boss()` is `not phases.is_empty()` — there is no separate boss flag to
  fall out of sync with the data. A `.tres` alone defines a new boss; no
  per-boss code.
- Each `BossPhase` optionally exercises any of **five powers**, all off by
  default (an omitted field means "this phase does not use that power"):
  1. **Moveset** — `skills`; `[]` keeps the enemy's own list. Served by
     `EnemyAI.usable_skills(enemy)`.
  2. **Stats** — `stat_multipliers`, only the five combat stats
     (`attack`/`defense`/`magic`/`arcane`/`speed`). Composed in `Character`'s
     stat getters alongside `StatusSystem.compose_stat` and
     `combat_stat_multiplier`, so it **stacks**, not overrides. `max_hp` is
     deliberately NOT accepted here — changing it would move the very HP
     thresholds that drive phase transitions (see Transformation below).
  3. **Summons** — `summons: [{"path", "count", "level"}]`, capped at
     `BattleManager.MAX_BATTLE_ENEMIES = 10`, enforced **at summon time**
     (`_summon_from_spec`), not at render time — `_setup_enemy_cards` truncates
     to `mini(enemies.size(), 10)`, so an 11th enemy would otherwise be alive
     with no card and no visible HP.
  4. **Field effects** — `turn_effect` + `turn_effect_chance`, rolled on the
     **boss's own turn** (`apply_boss_field_effect`, called from `_next_turn`
     before the boss picks its action) rather than "each round" — the
     turn-order model has no round boundary to hook. Delegates to
     `_apply_skill_status`, inheriting element immunity, the mutex rule and the
     downed-character guard for free.
  5. **Transformation** — `max_hp_multiplier` + `restore_hp`. The only way to
     change max HP.
- **Advancement is FORWARD-ONLY** (`should_advance_phase()` / `advance_phase()`),
  one step at a time — never recomputed from current HP. Recomputing can't
  express a transformation: refilling HP returns the fraction to 1.0, so a
  recomputing formula would drop the boss back to its opening form. Forward-only
  also makes "a boss never regresses a phase" true by construction.
- **Every crossed phase fires, in order** — `check_boss_phases` loops
  `while should_advance_phase()`, so a hit from 60% to 5% runs both phases'
  entries. Firing only the deepest phase would let burst damage skip a
  transformation entirely.
- A transformation with `restore_hp = true` halts the cascade with **no special
  case** — refilling HP means the next threshold stops being satisfied. One
  with `restore_hp = false` does NOT: max HP grows while current HP stays put,
  so the fraction drops and a later phase can fire in the same cascade. That's
  deliberate, and pinned by a test.
- A dead boss never transitions — no transform, no summon, no banner
  (`check_boss_phases` and `apply_boss_field_effect` both gate on `is_alive()`).
- Phases are checked at **one choke point**, the top of `_next_turn()` — damage
  lands in half a dozen places (player attack, player skill, enemy skill,
  counter...), and hooking there also guarantees a boss never acts in a stale
  phase.
- `EnemyAI`'s hard-coded low-HP enrage now applies to **non-boss enemies only**.
  A boss expresses the same idea through phase data; running both would leave
  two parallel mechanisms for "fights differently when hurt" interacting
  invisibly.
- Turn order is **NOT** re-sorted mid-round when a phase changes `speed` — it
  re-sorts only at `_start_new_round()`. Turn order locked for the round in
  progress is the genre convention, and re-sorting mid-round could give an
  actor two turns or none.
- UI: a boss gets a full-width battle card (`_setup_enemy_cards`); phase entry
  shows `banner_text` via the `boss_phase_changed` signal
  (`_on_boss_phase_changed` in `BattleScene.gd`) — `""` transitions silently.
- **First boss: Goblin Warlord** (`data/enemies/goblin_warlord.tres`) —
  exercises **four** of the five powers (moveset, stats, summons,
  transformation; no phase sets `turn_effect`). Its fixed encounter,
  `data/encounters/goblin_warlord_fight.tres`, is **referenced nowhere** —
  wiring it into the Goblin Castle was out of scope for this pass, so the
  fight is not yet reachable in play. See Track B item 1 in the roadmap.

### Equipment — `scripts/inventory/Equipment.gd` (`class_name Equipment`)  (P3)
- A piece of gear (Resource). `slot` (WEAPON/ARMOR/ACCESSORY), `rarity`
  (Rarity.Tier — cosmetic, NOT a gate), `stat_bonuses` (dict of any of
  attack/defense/magic/arcane/speed/max_hp/max_mp → int, may be negative),
  `class_restriction: Array[String]` (empty = any), `element_restriction: Array[int]`
  (ElementalSystem ints; empty = any). `can_equip(c)` ANDs class + element checks
  (class case-insensitive; element matches primary OR secondary). UI helpers:
  `rarity_color/rarity_name/slot_name/restriction_text/bonus_text`.
- **EquipmentFactory** (`class_name`, mirrors ItemFactory): `DEFS` of 18 named pieces;
  `create(name)` builds a fresh distinct instance (gear never stacks), `has_equipment`,
  `roll_drops(table)` (each successful roll yields `quantity` distinct pieces).
- **Slots per hero: 5** = 1 Weapon, 1 Armor, 3 Accessory.
- **Storage convention:** unequipped pool is shared on `party[0].inventory.equipment`
  (like items); equipped pieces live PER-HERO on each `hero.inventory`
  (`equipped_weapon`/`equipped_armor`/`equipped_accessories[3]`).
- `Inventory.equipment_bonus(stat)` sums `eq.bonus(stat)` over `equipped_list()`; the
  **Character stat getters add this in** (max_hp/max_mp/attack/defense/magic/arcane/speed).
- Cross-inventory moves go through STATIC `Inventory.equip_from_pool(hero, pool, eq,
  accessory_index=-1)` (honors can_equip; auto-picks first empty accessory when idx<0;
  returns displaced piece to pool) and `Inventory.unequip_to_pool(hero, pool, slot,
  accessory_index=0)`. Both call `hero.clamp_vitals()` since max HP/MP can change.
- Acquisition: starter loadouts seeded by `PartyFactory._seed_starter_equipment`; enemy
  drops via the unified drop pipeline (BattleManager routes each rolled name to
  ItemFactory vs EquipmentFactory; `GameManager.award_rewards` adds gear to the pool;
  VictoryScreen lists both). Persisted by SaveSerializer (pool + all equipped slots).

### ResonanceSystem (Node, child of BattleScene)
- Reads/writes `character.resonance_meter` directly (0–100); **persists across battles**
  (only resonance attacks reset it). `setup()` does NOT zero meters.
- `is_full(character)`, `get_full_resonance_characters()`, `spend_solo_ultimate`,
  `spend_combined_resonance`. Signals: `resonance_changed`, `resonance_full`.

### BattleManager (Node)
- State machine: `IDLE → CHOOSING_ACTION → CHOOSING_TARGET → EXECUTING_ACTION → ENEMY_TURN → BATTLE_OVER`.
- Turn order by `speed()`, rebuilt each round.
- **Turn-start flow (`_next_turn`)**: tick damage (poison/scorched/frostbite) →
  `emit turn_started` (UI hides action menu) → `StatusSystem.resolve_turn_skip` →
  if `woke_up`: emit wake banner, await ~1.75s → if `skip`: emit skip banner,
  await ~1.9s, advance to next actor → else `emit turn_ready_for_action`
  (UI shows action menu only now, so it never flashes during a skip).
- Player: `player_attack`, `player_use_skill`, `player_use_item`, `player_defend`.
  Enemy: `enemy_use_skill` (no MP deduction). `_apply_skill_status` routes status tokens.
- Signals: `battle_started`, `turn_started`, **`turn_ready_for_action`**,
  `action_performed`, `character_defeated`, `battle_ended`, `status_effect_triggered`.

### EnemyAI (static)
- `choose_action(enemy, party, enemies)` → `{skill, target, is_enraged, echo_tier}`.
- Memory Echo dodge tiers (must match `Enemy.MEMORY_THRESHOLD_*`): Tier1=3 enc→5%,
  Tier2=7→10%, Tier3=15→15%. `try_dodge` checked for both directions; resonance/
  can't-miss always hit.

### GameManager (Autoload)
- `party: Array[Character]` (max 4), source of truth, persists across battles.
- `ensure_default_party()` → `PartyFactory`; `start_new_game(slot)`; `revive_party()` (50%,
  retained + tested but no longer used since the P6 defeat→load flow).
- `gold` (clamped ≥0, `gold_changed`); `species_memory`; `award_rewards` (gold+items
  only — **VictoryScreen owns EXP** to avoid double-counting).
- **Saves: 3 slots** at `user://save_slot_{0,1,2}.json` (`SAVE_PATH_FORMAT`).
  `active_slot` (-1 = none) persisted to `user://config.cfg`. `save_to_slot`,
  `load_from_slot`, `slot_exists`, `get_slot_metadata`, `delete_slot`, `copy_slot`.
  P6 helpers: `has_active_save()`, `load_active_slot()` (loads active slot, sets
  `resuming_from_save`, returns the saved overworld scene path; used by DefeatScreen).
  (`user://savegame.json` is a legacy single-file path still referenced by an older
  Continue branch.)
- **Settings (P4):** `settings: SettingsModel` (live), loaded/applied at launch; persisted in
  `config.cfg [settings]`. Targeted apply helpers: `apply_audio_and_save`,
  `apply_display_and_save`, `apply_performance_and_save`, `apply_fps_overlay_and_save`,
  `save_settings`. Audio buses via `SettingsModel.ensure_buses()`; global UI button SFX
  auto-wired in `_on_node_added`.
- **Input mode + focus guard (P4):** `is_controller_mode()` / `input_mode_changed`;
  per-frame focus guard (PROCESS_MODE_ALWAYS) with `register_focus_scope` /
  `unregister_focus_scope` — see Controller Navigation below.
- **Auto-save (P5):** `autosave(scene_path, pos)` gated by `can_autosave()` (toggle +
  valid slot); emits `autosave_started` / `autosave_finished(success)`.
- Overworld↔battle handoff: `in_overworld_battle`, `pending_battle_enemies`,
  `pending_battle_background`, `pending_overworld_scene_path`, `pending_overworld_return_position`.
- **Roaming-enemy handoff + region state (P7):** `pending_roamer_id`, `last_battle_won`,
  `pending_flee_iframes`; region-scoped roamer persistence (`roamer_region`,
  `roamer_states`, `has_roamer_state_for`, `set_roamer_state`, `remove_roamer_state`,
  `clear_roamer_state`). See the Overworld & Encounters section.

### Overworld & Encounters (P7 — visible roaming enemies)
- `OverworldScene.gd` reads `@export var area: MapArea` (+ `@export field_rect`); hosts the
  `PauseMenu` (in a CanvasLayer above the camera, Esc opens it) and the `SaveIndicator`.
  Movement uses the remappable `move_*` actions (keyboard + controller, left-stick scaled).
- **No more random step-based encounters.** The scene spawns up to `MAX_ROAMERS` (4)
  **`RoamingEnemy`** nodes, each given a weighted-picked `EncounterGroup` and a random
  `TERRITORY_SIZE` home rect clear of `area.safe_zones`. A roamer **wanders inside its
  territory** and **chases the player only while the player is strictly inside that
  territory** (`home_rect.has_point` — no margin), clamping/steering back at the edges.
  Touching the player (also gated on the player being in-territory) emits `touched_player`;
  `OverworldScene._on_roamer_touched` freezes it, persists state, sets the `pending_battle_*`
  + `pending_roamer_id` handoff, and changes to BattleScene.
- **Region-scoped persistence (no respawn until you leave & return):** the scene fully
  reloads after every battle, so roamer state (id, group_index, position, home rect) is
  saved in `GameManager` keyed by scene path. On return to the SAME region the survivors
  are restored in place; a roamer the player **defeated** is dropped permanently. Entering a
  DIFFERENT region — or loading a save / starting a new game — calls `clear_roamer_state()`,
  so that original region repopulates fresh on the next visit. Fighting within a region
  never respawns it.
- **Flee i-frames:** fleeing a battle sets `pending_flee_iframes`; on return the player gets
  `FLEE_IFRAME_TIME` (3s) where no roamer touch can start a fight (player + roamers fade,
  but roamers keep wandering). If an enemy is still touching the player the instant the
  window ends, the battle starts immediately (the enemy keeps re-checking contact —
  it does NOT freeze itself on a blocked touch; only `OverworldScene` freezes it on accept).
- Safe zones (towns) suppress spawns + trigger the P5 auto-save on entry.
- `EncounterGroup`: `weight`, `min_party_level`, `enemy_pool`, `min_enemies`/`max_enemies`,
  `enemy_level_override`. `MapArea`: `area_name`, `battle_background_id`, `default_spawn`,
  `encounter_groups`, `safe_zones: Array[Rect2]`.

---

## Battle UI — Theming & Structure

### Shared theme — `scripts/ui/BattleUITheme.gd` (`class_name BattleUITheme`)
Single source of truth for the **amethyst aesthetic**: dark-plum bg, amethyst
border, rounded corners, drop shadow. Use these everywhere in battle UI:
- `panel_style(border, bg, border_width, corner_radius)` → StyleBoxFlat
- `make_panel(...)`, `make_button(text, font_size)`, `style_button(existing_btn, size)`
- Constants: `PANEL_BG`, `PANEL_BORDER` (amethyst), `SUBPANEL_BG`, `BUTTON_*`,
  `TEXT_PRIMARY/SUBTITLE/ACCENT`, `font_regular()`, `font_bold()`.

### Per-hero palette — `scripts/ui/HeroPalette.gd` (`class_name HeroPalette`)
- `HERO_BASE_COLORS`: Aria = blue `(0.30,0.65,1.00)`, Kael = red `(0.95,0.30,0.30)`,
  Lyra = lime `(0.55,0.95,0.45)`. Add new heroes here.
- `accent_for(name)`, `for_hero(name)` → palette dict (accent/subtitle/label/value/
  border/panel_bg/button states/separator). Used by LevelUpScreen, in-battle hero
  panels, and turn-order slots.

### Battle menus — sizing & behavior
All anchored bottom-right, sharing the bottom edge (`offset_bottom = -10`):
- **ActionMenu** (PanelContainer, `offset_top=-140` → **130px = hero-info height**).
  Buttons stretch to fill; `ActionGrid` has `size_flags_stretch_ratio = 2.0` so the
  2-row grid + 1-row Resonance button all end up equal height.
- **AttackMenu / ItemsMenu** (Control + inner `Panel`, `offset_top=-160` → **150px**,
  same as each other). Built dynamically; themed bg via `Panel` (not PanelContainer —
  Panel won't auto-shrink to content). Items list is scrollable with a themed slim
  scrollbar; slots are element/item-type-tinted; hover paints a subtle wash (no
  inner border); disabled item rows dim the whole slot.
- **ResonanceMenu** (PanelContainer, `offset_top=-10` + `grow_vertical = BEGIN`
  → **auto-grows upward** to fit however many attacks are available). Attack names
  use a `RichTextLabel` with per-character `[color]` BBCode for an **element-color
  gradient** (e.g. Aquatic Pyre sweeps blue→red), centered via a `CenterContainer`.
  Tier dividers (`_make_section_divider`): "✦ Duo Resonance ✦" (amber) and
  "✦ Trio Resonance ✦" (amethyst), each a label flanked by gradient-fade lines.
  Description popup is parented to UIRoot (not the PanelContainer) so it isn't
  laid out into the panel; cleaned up on close.
- **Menu rule going forward:** sub-menus opened over the action menu should *replace*
  it (hide the layer below), not stack. See PauseMenu confirm pattern.

### Other themed elements
- **Hero panels** (`BattleScene._update_hero_panel`): panel bg/border tinted with the
  hero's `HeroPalette` accent; name in accent color. HP/MP/Resonance bars keep their
  semantic colors (green→red HP, blue MP, purple resonance) for readability. Status
  chips appear in a `StatusRow` injected into each panel's layout.
- **Enemy cards** (`BattleScene._create_enemy_card`): border = `enemy.get_rarity_color()`
  (rarity tier), dark-plum bg.
- **Turn order indicator**: per-actor tinted slots (hero palette / enemy element),
  active slot gets the yellow accent border. No enclosing bg panel.
- **Portrait placeholders**: themed rounded panels (hero accent / enemy element border).
- **VictoryScreen / DefeatScreen**: content wrapped in a themed `PanelContainer` card
  (Victory = gold border + "✦ Victory ✦"; Defeat = crimson + "✦ Defeat ✦"), themed
  buttons, fade-in animates the whole card.

### Battle scene tree (BattleScene.tscn)
```
BattleScene (Node2D)
├── Background
├── CharactersLayer (Node2D)
│   ├── PartyPositions (VBoxContainer)  ← hero portrait wrappers (diagonal stack, on grass)
│   └── EnemyPositions (Node2D)         ← enemy portrait grid
└── BattleUI (CanvasLayer) → UIRoot (Control)
    ├── EnemyInfoRow ── enemy rarity-bordered cards across top
    ├── PartyStatusBar ── 3 hero panels bottom-left (130px tall)
    ├── ActionMenu (PanelContainer) ── Attack/Special/Items/Run/Resonance
    ├── AttackMenu / ItemsMenu / ResonanceMenu ── bottom-right, same footprint family
    ├── VictoryScreen / DefeatScreen / LevelUpScreen
    └── TurnOrderIndicator
```

---

## Party / Enemy Setup
- `PartyFactory.create_default_party()` → Aria (Mage/Water), Kael (Warrior/Fire),
  Lyra (Healer/Wind); 8 skills each + ultimate meta (`ultimate_name`/`ultimate_desc`).
  `base_arcane`: Aria 14, Lyra 12, Kael 5. Heroes start at full HP/MP.
  (Currently all three start with `experience = 85` — one battle from a level-up,
  for quick level-up testing; lower this for real play.)
- Wired buff skills: Tidal Barrier → `defense_buff`, War Cry → `attack_buff`,
  Wind Barrier → `defense_buff`, Tailwind → `speed_buff`, Iron Will → `regenerate`.
- 10 enemies in `data/enemies/*.tres`, loaded + `.duplicate(true)`'d. Enemies have
  **no MP** and `mp_cost = 0` on all skills. Status inflictors: Fire Drake→scorched,
  Frost Wyrm/Ice Golem→frostbite, Dark Wraith/Void Shade(Null Strike)→poison,
  Void Shade(Arcane Bolt)→magic_debuff, Wind Sprite(Cyclone Dart)→sleep,
  Storm Eagle(Talon Strike)→paralysis, Storm Eagle(Thunder Beak)/Kael Shield Bash→stun.

---

## Save System (3-slot, complete)
- **Full serialization (option 1B)** — `SaveSerializer` turns Character/Skill/Item/
  Inventory into JSON dicts and back (no PartyFactory dependency at load). Persists
  `secondary_element`, `resonance_meter`, `base_arcane`. Battle-temp state
  (status/buffs/debuffs/sleep_turn) is intentionally NOT serialized.
- **3 slots** + `active_slot` (config.cfg). New Game / Continue use `SaveSlotMenu`:
  occupied slots show Load + Copy; Delete only in the New-Game picker (not load mode).
- **Save UX is pause-menu driven** — Esc → `PauseMenu` → Save writes to `active_slot`.
  No mid-game slot picker.
- **PauseMenu confirm pattern** (reuse for future sub-menus): the main menu content
  lives in a `_main_content` wrapper. `_show_confirm` hides `_main_content` and shows
  the prompt alone; Cancel (`_dismiss_confirm`) frees the prompt and restores the menu;
  Esc backs out of an open prompt instead of closing the whole menu. **Sub-menus must
  replace, not stack.**

---

## Known Patterns & Conventions
- Characters/Skills/Items are **Resources** (`.new()`-able, not Nodes).
- `take_damage`/`take_magic_damage` return `{damage, multiplier, effectiveness, effectiveness_color}`.
- Status effects are plain strings (`"poison"`, `"stun"`, …); buff/debuff are dict keys
  (`"attack"`, `"magic"`, …).
- `_build_menu()` in dynamic menus always clears + rebuilds children.
- Fonts loaded inline or via `BattleUITheme.font_*()`.
- Battle results flow through `action_performed(result: Dictionary)`.
- A `Panel` (non-Container) reliably fills an anchored rect; a `PanelContainer`
  auto-shrinks/grows to its content — pick deliberately for fixed vs content-sized UI.

---

## Testing Policy (IMPORTANT)
- **Every new feature ships with a unit test.** Suites: `tests/suites/test_<feature>.gd`,
  `extends TestSuite`, methods prefixed `test_`, `assert_*` helpers. Register in
  `TestRunner.gd` `SUITE_PATHS`.
- Run: `tests/TestRunner.tscn` → F6, or headless (command above). **~2408 tests / 40 suites**
  currently: character, skill, elemental, rarity, enemy, encounter_group, resonance,
  enemy_ai, game_manager, party_factory, save_serializer, status_system, hero_palette,
  stats_screen, items_screen, item_factory, equipment, settings, input_map, focus_guard,
  auto_save, level_up_screen, defeat_flow, roaming_enemy.
- Tests touching GameManager must snapshot & restore global state.
- When fixing a bug, add a regression test that fails before the fix.
- **Adding a new `class_name` file:** the headless test runner won't see it until the
  global class cache is rebuilt — run the `--editor --quit-after 3` command once.
- **`test_save_serializer` count can dip** if real `user://save_slot_*.json` files exist
  from playing the game (some assertions are filesystem-state-dependent). Not a regression.

## Working in the Godot Editor
- **Any step the user must do in the editor must be numbered, explicit instructions** —
  which scene/file, the exact panel path, what to type, what success looks like.
- Prefer code/data changes you can make directly. Editor steps only for things that
  genuinely require the editor (scene-tree edits, asset import, running scenes).
- After script-only changes the user just reloads (Project → Reload Current Project)
  and runs; after `.tscn` changes, same.

## Superpowers Skills (use these)

The `superpowers` plugin is installed and **should be used** — it is not optional
scaffolding. Reach for the skill that matches the phase of work:

| Situation | Skill |
|---|---|
| Any new feature, mechanic, or behaviour change — BEFORE writing code | `superpowers:brainstorming` |
| A spec is approved and the work is multi-step | `superpowers:writing-plans` |
| Implementing a feature or bugfix | `superpowers:test-driven-development` |
| Any bug, failing test, or surprising behaviour | `superpowers:systematic-debugging` |
| About to say "done", "fixed", or "passing" | `superpowers:verification-before-completion` |
| Work is complete and headed for `main` | `superpowers:requesting-code-review`, then `superpowers:finishing-a-development-branch` |

`brainstorming` classifies work as **spike / bounded / architectural** and gates
implementation on the user approving that path's artifact. Respect the gate: a
bounded change needs a short design agreed in chat; a new subsystem needs a
written spec before any code. **Specs live at `<repo-root>/.claude/docs/superpowers/specs/`**
(not under `new-game-project/`), alongside the other Claude project files — note the
repo root is one level ABOVE the Godot project. Name them
`YYYY-MM-DD-<topic>-design.md`. They are committed and are the durable record of
*why* a system works the way it does, so read the relevant one before changing a
system it covers.

> **DO NOT use `superpowers:using-git-worktrees` on this project.** It conflicts
> with the standing workflow below: branches are created **inside the main
> checkout directory**, never as separate worktree directories. Every other
> superpowers skill applies normally.

Testing guidance from `test-driven-development` layers on top of this project's
own Testing Policy above — the policy (a suite per feature, registered in
`TestRunner.gd`) still governs where tests live and how they run.

## Permissions / Settings & Git Workflow
- Project allowlist: `<repo-root>/.claude/settings.json`. Allowlisted: safe read-only
  Bash (`cd`, `cat`, `grep`, `rg`, `ls`, `find`, `wc`, `head`, `tail`, `echo`,
  `git status/diff/log/branch/show`). `Edit`/`Write`/`MultiEdit` allowed repo-wide
  (scoped to repo path); edits outside the repo still prompt.
- Intentionally NOT allowlisted: `mkdir`/`rm`, `python3`/`node`/shells. Don't add
  without explicit user consent.
- **Branch-per-task workflow (REQUIRED — never work on `main` directly):**
  1. At the start of a task/feature, create and switch to a new descriptively-named
     branch off the latest `main` (e.g. `git checkout main && git pull && git checkout -b p1-stats-screen`).
  2. Do all work and commits on that branch.
  3. When the work is complete **and the user has confirmed it's good**, merge the
     branch into `main` (`--no-ff` is fine), then **delete the branch**:
     `git checkout main && git merge --no-ff <branch> -m "..." && git branch -d <branch>`.
     Task branches are typically **local-only**; only run `git push origin --delete <branch>`
     if you actually pushed that branch. Push `main` to origin when the user asks (or as the
     final step of finalizing) — `git push origin main`.
  4. Result after each task: only `main` remains; the task branch is gone.
  - In practice this session: branches stayed local, `main` is pushed to
    `origin/main` after finalizing each phase. Repo lives at
    `github.com/aJAYGamin/fantasy-rpg` (path `new-game-project/` inside it).
- Still ask before the finalize step — don't merge/push/delete until the user says
  the work is done. Creating the working branch up front is expected and doesn't need
  a prompt. Never commit straight to `main`.

---

## Development Phases

### Done
- **Core battle**: turn order, state machine, attack/skill/item/defend, victory/defeat/levelup.
- **Element system overhaul**: 16 elements, NORMAL/AMETHYST, dual-element, multiply-all
  damage formula, 2.0x super-effective.
- **`base_arcane`** magic-resistance stat.
- **Status-effect system**: 6 mutex statuses + per-stat buffs/debuffs, chips, banners,
  turn-skip gating, battle-end cleanup, enemy/hero inflictors.
- **Enemies ignore MP.**
- **Save system**: 3-slot full serialization, slot picker, pause menu, quit confirm.
- **Overworld** (Phase 2/3), MapArea/EncounterGroup data. Encounters are now VISIBLE
  roaming enemies (P7), not invisible step-based rolls.
- **UI theming pass**: shared BattleUITheme + HeroPalette; themed action/attack/items/
  resonance menus, hero panels, enemy cards (rarity border), turn order, victory/defeat,
  pause menu; resonance element-gradient text + auto-grow + decorative tier dividers.
- **Phase P1 — Pause-menu Stats screen** (`scripts/ui/StatsScreen.gd`, `class_name StatsScreen`):
  full-screen 3-column per-hero page opened from PauseMenu (replace-not-stack). Left:
  portrait/name/Lv, XP bar + lifetime "Total XP earned" (`Character.total_experience_earned()`),
  affinity, resonance meter + solo ultimate. Middle: bio stacked on top of the vertical
  core-stats list (HP/MP/ATK/DEF/MAG/ARC/SPD). Right: attack/special cards (2-per-row,
  always show element incl. NORMAL "◇"). ←/→ or name tabs cycle heroes. Pure testable
  `build_hero_view_model()` (suite `stats_screen`).
- **Phase P2 — Pause-menu Items screen** (`scripts/ui/ItemsScreen.gd`, `class_name ItemsScreen`):
  full-screen 4-tab page (Items / Healing Items / Battle Items / Key Items) opened from
  PauseMenu (replace-not-stack); ←/→ cycle tabs. Field-use flow: ALL_ALLIES applies to all
  alive; SINGLE_ALLY opens a hero target picker; battle-only/key items are display-only.
  Items are now data-driven via **`ItemFactory`** (single source of named defs + `create()`);
  `PartyFactory` seeds starter items through it. A few enemies have `drop_table`s
  (dark_wraith/sea_serpent/earth_golem); `BattleManager._calculate_rewards` rolls drops via
  `ItemFactory.roll_drops`, `GameManager.award_rewards` adds them to the shared party
  inventory (`party[0].inventory`), and `VictoryScreen` lists drops with counts. Suites
  `items_screen`, `item_factory`.
- **Phase P3 — Equipment system** (see the Equipment core-system section above):
  `Equipment` + `EquipmentFactory` resources; 5 slots/hero (1 Weapon, 1 Armor, 3
  Accessory); flexible per-stat bonuses summed into the Character stat getters via
  `Inventory.equipment_bonus`; class/element restrictions (rarity is cosmetic). Shared
  unequipped pool on `party[0].inventory.equipment`, equipped slots per-hero; moves via
  static `Inventory.equip_from_pool`/`unequip_to_pool` (clamp vitals). Pause-menu
  `EquipmentScreen` (`class_name`): hero tabs, live stats with equipment deltas, 5
  selectable slots + unequip, restriction-gated equippable pool. Starter loadouts +
  enemy drops (unified drop pipeline). Full SaveSerializer round-trip. Suite `equipment`.
- **Phase P4 — Settings menu + difficulty + full input remapping + controller navigation**
  (`scripts/ui/SettingsScreen.gd` `class_name SettingsScreen`; `scripts/settings/SettingsModel.gd`
  `class_name SettingsModel`; `scripts/settings/InputMapConfig.gd` `class_name InputMapConfig`;
  `scripts/ui/FocusUtil.gd` `class_name FocusUtil`). Persisted in `user://config.cfg` `[settings]`
  (alongside `[save] last_slot`); `GameManager.settings` is the live model, loaded/applied at launch.
  `SettingsScreen` is a category hub (Game / Controls / Audio / Display / Performance, in that order);
  Controls splits into Keyboard / Controller sub-views. Same screen serves the main menu (standalone
  overlay, owns Esc) and the pause menu (replace-not-stack sub-view). Targeted apply helpers
  (`apply_audio_and_save` / `apply_display_and_save` / `apply_performance_and_save` /
  `apply_fps_overlay_and_save` / `save_settings`) so changing one group never triggers unrelated side
  effects (e.g. volume changes don't flicker the window).
  - **Audio:** Master/Music/SFX volume → three AudioServer buses (Master + programmatic Music/SFX via
    `SettingsModel.ensure_buses()`). Global UI SFX (`misc_menu_4.wav`) auto-wired to every Button's
    `pressed`+`mouse_entered` by GameManager (plays while paused). Main-menu music loops.
  - **Display:** window mode (Fullscreen / Borderless / Windowed) + resolution dropdown.
    `apply_display()` is **idempotent** (guards each transition on current mode — re-issuing macOS
    fullscreen crashes). Game **boots windowed** (`project.godot` has no `window/size/mode`) then
    applies the saved mode deferred, so the saved mode sticks across restarts. NOTE: window ops are
    no-ops while the game runs **embedded in the editor's Game tab** (Godot 4.6) — that's an editor
    toggle, not a code issue.
  - **Performance:** framerate cap / V-Sync / on-screen FPS counter (global CanvasLayer overlay).
  - **Game:** Difficulty (Easy/Normal/Hard) + Auto-Save toggle (consumed by P5). Difficulty scales
    enemy combat stats via `Character.combat_stat_multiplier` (×0.5 / ×1.0 / ×2.0, applied to battle
    copies in `BattleScene.start_battle`), Hard gives +25% gold/XP and caps healing/battle item stacks
    at `Inventory.HARD_ITEM_CAP` (10 each; drops skip when capped), and reserves a `shop_price_mult`.
  - **Controls:** stick sensitivity (left scales movement; right reserved), live device statuses
    (controller name / "No Controller Found"; keyboard+mouse are activity-based since Godot can't
    enumerate them), and full **keyboard + controller remapping** via `InputMapConfig` — named actions
    (`move_*`/`confirm`/`cancel`/`pause`) with per-device defaults, press-to-bind, per-device + global
    reset, persisted to `[input]`; `confirm`/`cancel` mirror onto `ui_accept`/`ui_cancel`.
  - **Controller menu navigation (centralized focus guard):** `GameManager` tracks input mode
    (`is_controller_mode()`, `input_mode_changed`) and runs a per-frame **focus guard** (PROCESS_MODE_ALWAYS,
    works while paused). Menus call `register_focus_scope(ctrl)` / `unregister_focus_scope(ctrl)`; the
    guard makes ONLY the topmost visible scope's controls focusable (locks out background — no leak),
    re-grabs focus when lost (covers rebuilds / next hero / re-entry), and in keyboard+mouse mode forces
    everything click-only (release happens once on transition, NOT per-frame — per-frame release cancels
    in-progress clicks). Category tabs are tagged `BattleUITheme.mark_no_focus` (cycled with L1/R1, never
    focused). `FocusUtil` holds the L1/R1 detection. Screens detach old children immediately on rebuild
    (not deferred queue_free) so stale full-rect overlays can't swallow clicks. Back = controller B /
    Esc (`ui_cancel`) everywhere; battle sub-menus + target select honor it too.
    - **Disabled controls are FOCUS_NONE**, not merely un-grabbable. Godot's neighbor search only skips
      FOCUS_NONE, so a greyed button left focusable is a dead end that swallows the d-pad (the main
      menu's disabled Continue blocked every option under it).
    - **The top scope is re-walked every frame**, not only when the active scope changes. Menus rebuild
      their contents constantly (item tabs, the next hero's page, the skill grid) and fresh controls are
      born FOCUS_ALL; a change-only walk left them inconsistent — the Items "?" buttons were reachable in
      whichever tab happened to be built last and nowhere else. `Control.set_focus_mode` early-returns
      when unchanged, so the walk is cheap.
    - **Remembered focus:** `set_preferred_focus(scope, ctrl)` names where the guard should land on its
      NEXT re-grab in that scope, so backing out of a sub-view returns to the entry you left from instead
      of the top of the list. One-shot (consumed on use) so ordinary rebuilds don't keep yanking focus
      back. `PauseMenu` records the entry that opened each sub-view; `SettingsScreen` keys off the
      category name (`_returning_from`) because its buttons are rebuilt per view.
    - **Wrap-around navigation:** `_wire_focus_wrap` gives a control an explicit `focus_neighbor_*`
      ONLY on sides where the geometric search finds nothing, so the last menu entry loops to the
      first (and back) while the middle of a menu, 2-column grids and side-by-side rows keep
      navigating normally. Ties prefer staying on the same column/row. The links are recorded in meta
      and cleared before each recompute — a stale link would make the "has no neighbour" test lie —
      and hand-authored neighbours from a `.tscn` are never touched. Godot's own navigation and the
      auto-repeat below both go through `find_valid_focus_neighbor`, so they wrap identically.
      (The Items/Stats/Equipment *category tabs* already looped separately, via the `%` in their
      L1/R1 handlers.)
    - **Held-direction auto-repeat:** `HoldRepeat` (`scripts/ui/HoldRepeat.gd`) + `GameManager._update_nav_repeat`
      keep moving focus while `ui_up`/`ui_down`/`ui_left`/`ui_right` is held — initial delay, a normal
      cadence, then a faster one after `ACCELERATE_AFTER` (3s) for long lists. It drives
      `find_valid_focus_neighbor` directly rather than synthesizing events, so it inherits the same skip
      rules as a real press. Keyboard and controller both, never in pure-mouse mode. The same helper
      repeats L1/R1 (or Q/E) category cycling on the Stats / Items / Equipment screens, via
      `FocusUtil.prev_category_held()` / `next_category_held()`; `_input` still owns the first press.
      Category cycling uses `HoldRepeat.for_category()` — a MUCH longer initial delay (0.9s vs 0.42s),
      because each step swaps the whole page. With the list timings a ~0.5s press advanced two tabs and
      a ~0.9s press lapped all four and landed back where it started, which reads exactly like the tab
      wrap being broken. Any press up to ~1s must move exactly one category.
  - Suites: `settings`, `input_map`, `focus_guard`, `hold_repeat`.
- **Phase P5 — Auto-save** (`scripts/save/AutoSaveSystem.gd` `class_name AutoSaveSystem`;
  `scripts/ui/SaveIndicator.gd` `class_name SaveIndicator`): auto-saves to the active slot on
  entering a town/safe zone. `MapArea.safe_zones: Array[Rect2]` lists town rects in world space
  (Fallster Plains has three, matching the Marker1/2/3 placeholder towns). `AutoSaveSystem` is a
  pure tracker: `update(pos, zones)` returns true only on the outside→inside transition (fires once
  per entry; re-entry refires; zone-to-zone doesn't), and `in_safe_zone()` suppresses random
  encounters while standing in a town. `OverworldScene._physics_process` drives it and calls
  `GameManager.autosave(scene_path, pos)`, which is gated by `can_autosave()` (settings toggle +
  valid `active_slot`) and emits `autosave_started`/`autosave_finished(success)`. `SaveIndicator`
  (bottom-right, BattleUITheme-styled, on its own CanvasLayer) listens to those signals: fades in
  "✦ Saving Game…" then "✦ Saved Game" and fades out. Suite `auto_save`.
- **Phase P6 — Defeat → load flow** (`scripts/battle/DefeatScreen.gd`): the old "revive party at
  50% HP and walk back" hack is replaced with a proper game-over. The DefeatScreen now offers
  **Load Last Save** (loads the active slot via `GameManager.load_active_slot()`, which sets
  `resuming_from_save` and returns the saved overworld scene path) and **Quit to Main Menu**.
  Load is disabled/greyed when `GameManager.has_active_save()` is false (no loadable slot), so the
  focus guard lands on Quit. `revive_party()` is retained (still unit-tested) but no longer used by
  the defeat flow. Suite `defeat_flow`.
- **Phase P7 (part 1) — Visible roaming enemies** (`scripts/overworld/RoamingEnemy.gd`
  `class_name RoamingEnemy`): replaces invisible step-based random encounters with on-map enemy
  sprites (Mario & Luigi style). A `RoamingEnemy` (CharacterBody2D, placeholder crimson square)
  **wanders within its own territory** (`home_rect`) and **chases** the player only while the
  player is inside that territory (hysteresis: in at `DETECT_RADIUS`, out at `LOSE_RADIUS` or when
  the player leaves home); it clamps/steers back so it never leaves its area. Touching the player
  emits `touched_player`. `OverworldScene` spawns up to `MAX_ROAMERS` (4), each with a random
  `TERRITORY_SIZE` rect clear of `MapArea.safe_zones` towns, carrying a weighted-picked
  `EncounterGroup`.
  - **No respawn until you leave & return:** roamer state (id, group index, position, territory)
    is persisted in `GameManager` keyed by the region's scene path (`roamer_region` /
    `roamer_states` / `has_roamer_state_for`). The scene reloads after each battle, so on return
    the survivors are **restored** in place; a WON roamer is removed permanently
    (`remove_roamer_state(id)`). Entering a *different* region (or loading a save / new game)
    clears the state via `clear_roamer_state()`, so the original region repopulates fresh on the
    next visit — but fighting within a region never respawns it.
  - **Flee i-frames:** running from a battle sets `pending_flee_iframes`; on overworld return the
    player gets `FLEE_IFRAME_TIME` (3s) where no roamer touch can start a battle (immune to all),
    roamers fade (`set_faded`) but keep wandering, then normal play resumes.
  - Handoff: `pending_battle_*` + `pending_roamer_id`; `BattleScene._on_battle_ended` records
    `last_battle_won`. Safe zones still suppress spawns + auto-save on entry. Suite `roaming_enemy`.
- **Phase P8 — Skill learning** (`Skill.unlock_level`, `Character._learn_skills_at_level`):
  heroes carry all 8 skill slots from the start but a slot only becomes usable once
  `level` reaches its `unlock_level`. Keeping the array whole preserves the positional
  contract the battle menus depend on (0-3 attacks, 4-7 specials) — shrinking it would
  re-slot every later skill. `unlock_level` defaults to **1**, so enemy skills, every
  `data/skills/*.tres`, and pre-P8 saves are unaffected and only heroes opt in.
  - Curve lives in `PartyFactory.SKILL_UNLOCK_LEVELS` (shared by all three heroes so
    pacing is easy to balance): slots unlock at `[1,1,2,7,1,4,10,15]`. Heroes open with
    2 attacks + 1 special, and **level 2 always teaches something** — an empty first
    level-up makes the feature look broken.
  - `Character`: `is_skill_known(i)`, `known_skills()`, `skills_unlocked_at(lvl)`,
    `next_skill_to_learn()`. `pending_learned` collects what a `gain_experience()` call
    taught (covering a multi-level jump) and is cleared at the start of the next award;
    it is battle-temp and NOT serialized — `level` + each `unlock_level` are the durable
    facts. `AttackMenu` filters both menus through `is_skill_known`.
  - `SaveSerializer` persists `unlock_level` (defaulting to 1 on read) — without it a
    load silently unlocked a hero's entire kit.
  - UI: `LevelUpScreen` adds "✦ Learned X!" lines; `StatsScreen` still shows locked
    skills but dimmed with the level they arrive at, so the player sees what's coming.
    Suite `skill_learning`.

### Roadmap (agreed order — work top-down)

> **Next session starts at Track B.** Art stays parked until Track D: a 70-prop
> library and one animation are committed under `assets/props/` but **nothing is
> placed in any scene on purpose**. Don't place props, repaint maps, or generate
> art unless explicitly asked. See **Art pipeline (parked)** below for what
> already exists so it isn't rebuilt.

**What is already done** (the older P7p2/P10 entries here were stale and have been
corrected): the Fallster Plains map, its towns/village/shops/inn interiors, the
Forest, Mountain Pass and Goblin Castle scenes, map-to-map transitions, the
dialogue system **including its choice UI** (`DialogueBox`), the quest system
(`Quest`/`QuestFactory`/`QuestLog` + `QuestScreen`), shops, time-of-day, input
profiles, movesets/loadouts, rest areas, and the controller-navigation pass.

#### Track B — Systems breadth  ← **current**
1. **Boss enemies — DONE.** `is_boss()` on `Enemy` (an enemy with `phases` IS a
   boss — no separate flag), a full-width battle card, and full multi-phase
   behaviour: moveset, stats, summons, field effects, transformation. See
   **Boss Phases** in Core Systems above. First boss: Goblin Warlord, exercising
   four of the five powers. **Not yet reachable in play** — its fixed encounter
   (`data/encounters/goblin_warlord_fight.tres`) is referenced nowhere; wiring
   it into the Goblin Castle was out of scope here and is the obvious next step.
2. **Status-cleansing items and skills — next.** The antidote covers poison/burn only.
   Extend cleansing to `scorched`, `frostbite`, `sleep` and especially
   `paralysis`, which currently clears **only at battle end** — a real hole.
3. **More skills, with varied effects and costs.** Widen beyond the current
   damage/heal/buff shapes: multi-turn effects, HP-cost or resonance-cost moves,
   conditional power, self-debuff trade-offs. `Skill` already carries
   `status_to_apply`, `status_chance` and `resonance_gain_override` to build on.

#### Track C — Hardening
- **Roamer state in saves** — currently in-memory only, so a hard quit respawns a
  region. Write it into the save JSON.
- **Virtual cursor + mouse sensitivity** (the deferred "Chunk D" of P4) — needs a
  virtual cursor that reworks menu click routing.
- **Stats screen format tweaks** — minor visual/format work the user deferred.
- **Save/load edge cases** — every new field must reach `SaveSerializer` or it
  silently resets on load.

#### Track A — Story progression (second to last)
- `GameManager.story_flags` exists but is **referenced by nothing** — the story
  system is a declared variable and no more. Make it real: flags that gate NPC
  dialogue, zones and quest advancement.
- A **scripted-event / cutscene sequencer** on top of `DialogueManager` (move an
  actor, wait, show dialogue, fade, set a flag).
- Wire the main quest through it. The seed already exists in `QuestFactory`:
  `amethyst_awakening` — *"A violet blight is creeping across Fallster, and the
  Amethyst stirs in answer."* **The premise is the user's to define — ask before
  building story content**, and build on this seed rather than replacing it
  unless they say otherwise. The AMETHYST element and the triple-hero resonance
  are the intended narrative payoff.

#### Track D — Real art (last)
- Place the existing 70-prop library; animate the remaining fire props.
- Player sprite, hero/enemy portraits and battle sprites (placeholders are
  coloured squares / letter tiles today), custom cursor.
- Map art is already done.

### Art pipeline (parked — built, committed, deliberately NOT applied)
Generated in SpriteFlow and committed, but **not placed in any scene**. Resume at P9.

- **70 static props** in `assets/props/static/`, all 512x512 transparent PNGs, every one
  registered in `PropLibrary.DEFS` with a world-space `height` and a `category`
  (tree, flower, ground, crop, water_edge, rock, structure, debris, light, decor,
  container, furniture, wares, dungeon, arcane). The art all arrives ~430px regardless
  of subject, so **the library height is the only thing keeping a daisy from rendering
  as tall as an oak** — heights were eyeballed against a 32-unit player block.
- **1 animation**: `assets/props/animated/candle/` (32 frames). The other eight fire
  props in the `light` category are generated as statics and ready to animate.
- **Prop scenes** (`scripts/props/`): `StaticProp` and `AnimatedProp` are foot-anchored
  — **the node's position is where the prop meets the ground**, which is what the
  existing y-sort/`DepthOverlay` walk-behind compares against. Both are `@tool` with a
  `prop_name` dropdown; both build their children at runtime and leave them **unowned**,
  so nothing is serialised into the `.tscn`. `AnimatedProp` desyncs each instance
  (random start frame + speed jitter) so a row of torches doesn't flicker in lockstep,
  and prefers a `PointLight2D` over a baked glow. `PropShadow` is a shared contact
  shadow. `PropScatter` works and is tested but **the user places props by hand** — it
  is unused, kept only for a possible dense forest later.
- **`tools/import_animation.gd`** — run a SpriteFlow animation export through this
  before committing it. Pro Mode returns 32 frames at ~1100px on a mostly-empty canvas;
  the candle went 8.4MB → 0.4MB (23.9x). It crops every frame to the **union** of their
  opaque bounds (per-frame trimming would re-centre the art and make the prop jitter),
  runs `fix_alpha_edges()` before downscaling to avoid a dark fringe, renames frames to
  `frame_NN.png`, and reports base drift / size wobble so a bad loop gets re-rolled.
  Usage is in the file header.
- **SpriteFlow settings that matter** (learned the hard way): Game Prop's **Style source
  must be `Upload reference`** with a crop of the actual map — the default `16-bit Pixel`
  preset is what made the first candle blocky, and none of the four presets fit. Prop
  lists are one short descriptor per line and the line count must match the 4/9/16
  toggle exactly. In Sprite Motion, **Pro Mode locks frames to 32 and forces Enhance
  Prompt on**; both are fine (pacing is `AnimatedProp.fps`, and the "…completely still"
  clause in each prompt keeps Enhance in check — measured 2px drift on the candle).
- **The prompts live in the "Amethyst Prop Atlas" artifact** — all 7 batch lists and 18
  Sprite Motion prompts, ready to copy. Ask the user for the link if it's needed.
- **Map state**: `FallsterPlains.png` is the 4K upscale (`MapImage` scale halved to
  `0.9609375, 0.9861111` so the world stays exactly 3936x2272 and every collision
  polygon stays valid). An automated repaint that erased the painted trees/flowers was
  built and then **reverted at the user's request** — it's recoverable in `d4d7444` if
  the prop-replacement plan is ever resumed. The forest borders were always going to
  stay painted: they merge into 4 connected masses of 1.65M px that can't be separated.

### Deferred / known follow-ups
These are **scheduled as Track C** in the Roadmap above; the detail lives here.
- **Virtual cursor + mouse sensitivity (was "Chunk D" of P4):** a themed in-game cursor
  plus a working mouse-sensitivity slider. Needs a virtual cursor that reworks menu click
  routing, which is why it keeps being pushed back. Not started.
- **Stats screen format tweaks:** minor visual/format work on the P1 Stats screen that the
  user deferred "to some point later" — expect them.
- **Roamer state is in-memory only** (per session), not written into the save JSON. After a
  hard quit + load, a region spawns fresh.
- **Two play-testing flags exist and are currently OFF** — `PartyFactory.TEST_UNLOCK_ALL_SKILLS`
  (gives every hero its whole 12-move pool at level 1) and the shipping value of
  `GameManager.REST_REFRESH_BATTLES` (5). Flip them only for play-testing, and turn them
  back before committing anything that matters.

### Backlog / ideas (not yet scheduled)
- More heroes (add to `PartyFactory` + `HeroPalette.HERO_BASE_COLORS` +
  `ResonanceMenu.COMBINED_ATTACK_NAMES`) — broader blast radius than it looks:
  battle-UI layout, resonance naming and save serialization all move.
- Fixed-composition encounters are implemented (`EncounterGroup.is_fixed`) but
  nothing uses them yet — Track B's boss is their first customer.
- Boss enemies, status cleansing and new skill shapes have moved OUT of this list
  and into **Track B** above.
