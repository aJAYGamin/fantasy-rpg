class_name TestSuite
extends RefCounted

## Base class for all unit-test suites.
## Subclass it, add methods prefixed with `test_`, and use the assert_* helpers.
## run() auto-discovers and runs every test_ method and returns a result dict.

var _pass: int = 0
var _fail: int = 0
var _log: Array[String] = []

func suite_name() -> String:
	return "Unnamed Suite"

# --- Assertion helpers ---
func _record(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		_log.append("  PASS  " + label)
	else:
		_fail += 1
		_log.append("  FAIL  " + label)

func assert_true(cond, label: String) -> void:
	_record(cond == true, label)

func assert_false(cond, label: String) -> void:
	_record(cond == false, label)

func assert_eq(actual, expected, label: String) -> void:
	_record(actual == expected, "%s (got %s, expected %s)" % [label, actual, expected])

func assert_ne(actual, expected, label: String) -> void:
	_record(actual != expected, "%s (got %s, expected != %s)" % [label, actual, expected])

func assert_near(actual: float, expected: float, tol: float, label: String) -> void:
	_record(absf(actual - expected) <= tol, "%s (got %s, expected ~%s)" % [label, actual, expected])

func assert_in_range(actual: float, lo: float, hi: float, label: String) -> void:
	_record(actual >= lo and actual <= hi, "%s (got %s, expected [%s, %s])" % [label, actual, lo, hi])

# --- Runner entry point ---
func run() -> Dictionary:
	for m in get_method_list():
		var n: String = m["name"]
		if n.begins_with("test_"):
			call(n)
	return {"name": suite_name(), "pass": _pass, "fail": _fail, "log": _log}
