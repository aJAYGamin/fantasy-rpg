# Move Library + Unified Resolver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move every hero and enemy move into its own file so moves can be shared, save moves by reference, and replace the two drifted skill resolvers with one — fixing enemy area attacks that currently hit a single hero.

**Architecture:** 86 `Skill` resources live flat in `data/skills/`. Heroes hold their own `.duplicate()` of each file (stamped with per-hero unlock level and category); enemies reference the files directly. Saves store the existing per-skill dictionary plus a `source_path`, loading behaviour from the file when it exists and falling back to the snapshot. `BattleManager.resolve_skill` becomes the only skill resolver, with target expansion in one place.

**Tech Stack:** Godot 4.6.1, GDScript. Tests use the project's `TestSuite` harness.

**Spec:** `.claude/docs/superpowers/specs/2026-09-26-move-library-and-unified-resolver-design.md`

## Global Constraints

- **Godot 4.6.1**, binary `/Applications/Godot.app/Contents/MacOS/Godot`.
- **Run tests** from `new-game-project/`: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/TestRunner.tscn --quit-after 5`. **Baseline: 2498 passing, 0 failed.** Never let it drop.
- **Branch `move-library-unified-resolver`** — already created, spec already committed. Never commit to `main`.
- **Commit attribution:** every commit message ends `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Write commit messages to a file and use `git commit -F <file>`.** Backticks inside a shell heredoc are executed as command substitution and silently corrupt the message — this has happened twice in this repo.
- **Tests run synchronously in one frame.** No `await`. No reliance on `queue_free()` having finished.
- **Tool scripts run as SCENES, not `--script`.** `Inventory.gd` reads `GameManager.settings`, and a `--script` SceneTree runs before autoloads exist, so building the party there crashes. Pattern: a `.tscn` whose root `Node` does its work in `_ready()` after `await get_tree().process_frame`, then `get_tree().quit()`.
- **After any task that creates or rewrites `.tres` files**, run the headless editor rescan before trusting a test run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --quit-after 3 --path .`
- **Library:** exactly **86** files, flat in `res://data/skills/`, each named `snake_case(skill_name) + ".tres"` (lowercase, every run of non-`[a-z0-9]` characters becomes `_`, leading/trailing `_` stripped). Verified: **no name or filename collisions** exist among the 34 hero + 51 inline enemy + 1 existing (`Blizzard`) moves.
- **Mend merge (user decision):** `mend.tres` = **Light, power 1.8, 12 MP**. `grand_mend.tres` = **Light, power 1.5, 30 MP**.
- **Library files carry neutral per-hero fields:** `unlock_level = 1`, `category = Skill.SkillCategory.ATTACK`, `source_path = ""`.
- **Action names:** a damage skill emits `"skill_physical"` (STRIKE/RANGED) or `"skill_magic"` (MAGIC) **for heroes and enemies alike**. Never `"attack"` for a skill.
- **Enemies never pay MP.**
- **Out of scope:** new skill mechanics (Spec B), multi-turn (Spec C), basic attacks (`player_attack`, the enemy no-skill attack), rebalancing, art.
- **No new `class_name`** is introduced.
- **Tests must not kill characters through `handle_defeat`** unless defeat is what they test: `handle_defeat` reports quest progress to the live `GameManager`. Give damage targets enough HP to survive.

## Review Focus

Failure modes the spec implies that no happy-path test would catch. Each is pinned by a test in the owning task.

1. **The load path hands two heroes the same cached object.** `load()` returns Godot's cached resource; if save loading does not duplicate it, Aria's and Lyra's Mend become one object again after a save/load and the clobbering the whole design avoids comes straight back. *(Task 4)*
2. **Loading takes `unlock_level` / `category` from the file instead of the save.** Library files carry `unlock_level = 1`, so every hero would unlock every move at level 1 — the exact P8 bug. *(Task 4)*
3. **An area attack against a party with a downed hero** must skip the downed one, hit the living, and not crash. *(Task 5)*
4. **An enemy's `ALL_ALLIES` skill must include allies summoned mid-battle**, which are appended to `enemies` after the fight starts. *(Task 5)*
5. **A pre-migration save of Lyra's Wind Mend re-links to the shared Light Mend at 12 MP.** An intended change the player will see; pinned so it is deliberate, not accidental. *(Task 4)*

---

## File Structure

| File | Responsibility |
|---|---|
| `tools/capture_move_baseline.tscn` / `.gd` *(new)* | One-shot: records every pool and enemy move before migration |
| `tests/fixtures/move_library_baseline.json` *(new, generated)* | The pre-migration reference the migration is checked against |
| `tools/extract_move_library.tscn` / `.gd` *(new)* | One-shot, idempotent: writes the 86 files and rewires enemies |
| `data/skills/*.tres` *(86, generated)* | One move each |
| `data/enemies/*.tres` *(14, regenerated)* | Reference library files instead of inline moves |
| `scripts/characters/Skill.gd` *(modify)* | Adds `source_path` |
| `scripts/PartyFactory.gd` *(modify)* | Builds pools from library copies; loses `_make_skill` / `_make_status_skill` |
| `scripts/save/SaveSerializer.gd` *(modify)* | Saves and loads moves by reference |
| `scripts/battle/BattleManager.gd` *(modify)* | `expand_targets`, `resolve_skill`; the two resolvers become wrappers |
| `tests/suites/test_move_library.gd` *(new)* | Library, pools, saves |
| `tests/suites/test_skill_resolver.gd` *(new)* | Targeting and resolution |
| `CLAUDE.md` *(modify)* | Documents the system |

---

## Task 1: Capture the pre-migration baseline

**Files:**
- Create: `tools/capture_move_baseline.tscn`, `tools/capture_move_baseline.gd`
- Create (generated): `tests/fixtures/move_library_baseline.json`
- Create: `tests/suites/test_move_library.gd`
- Modify: `tests/TestRunner.gd`

**Interfaces:**
- Consumes: `PartyFactory.create_default_party()`, `SaveSerializer.serialize_skill(s)`, `ResourceLoader.list_directory(path)`.
- Produces: the fixture JSON, shaped `{"heroes": {"Aria": [<serialize_skill dict>, ... 12]}, "enemies": {"res://data/enemies/x.tres": {"uid": "uid://...", "skills": [<dict>...], "phase_skills": [[<dict>...], ...]}}}`. Tasks 2 and 3 compare against it.

This task must run on the **current, unmodified** code. Its output is the reference the migration is judged by.

- [ ] **Step 1: Write the capture tool**

Create `tools/capture_move_baseline.gd`:

```gdscript
extends Node

## One-shot: records every hero's move pool and every enemy's moves exactly as
## they are BEFORE the move-library migration, so the migration can be checked
## automatically rather than by eye.
##
##   godot --headless --path . res://tools/capture_move_baseline.tscn
##
## Writes tests/fixtures/move_library_baseline.json. Run it ONCE, on the
## pre-migration code. Re-running after the migration would overwrite the
## reference with the migrated state and make the comparison meaningless.

const OUT := "res://tests/fixtures/move_library_baseline.json"

func _ready() -> void:
	await get_tree().process_frame

	var heroes := {}
	for hero in PartyFactory.create_default_party():
		var pool: Array = []
		for s in hero.skills:
			pool.append(SaveSerializer.serialize_skill(s))
		heroes[hero.character_name] = pool

	var enemies := {}
	for f in ResourceLoader.list_directory("res://data/enemies"):
		if not f.ends_with(".tres"):
			continue
		var path := "res://data/enemies/" + f
		var e: Enemy = load(path)
		var skills: Array = []
		for s in e.skills:
			skills.append(SaveSerializer.serialize_skill(s))
		var phase_skills: Array = []
		for ph in e.phases:
			var ps: Array = []
			for s in ph.skills:
				ps.append(SaveSerializer.serialize_skill(s))
			phase_skills.append(ps)
		enemies[path] = {
			"uid": ResourceUID.id_to_text(ResourceLoader.get_resource_uid(path)),
			"skills": skills,
			"phase_skills": phase_skills,
		}

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/fixtures"))
	var out := FileAccess.open(OUT, FileAccess.WRITE)
	out.store_string(JSON.stringify({"heroes": heroes, "enemies": enemies}, "\t"))
	out.close()
	print("baseline: %d heroes, %d enemies -> %s" % [heroes.size(), enemies.size(), OUT])
	get_tree().quit()
```

