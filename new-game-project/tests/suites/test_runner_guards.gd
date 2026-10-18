extends TestSuite

## The test runner's two protections for the developer's machine: it only runs headless
## (a windowed run installs the cursor's window hook, and the hold tests capture and
## warp the real pointer), and it puts user://config.cfg back as it found it.

const Runner := preload("res://tests/TestRunner.gd")
const _TEMP := "user://runner_guard_test.tmp"

func suite_name() -> String:
	return "RunnerGuards"

func test_the_runner_refuses_a_windowed_run_and_says_how_to_run_headless() -> void:
	assert_eq(Runner.refusal_for("headless"), "", "the headless display runs the tests")
	for display in ["macos", "windows", "x11", "wayland"]:
		var line: String = Runner.refusal_for(display)
		assert_true(line.begins_with("Run the tests headless: "), "a %s window is refused with the instruction" % display)
		assert_true(line.contains("--headless") and line.contains("res://tests/TestRunner.tscn"),
				"and the line carries the whole command (%s)" % display)
		assert_false(line.contains("\n"), "as one line (%s)" % display)

func test_a_changed_file_is_put_back_exactly() -> void:
	_write(_TEMP, PackedByteArray([1, 2, 3, 0, 255]))
	var kept: Dictionary = Runner.keep_file(_TEMP)
	_write(_TEMP, PackedByteArray([9]))
	Runner.put_back(kept)
	assert_eq(FileAccess.get_file_as_bytes(_TEMP), PackedByteArray([1, 2, 3, 0, 255]), "the bytes are back, byte for byte")
	DirAccess.remove_absolute(_TEMP)

func test_a_file_that_was_absent_is_removed_again() -> void:
	DirAccess.remove_absolute(_TEMP)
	var kept: Dictionary = Runner.keep_file(_TEMP)
	_write(_TEMP, PackedByteArray([7, 7]))
	Runner.put_back(kept)
	assert_false(FileAccess.file_exists(_TEMP), "a file the run created is gone again")

func test_an_empty_file_comes_back_empty_not_absent() -> void:
	_write(_TEMP, PackedByteArray())
	var kept: Dictionary = Runner.keep_file(_TEMP)
	_write(_TEMP, PackedByteArray([4]))
	Runner.put_back(kept)
	assert_true(FileAccess.file_exists(_TEMP), "an empty file is still there")
	assert_eq(FileAccess.get_file_as_bytes(_TEMP).size(), 0, "and empty")
	DirAccess.remove_absolute(_TEMP)

func test_the_runner_guards_the_file_the_game_saves_its_settings_to() -> void:
	assert_eq(Runner.CONFIG_PATH, GameManager.USER_CONFIG_PATH, "config.cfg is the file the runner keeps and restores")

func _write(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
