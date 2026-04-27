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
  GameManager.gd              # Autoload: party, gold, saves, species memory
  GradientDivider.gd          # Visual utility node
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
- `SkillType`: `DAMAGE`, `HEAL`, `BUFF`
- `AttackType`: `STRIKE`, `RANGED`, `MAGIC`, `STATUS`
- `TargetType`: `SINGLE_ENEMY`, `ALL_ENEMIES`, `SINGLE_ALLY`, `ALL_ALLIES`, `SELF`
- Key methods:
  - `calculate_value(user)` — damage/heal amount based on stats × power
  - `can_use(user)` — checks MP and stun status
  - `get_attack_type_display()` → "Strike" / "Ranged" / "Magic" / "Status"
  - `get_skill_type_display()` → delegates to attack type for DAMAGE, else "Heal"/"Buff"
  - `get_target_description()` → human-readable target string
  - `get_resonance_gain()` → float (default 10.0 for DAMAGE skills)
  - `get_element_display()` → icon + name string
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
- Static class. `choose_action(enemy, party, enemies)` → `{skill, targets}`
- Memory Echo: the more times a species is fought, the higher their dodge chance (Tier 1: 5%, Tier 2: 10%, Tier 3: 15%)
- `try_dodge(target, is_resonance, can_miss)` — resonance attacks always hit

### GameManager (Autoload)
- `party: Array[Character]` (max 4)
- `gold: int` with setter (clamps to ≥0, emits `gold_changed`)
- `species_memory: Dictionary` — species name → encounter count
- `award_rewards(rewards)` — distributes EXP (shared) + gold + items
- Save/load to `user://savegame.json`
- `record_battle_against(species)`, `get_species_memory(species)`

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

## Test Battle Setup (in BattleScene._start_test_battle)
Heroes: **Aria** (Mage/Arcane), **Kael** (Warrior/Fire), **Lyra** (Ranger/Wind)
- Aria: Arcane Slash, Frost Bolt, Dark Pulse, Arcane Storm | Specials: index 4–7
- Each hero has `set_meta("ultimate_name", ...)` and `set_meta("ultimate_desc", ...)`
- Enemies: currently spawned inline; use `EnemyLayout.GRID_2COL` by default

---

## Known Patterns & Conventions
- All characters/skills/items are **Resources** (not Nodes) so they can be created with `.new()`
- `Character.take_damage()` returns a Dictionary: `{damage, multiplier, effectiveness, effectiveness_color}`
- Status effects are plain strings: `"poison"`, `"regenerate"`, `"stun"`, `"burn"`, `"buff_atk_20"`, etc.
- `_build_menu()` in AttackMenu/ResonanceMenu/ItemsMenu always clears and rebuilds children from scratch
- Fonts are always loaded inline: `load("res://fonts/Cinzel-Regular.ttf")`
- All battle-result data flows through the `action_performed(result: Dictionary)` signal

---

## Recent Bug Fixed
**Error:** `Invalid call. Nonexistent function 'get_skill_type_display' in base 'Resource (Skill)'`
**Location:** `AttackMenu.gd:285`
**Fix:** Added `get_skill_type_display()` to `Skill.gd`. For DAMAGE skills it delegates to
`get_attack_type_display()`; for HEAL/BUFF it returns the type name directly.

---

## Next Steps / Open Tasks
- Fix any remaining errors in AttackMenu or related scripts
- Expand enemy roster with `.tres` resource files
- Build overworld / map scene
- Add equipment system (Inventory.get_weapon_attack / get_armor_defense currently return 0)
- Implement `_learn_skills_at_level()` per hero subclass
- Save/load for party characters (currently only gold/flags/memory are saved)