Create `tools/capture_move_baseline.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tools/capture_move_baseline.gd" id="1"]

[node name="CaptureMoveBaseline" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: Run it**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tools/capture_move_baseline.tscn
```
Expected output ends: `baseline: 3 heroes, 14 enemies -> res://tests/fixtures/move_library_baseline.json`

- [ ] **Step 3: Write the test that pins the fixture**

Create `tests/suites/test_move_library.gd`:

```gdscript
extends TestSuite

## The move library: every move lives in its own file, heroes hold their own
## copies, saves reference moves by file — and nothing about any hero's or
## enemy's kit changed except the approved Mend / Grand Mend merge.

func suite_name() -> String:
	return "MoveLibrary"

const BASELINE := "res://tests/fixtures/move_library_baseline.json"
const LIB := "res://data/skills/"

func _baseline() -> Dictionary:
	var f := FileAccess.open(BASELINE, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

## "" when `actual` agrees with `expected` on every key `expected` has (minus
## `ignore`); otherwise a description of the first mismatch. JSON has a single
## number type, so numbers compare as floats.
func _move_diff(actual: Dictionary, expected: Dictionary, ignore: Array = []) -> String:
	for k in expected:
		if k in ignore:
			continue
		var a = actual.get(k)
		var e = expected[k]
		if (a is int or a is float) and (e is int or e is float):
			if not is_equal_approx(float(a), float(e)):
				return "%s: got %s, expected %s" % [k, str(a), str(e)]
		elif a != e:
			return "%s: got %s, expected %s" % [k, str(a), str(e)]
	return ""

func test_baseline_fixture_is_present_and_complete() -> void:
	var b := _baseline()
	assert_false(b.is_empty(), "the pre-migration baseline exists and parses")
	var heroes: Dictionary = b.get("heroes", {})
	for name in ["Aria", "Kael", "Lyra"]:
		assert_eq((heroes.get(name, []) as Array).size(), 12, "%s's full pool was captured" % name)
	assert_eq((b.get("enemies", {}) as Dictionary).size(), 14, "all 14 enemy files were captured")
```

- [ ] **Step 4: Register the suite**

In `tests/TestRunner.gd` `SUITE_PATHS`, after `"res://tests/suites/test_boss_phases.gd",` add:
```gdscript
	"res://tests/suites/test_move_library.gd",
```

- [ ] **Step 5: Run the tests**

Run the test command. Expected: `MoveLibrary [OK]`, TOTAL 0 failed, ≥ 2498 passed.

- [ ] **Step 6: Commit**

```bash
git add tools/capture_move_baseline.gd tools/capture_move_baseline.tscn tests/fixtures/move_library_baseline.json tests/suites/test_move_library.gd tests/TestRunner.gd
git commit -F /tmp/task1-msg.txt
```
Message: `Capture the pre-migration move baseline` — explain that the fixture is the reference the migration is verified against, and that the tool must never be re-run after migration.

---

## Task 2: Build the library and rewire enemies

**Files:**
- Modify: `scripts/characters/Skill.gd`
- Create: `tools/extract_move_library.tscn`, `tools/extract_move_library.gd`
- Generated: 86 files in `data/skills/`; 14 rewritten `data/enemies/*.tres`
- Delete: `data/skills/Skill_blizzard.tres`
- Modify: `tests/suites/test_move_library.gd`

**Interfaces:**
- Consumes: the fixture (Task 1); `PartyFactory._create_aria()`, `_create_kael()`, `_create_lyra()` (still built from `_make_skill` at this point).
- Produces: `Skill.source_path: String` (exported, default `""`). The 86 library files. Enemies whose every move (including every `BossPhase.skills` entry) is a library resource.

- [ ] **Step 1: Add `source_path` to Skill**

In `scripts/characters/Skill.gd`, directly after `@export var category: SkillCategory = SkillCategory.ATTACK`, add:

```gdscript

## The library file this move was loaded from ("" for a move with no file).
## Set on each hero's own copy; read by SaveSerializer to save the move by
## reference, so an edited move file reaches existing saves. Library files
## themselves leave it empty.
@export var source_path: String = ""
```

- [ ] **Step 2: Write the failing tests**

Append to `tests/suites/test_move_library.gd`:

```gdscript
# --------------------------------------------------- the library itself

func _library_files() -> Array[String]:
	var out: Array[String] = []
	for f in ResourceLoader.list_directory(LIB):
		if f.ends_with(".tres"):
			out.append(LIB + f)
	return out

func _enemy_paths() -> Array[String]:
	var out: Array[String] = []
	for f in ResourceLoader.list_directory("res://data/enemies"):
		if f.ends_with(".tres"):
			out.append("res://data/enemies/" + f)
	return out

func _is_library_move(s: Skill) -> bool:
	# An inline sub-resource's path looks like "res://data/enemies/x.tres::Skill_y".
	return s != null and s.resource_path.begins_with(LIB) and not s.resource_path.contains("::")

func test_the_library_holds_every_move() -> void:
	assert_eq(_library_files().size(), 86, "34 hero + 51 enemy + blizzard = 86 moves")

func test_every_library_file_is_a_skill() -> void:
	for path in _library_files():
		assert_true(load(path) is Skill, "%s loads as a Skill" % path)

func test_library_files_carry_no_per_hero_data() -> void:
	# When a hero learns a move is stamped on that hero's own copy. A file that
	# carried it would leak one hero's unlock level to every user of the move.
	for path in _library_files():
		var s: Skill = load(path)
		assert_eq(s.unlock_level, 1, "%s has the neutral unlock level" % path)
		assert_eq(int(s.category), int(Skill.SkillCategory.ATTACK), "%s has the neutral category" % path)
		assert_eq(s.source_path, "", "%s does not point at itself" % path)

func test_every_enemy_move_is_a_library_file() -> void:
	for path in _enemy_paths():
		var e: Enemy = load(path)
		for s in e.skills:
			assert_true(_is_library_move(s), "%s: %s comes from the library" % [path, s.skill_name])
		for ph in e.phases:
			for s in ph.skills:
				assert_true(_is_library_move(s), "%s phase move %s comes from the library" % [path, s.skill_name])

func test_enemy_moves_are_unchanged_by_the_migration() -> void:
	var b: Dictionary = _baseline().get("enemies", {})
	for path in _enemy_paths():
		var expected: Dictionary = b.get(path, {})
		var e: Enemy = load(path)
		var want: Array = expected.get("skills", [])
		assert_eq(e.skills.size(), want.size(), "%s kept its move count" % path)
		for i in mini(e.skills.size(), want.size()):
			var diff := _move_diff(SaveSerializer.serialize_skill(e.skills[i]), want[i])
			assert_eq(diff, "", "%s move %d unchanged" % [path, i])
		var want_phases: Array = expected.get("phase_skills", [])
		for p in mini(e.phases.size(), want_phases.size()):
			var wp: Array = want_phases[p]
			for i in mini(e.phases[p].skills.size(), wp.size()):
				var diff := _move_diff(SaveSerializer.serialize_skill(e.phases[p].skills[i]), wp[i])
				assert_eq(diff, "", "%s phase %d move %d unchanged" % [path, p, i])

func test_enemy_uids_survive_the_rewrite() -> void:
	# Encounter groups reference enemies by uid. A rewrite that minted new uids
	# would orphan every encounter that uses them.
	var b: Dictionary = _baseline().get("enemies", {})
	for path in _enemy_paths():
		var now := ResourceUID.id_to_text(ResourceLoader.get_resource_uid(path))
		assert_eq(now, String((b.get(path, {}) as Dictionary).get("uid", "")), "%s kept its uid" % path)

func test_blizzard_was_renamed_and_rewired() -> void:
	assert_false(ResourceLoader.exists(LIB + "Skill_blizzard.tres"), "the old name is gone")
	for path in ["res://data/enemies/ice_golem.tres", "res://data/enemies/frost_wyrm.tres"]:
		var e: Enemy = load(path)
		var found := false
		for s in e.skills:
			if s.resource_path == LIB + "blizzard.tres":
				found = true
		assert_true(found, "%s uses blizzard.tres" % path)

func test_mend_is_the_merged_heal() -> void:
	var mend: Skill = load(LIB + "mend.tres")
	assert_eq(int(mend.element), int(ElementalSystem.Element.LIGHT), "Mend is Light")
	assert_eq(mend.mp_cost, 12, "Mend costs Lyra's 12 MP")
	assert_true(is_equal_approx(mend.power, 1.8), "Mend keeps power 1.8")
	var grand: Skill = load(LIB + "grand_mend.tres")
	assert_eq(int(grand.element), int(ElementalSystem.Element.LIGHT), "Grand Mend is Light")
	assert_eq(grand.mp_cost, 30, "Grand Mend keeps 30 MP")
	assert_true(is_equal_approx(grand.power, 1.5), "Grand Mend keeps power 1.5")
```

