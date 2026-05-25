extends Node

## Unit test runner.
##
## HOW TO RUN:
##   Open tests/TestRunner.tscn in Godot and press F6 (Run Current Scene),
##   then read pass/fail results in the Output panel.
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
]

func _ready() -> void:
	print("\n========================================")
	print("  THE AMETHYST REQUIEM — UNIT TESTS")
	print("========================================")

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

	print("\n========================================")
	print("  TOTAL: %d passed, %d failed" % [grand_pass, grand_fail])
	if grand_fail == 0:
		print("  ALL TESTS PASSED")
	else:
		print("  FAILING SUITES: %s" % ", ".join(failed_suites))
	print("========================================\n")
