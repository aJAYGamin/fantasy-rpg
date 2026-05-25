# The Amethyst Requiem — Project Context for Claude Code

## Project Overview
A turn-based RPG built in **Godot 4 (GDScript)**, currently in active development.
The core battle system is largely complete. The focus going forward is fixing bugs,
polishing UI, and expanding content (maps, enemies, items, story).

---

## Engine & Setup
- **Engine:** Godot 4.6.1 stable
- **Language:** GDScript
- **Autoload Singleton:** `GameManager` (`res://scripts/GameManager.gd`)
- **Main scenes:** `MainMenu.tscn`, `BattleScene.tscn`
- **Fonts:** Cinzel-Regular.ttf, Cinzel-Bold.ttf (`res://fonts/`)

---

## File Structure
```
scripts/
  GameManager.gd              # Autoload: party, gold, saves, species memory, overworld↔battle handoff
  PartyFactory.gd             # Static: builds the default party (Aria/Kael/Lyra) with skills
  GradientDivider.gd          # Visual utility node
  overworld/
    OverworldScene.gd         # Free-roam controller; step-based encounter rolls
    Player.gd                 # CharacterBody2D, 8-dir arrow/controller movement
    MapArea.gd                # Resource: area metadata + encounter group list
    EncounterGroup.gd         # Resource: weighted encounter (pool + count range + level gate)
  save/
    SaveSerializer.gd         # Pure static: Character/Skill/Item/Inventory ↔ Dictionary (full, option 1B)
  battle/
    BattleScene.gd            # Main battle controller & UI wiring
    BattleManager.gd          # Turn logic, state machine, action dispatch
    AttackMenu.gd             # Attack/Special skill picker (2x2 grid)
    ResonanceMenu.gd          # Resonance/ultimate action picker
    ItemsMenu.gd              # In-battle item picker
    VictoryScreen.gd          # Post-battle EXP/gold animation + level-up trigger
    LevelUpScreen.gd          # Stat gain display per hero
    DefeatScreen.gd           # Continue / Quit Game
    TurnOrderIndicator.gd     # Side panel showing upcoming turn order
    EnemyAI.gd                # Enemy decision-making + Memory Echo dodge logic
    ResonanceSystem.gd        # Resonance meter management for all party members
    EnemyInfoRow.gd           # Top HUD — enemy HP/name cards
    PartyStatusBar.gd         # Bottom HUD — hero HP/MP bars + resonance pips
  characters/
    Character.gd              # Base class (Resource) for heroes & enemies
    Enemy.gd                  # Extends Character; adds drops, EXP/gold rewards, Memory Echo
    Skill.gd                  # Skill resource: damage/heal/buff, attack types, elements
  inventory/
    Inventory.gd              # Per-character item container
    Item.gd                   # Item resource with use() logic
  systems/
    ElementalSystem.gd        # Element enum, weakness/resistance tables, colors, icons
    Rarity.gd                 # Enemy rarity tiers (COMMON→LEGENDARY), multipliers
scenes/
  BattleScene.tscn
  MainMenu.tscn
  OverworldScene.tscn         # has a MapArea (Fallster Plains) assigned via @export
data/                         # data-driven content (.tres resources)
  enemies/                    # one .tres per enemy (stats + skills, some shared)
  skills/                     # shared skill .tres files (referenced by enemies)
  encounters/                 # EncounterGroup .tres files
  maps/                       # MapArea .tres files (fallster_plains.tres)
tests/                        # unit tests (see Testing Policy)
  TestRunner.tscn/.gd         # run this scene (F6) to execute all suites
  TestSuite.gd                # base class with assert_* helpers
  suites/                     # one test_<feature>.gd per system
assets/
  backgrounds/
    FallsterPlains.png
  characters/
  enemies/
  icons/
  ui/
fonts/
music/
```

---

## Core Systems

### Character (Resource)
Base class for all heroes and enemies.
- Stats: `base_hp`, `base_mp`, `base_attack`, `base_defense`, `base_magic`, `base_speed`
- Scaled by level: `max_hp()`, `max_mp()`, `attack_power()`, `defense_power()`, `magic_power()`, `speed()`
- Elemental affinity: `element`, `extra_weakness`, `extra_resistance`
- Leveling: `gain_experience(amount)` → returns `true` if leveled up; `level_up()` restores HP/MP
- Status effects: `add_status()`, `remove_status()`, `is_status()`, `process_status_effects()`
- Inventory: per-character `Inventory` resource