- [ ] **Step 3: Run to verify they fail**

Expected: FAIL — `the library holds every move` reports 1, not 86.

- [ ] **Step 4: Write the extraction tool**

Create `tools/extract_move_library.gd`:

```gdscript
extends Node

## One-shot migration: writes every hero and enemy move to its own file in
## data/skills/, then rewires each enemy .tres to reference those files instead
## of carrying its moves inline.
##
##   godot --headless --path . res://tools/extract_move_library.tscn
##
## Idempotent: a move whose file already exists is not rewritten, and an enemy
## move that already references a library file is left alone, so re-running it
## after the migration changes nothing. Kept in the repo so the migration can
## be audited. Verify with the MoveLibrary test suite, which compares every
## pool and every enemy against tests/fixtures/move_library_baseline.json.

const LIB := "res://data/skills/"
const LEGACY_BLIZZARD := "res://data/skills/Skill_blizzard.tres"

## Aria and Lyra each defined their own Mend and Grand Mend. Merged into one
## shared move each (user decision): Light element; Mend at Lyra's 12 MP
## because she is the party's dedicated healer. Grand Mend was already 30 MP
## for both. Applied whichever hero's version is written first.
const MERGE_OVERRIDES := {
	"Mend": {"element": ElementalSystem.Element.LIGHT, "mp_cost": 12},
	"Grand Mend": {"element": ElementalSystem.Element.LIGHT, "mp_cost": 30},
}

var _written := {}   # skill_name -> library path

static func file_for(skill_name: String) -> String:
	var runs := RegEx.new()
	runs.compile("[^a-z0-9]+")
	var edges := RegEx.new()
	edges.compile("^_+|_+$")
	var snake := edges.sub(runs.sub(skill_name.to_lower(), "_", true), "", true)
	return LIB + snake + ".tres"

func _ready() -> void:
	await get_tree().process_frame

	for hero in [PartyFactory._create_aria(), PartyFactory._create_kael(), PartyFactory._create_lyra()]:
		for s in hero.skills:
			_write_move(s)

	var rewired := 0
	for f in ResourceLoader.list_directory("res://data/enemies"):
		if not f.ends_with(".tres"):
			continue
		var path := "res://data/enemies/" + f
		var e: Enemy = load(path)
		var changed := false
		var skills: Array[Skill] = []
		for s in e.skills:
			var ref := _library_ref(s)
			changed = changed or ref != s
			skills.append(ref)
		e.skills = skills
		for ph in e.phases:
			var ps: Array[Skill] = []
			for s in ph.skills:
				var ref := _library_ref(s)
				changed = changed or ref != s
				ps.append(ref)
			ph.skills = ps
		if changed:
			var err := ResourceSaver.save(e, path)
			if err != OK:
				push_error("could not rewrite %s (error %d)" % [path, err])
				get_tree().quit(1)
				return
			rewired += 1

	if ResourceLoader.exists(LEGACY_BLIZZARD):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY_BLIZZARD))

	print("library: %d moves written, %d enemies rewired" % [_written.size(), rewired])
	get_tree().quit()

## Writes `src` to its library file (unless that file already exists) and
## returns the path. Library files describe what a move DOES; when a particular
## hero learns it is stamped on that hero's own copy, so the file carries the
## neutral defaults.
func _write_move(src: Skill) -> String:
	var name := src.skill_name
	if _written.has(name):
		return _written[name]
	var path := file_for(name)
	if not ResourceLoader.exists(path):
		var move: Skill = src.duplicate(true)
		move.unlock_level = 1
		move.category = Skill.SkillCategory.ATTACK
		move.source_path = ""
		if MERGE_OVERRIDES.has(name):
			for key in MERGE_OVERRIDES[name]:
				move.set(key, MERGE_OVERRIDES[name][key])
		var err := ResourceSaver.save(move, path)
		if err != OK:
			push_error("could not write %s (error %d)" % [path, err])
	_written[name] = path
	return path

## The library resource an enemy should reference in place of `s`. A move that
## is already a library file is kept, except the legacy Skill_blizzard.tres,
## which is re-pointed at blizzard.tres.
func _library_ref(s: Skill) -> Skill:
	if s.resource_path.begins_with(LIB) and not s.resource_path.contains("::") \
			and s.resource_path != LEGACY_BLIZZARD:
		return s
	return load(_write_move(s))
```

Create `tools/extract_move_library.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tools/extract_move_library.gd" id="1"]

[node name="ExtractMoveLibrary" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 5: Run the migration, then rescan**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tools/extract_move_library.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --quit-after 3 --path .
```
Expected: `library: 86 moves written, 14 enemies rewired`.

If the count is not 86, **stop** — do not patch files by hand. Find why (a name that maps to an unexpected filename, or a move reached through a path the tool does not walk) and fix the tool, then `git checkout -- data/` and re-run.

- [ ] **Step 6: Run the tests to verify they pass**

Expected: `MoveLibrary [OK]`, TOTAL 0 failed. Every pre-existing suite must still pass — the enemies were rewritten, so encounter, boss and battle suites are the real check that nothing broke.

- [ ] **Step 7: Commit**

