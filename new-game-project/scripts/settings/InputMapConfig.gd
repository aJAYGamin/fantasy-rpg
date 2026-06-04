class_name InputMapConfig
extends RefCounted

## Named, remappable input actions + their persistence. The game uses these
## custom actions (move_*/confirm/cancel/pause); `confirm`/`cancel` are mirrored
## onto the built-in ui_accept/ui_cancel so existing menu code follows remaps.
##
## Events are stored in config as plain dicts so they round-trip through
## ConfigFile and survive restarts:
##   key   -> {"type":"key",  "keycode": <physical keycode>}
##   joyb  -> {"type":"joyb", "button":  <button index>}
##   joym  -> {"type":"joym", "axis": <axis>, "value": <±1.0>}

const CONFIG_SECTION := "input"

# Remappable actions in UI order, with display labels.
const ACTIONS: Array = [
	{"action": "move_up", "label": "Move Up"},
	{"action": "move_down", "label": "Move Down"},
	{"action": "move_left", "label": "Move Left"},
	{"action": "move_right", "label": "Move Right"},
	{"action": "confirm", "label": "Confirm"},
	{"action": "cancel", "label": "Cancel / Back"},
	{"action": "pause", "label": "Pause / Menu"},
]

# Default bindings (keyboard + controller) per action.
static func defaults() -> Dictionary:
	return {
		"move_up": [
			{"type": "key", "keycode": KEY_W},
			{"type": "key", "keycode": KEY_UP},
			{"type": "joym", "axis": JOY_AXIS_LEFT_Y, "value": -1.0},
			{"type": "joyb", "button": JOY_BUTTON_DPAD_UP},
		],
		"move_down": [
			{"type": "key", "keycode": KEY_S},
			{"type": "key", "keycode": KEY_DOWN},
			{"type": "joym", "axis": JOY_AXIS_LEFT_Y, "value": 1.0},
			{"type": "joyb", "button": JOY_BUTTON_DPAD_DOWN},
		],
		"move_left": [
			{"type": "key", "keycode": KEY_A},
			{"type": "key", "keycode": KEY_LEFT},
			{"type": "joym", "axis": JOY_AXIS_LEFT_X, "value": -1.0},
			{"type": "joyb", "button": JOY_BUTTON_DPAD_LEFT},
		],
		"move_right": [
			{"type": "key", "keycode": KEY_D},
			{"type": "key", "keycode": KEY_RIGHT},
			{"type": "joym", "axis": JOY_AXIS_LEFT_X, "value": 1.0},
			{"type": "joyb", "button": JOY_BUTTON_DPAD_RIGHT},
		],
		"confirm": [
			{"type": "key", "keycode": KEY_ENTER},
			{"type": "key", "keycode": KEY_SPACE},
			{"type": "joyb", "button": JOY_BUTTON_A},
		],
		"cancel": [
			{"type": "key", "keycode": KEY_ESCAPE},
			{"type": "joyb", "button": JOY_BUTTON_B},
		],
		"pause": [
			{"type": "key", "keycode": KEY_ESCAPE},
			{"type": "joyb", "button": JOY_BUTTON_START},
		],
	}

# --- Event (de)serialization -------------------------------------------------
static func build_event(d: Dictionary) -> InputEvent:
	match String(d.get("type", "")):
		"key":
			var ek := InputEventKey.new()
			ek.physical_keycode = int(d.get("keycode", 0))
			return ek
		"joyb":
			var eb := InputEventJoypadButton.new()
			eb.button_index = int(d.get("button", 0))
			return eb
		"joym":
			var em := InputEventJoypadMotion.new()
			em.axis = int(d.get("axis", 0))
			em.axis_value = float(d.get("value", 0.0))
			return em
	return null

