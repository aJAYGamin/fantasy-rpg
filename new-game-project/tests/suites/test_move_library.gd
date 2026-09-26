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

## Reads the uid text straight out of a .tres file's [gd_resource ...] header
## line (its actual on-disk source of truth), instead of through
## ResourceLoader.get_resource_uid() — that call answers from this machine's
## local, gitignored .godot/uid_cache.bin, which keeps remembering a file's
## OLD uid even after the uid= attribute has been silently dropped from the
## header text. A fresh checkout has no such cache, so the header is the only
## thing that matters. Returns "" when the header has no uid= attribute.
func _header_uid(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var header := f.get_line()
	f.close()
	var re := RegEx.new()
	re.compile("uid=\"([^\"]+)\"")
	var m := re.search(header)
	return m.get_string(1) if m else ""

func test_enemy_uids_survive_the_rewrite() -> void:
	# This guard is defensive, not load-bearing today: every one of the 16
	# encounter-group references to these enemies is by path (see
	# data/encounters/*.tres), and none of the ten real uids checked below
	# appears anywhere outside its own file. It still earns its place,
	# because a future reference by uid would silently orphan if a rewrite
	# ever minted a new one.
	#
	# CONTROLLER RULING: four enemy files (earth_golem, goblin_warlord,
	# light_golem, void_shade) had NO uid in their .tres header before this
	# migration — the baseline recorded that as the literal string
	# "uid://<invalid>". They did NOT change: they are still uid-less after
	# the rewrite, and that absence is pinned below rather than merely
	# tolerated. Every enemy that DID have a real uid must still have that
	# exact uid, read from the header text, after the rewrite.
	var b: Dictionary = _baseline().get("enemies", {})
	for path in _enemy_paths():
		var baseline_uid := String((b.get(path, {}) as Dictionary).get("uid", ""))
		var header_uid := _header_uid(path)
		if baseline_uid == "uid://<invalid>":
			assert_eq(header_uid, "", "%s is still uid-less" % path)
		else:
			assert_eq(header_uid, baseline_uid, "%s kept its uid" % path)

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