```bash
git add scripts/characters/Skill.gd tools/extract_move_library.gd tools/extract_move_library.tscn data/skills/ data/enemies/ tests/suites/test_move_library.gd
git add -u data/skills/
git commit -F /tmp/task2-msg.txt
```
Message: `Move every move into data/skills and rewire enemies` — 86 files, generated not hand-written; enemies verified unchanged against the baseline with uids preserved; Mend/Grand Mend merged to Light, Mend at 12 MP; `Skill_blizzard.tres` replaced by `blizzard.tres` (regenerated rather than renamed, so its old uid is simply unreferenced).

---

## Task 3: Build hero pools from the library

**Files:**
- Modify: `scripts/PartyFactory.gd` (`_create_aria`, `_create_kael`, `_create_lyra`; remove `_make_skill`, `_make_status_skill`)
- Modify: `tests/suites/test_move_library.gd`

**Interfaces:**
- Consumes: the 86 library files (Task 2); `Skill.source_path`.
- Produces: `PartyFactory._move(file: String) -> Skill` — returns a hero's own copy of `res://data/skills/<file>` with `source_path` set. Every hero skill has a non-empty `source_path`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_move_library.gd`:

```gdscript
# --------------------------------------------------- hero pools

func _hero(name: String) -> Character:
	for h in PartyFactory.create_default_party():
		if h.character_name == name:
			return h
	return null

func _find(hero: Character, skill_name: String) -> Skill:
	for s in hero.skills:
		if s.skill_name == skill_name:
			return s
	return null

## The approved differences from the baseline: the Mend / Grand Mend merge.
## Keyed "<hero>:<slot>", each the fields allowed to differ and their new value.
const MERGE_DELTAS := {
	"Aria:3": {"mp_cost": 12},
	"Lyra:1": {"element": ElementalSystem.Element.LIGHT},
	"Lyra:6": {"element": ElementalSystem.Element.LIGHT},
}

func test_every_hero_move_is_a_copy_of_a_library_file() -> void:
	for hero in PartyFactory.create_default_party():
		for s in hero.skills:
			assert_true(s.source_path.begins_with(LIB), "%s: %s knows its file" % [hero.character_name, s.skill_name])
			assert_true(ResourceLoader.exists(s.source_path), "and that file exists")
			assert_ne(s, load(s.source_path), "it is the hero's own copy, not the shared file")

func test_hero_pools_match_the_baseline() -> void:
	var b: Dictionary = _baseline().get("heroes", {})
	for hero in PartyFactory.create_default_party():
		var want: Array = b.get(hero.character_name, [])
		assert_eq(hero.skills.size(), want.size(), "%s kept 12 moves" % hero.character_name)
		for i in mini(hero.skills.size(), want.size()):
			var key := "%s:%d" % [hero.character_name, i]
			var allowed: Dictionary = MERGE_DELTAS.get(key, {})
			var got := SaveSerializer.serialize_skill(hero.skills[i])
			assert_eq(_move_diff(got, want[i], allowed.keys()), "", "%s unchanged" % key)
			for field in allowed:
				assert_eq(int(got[field]), int(allowed[field]), "%s %s is the merged value" % [key, field])

func test_aria_and_lyra_share_one_mend_file() -> void:
	var aria := _find(_hero("Aria"), "Mend")
	var lyra := _find(_hero("Lyra"), "Mend")
	assert_eq(aria.source_path, LIB + "mend.tres", "Aria's Mend comes from mend.tres")
	assert_eq(lyra.source_path, LIB + "mend.tres", "so does Lyra's")

func test_shared_move_copies_do_not_interfere() -> void:
	# The regression the whole copy design exists to prevent. Sharing is by
	# reference, so without copies the second hero built would overwrite the
	# first hero's unlock level for both of them.
	var party := PartyFactory.create_default_party()
	var aria: Skill = null
	var lyra: Skill = null
	for h in party:
		if h.character_name == "Aria":
			aria = _find(h, "Mend")
		elif h.character_name == "Lyra":
			lyra = _find(h, "Mend")
	assert_ne(aria, lyra, "two heroes, two objects")
	assert_eq(aria.unlock_level, 7, "Aria learns Mend at 7 (pool slot 3)")
	assert_eq(lyra.unlock_level, 1, "Lyra learns Mend at 1 (pool slot 1)")
	aria.unlock_level = 99
	assert_eq(lyra.unlock_level, 1, "changing Aria's copy leaves Lyra's alone")
	assert_eq((load(LIB + "mend.tres") as Skill).unlock_level, 1, "and leaves the file alone")
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — `source_path` is empty for every hero move.

- [ ] **Step 3: Add the copy helper**

In `scripts/PartyFactory.gd`, add above `static func create_default_party()`:

```gdscript
const MOVES := "res://data/skills/"

## A hero's own copy of a library move. The file is the single definition of
## what the move does; the copy belongs to this hero, so stamping its unlock
## level and category — which differ per hero — can never leak into the file
## or into another hero who shares the move.
static func _move(file: String) -> Skill:
	var path := MOVES + file
	var template: Skill = load(path)
	var copy: Skill = template.duplicate(true)
	copy.source_path = path
	return copy