static func serialize_event(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var kc: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		return {"type": "key", "keycode": kc}
	elif ev is InputEventJoypadButton:
		return {"type": "joyb", "button": ev.button_index}
	elif ev is InputEventJoypadMotion:
		return {"type": "joym", "axis": ev.axis, "value": (1.0 if ev.axis_value >= 0.0 else -1.0)}
	return {}

# --- Apply / reset -----------------------------------------------------------
# Ensures every action exists and sets its events from `custom`
# (action -> [event-dicts]); missing actions fall back to defaults. Then mirrors
# confirm/cancel onto ui_accept/ui_cancel.
static func apply(custom: Dictionary) -> void:
	var defs := defaults()
	for meta in ACTIONS:
		var action: String = meta["action"]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var ev_dicts: Array = custom.get(action, defs.get(action, []))
		for d in ev_dicts:
			var ev := build_event(d)
			if ev != null:
				InputMap.action_add_event(action, ev)
	_mirror_ui()

static func reset_all() -> void:
	apply({})

static func reset_action(action: String) -> void:
	var defs := defaults()
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	for d in defs.get(action, []):
		var ev := build_event(d)
		if ev != null:
			InputMap.action_add_event(action, ev)
	_mirror_ui()

# Restores only one device's default bindings for an action, keeping the other.
static func reset_keyboard_action(action: String) -> void:
	_reset_device(action, true)

static func reset_controller_action(action: String) -> void:
	_reset_device(action, false)

static func _reset_device(action: String, keyboard: bool) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var defs := defaults()
	var kept: Array[InputEvent] = []
	for e in InputMap.action_get_events(action):
		var is_kb := e is InputEventKey
		if keyboard != is_kb:
			kept.append(e)   # keep the other device's events
	InputMap.action_erase_events(action)
	for e in kept:
		InputMap.action_add_event(action, e)
	for d in defs.get(action, []):
		var d_is_kb := String(d.get("type", "")) == "key"
		if d_is_kb == keyboard:
			var ev := build_event(d)
			if ev != null:
				InputMap.action_add_event(action, ev)
	_mirror_ui()

static func reset_all_keyboard() -> void:
	for meta in ACTIONS:
		reset_keyboard_action(meta["action"])

static func reset_all_controller() -> void:
	for meta in ACTIONS:
		reset_controller_action(meta["action"])

# Replaces this action's keyboard binding (keeps controller events).
static func rebind_keyboard(action: String, ev: InputEventKey) -> void:
	_rebind(action, ev, true)

# Replaces this action's controller binding (keeps keyboard events).
static func rebind_controller(action: String, ev: InputEvent) -> void:
	_rebind(action, ev, false)

static func _rebind(action: String, new_ev: InputEvent, keyboard: bool) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var kept: Array[InputEvent] = []
	for e in InputMap.action_get_events(action):
		var is_kb := e is InputEventKey
		if keyboard != is_kb:
			kept.append(e)   # keep the other device's events
	InputMap.action_erase_events(action)
	for e in kept:
		InputMap.action_add_event(action, e)
	InputMap.action_add_event(action, new_ev)
	_mirror_ui()

static func _mirror_ui() -> void:
	_copy_action_to("confirm", "ui_accept")
	_copy_action_to("cancel", "ui_cancel")

static func _copy_action_to(src: String, dst: String) -> void:
	if not InputMap.has_action(src) or not InputMap.has_action(dst):
		return
	InputMap.action_erase_events(dst)
	for ev in InputMap.action_get_events(src):
		InputMap.action_add_event(dst, ev)

# --- Config persistence ------------------------------------------------------
static func load_custom(cfg: ConfigFile) -> Dictionary:
	var out := {}
	for meta in ACTIONS:
		var action: String = meta["action"]
		if cfg.has_section_key(CONFIG_SECTION, action):
			out[action] = cfg.get_value(CONFIG_SECTION, action)
	return out

static func save_to_config(cfg: ConfigFile) -> void:
	for meta in ACTIONS:
		var action: String = meta["action"]
		var arr: Array = []
		if InputMap.has_action(action):
			for ev in InputMap.action_get_events(action):
				var d := serialize_event(ev)
				if not d.is_empty():
					arr.append(d)
		cfg.set_value(CONFIG_SECTION, action, arr)

# --- Display helpers ---------------------------------------------------------
static func describe_keyboard(action: String) -> String:
	if InputMap.has_action(action):
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				var kc: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
				return OS.get_keycode_string(kc)
	return "—"

static func describe_controller(action: String) -> String:
	if InputMap.has_action(action):
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton:
				return joy_button_name(ev.button_index)
			elif ev is InputEventJoypadMotion:
				return joy_axis_name(ev.axis, ev.axis_value)
	return "—"

static func joy_button_name(idx: int) -> String:
	match idx:
		JOY_BUTTON_A: return "A / Cross"
		JOY_BUTTON_B: return "B / Circle"
		JOY_BUTTON_X: return "X / Square"
		JOY_BUTTON_Y: return "Y / Triangle"
		JOY_BUTTON_LEFT_SHOULDER: return "LB / L1"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB / R1"
		JOY_BUTTON_BACK: return "Select / Share"
		JOY_BUTTON_START: return "Start / Options"
		JOY_BUTTON_LEFT_STICK: return "L-Stick Click"
		JOY_BUTTON_RIGHT_STICK: return "R-Stick Click"
		JOY_BUTTON_DPAD_UP: return "D-Pad Up"
		JOY_BUTTON_DPAD_DOWN: return "D-Pad Down"
		JOY_BUTTON_DPAD_LEFT: return "D-Pad Left"
		JOY_BUTTON_DPAD_RIGHT: return "D-Pad Right"
	return "Button %d" % idx

static func joy_axis_name(axis: int, value: float) -> String:
	var dir_pos := value >= 0.0
	match axis:
		JOY_AXIS_LEFT_X: return "L-Stick Right" if dir_pos else "L-Stick Left"
		JOY_AXIS_LEFT_Y: return "L-Stick Down" if dir_pos else "L-Stick Up"
		JOY_AXIS_RIGHT_X: return "R-Stick Right" if dir_pos else "R-Stick Left"
		JOY_AXIS_RIGHT_Y: return "R-Stick Down" if dir_pos else "R-Stick Up"
		JOY_AXIS_TRIGGER_LEFT: return "LT / L2"
		JOY_AXIS_TRIGGER_RIGHT: return "RT / R2"
	return "Axis %d" % axis