### Skill (Resource)
- `SkillType`: `DAMAGE`, `STATUS`  ⚠️ (refactored — was `DAMAGE/HEAL/BUFF`)
- `StatusType`: `HEAL`, `BUFF`, `DEBUFF` — sub-category used when `skill_type == STATUS`
- `AttackType`: `STRIKE`, `RANGED`, `MAGIC`, `STATUS`
- `TargetType`: `SINGLE_ENEMY`, `ALL_ENEMIES`, `SINGLE_ALLY`, `ALL_ALLIES`, `SELF`
- Key methods:
  - `calculate_value(user)` — damage/heal amount based on stats × power
  - `can_use(user)` — checks MP and stun status
  - `is_heal()` / `is_buff()` / `is_debuff()` — true when STATUS + matching status_type
  - `is_physical()` / `is_magic()`
  - `get_attack_type_display()` → "Strike" / "Ranged" / "Magic" / "Status"
  - `get_skill_type_display()` → attack type for DAMAGE, else "Heal"/"Buff"/"Debuff"
  - `get_target_description()` → human-readable target string
  - `get_resonance_gain()` → float (default 10.0 for DAMAGE skills, 0 for STATUS)
  - `get_element_display()` → icon + name string
- `skills` is `@export` on Character — enemies define skills in `.tres` files
- Hero skills: indices 0–3 = attacks, 4–7 = specials
- `resonance_gain_override`: set ≥ 0.0 to override default resonance per use

### ElementalSystem (Autoload or static class)
- Elements: `NONE, FIRE, ICE, LIGHTNING, WATER, EARTH, WIND, LIGHT, DARK, ARCANE`
- `get_element_name()`, `get_element_icon()`, `get_element_color()`
- Weakness/resistance multipliers applied in `Character.take_damage()` and `take_magic_damage()`

### Rarity
- Tiers: `COMMON, UNCOMMON, RARE, EPIC, LEGENDARY`
- `get_exp_multiplier()`, `get_loot_multiplier()`, `get_color()`, `get_name()`

### ResonanceSystem (Node, child of BattleScene)
- Tracks a 0–100 resonance meter per party member
- Gains: 10% per damage skill/attack; 10% when taking damage
- `on_attack(attacker)`, `on_skill_used(user, skill)`, `on_damage_taken(character)`
- `is_full(character)` → bool; `can_combine(characters)` → bool (≥2 members all full)
- `spend_solo_ultimate(character)`, `spend_combined_resonance(characters)`
- Signals: `resonance_changed`, `resonance_full`, `resonance_spent`, `combined_resonance_ready`

### BattleManager (Node)
- State machine: `IDLE → CHOOSING_ACTION → CHOOSING_TARGET → EXECUTING_ACTION → ENEMY_TURN → BATTLE_OVER`
- Turn order built by speed, rebuilt each round
- Player actions: `player_attack()`, `player_use_skill()`, `player_use_item()`
- Enemy actions: `enemy_use_skill()`
- Signals: `battle_started`, `turn_started`, `action_performed`, `character_defeated`, `battle_ended`, `status_effect_triggered`

### EnemyAI
- Static class. `choose_action(enemy, party, enemies)` → `{skill, target, is_enraged, echo_tier}`
- Memory Echo dodge thresholds (`ECHO_TIER_*`, must match `Enemy.MEMORY_THRESHOLD_*`):
  - Tier 1 = 3 encounters → 5% dodge
  - Tier 2 = 7 encounters → 10% dodge
  - Tier 3 = 15 encounters → 15% dodge
- `try_dodge(target, is_resonance, can_miss)` — resonance/can't-miss always hit
- Dodge is checked in BattleManager for **both** enemy→hero and hero→enemy attacks

### GameManager (Autoload)
- `party: Array[Character]` (max 4) — source of truth; persists across battles
- `ensure_default_party()` — populates via `PartyFactory` if empty
- `gold: int` with setter (clamps to ≥0, emits `gold_changed`)
- `species_memory: Dictionary` — species name → encounter count
- `award_rewards(rewards)` — gold + items only. **EXP is NOT applied here** —
  VictoryScreen owns the EXP/level-up flow (applying it both places double-counts).
- `revive_party()` — dead members → 50% HP
- Overworld↔battle handoff: `in_overworld_battle`, `pending_battle_enemies: Array[Enemy]`,
  `pending_battle_background`, `pending_overworld_scene_path`, `pending_overworld_return_position`
- Save/load to `user://savegame.json`
- `record_battle_against(species)`, `get_species_memory(species)`

