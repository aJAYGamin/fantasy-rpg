# The Amethyst Requiem — Project Context for Claude Code

## Project Overview
A turn-based JRPG built in **Godot 4 (GDScript)**, in active development.
The core battle system, status-effect system, save system, and a heavily-themed
battle UI are complete. Focus going forward: building out the pause-menu
sub-screens (Stats/Items/Equipment/Settings), a main-menu Settings screen,
auto-save, more overworld content, and eventually story.

---

## Engine & Setup
- **Engine:** Godot 4.6.1 stable (binary on this machine: `/Applications/Godot.app/Contents/MacOS/Godot`)
- **Language:** GDScript
- **Autoload Singleton:** `GameManager` (`res://scripts/GameManager.gd`)
- **Main scenes:** `MainMenu.tscn`, `OverworldScene.tscn`, `BattleScene.tscn`
- **Fonts:** Cinzel-Regular.ttf, Cinzel-Bold.ttf (`res://fonts/`)
- **Run tests headless:** `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/TestRunner.tscn --quit-after 5` (currently **370 tests, 13 suites**)
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
  overworld/
    OverworldScene.gd         # Free-roam controller; step-based encounter rolls; pause menu host
    Player.gd                 # CharacterBody2D, 8-dir arrow/controller movement
    MapArea.gd                # Resource: area metadata + encounter group list
    EncounterGroup.gd         # Resource: weighted encounter (pool + count range + level gate)
  save/
    SaveSerializer.gd         # Pure static: Character/Skill/Item/Inventory ↔ Dictionary (full, option 1B)
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
  inventory/
    Inventory.gd              # Per-character item container
    Item.gd                   # Item resource with use() logic
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
  suites/                     # one test_<feature>.gd per system (13 suites)
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
- `ensure_default_party()` → `PartyFactory`; `start_new_game(slot)`; `revive_party()` (50%).
- `gold` (clamped ≥0, `gold_changed`); `species_memory`; `award_rewards` (gold+items
  only — **VictoryScreen owns EXP** to avoid double-counting).
- **Saves: 3 slots** at `user://save_slot_{0,1,2}.json` (`SAVE_PATH_FORMAT`).
  `active_slot` (-1 = none) persisted to `user://config.cfg`. `save_to_slot`,
  `load_from_slot`, `slot_exists`, `get_slot_metadata`, `delete_slot`, `copy_slot`.
  (`user://savegame.json` is a legacy single-file path still referenced by an older
  Continue branch.)
- Overworld↔battle handoff: `in_overworld_battle`, `pending_battle_enemies`,
  `pending_battle_background`, `pending_overworld_scene_path`, `pending_overworld_return_position`.

### Overworld & Encounters
- `OverworldScene.gd` reads `@export var area: MapArea`; hosts the `PauseMenu`
  (in a CanvasLayer so it renders above the camera). Esc opens it.
- Movement: 8-dir `ui_*` (arrows + gamepad). Encounter: every 32px = 1 step;
  chance += 1%/step, resets on encounter. Weighted pick among `area.encounter_groups`
  gated by `min_party_level`; group deep-copies enemies (optional `enemy_level_override`).
- `EncounterGroup`: `weight`, `min_party_level`, `enemy_pool`, `min_enemies`/`max_enemies`,
  `enemy_level_override`. `MapArea`: `area_name`, `battle_background_id`, `default_spawn`,
  `encounter_groups`.

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
- Run: `tests/TestRunner.tscn` → F6, or headless (command above). **370 tests / 13 suites**
  currently (character, skill, elemental, rarity, enemy, encounter_group, resonance,
  enemy_ai, game_manager, party_factory, save_serializer, status_system, hero_palette).
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
     branch into `main` (fast-forward when possible), push `main`, then **delete the
     branch** (local + remote): `git checkout main && git merge <branch> && git push origin main && git branch -d <branch> && git push origin --delete <branch>`.
  4. Result after each task: only `main` remains; the task branch is gone.
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
- **Overworld + step encounters** (Phase 2/3), MapArea/EncounterGroup data.
- **UI theming pass**: shared BattleUITheme + HeroPalette; themed action/attack/items/
  resonance menus, hero panels, enemy cards (rarity border), turn order, victory/defeat,
  pause menu; resonance element-gradient text + auto-grow + decorative tier dividers.

### Planned (next phases)
- **Phase P1 — Pause-menu Stats screen**: per-hero info page (model, bio, level, XP,
  HP/MP and ATK/DEF/MAG/ARC/SPD, learned attacks/specials with descriptions, solo
  resonance). Reuse the PauseMenu replace-not-stack pattern + BattleUITheme.
- **Phase P2 — Pause-menu Items screen**: Items / Battle Items / Key Items tabs;
  shared item list UI with the battle ItemsMenu styling.
- **Phase P3 — Equipment system**: weapons/armor resources; `Inventory.get_weapon_attack()`/
  `get_armor_defense()` currently return 0 — wire them into Character stat getters;
  pause-menu Equipment screen to equip/unequip.
- **Phase P4 — Settings menu (main menu + pause menu)**: audio volume, auto-save toggle,
  (later) controller bindings, text speed. Persist to `user://config.cfg`.
- **Phase P5 — Auto-save**: trigger on town/safe-area entry (`MapArea.auto_save_on_enter`)
  and story-cutscene calls; gated by the Settings toggle; save-status indicator (bottom-right).
- **Phase P6 — Defeat → load flow**: replace the current "revive at 50%" with a proper
  Continue (load `active_slot`) / Quit (MainMenu) game-over.
- **Phase P7 — More overworld content**: additional MapArea files + map-to-map
  connections/transitions; fixed-composition encounters for tutorial/story battles.
- **Phase P8 — Skill learning**: implement `Character._learn_skills_at_level()` per hero
  (currently a stub).
- **Phase P9 — Real art**: player sprite, overworld tilemap, enemy/hero portraits
  (placeholders are colored letter-tiles today).
- **Phase P10 — Story & cutscenes**: dialogue system, story flags, scripted events;
  the title "The Amethyst Requiem" and the AMETHYST element/triple-resonance are the
  narrative payoff.

### Backlog / ideas
- Boss enemies (full-width cards, multi-phase, unique mechanics).
- Status-cleansing items/skills (antidote already exists for poison/burn — extend to
  the new statuses), and a way to cure paralysis (currently only clears at battle end).
- More heroes (add to `PartyFactory` + `HeroPalette.HERO_BASE_COLORS` +
  `ResonanceMenu.COMBINED_ATTACK_NAMES`).
