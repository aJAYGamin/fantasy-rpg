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
