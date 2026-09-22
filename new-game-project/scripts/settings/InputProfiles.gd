class_name InputProfiles
extends RefCounted

## Three switchable keybind profiles per device (keyboard and controller each
## get their own three, chosen independently).
##
## A profile holds ONE device's half of the bindings, as {action: [event dicts]}
## in the same shape InputMapConfig serializes. The live InputMap always mirrors
## the two active profiles; the other four sit here until selected.
##
## The live InputMap is still the source of truth while the player is editing,
## so anything that changes bindings must call `sync_from_input_map()` before a
## switch or a save — otherwise the edit is captured into the wrong slot, or
## lost. `switch_to()` and `reset_active()` handle that themselves.

const COUNT := 3
const SECTION := "input_profiles"
const MAX_NAME_LENGTH := 18

## Per-device profile bindings, COUNT entries each.
var keyboard_bindings: Array = []
var controller_bindings: Array = []
## Per-device profile names, COUNT entries each.
var keyboard_names: Array = []
var controller_names: Array = []

var _active_keyboard: int = 0
var _active_controller: int = 0

func _init() -> void:
	reset_everything()

## Every profile on both devices back to stock bindings and default names.
func reset_everything() -> void:
	keyboard_bindings = []
	controller_bindings = []
	keyboard_names = []
	controller_names = []
	for i in COUNT:
		keyboard_bindings.append(InputMapConfig.device_defaults(true))
		controller_bindings.append(InputMapConfig.device_defaults(false))
		keyboard_names.append(default_name(i))
		controller_names.append(default_name(i))
	_active_keyboard = 0
	_active_controller = 0

static func default_name(index: int) -> String:
	return "Profile %d" % (index + 1)

static func is_valid_index(index: int) -> bool:
	return index >= 0 and index < COUNT

# --- accessors ---------------------------------------------------------------

func _bindings_array(keyboard: bool) -> Array:
	return keyboard_bindings if keyboard else controller_bindings

func _names_array(keyboard: bool) -> Array:
	return keyboard_names if keyboard else controller_names

func active_index(keyboard: bool) -> int:
	return _active_keyboard if keyboard else _active_controller

func bindings_for(keyboard: bool, index: int) -> Dictionary:
	if not is_valid_index(index):
		return {}
	return _bindings_array(keyboard)[index]

func set_bindings(keyboard: bool, index: int, data: Dictionary) -> void:
	if not is_valid_index(index):
		return
	_bindings_array(keyboard)[index] = data.duplicate(true)

func name_for(keyboard: bool, index: int) -> String:
	if not is_valid_index(index):
		return ""
	return String(_names_array(keyboard)[index])

## Renames a profile, returning the name actually stored. Blank or
## whitespace-only input falls back to the numbered default rather than leaving
## an unlabelled entry in the picker.
func set_name(keyboard: bool, index: int, new_name: String) -> String:
	if not is_valid_index(index):
		return ""
	var clean := new_name.strip_edges()
	if clean.length() > MAX_NAME_LENGTH:
		clean = clean.substr(0, MAX_NAME_LENGTH).strip_edges()
	if clean == "":
		clean = default_name(index)
	_names_array(keyboard)[index] = clean
	return clean

# --- live InputMap <-> profiles ----------------------------------------------

## Captures the live InputMap into BOTH active slots. Call after any rebind so
## the model matches what the player just set.
func sync_from_input_map() -> void:
	set_bindings(true, _active_keyboard, InputMapConfig.capture_device(true))
	set_bindings(false, _active_controller, InputMapConfig.capture_device(false))

## Pushes both active profiles into the live InputMap. Used at startup.
func apply_active() -> void:
	InputMapConfig.apply_device(bindings_for(true, _active_keyboard), true)
	InputMapConfig.apply_device(bindings_for(false, _active_controller), false)