```

- [ ] **Step 4: Replace each hero's skill construction**

In each of `_create_aria`, `_create_kael` and `_create_lyra`, replace **everything from the first `var ... = _make_skill(` / `_make_status_skill(` statement through the end of the `hero.skills = [...] as Array[Skill]` statement** with the block below. Those ranges contain nothing but skill construction (checked); keep every stat, meta and bio line outside them.

`_create_aria`:
```gdscript
	hero.skills = [
		_move("aqua_slash.tres"), _move("frost_bolt.tres"), _move("tide_pulse.tres"), _move("mend.tres"),
		_move("tidal_requiem.tres"), _move("hydro_pierce.tres"), _move("tidal_barrier.tres"), _move("grand_mend.tres"),
		_move("riptide_lash.tres"), _move("glacial_shard.tres"), _move("abyssal_veil.tres"), _move("maelstrom.tres"),
	] as Array[Skill]
```

`_create_kael`:
```gdscript
	hero.skills = [
		_move("flame_strike.tres"), _move("shield_bash.tres"), _move("war_cry.tres"), _move("inferno.tres"),
		_move("phoenix_fury.tres"), _move("molten_blade.tres"), _move("iron_will.tres"), _move("flame_wall.tres"),
		_move("cinder_cleave.tres"), _move("guard_crush.tres"), _move("ember_ward.tres"), _move("scorched_earth.tres"),
	] as Array[Skill]
```

`_create_lyra`:
```gdscript
	hero.skills = [
		_move("wind_slash.tres"), _move("mend.tres"), _move("gust.tres"), _move("wind_barrier.tres"),
		_move("gale_requiem.tres"), _move("cyclone.tres"), _move("grand_mend.tres"), _move("tailwind.tres"),
		_move("zephyr_cut.tres"), _move("feather_volley.tres"), _move("restoring_breeze.tres"), _move("sanctuary.tres"),
	] as Array[Skill]
```

**The order is load-bearing.** `SKILL_UNLOCK_LEVELS`, `SKILL_CATEGORIES` and the equipped loadout are all positional.

- [ ] **Step 5: Delete the builders**

Delete the whole of `static func _make_skill(...)` and `static func _make_status_skill(...)`. Nothing outside `PartyFactory.gd` calls them (checked; `StatsScreen._make_skill_card` and the test-local `_make_skill` in `test_save_serializer.gd` are unrelated).

- [ ] **Step 6: Run the tests to verify they pass**

Expected: `MoveLibrary [OK]`, TOTAL 0 failed. `SkillLearning`, `Moveset`, `StatsScreen` and `LoadoutEditor` exercise the pools and must stay green.

- [ ] **Step 7: Commit**

`git commit -F` with message `Build hero pools from the move library` — heroes hold their own copies; the Mend clobber regression is pinned; `_make_skill` / `_make_status_skill` removed.

---

## Task 4: Save moves by reference

**Files:**
- Modify: `scripts/save/SaveSerializer.gd` (`serialize_skill`, `deserialize_skill`, `deserialize_character`; add two functions)
- Modify: `tests/suites/test_move_library.gd`

**Interfaces:**
- Consumes: `Skill.source_path`; library files.
- Produces:
  - `SaveSerializer.MOVE_LIBRARY := "res://data/skills/"`
  - `SaveSerializer.move_library_index() -> Dictionary` — `skill_name -> library path`.
  - `SaveSerializer.resolve_saved_skill(d: Dictionary, index: Dictionary) -> Skill`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_move_library.gd`:

```gdscript
# --------------------------------------------------- saves

func _round_trip(hero: Character) -> Character:
	return SaveSerializer.deserialize_character(SaveSerializer.serialize_character(hero))

func test_a_saved_pool_keeps_its_files() -> void:
	var lyra := _hero("Lyra")
	var back := _round_trip(lyra)
	assert_eq(back.skills.size(), lyra.skills.size(), "same pool size")
	for i in lyra.skills.size():
		assert_eq(back.skills[i].skill_name, lyra.skills[i].skill_name, "slot %d keeps its move" % i)
		assert_eq(back.skills[i].source_path, lyra.skills[i].source_path, "and its file")

func test_loaded_heroes_get_their_own_copies() -> void:
	# REVIEW FOCUS 1. load() returns Godot's cached object; if loading did not
	# duplicate it, a save/load would put Aria and Lyra back on ONE Mend object.
	var aria := _round_trip(_hero("Aria"))
	var lyra := _round_trip(_hero("Lyra"))
	var a := _find(aria, "Mend")
	var l := _find(lyra, "Mend")
	assert_ne(a, l, "two loaded heroes, two objects")
	assert_ne(a, load(LIB + "mend.tres"), "and neither is the cached file itself")
	a.unlock_level = 99
	assert_eq(l.unlock_level, 1, "so changing one cannot change the other")

func test_unlock_level_comes_from_the_save_not_the_file() -> void:
	# REVIEW FOCUS 2. Library files carry unlock_level 1; taking it from the file
	# would unlock every move at level 1 — the original P8 bug.
	var aria := _hero("Aria")
	var back := _round_trip(aria)
	for i in aria.skills.size():
		assert_eq(back.skills[i].unlock_level, aria.skills[i].unlock_level, "slot %d keeps its unlock level" % i)
		assert_eq(int(back.skills[i].category), int(aria.skills[i].category), "slot %d keeps its category" % i)
	assert_eq(_find(back, "Maelstrom").unlock_level, 18, "a late move stays late")

func test_an_edited_move_file_reaches_an_existing_save() -> void:
	var saved := SaveSerializer.serialize_character(_hero("Lyra"))
	var template: Skill = load(LIB + "cyclone.tres")
	var original := template.power
	template.power = 9.5
	var back := SaveSerializer.deserialize_character(saved)
	# Restore BEFORE asserting: load() returns the cached instance, so an
	# unrestored edit would leak into every later test that loads Cyclone.
	template.power = original
	assert_true(is_equal_approx(_find(back, "Cyclone").power, 9.5), "the balance change reached the save")

func test_a_missing_file_falls_back_to_the_snapshot() -> void:
	var d := SaveSerializer.serialize_skill(_find(_hero("Lyra"), "Cyclone"))
	d["source_path"] = "res://data/skills/was_deleted.tres"
	d["power"] = 4.25
	var s := SaveSerializer.resolve_saved_skill(d, {})
	assert_eq(s.skill_name, "Cyclone", "the save still loads")
	assert_true(is_equal_approx(s.power, 4.25), "from its snapshot")

func test_a_legacy_save_relinks_by_name() -> void:
	var d := SaveSerializer.serialize_skill(_find(_hero("Lyra"), "Cyclone"))
	d.erase("source_path")                      # written before moves had files
	d["power"] = 0.1
	var s := SaveSerializer.resolve_saved_skill(d, SaveSerializer.move_library_index())
	assert_eq(s.source_path, LIB + "cyclone.tres", "re-linked to its file")
	assert_true(is_equal_approx(s.power, (load(LIB + "cyclone.tres") as Skill).power), "so it gets current balance")

func test_a_legacy_wind_mend_becomes_the_shared_light_mend() -> void:
	# REVIEW FOCUS 5. An intended, player-visible change: an old save's Wind
	# Mend re-links to the merged Light Mend at 12 MP.
	var d := {"skill_name": "Mend", "element": ElementalSystem.Element.WIND, "mp_cost": 12,
			"unlock_level": 1, "category": Skill.SkillCategory.ATTACK}
	var s := SaveSerializer.resolve_saved_skill(d, SaveSerializer.move_library_index())
	assert_eq(int(s.element), int(ElementalSystem.Element.LIGHT), "now Light")
	assert_eq(s.mp_cost, 12, "still 12 MP")
	assert_eq(s.unlock_level, 1, "with the hero's own unlock level")

func test_a_legacy_save_with_an_unknown_name_uses_its_snapshot() -> void:
	var d := {"skill_name": "Forgotten Technique", "power": 3.3, "unlock_level": 4}
	var s := SaveSerializer.resolve_saved_skill(d, SaveSerializer.move_library_index())
	assert_eq(s.skill_name, "Forgotten Technique", "loads anyway")
	assert_true(is_equal_approx(s.power, 3.3), "from the snapshot")

func test_the_equipped_loadout_survives_a_reload() -> void:
	var aria := _hero("Aria")
	var back := _round_trip(aria)
	for slot in Character.EQUIP_SLOTS:
		var before := aria.equipped_skill(false, slot)
		var after := back.equipped_skill(false, slot)
		if before == null:
			assert_eq(after, null, "empty attack slot %d stays empty" % slot)
		else:
			assert_eq(after.skill_name, before.skill_name, "attack slot %d keeps its move" % slot)

func test_the_library_index_covers_every_move() -> void:
	var index := SaveSerializer.move_library_index()
	assert_eq(index.size(), 86, "every library move is indexed")
	assert_eq(index.get("Mend", ""), LIB + "mend.tres", "and names map to files")
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — `Nonexistent function 'resolve_saved_skill'`.

- [ ] **Step 3: Save and read `source_path`**

In `serialize_skill`, add after `"category": int(s.category),`:
```gdscript
		"source_path": s.source_path,
```

In `deserialize_skill`, add before `return s`:
```gdscript
	s.source_path = String(d.get("source_path", ""))
```

- [ ] **Step 4: Add the index and the resolver**

Add to `scripts/save/SaveSerializer.gd`, after `deserialize_skill`:

```gdscript
const MOVE_LIBRARY := "res://data/skills/"

## skill_name -> library path, used to re-link saves made before moves had
## files. Built from ResourceLoader.list_directory rather than DirAccess: in an
## exported build text resources are remapped, and a raw directory listing
## shows "foo.tres.remap" instead of "foo.tres".
static func move_library_index() -> Dictionary:
	var index := {}
	for f in ResourceLoader.list_directory(MOVE_LIBRARY):
		if not f.ends_with(".tres"):
			continue
		var s = load(MOVE_LIBRARY + f)
		if s is Skill:
			index[s.skill_name] = MOVE_LIBRARY + f
	return index

## Rebuilds one saved pool entry. What the move DOES comes from its library file
## when that file exists — so an edited move reaches existing saves. When the
## file is gone, the saved dictionary is the snapshot, so a save never breaks.
##
## When this hero learns the move (unlock_level, category) ALWAYS comes from the
## save: library files carry neutral defaults, and taking them from the file
## would unlock every move at level 1.
##
## The file is duplicated, never used directly: load() returns Godot's cached
## object, and handing it out would put every hero who knows the move back onto
## one shared object.
static func resolve_saved_skill(d: Dictionary, index: Dictionary) -> Skill:
	var path := ""
	if d.has("source_path"):
		path = String(d["source_path"])
	else:
		# Saved before moves had files: re-link by name.
		path = String(index.get(String(d.get("skill_name", "")), ""))
	if path != "" and ResourceLoader.exists(path):
		var template = load(path)
		if template is Skill:
			var copy: Skill = template.duplicate(true)
			copy.source_path = path
			copy.unlock_level = int(d.get("unlock_level", 1))
			copy.category = int(d.get("category", Skill.SkillCategory.ATTACK))
			return copy
	return deserialize_skill(d)
```

- [ ] **Step 5: Use it when loading a character**

In `deserialize_character`, replace:
```gdscript
	var typed_skills: Array[Skill] = []
	for sd in d.get("skills", []):
		typed_skills.append(deserialize_skill(sd))
	c.skills = typed_skills
```
with:
```gdscript
	# Moves load by reference (see resolve_saved_skill). The name index is only
	# needed for saves written before moves had files, so it is built lazily.
	var typed_skills: Array[Skill] = []
	var index := {}
	var index_built := false
	for sd in d.get("skills", []):
		if not sd.has("source_path") and not index_built:
			index = move_library_index()
			index_built = true
		typed_skills.append(resolve_saved_skill(sd, index))
	c.skills = typed_skills
```
Keep the saved order — the equipped loadout stores indices into this array.

- [ ] **Step 6: Run the tests to verify they pass**

Expected: `MoveLibrary [OK]`; `SaveSerializer`, `SkillLearning` and `Moveset` stay green. TOTAL 0 failed.

- [ ] **Step 7: Commit**

`git commit -F` with message `Save moves by reference, with a snapshot fallback`.

---

## Task 5: Target expansion

**Files:**
- Modify: `scripts/battle/BattleManager.gd`
- Create: `tests/suites/test_skill_resolver.gd`
- Modify: `tests/TestRunner.gd`

**Interfaces:**
- Consumes: `BattleManager.party`, `BattleManager.enemies` (`Array[Character]`).
- Produces: `BattleManager.expand_targets(user: Character, skill: Skill, chosen: Array[Character]) -> Array[Character]`. Not yet called by the resolvers — Task 6 wires it in.

- [ ] **Step 1: Write the failing tests**

Create `tests/suites/test_skill_resolver.gd`:

```gdscript
extends TestSuite

## One skill resolver for heroes and enemies. Target expansion is relative to
## the user's side, so an enemy's ALL_ENEMIES is the whole party — it used to
## hit a single hero, because expansion existed only in the player's menu.

func suite_name() -> String:
	return "SkillResolver"

## Enough HP that no test here kills anyone by accident: handle_defeat reports
## quest progress to the live GameManager. Defence is zeroed explicitly so a
## probe always lands damage rather than relying on the default of 5.
##
## Enemies get their own species: Memory Echo dodge keys on species through
## GameManager.species_memory, and the default "Unknown" may already have an
## encounter count from other tests or real saves — which would make these
## tests randomly dodge.
func _unit(name: String, hero: bool) -> Character:
	var c: Character = Character.new() if hero else Enemy.new()
	if not hero:
		(c as Enemy).species = "SkillResolverTestDummy"
	c.character_name = name
	c.base_hp = 5000
	c.base_mp = 500
	c.base_attack = 20
	c.base_magic = 20
	c.base_defense = 0
	c.base_arcane = 0
	c.level = 1
	c.current_hp = c.max_hp()
	c.current_mp = c.max_mp()
	return c

func _manager(heroes: int, foes: int) -> BattleManager:
	var bm := BattleManager.new()
	var p: Array[Character] = []
	for i in heroes:
		p.append(_unit("Hero%d" % i, true))
	var e: Array[Character] = []
	for i in foes:
		e.append(_unit("Foe%d" % i, false))
	bm.party = p
	bm.enemies = e
	return bm

func _skill(target: Skill.TargetType, kind: Skill.SkillType = Skill.SkillType.DAMAGE) -> Skill:
	var s := Skill.new()
	s.skill_name = "Probe"
	s.skill_type = kind
	s.attack_type = Skill.AttackType.STRIKE
	s.target_type = target
	s.power = 1.0
	return s

func test_an_enemy_area_attack_targets_the_whole_party() -> void:
	var bm := _manager(3, 1)
	var got := bm.expand_targets(bm.enemies[0], _skill(Skill.TargetType.ALL_ENEMIES), [bm.party[0]])
	assert_eq(got.size(), 3, "every hero, not just the one the AI picked")
	bm.free()

func test_a_hero_area_attack_targets_every_enemy() -> void:
	var bm := _manager(1, 4)
	var got := bm.expand_targets(bm.party[0], _skill(Skill.TargetType.ALL_ENEMIES), [])
	assert_eq(got.size(), 4, "every enemy")
	bm.free()

func test_all_allies_is_relative_to_the_user() -> void:
	var bm := _manager(2, 3)
	var for_hero := bm.expand_targets(bm.party[0], _skill(Skill.TargetType.ALL_ALLIES), [])
	var for_enemy := bm.expand_targets(bm.enemies[0], _skill(Skill.TargetType.ALL_ALLIES), [])
	assert_eq(for_hero.size(), 2, "a hero's allies are the party")
	assert_eq(for_enemy.size(), 3, "an enemy's allies are its fellow enemies")
	assert_false(for_enemy.has(bm.party[0]), "never a hero")
	bm.free()

func test_self_targets_the_user_on_both_sides() -> void:
	# SELF used to work only for enemies.
	var bm := _manager(1, 1)
	var h := bm.expand_targets(bm.party[0], _skill(Skill.TargetType.SELF), [])
	var e := bm.expand_targets(bm.enemies[0], _skill(Skill.TargetType.SELF), [])
	assert_eq(h.size(), 1, "one target for a hero")
	assert_eq(h[0], bm.party[0], "and it is the hero")
	assert_eq(e.size(), 1, "one target for an enemy")
	assert_eq(e[0], bm.enemies[0], "and it is the enemy")
	bm.free()

func test_a_single_target_keeps_the_chosen_target() -> void:
	var bm := _manager(3, 1)
	var got := bm.expand_targets(bm.enemies[0], _skill(Skill.TargetType.SINGLE_ENEMY), [bm.party[2]])
	assert_eq(got.size(), 1, "only one target")
	assert_eq(got[0], bm.party[2], "and it is the one chosen")
	bm.free()

func test_an_area_attack_skips_a_downed_hero() -> void:
	# REVIEW FOCUS 3.
	var bm := _manager(3, 1)
	bm.party[1].current_hp = 0
	var got := bm.expand_targets(bm.enemies[0], _skill(Skill.TargetType.ALL_ENEMIES), [])
	assert_eq(got.size(), 2, "only the living")
	assert_false(got.has(bm.party[1]), "never the downed hero")
	bm.free()

func test_all_allies_includes_a_mid_battle_summon() -> void:
	# REVIEW FOCUS 4. Boss summons are appended to `enemies` after the fight starts.
	var bm := _manager(1, 1)
	bm.enemies.append(_unit("Summoned", false))
	var got := bm.expand_targets(bm.enemies[0], _skill(Skill.TargetType.ALL_ALLIES), [])
	assert_eq(got.size(), 2, "the summon counts as an ally")
	bm.free()
```

- [ ] **Step 2: Register the suite**

In `tests/TestRunner.gd` `SUITE_PATHS`, after the `test_move_library.gd` entry, add:
```gdscript
	"res://tests/suites/test_skill_resolver.gd",
```

- [ ] **Step 3: Run to verify they fail**

Expected: FAIL — `Nonexistent function 'expand_targets'`.

- [ ] **Step 4: Implement expansion**

Add to `scripts/battle/BattleManager.gd`, above `func player_use_skill`:

```gdscript
# --- Targeting ---------------------------------------------------------------

## The characters a skill actually hits, from the USER's point of view: an
## enemy's ALL_ENEMIES is the party. This is the only place targets are
## expanded — it used to happen solely in the player's AttackMenu, so every
## enemy area attack in the game hit exactly one hero.
##
## Area targets exclude the downed. A single target is returned as chosen even
## if downed, and the resolver skips it, matching previous behaviour.
func expand_targets(user: Character, skill: Skill, chosen: Array[Character]) -> Array[Character]:
	var out: Array[Character] = []
	match skill.target_type:
		Skill.TargetType.SELF:
			out.append(user)
		Skill.TargetType.ALL_ENEMIES:
			for c in _opponents_of(user):
				if c.is_alive():
					out.append(c)
		Skill.TargetType.ALL_ALLIES:
			for c in _allies_of(user):
				if c.is_alive():
					out.append(c)
		_:
			for c in chosen:
				out.append(c)
	return out

func _opponents_of(user: Character) -> Array[Character]:
	return enemies if party.has(user) else party

func _allies_of(user: Character) -> Array[Character]:
	return party if party.has(user) else enemies
```

- [ ] **Step 5: Run the tests to verify they pass**

Expected: `SkillResolver [OK]`, TOTAL 0 failed.

- [ ] **Step 6: Commit**

`git commit -F` with message `Add side-relative target expansion`.

---

## Task 6: One resolver for both sides

**Files:**
- Modify: `scripts/battle/BattleManager.gd` (`player_use_skill`, `enemy_use_skill`, `_execute_enemy_turn`; add `resolve_skill`)
- Modify: `tests/suites/test_skill_resolver.gd`

**Interfaces:**
- Consumes: `expand_targets` (Task 5); `EnemyAI.try_dodge(target)`; `_apply_skill_status`; `handle_defeat`.
- Produces: `BattleManager.resolve_skill(user: Character, skill: Skill, chosen: Array[Character]) -> void`. `player_use_skill` and `enemy_use_skill` become wrappers around it.

- [ ] **Step 1: Write the failing tests**

Append to `tests/suites/test_skill_resolver.gd`:

```gdscript
# --------------------------------------------------- resolution

func _capture(bm: BattleManager) -> Array:
	var out: Array = []
	bm.action_performed.connect(func(r): out.append(r))
	return out

func test_an_enemy_area_attack_damages_every_hero() -> void:
	# The bug, end to end.
	var bm := _manager(3, 1)
	var hits := _capture(bm)
	var before: Array = bm.party.map(func(h): return h.current_hp)
	bm.enemy_use_skill(bm.enemies[0], _skill(Skill.TargetType.ALL_ENEMIES), [bm.party[0]])
	assert_eq(hits.size(), 3, "one result per hero")
	for i in 3:
		assert_true(bm.party[i].current_hp < before[i], "hero %d took damage" % i)
	bm.free()

func test_a_strike_skill_emits_skill_physical_on_both_sides() -> void:
	# "attack" routes a HERO to on_attack instead of on_skill_used, which grants
	# different resonance. Neither side may emit it for a skill.
	var bm := _manager(1, 1)
	var hits := _capture(bm)
	bm.enemy_use_skill(bm.enemies[0], _skill(Skill.TargetType.SINGLE_ENEMY), [bm.party[0]])
	bm.resolve_skill(bm.party[0], _skill(Skill.TargetType.SINGLE_ENEMY), [bm.enemies[0]])
	assert_eq(hits[0]["action"], "skill_physical", "enemy strike")
	assert_eq(hits[1]["action"], "skill_physical", "hero strike")
	bm.free()

func test_a_magic_skill_emits_skill_magic() -> void:
	var bm := _manager(1, 1)
	var hits := _capture(bm)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.attack_type = Skill.AttackType.MAGIC
	bm.resolve_skill(bm.party[0], s, [bm.enemies[0]])
	assert_eq(hits[0]["action"], "skill_magic", "magic")
	bm.free()

func test_resonance_flag_is_set_once_per_action() -> void:
	var bm := _manager(1, 4)
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], _skill(Skill.TargetType.ALL_ENEMIES), [])
	var firsts := hits.filter(func(r): return r.get("is_first_target", false))
	assert_eq(firsts.size(), 1, "an area attack grants resonance once, not per target")
	bm.free()

