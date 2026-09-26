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
