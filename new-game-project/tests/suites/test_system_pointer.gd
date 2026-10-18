extends TestSuite

## SystemPointer: the computer's own pointer as the themed cursor uses it, captured while the
## game holds the mouse and shown, dressed as the cursor, while it lets go. Headless has no
## pointer to move, so these check its sizing and that every call reaching it lives in it.

func suite_name() -> String:
	return "SystemPointer"

## Calls that reach the OS pointer: its mode, where it is, its look and its shape. Setting
## Input.mouse_mode is matched by SETS_MOUSE_MODE instead.
const OS_POINTER_CALLS: Array[String] = [
	"get_mouse_position(", "get_local_mouse_position(", "get_global_mouse_position(",
	"mouse_get_position(", "warp_mouse(", "set_mouse_mode(", "mouse_set_mode(",
	"set_custom_mouse_cursor(", "cursor_set_custom_image(", "set_default_cursor_shape(",
	"cursor_set_shape(",
]
## An assignment to mouse_mode, spaced or not; a comparison (==) is not one.
const SETS_MOUSE_MODE := "mouse_mode\\s*=(?!=)"
const HOME := "res://scripts/cursor/SystemPointer.gd"

func test_the_system_cursor_is_the_size_the_cursor_is_drawn() -> void:
	# A window 2.625x the base size on a Retina screen: 2.625 window pixels a base pixel,
	# 2 window pixels a point, and a Mac cursor image is measured in points.
	assert_near(SystemPointer.os_cursor_scale(2.625, 2.0, "A"), 1.3125, 0.0001, "a Retina Mac draws it in points")
	assert_near(SystemPointer.os_cursor_scale(1.5, 1.0, "A"), 1.5, 0.0001, "elsewhere in window pixels")
	for shape: String in CursorArt.SHAPES:
		var s := SystemPointer.os_cursor_scale(12.0, 1.0, shape)
		var img := CursorArt.image(shape, "amethyst", s)
		var big := maxi(img.get_width(), img.get_height())
		assert_true(big <= SystemPointer.OS_CURSOR_MAX, "%s fits a system cursor's 256 px at any window size (%d px)" % [shape, big])
		assert_true(big >= 250, "%s is capped only as far as it must be (%d px)" % [shape, big])

func test_every_call_to_the_system_pointer_is_in_system_pointer() -> void:
	# The drawn cursor stands in for the OS pointer everywhere, and with the mouse held the
	# OS pointer is hidden and where it sits means nothing. One small file making every call
	# to it keeps that rule easy to see and to keep.
	var sets_mode := RegEx.create_from_string(SETS_MOUSE_MODE)
	var offenders: Array[String] = []
	for path in _scripts("res://scripts"):
		if path == HOME:
			continue
		var code := _code(path)
		for call in OS_POINTER_CALLS:
			if code.contains(call):
				offenders.append("%s: %s" % [path.get_file(), call])
		if sets_mode.search(code) != null:
			offenders.append("%s: mouse_mode =" % path.get_file())
	assert_true(offenders.is_empty(), "no script but SystemPointer calls the OS pointer (%s)" % ", ".join(offenders))
	var own := _code(HOME)
	for call in ["get_mouse_position(", "warp_mouse(", "set_custom_mouse_cursor(", "cursor_set_shape("]:
		assert_true(own.contains(call), "SystemPointer makes the %s call" % call)
	assert_true(sets_mode.search(own) != null, "and sets the mouse mode")

func test_the_scan_tells_setting_the_mouse_mode_from_reading_it() -> void:
	var sets_mode := RegEx.create_from_string(SETS_MOUSE_MODE)
	assert_true(sets_mode.search("Input.mouse_mode = Input.MOUSE_MODE_VISIBLE") != null, "an assignment")
	assert_true(sets_mode.search("Input.mouse_mode=Input.MOUSE_MODE_VISIBLE") != null, "one written without spaces")
	assert_true(sets_mode.search("if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:") == null, "but not a comparison")
	assert_true(sets_mode.search("return hold.mouse_mode()") == null, "or a call")

## Every .gd file under `dir`, at any depth.
func _scripts(dir: String) -> Array[String]:
	var found: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			found.append(dir.path_join(f))
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_scripts(dir.path_join(sub)))
	return found

## A script's code with its comments cut off, so a comment naming a call doesn't count.
func _code(path: String) -> String:
	var lines := PackedStringArray()
	for line in FileAccess.get_file_as_string(path).split("\n"):
		lines.append(line.get_slice("#", 0))
	return "\n".join(lines)