func test_heroes_pay_mp_and_enemies_do_not() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SINGLE_ENEMY)
	s.mp_cost = 30
	var hero_mp := bm.party[0].current_mp
	var foe_mp := bm.enemies[0].current_mp
	bm.resolve_skill(bm.party[0], s, [bm.enemies[0]])
	bm.resolve_skill(bm.enemies[0], s, [bm.party[0]])
	assert_eq(bm.party[0].current_mp, hero_mp - 30, "the hero paid")
	assert_eq(bm.enemies[0].current_mp, foe_mp, "the enemy did not")
	bm.free()

func test_self_heals_the_hero_who_casts_it() -> void:
	var bm := _manager(1, 1)
	var s := _skill(Skill.TargetType.SELF, Skill.SkillType.STATUS)
	s.status_type = Skill.StatusType.HEAL
	bm.party[0].current_hp = 100
	bm.resolve_skill(bm.party[0], s, [])
	assert_true(bm.party[0].current_hp > 100, "SELF now works for heroes")
	bm.free()

func test_dodge_is_rolled_per_target() -> void:
	var bm := _manager(3, 1)
	bm.party[1].set_meta("dodge_chance", 1.0)
	var hits := _capture(bm)
	bm.enemy_use_skill(bm.enemies[0], _skill(Skill.TargetType.ALL_ENEMIES), [bm.party[0]])
	var dodged := hits.filter(func(r): return r["action"] == "dodge")
	assert_eq(dodged.size(), 1, "exactly the hero who dodges")
	assert_eq(dodged[0]["target"], bm.party[1], "and it is that hero")
	bm.free()

