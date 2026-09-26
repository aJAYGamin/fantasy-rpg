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
			# Capture the uid BEFORE resaving. ResourceSaver.save() called
			# outside the editor does not re-embed a resource's "uid=" text
			# attribute in the .tres header — the value keeps resolving via
			# this process's ResourceUID table (and this machine's cached
			# .godot/uid_cache.bin), but a fresh checkout with no such cache
			# would then see this file as uid-less and mint a NEW uid for it,
			# silently orphaning every encounter that references the old one.
			# So the uid is restored into the header text explicitly below.
			var original_uid := ResourceLoader.get_resource_uid(path)
			var err := ResourceSaver.save(e, path)
			if err != OK:
				push_error("could not rewrite %s (error %d)" % [path, err])
				get_tree().quit(1)
				return
			_restore_uid_in_header(path, original_uid)
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

## Re-embeds `uid` as a `uid="uid://..."` attribute on the [gd_resource ...]
## header line of the .tres just written at `path`, if that line doesn't
## already carry one. A no-op when `uid` is invalid (the file had no uid
## before this migration touched it either).
func _restore_uid_in_header(path: String, uid: int) -> void:
	if uid == ResourceUID.INVALID_ID:
		return
	var abs_path := ProjectSettings.globalize_path(path)
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		push_error("could not reopen %s to restore its uid" % path)
		return
	var text := f.get_as_text()
	f.close()
	var nl := text.find("\n")
	var header := text.substr(0, nl)
	if header.contains("uid=\""):
		return
	var close_bracket := header.rfind("]")
	var new_header := "%s uid=\"%s\"%s" % [header.substr(0, close_bracket), ResourceUID.id_to_text(uid), header.substr(close_bracket)]
	var out := FileAccess.open(abs_path, FileAccess.WRITE)
	out.store_string(new_header + text.substr(nl))
	out.close()

## The library resource an enemy should reference in place of `s`. A move that
## is already a library file is kept, except the legacy Skill_blizzard.tres,
## which is re-pointed at blizzard.tres.
func _library_ref(s: Skill) -> Skill:
	if s.resource_path.begins_with(LIB) and not s.resource_path.contains("::") \
			and s.resource_path != LEGACY_BLIZZARD:
		return s
	return load(_write_move(s))
