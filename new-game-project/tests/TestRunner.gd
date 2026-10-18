extends Node

## Unit test runner.
##
## HOW TO RUN: headless, from the project folder (new-game-project/):
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/TestRunner.tscn --quit-after 5
## Not with F6 / Run Current Scene: a windowed run installs the cursor's window hook, and the
## hold tests then capture and warp the developer's real pointer. A windowed run refuses
## itself (refusal_for) and quits.
##
## The run also keeps user://config.cfg as it found it (keep_file / put_back): whatever
## the suites save, the developer's own settings are back when it ends.
##
## GameManager (autoload) is available because this runs as a scene in the tree.
##
## When you add a new feature, add a `tests/suites/test_<feature>.gd`
## (extends TestSuite, methods prefixed `test_`) and register it in SUITE_PATHS.

const SUITE_PATHS := [
	"res://tests/suites/test_character.gd",
	"res://tests/suites/test_skill.gd",
	"res://tests/suites/test_elemental.gd",
	"res://tests/suites/test_rarity.gd",
	"res://tests/suites/test_enemy.gd",
	"res://tests/suites/test_encounter_group.gd",
	"res://tests/suites/test_resonance.gd",
	"res://tests/suites/test_enemy_ai.gd",
	"res://tests/suites/test_game_manager.gd",
	"res://tests/suites/test_party_factory.gd",
	"res://tests/suites/test_save_serializer.gd",
	"res://tests/suites/test_save_coverage.gd",
	"res://tests/suites/test_status_system.gd",
	"res://tests/suites/test_hero_palette.gd",
	"res://tests/suites/test_stats_screen.gd",
	"res://tests/suites/test_items_screen.gd",
	"res://tests/suites/test_item_factory.gd",
	"res://tests/suites/test_equipment.gd",
	"res://tests/suites/test_settings.gd",
	"res://tests/suites/test_input_map.gd",
	"res://tests/suites/test_focus_guard.gd",
	"res://tests/suites/test_hold_repeat.gd",
	"res://tests/suites/test_auto_save.gd",
	"res://tests/suites/test_level_up_screen.gd",
	"res://tests/suites/test_defeat_flow.gd",
	"res://tests/suites/test_roaming_enemy.gd",
	"res://tests/suites/test_map_transition.gd",
	"res://tests/suites/test_map_zone.gd",
	"res://tests/suites/test_roamer_territory.gd",
	"res://tests/suites/test_depth_overlay.gd",
	"res://tests/suites/test_dialogue.gd",
	"res://tests/suites/test_quests.gd",
	"res://tests/suites/test_time.gd",
	"res://tests/suites/test_shop.gd",
	"res://tests/suites/test_props.gd",
	"res://tests/suites/test_input_profiles.gd",
	"res://tests/suites/test_skill_learning.gd",
	"res://tests/suites/test_moveset.gd",
	"res://tests/suites/test_rest_area.gd",
	"res://tests/suites/test_loadout_editor.gd",
	"res://tests/suites/test_loadout_screen.gd",
	"res://tests/suites/test_boss_phases.gd",
	"res://tests/suites/test_move_library.gd",
	"res://tests/suites/test_skill_resolver.gd",
	"res://tests/suites/test_status_chips.gd",
	"res://tests/suites/test_battle_menu_gating.gd",
	"res://tests/suites/test_enemy_cards.gd",
	"res://tests/suites/test_meter_bars.gd",
	"res://tests/suites/test_skill_options.gd",
	"res://tests/suites/test_scrollbars.gd",
	"res://tests/suites/test_multi_turn.gd",
	"res://tests/suites/test_cursor_art.gd",
	"res://tests/suites/test_cursor_motion.gd",
	"res://tests/suites/test_cursor_hold.gd",
	"res://tests/suites/test_virtual_cursor.gd",
	"res://tests/suites/test_cycler_row.gd",
	"res://tests/suites/test_runner_guards.gd",
]

## The one supported way to run the suites.
const HEADLESS_COMMAND := "/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/TestRunner.tscn --quit-after 5"
## The file the game saves its settings, bindings and active slot to.
const CONFIG_PATH := "user://config.cfg"

## "" when the suites may run on this display driver, otherwise the one line to print
## in place of running them. Only the headless driver has no real window and pointer.
static func refusal_for(display_name: String) -> String:
	if display_name == "headless":
		return ""
	return "Run the tests headless: " + HEADLESS_COMMAND

## Notes a file as it is now (its bytes, or that it is absent) for put_back.
static func keep_file(path: String) -> Dictionary:
	var had := FileAccess.file_exists(path)
	return {
		"path": path,
		"had": had,
		"bytes": FileAccess.get_file_as_bytes(path) if had else PackedByteArray(),
	}

## Puts a file back as keep_file found it: the same bytes, or gone again if it was absent.
static func put_back(kept: Dictionary) -> void:
	var path: String = kept["path"]
	if kept["had"]:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_buffer(kept["bytes"])
			f.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func _ready() -> void:
	var refusal := refusal_for(DisplayServer.get_name())
	if refusal != "":
		print(refusal)
		get_tree().quit(1)
		return

	print("\n========================================")
	print("  THE AMETHYST REQUIEM — UNIT TESTS")
	print("========================================")

	var kept_config := keep_file(CONFIG_PATH)

	var grand_pass := 0
	var grand_fail := 0
	var failed_suites: Array[String] = []

	for path in SUITE_PATHS:
		var script: GDScript = load(path)
		if script == null:
			print("\n[!] Could not load suite: %s" % path)
			grand_fail += 1
			failed_suites.append(path)
			continue
		var suite: TestSuite = script.new()
		var result: Dictionary = suite.run()
		var p: int = result["pass"]
		var f: int = result["fail"]
		grand_pass += p
		grand_fail += f

		var status := "OK" if f == 0 else "FAILED"
		print("\n--- %s [%s]  (%d/%d) ---" % [result["name"], status, p, p + f])
		for line in result["log"]:
			# Only print failures unless the whole suite passed cleanly
			if f == 0:
				continue
			if line.begins_with("  FAIL"):
				print(line)
		if f > 0:
			failed_suites.append(result["name"])

	put_back(kept_config)

	print("\n========================================")
	print("  TOTAL: %d passed, %d failed" % [grand_pass, grand_fail])
	if grand_fail == 0:
		print("  ALL TESTS PASSED")
	else:
		print("  FAILING SUITES: %s" % ", ".join(failed_suites))
	print("========================================\n")