func test_downed_targets_are_skipped() -> void:
	var bm := _manager(1, 1)
	bm.enemies[0].current_hp = 0
	var hits := _capture(bm)
	bm.resolve_skill(bm.party[0], _skill(Skill.TargetType.SINGLE_ENEMY), [bm.enemies[0]])
	assert_true(hits.is_empty(), "no action on a downed target")
	bm.free()

func _function_body(src: String, name: String) -> String:
	var start := src.find("func %s(" % name)
	if start < 0:
		return ""
	var end := src.find("\nfunc ", start + 1)
	return src.substr(start, (end - start) if end > 0 else -1)

func test_an_enemy_skill_is_dodge_rolled_once_not_twice() -> void:
	# _execute_enemy_turn awaits real timers, so it cannot be driven from a
	# synchronous test; this pins the structure instead. Dodge is now rolled
	# inside resolve_skill, so the enemy turn must not roll it again first —
	# two rolls would make a 50% dodge land 75% of the time.
	var src := FileAccess.get_file_as_string("res://scripts/battle/BattleManager.gd")
	assert_true(_function_body(src, "resolve_skill").contains("try_dodge"), "the resolver rolls dodge")
	var turn := _function_body(src, "_execute_enemy_turn")
	var skill_branch := turn.substr(turn.find("if skill != null:"))
	skill_branch = skill_branch.substr(0, skill_branch.find("\n\telse:"))
	assert_false(skill_branch.contains("try_dodge"), "the enemy turn does not roll it again for a skill")
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — `Nonexistent function 'resolve_skill'`, and `an enemy area attack damages every hero` reports 1 result, not 3.