## Selects another profile for one device: the in-progress bindings are captured
## into the outgoing slot first, so switching away never discards an edit.
func switch_to(keyboard: bool, index: int) -> void:
	if not is_valid_index(index):
		return
	set_bindings(keyboard, active_index(keyboard), InputMapConfig.capture_device(keyboard))
	if keyboard:
		_active_keyboard = index
	else:
		_active_controller = index
	InputMapConfig.apply_device(bindings_for(keyboard, index), keyboard)

## Restores stock bindings for the ACTIVE profile of one device only, leaving
## that device's other two profiles alone.
func reset_active(keyboard: bool) -> void:
	var defs := InputMapConfig.device_defaults(keyboard)
	set_bindings(keyboard, active_index(keyboard), defs)
	InputMapConfig.apply_device(defs, keyboard)

# --- persistence --------------------------------------------------------------

func to_config(cfg: ConfigFile) -> void:
	cfg.set_value(SECTION, "keyboard_active", _active_keyboard)
	cfg.set_value(SECTION, "controller_active", _active_controller)
	cfg.set_value(SECTION, "keyboard_names", keyboard_names)
	cfg.set_value(SECTION, "controller_names", controller_names)
	for i in COUNT:
		cfg.set_value(SECTION, "keyboard_%d" % i, keyboard_bindings[i])
		cfg.set_value(SECTION, "controller_%d" % i, controller_bindings[i])

## Reads profiles back. When the section is missing, an existing player's flat
## `[input]` bindings are migrated into profile 1 of each device so an upgrade
## doesn't silently reset their controls; the other profiles start at defaults.
func from_config(cfg: ConfigFile) -> void:
	reset_everything()
	if not cfg.has_section(SECTION):
		_migrate_legacy(cfg)
		return
	_active_keyboard = clampi(int(cfg.get_value(SECTION, "keyboard_active", 0)), 0, COUNT - 1)
	_active_controller = clampi(int(cfg.get_value(SECTION, "controller_active", 0)), 0, COUNT - 1)

	var kn: Array = cfg.get_value(SECTION, "keyboard_names", [])
	var cn: Array = cfg.get_value(SECTION, "controller_names", [])
	for i in COUNT:
		if i < kn.size():
			set_name(true, i, String(kn[i]))
		if i < cn.size():
			set_name(false, i, String(cn[i]))
		var kb = cfg.get_value(SECTION, "keyboard_%d" % i, null)
		if kb is Dictionary:
			keyboard_bindings[i] = _sanitize(kb, true)
		var cb = cfg.get_value(SECTION, "controller_%d" % i, null)
		if cb is Dictionary:
			controller_bindings[i] = _sanitize(cb, false)

func _migrate_legacy(cfg: ConfigFile) -> void:
	var legacy := InputMapConfig.load_custom(cfg)
	if legacy.is_empty():
		return
	var kb := {}
	var cb := {}
	for meta in InputMapConfig.ACTIONS:
		var action: String = meta["action"]
		var k: Array = []
		var c: Array = []
		for d in legacy.get(action, []):
			if not (d is Dictionary):
				continue
			if String(d.get("type", "")) == "key":
				k.append(d.duplicate())
			else:
				c.append(d.duplicate())
		kb[action] = k
		cb[action] = c
	keyboard_bindings[0] = kb
	controller_bindings[0] = cb

## Drops anything that isn't a well-formed event dict for this device, and
## guarantees an entry per action, so a hand-edited or partial config can't
## leave an action unbound in a way the UI can't explain.
func _sanitize(raw: Dictionary, keyboard: bool) -> Dictionary:
	var out := {}
	for meta in InputMapConfig.ACTIONS:
		var action: String = meta["action"]
		var arr: Array = []
		for d in raw.get(action, []):
			if not (d is Dictionary):
				continue
			if (String(d.get("type", "")) == "key") == keyboard:
				arr.append(d.duplicate())
		out[action] = arr
	return out