### Overworld & Encounter System
- `OverworldScene.gd` reads an `@export var area: MapArea` (assigned per scene)
- Movement: 8-dir, `ui_*` actions (arrow keys + gamepad auto-bound for future controller)
- Encounters: every 32px = 1 "step"; encounter chance += 1%/step, resets on encounter
- On encounter: weighted-random pick among `area.encounter_groups` filtered by
  `min_party_level` (vs party's max level); group instantiates deep-copied enemies
  (with optional `enemy_level_override`) into `GameManager.pending_battle_enemies`
- Battle exits (victory continue / run / defeat continue) return to the overworld
  at `pending_overworld_return_position`; defeat revives party at 50% HP
- `BattleScene._ready()` branches: `in_overworld_battle` → `_start_overworld_battle()`,
  else `_start_test_battle()` (10-enemy debug battle via F5/F6 on BattleScene)
- **EncounterGroup**: `weight`, `min_party_level`, `enemy_pool: Array[Enemy]`,
  `min_enemies`/`max_enemies`, `enemy_level_override` (0 = keep template level).
  Fixed-composition mode (tutorials/story) is a planned future flag.
- **MapArea**: `area_name`, `battle_background_id`, `default_spawn`, `encounter_groups`

---

## Battle UI Structure (BattleScene.tscn)
```
BattleScene (Node2D)
├── Background (Sprite2D / TextureRect)
├── CharactersLayer (Node2D)
│   ├── PartyPositions (VBoxContainer)  ← hero portrait wrappers
│   └── EnemyPositions (Node2D)         ← enemy portrait grid
└── BattleUI (CanvasLayer)
    └── UIRoot (Control)
        ├── EnemyInfoRow (HBoxContainer)   ← enemy HP cards across top
        ├── PartyStatusBar (HBoxContainer) ← 3 hero panels bottom-left
        ├── ActionMenu                     ← Attack / Special / Items / Run / Resonance
        ├── VictoryScreen
        ├── DefeatScreen
        ├── LevelUpScreen
        │   ├── Overlay (ColorRect)
        │   └── PanelsRow (HBoxContainer)
        ├── TurnOrderIndicator (VBoxContainer)
        ├── AttackMenu       ← skill picker (attack or special)
        ├── ResonanceMenu    ← resonance ultimate picker
        └── ItemsMenu        ← in-battle item picker
```

---

## AttackMenu Details
- Shows 4 skills in a 2×2 grid (attacks: hero.skills[0–3], specials: [4–7])
- Each slot: skill name button + `?` description toggle + element/type/MP info row
- `_get_attack_type(skill)` — returns display string, used for coloring via `ATTACK_TYPE_COLORS`
- `ATTACK_TYPE_COLORS`: Strike=orange, Magic=purple, Ranged=green, Status=pink, Resonance=lavender
- Signals: `move_selected(skill, targets)`, `menu_closed`
- If `targets` array is empty when `move_selected` fires, BattleScene enters target selection mode

---

## VictoryScreen Flow
1. Delay 1.2s → fade in overlay + content
2. Build party EXP bars, build rewards label
3. Animate gold count-up (1.2s tween)
4. Animate EXP bars (1.2s tween)
5. Apply EXP via `hero.gain_experience()`; collect leveled heroes
6. Show Continue button (labelled "Level Up!" if any hero leveled)
7. On Continue: if leveled heroes exist → hide VictoryScreen, show LevelUpScreen
8. After LevelUpScreen completes (`level_up_complete` signal) → show VictoryScreen again, re-animate EXP from 0

---

## Party / Enemy Setup
- Heroes built by `PartyFactory.create_default_party()` → Aria (Mage/Arcane),
  Kael (Warrior/Fire), Lyra (Healer/Wind); each 8 skills + ultimate meta.
  Stored in `GameManager.party`, persists across battles.
- Enemies are `.tres` files in `data/enemies/`, loaded + `.duplicate(true)`'d.
  Shared skills live in `data/skills/` and are referenced by multiple enemies.
- `_start_test_battle()` = 10-enemy debug battle (F5/F6 on BattleScene directly).

---

## Known Patterns & Conventions
- All characters/skills/items are **Resources** (not Nodes) so they can be created with `.new()`
- `Character.take_damage()` returns a Dictionary: `{damage, multiplier, effectiveness, effectiveness_color}`
- Status effects are plain strings: `"poison"`, `"regenerate"`, `"stun"`, `"burn"`, `"buff_atk_20"`, etc.
- `_build_menu()` in AttackMenu/ResonanceMenu/ItemsMenu always clears and rebuilds children from scratch
- Fonts are always loaded inline: `load("res://fonts/Cinzel-Regular.ttf")`
- All battle-result data flows through the `action_performed(result: Dictionary)` signal

---

## Testing Policy (IMPORTANT)
- **Every new feature must ship with a unit test**, no matter how small.
- Tests live in `tests/suites/test_<feature>.gd`, `extends TestSuite`, methods
  prefixed `test_`, using `assert_*` helpers from `tests/TestSuite.gd`.
- Register new suites in `TestRunner.gd`'s `SUITE_PATHS`.
- Run: open `tests/TestRunner.tscn` → F6 (Run Current Scene) → read the Output panel.
  GameManager autoload is available because the runner runs in the scene tree.
- Tests touching autoload/global state (GameManager) must snapshot & restore it.
- When fixing a bug, add a regression test that fails before the fix.

## Working in the Godot Editor
- **Any step that the user must perform in the Godot editor must be given as
  numbered, step-by-step instructions.** Do not assume the user knows where
  menus/buttons live. Include: which scene/file to open, the exact path through
  panels (e.g. "Inspector → Resource → New EncounterGroup"), what to type, and
  what to expect to see when it worked.
- Prefer code/data changes you can make directly. Editor steps are only for
  things that genuinely cannot be done via files (scene-tree edits the user
  must trigger, importing assets, running scenes, etc.).

## Permissions / Settings
- Project allowlist: `<repo-root>/.claude/settings.json` (`permissions.allow`).
- Allowlisted = safe read-only Bash (`cd`, `cat`, `grep`, `rg`, `ls`, `find`,
  `wc`, `head`, `tail`, `echo`, `git status/diff/log/branch/show`).
- `Edit`/`Write`/`MultiEdit` are allowed **repo-wide without prompting**, scoped
  to the repo root path (`Edit(//.../fantasy-rpg/**)` etc). Edits *outside* the
  repo still prompt — keep that boundary; don't broaden to a blanket tool grant.
- Intentionally NOT allowlisted: `mkdir`/`rm` (mutating), `python3`/`node`/shells
  (arbitrary code execution). Don't add these without explicit user consent.
- Work directly on `main` (not in worktrees) unless the user asks for a branch.

---

## Save System Design Decisions (Phase S series — in progress)
- **Full serialization (option 1B)** — every Character/Skill/Item field saved as
  JSON dict. Reconstructs Resources without depending on PartyFactory at load time.
- **3 slots** at `user://save_slot_{0,1,2}.json`. `GameManager.active_slot`
  tracks the current slot (-1 = none); persisted to `user://config.cfg`.
- **Continue behavior:** if exactly one save exists, Continue loads it directly.
  If multiple exist, Continue opens `SaveSlotMenu` in load mode (occupied slots
  show "Load" + Copy; empty slots are non-interactive). Delete is hidden in
  load mode so a player choosing what to continue can't accidentally erase a
  save — deletion lives only in the New Game picker. Disabled if zero saves.
- **Save UX is pause-menu driven, not save points.** Esc in the overworld opens
  `PauseMenu` (Resume / Save / Stats / Items / Equipment / Settings / Quit).
  Save writes to `active_slot` (the slot the player chose at New Game / Continue);
  no slot picker mid-game. Quit to Main Menu prompts a confirm, then transitions.
- **Auto-save triggers (planned, Phase S7):** entering a town/city/village
  (`MapArea.auto_save_on_enter`), and explicit story-cutscene calls.
  Player-toggleable in Settings (planned, Phase S6).
- **Defeat flow** (planned): party defeated → Continue / Quit screen.
  Continue = load from active slot; Quit = MainMenu. (Currently defeat still
  revives at 50% and returns to overworld — gets replaced once slots are wired.)

## Recent Changes (most recent first)
- **Phase 3:** `MapArea` + `EncounterGroup` resources; data-driven weighted
  encounters with party-level gating; enemy level override per group.
- **Phase 2:** Overworld scene, step-based encounters, battle round-trip,
  `PartyFactory`, party persistence in `GameManager`.
- **UI:** animated HP/MP/Resonance bars (`_animate_bar`, 0.3s tween); fixed-width
  centered enemy cards (bosses will use full-width later); enemy level indicator.
- **Bug fixes:** level-up no longer restores HP/MP; EXP applied once (VictoryScreen
  only); Memory Echo dodge wired into hero→enemy attacks + thresholds lowered to 3/7/15.
- **Skill refactor:** `SkillType` is `DAMAGE/STATUS`; `StatusType` added;
  `is_heal/is_buff/is_debuff` added; `Character.skills` is `@export`.
- Enemy roster moved to `data/enemies/*.tres`; shared skills in `data/skills/`.

## Next Steps / Open Tasks
- Save/load: 3 save slots, fixed save points, toggleable auto-save after battles
- Settings menu (auto-save toggle, etc.)
- Save status indicator (placeholder, bottom-right)
- More overworld areas (MapArea files) + map-to-map connections
- Equipment system (Inventory.get_weapon_attack / get_armor_defense return 0)
- Implement `_learn_skills_at_level()` per hero
- Real art: player sprite, overworld map, enemy/hero portraits
- Fixed-composition encounters for tutorial/story battles