- [ ] **Step 3: Add `resolve_skill`**

Add to `scripts/battle/BattleManager.gd`, directly after `_allies_of`:

```gdscript
# --- Skill resolution --------------------------------------------------------

## The single skill resolver for heroes AND enemies. There used to be two
## ~50-line near-copies that had already drifted: SELF targeting existed on one
## side only, dodge was rolled in different places, and the same outcome
## emitted different action names. Every skill mechanic lands here, once.
func resolve_skill(user: Character, skill: Skill, chosen: Array[Character]) -> void:
	if not skill.can_use(user):
		return
	var targets := expand_targets(user, skill, chosen)
	# Enemies have no MP pool; Skill.can_use already exempts them.
	if not (user is Enemy):
		user.use_mp(skill.mp_cost)

	var first := true
	for target in targets:
		if not target.is_alive():
			continue
		var result := {"actor": user, "target": target, "skill": skill, "is_first_target": first}
		first = false

		if skill.skill_type == Skill.SkillType.DAMAGE:
			# Dodge per target, for both sides.
			if EnemyAI.try_dodge(target):
				result["action"] = "dodge"
				result["value"] = 0
				result["target_alive"] = target.is_alive()
				emit_signal("action_performed", result)
				continue
			var value := skill.calculate_value(user)
			match skill.attack_type:
				Skill.AttackType.STRIKE, Skill.AttackType.RANGED:
					_record_damage(result, target.take_damage(value, skill.element, skill.secondary_element))
					# "skill_physical", never "attack": for a HERO, "attack" routes to
					# on_attack instead of on_skill_used and grants different resonance.
					result["action"] = "skill_physical"
				Skill.AttackType.MAGIC:
					_record_damage(result, target.take_magic_damage(value, skill.element, skill.secondary_element))
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

		# A damage skill's status rider rolls per target.
		if skill.skill_type == Skill.SkillType.DAMAGE and skill.status_to_apply != "" \
				and randf() < skill.status_chance:
			_apply_skill_status(target, skill.status_to_apply)

		result["target_alive"] = target.is_alive()
		emit_signal("action_performed", result)
		if not target.is_alive():
			handle_defeat(target)

func _record_damage(result: Dictionary, dmg: Dictionary) -> void:
	result["value"] = dmg.get("damage", 0)
	result["multiplier"] = dmg.get("multiplier", 1.0)
	result["effectiveness"] = dmg.get("effectiveness", "")
	result["effectiveness_color"] = dmg.get("effectiveness_color", Color.WHITE)
```

- [ ] **Step 4: Make the two resolvers wrappers**

Replace the **entire body** of `player_use_skill` with:
```gdscript
	if state != BattleState.CHOOSING_ACTION and state != BattleState.CHOOSING_TARGET:
		return
	# Checked here as well as in resolve_skill so an unusable skill leaves the
	# turn open, exactly as before.
	if not skill.can_use(user):
		return
	resolve_skill(user, skill, targets)
	end_player_turn()
```

Replace the **entire body** of `enemy_use_skill` with:
```gdscript
	resolve_skill(enemy, skill, targets)
```

- [ ] **Step 5: Remove the outer dodge for enemy skills**

In `_execute_enemy_turn`, replace:
```gdscript
	if skill != null:
		if EnemyAI.try_dodge(target):
			var dodge_result = {
				"action": "dodge",
				"actor": enemy,
				"target": target,
				"value": 0,
				"target_alive": target.is_alive()
			}
			emit_signal("action_performed", dodge_result)
		else:
			enemy_use_skill(enemy, skill, [target])
```
with:
```gdscript
	if skill != null:
		# Dodge is rolled per target inside resolve_skill. Rolling it here as well
		# would make every enemy skill dodge-checked twice.
		enemy_use_skill(enemy, skill, [target])
```
Leave the `else:` branch (the enemy's basic attack, which keeps its own dodge roll) exactly as it is.

- [ ] **Step 6: Run the tests to verify they pass**

Expected: `SkillResolver [OK]`, TOTAL 0 failed. `BossPhases`, `EnemyAI`, `StatusSystem` and `Resonance` all exercise battle resolution and must stay green.

- [ ] **Step 7: Commit**

`git commit -F` with message `Resolve every skill through one function` — explain the enemy-AoE fix and that it is a deliberate difficulty increase for nine enemies; dodge per target; unified action names; outer enemy-skill dodge removed.

---

## Task 7: Document the system

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add a Core Systems section**

Under `## Core Systems`, after the `### Skill (Resource)` section, add `### Move library — data/skills/` covering: every move is a file; heroes hold `.duplicate()` copies with per-hero `unlock_level`/`category` and `source_path`; enemies reference files directly; why copies and not a wrapper (7 scripts + 8 test files read the pool as `Skill`); the Mend merge (Light, 12 MP); saves by reference with snapshot fallback and name re-linking; that the loader must duplicate and must take unlock level from the save; `ResourceLoader.list_directory` over `DirAccess` because of export remaps; and the two one-shot tools and that `capture_move_baseline` must never be re-run.

- [ ] **Step 2: Update the resolver and file-structure notes**

- In the `### BattleManager` section, record `resolve_skill` as the single resolver, `expand_targets` as the only target expansion, and the action-name rule.
- In `## File Structure`, add `data/skills/` (86 files), `tools/extract_move_library.*` and `tools/capture_move_baseline.*`, and `tests/fixtures/`.
- Remove the stale line in the Skill section saying `Hero skills: indices 0–3 = attacks, 4–7 = specials`; pools are 12 moves with categories.

- [ ] **Step 3: Update the roadmap**

In `#### Track B`, rewrite item 3 to record that Spec A (move library + unified resolver) is done, and that Specs B (mechanics) and C (multi-turn) remain. Note the four "honest skill" gaps (Cyclone, Hydro Pierce, Gale Requiem, Frost Bolt) belong to Spec B.

- [ ] **Step 4: Update test counts**

Update both `~2461 tests / 40 suites` references to the real numbers from a final test run.

- [ ] **Step 5: Run the full suite**

Expected: ALL TESTS PASSED, 0 failed.

- [ ] **Step 6: Commit**

`git commit -F` with message `Document the move library and unified resolver`.

---

## Done criteria

- 86 moves in `data/skills/`; no enemy holds an inline move; no hero move is built in code.
- Every hero pool and every enemy matches the pre-migration baseline except the approved Mend/Grand Mend merge.
- Saves round-trip by reference; an edited move reaches an existing save; a deleted file and a legacy save both still load.
- An enemy area attack hits every living hero.
- All five Review Focus cases pinned; full suite green with no drop below 2498.
