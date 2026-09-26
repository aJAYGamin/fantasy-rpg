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
