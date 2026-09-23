class_name RestScreen
extends Control

## The campfire scene. Fades in over the overworld, offers Rest or Learn/Forget
## Moves, and for a rest asks which part of the day to sleep until.
##
## The backdrop currently borrows assets/props/static/campfire.png as a stand-in
## until dedicated art exists — swap BACKDROP_PATH and drop the glow when it
## arrives.

signal finished   ## emitted once the player is done and the overworld resumes

const BACKDROP_PATH := "res://assets/props/static/campfire.png"
const FADE_TIME := 0.45

var _root: VBoxContainer = null
var _dim: ColorRect = null

func setup() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = true
	_build_backdrop()
	_show_main_menu()
	GameManager.register_focus_scope(self)
	# Fade in rather than cutting: the campfire is a change of place, and a hard
	# cut from the overworld reads as a glitch.
	modulate.a = 0.0
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(self, "modulate:a", 1.0, FADE_TIME)

func _exit_tree() -> void:
	GameManager.unregister_focus_scope(self)
	if get_tree() != null:
		get_tree().paused = false

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_leave()
		get_viewport().set_input_as_handled()

# --- scene ---------------------------------------------------------------------

func _build_backdrop() -> void:
	var screen := get_viewport_rect().size

	_dim = ColorRect.new()
	_dim.color = Color(0.05, 0.04, 0.08, 1.0)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.custom_minimum_size = screen
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	# Warm firelight pooling out of the centre.
	var glow := TextureRect.new()
	glow.texture = PropShadow.texture()
	glow.modulate = Color(1.0, 0.62, 0.26, 0.30)
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.size = Vector2(screen.x * 1.1, screen.x * 1.1)
	glow.position = (screen - glow.size) * 0.5
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	if ResourceLoader.exists(BACKDROP_PATH):
		var fire := TextureRect.new()
		fire.texture = load(BACKDROP_PATH)
		fire.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fire.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var h: float = clampf(screen.y * 0.42, 180.0, 420.0)
		fire.size = Vector2(h, h)
		fire.position = Vector2((screen.x - h) * 0.5, screen.y * 0.30)
		fire.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fire)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.custom_minimum_size = screen
	add_child(center)

	var panel := BattleUITheme.make_panel()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)

	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 10)
	panel.add_child(_root)

func _clear_root() -> void:
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()

# --- menus ---------------------------------------------------------------------

func _show_main_menu() -> void:
	_clear_root()
	_root.add_child(_title("✦  Camp  ✦"))
	_root.add_child(_note("The fire burns low and steady."))
	_root.add_child(_gap())

	var rest := BattleUITheme.make_button("Rest", 14)
	rest.custom_minimum_size = Vector2(0, 40)
	rest.pressed.connect(_show_phase_menu)
	_root.add_child(rest)

	var moves := BattleUITheme.make_button("Learn / Forget Moves", 14)
	moves.custom_minimum_size = Vector2(0, 40)
	moves.pressed.connect(_open_moves)
	_root.add_child(moves)

	var swaps := GameManager.rest_swaps_remaining
	_root.add_child(_note("Swaps available: %d" % swaps))

	var leave := BattleUITheme.make_button("← Leave", 13)
	leave.custom_minimum_size = Vector2(0, 34)
	leave.pressed.connect(_leave)
	_root.add_child(leave)

func _show_phase_menu() -> void:
	_clear_root()
	_root.add_child(_title("Rest until…"))
	_root.add_child(_note("Time passes until the hour you choose."))
	_root.add_child(_gap())

	for p in [TimeOfDay.Phase.DAWN, TimeOfDay.Phase.DAY, TimeOfDay.Phase.DUSK, TimeOfDay.Phase.NIGHT]:
		var t := TimeOfDay.new()
		t.set_minutes(TimeOfDay.phase_start_minutes(p))
		var b := BattleUITheme.make_button("%s  ·  %s" % [t.phase_name(), t.clock_text()], 13)
		b.custom_minimum_size = Vector2(0, 36)
		b.pressed.connect(func(): _do_rest(p))
		_root.add_child(b)

	var back := BattleUITheme.make_button("← Back", 13)
	back.custom_minimum_size = Vector2(0, 32)
	back.pressed.connect(_show_main_menu)
	_root.add_child(back)

func _do_rest(phase: int) -> void:
	var result := GameManager.rest_at_camp(phase)
	_clear_root()
	_root.add_child(_title("✦  Rested  ✦"))

	var t := TimeOfDay.new()
	t.set_minutes(GameManager.clock.minutes)
	_root.add_child(_note("The party wakes at %s, %s." % [t.clock_text(), t.phase_name()]))
	_root.add_child(_gap())

	var healed: Dictionary = result["healed"]
	if healed.is_empty():
		_root.add_child(_note("No one was well enough to benefit."))
	else:
		for name in healed:
			var h: Dictionary = healed[name]
			_root.add_child(_line("%s  +%d HP  +%d MP" % [name, int(h["hp"]), int(h["mp"])]))
	_root.add_child(_note("Resonance +%d" % int(GameManager.REST_RESONANCE)))
	_root.add_child(_gap())

	var go := BattleUITheme.make_button("Continue", 14)
	go.custom_minimum_size = Vector2(0, 38)
	go.pressed.connect(_leave)
	_root.add_child(go)

func _open_moves() -> void:
	var screen := LoadoutScreen.new()
	add_child(screen)
	screen.setup(LoadoutEditor.Mode.CAMPFIRE)
	# The loadout screen leaves the pause state as it found it, so the campfire
	# stays paused underneath; just redraw to show the swaps just spent.
	screen.closed.connect(func(): _show_main_menu())

func _leave() -> void:
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(self, "modulate:a", 0.0, FADE_TIME)
	t.tween_callback(func():
		finished.emit()
		queue_free())

# --- primitives ----------------------------------------------------------------

func _title(text: String) -> Label:
	return _mk(text, BattleUITheme.font_bold(), 20, BattleUITheme.TEXT_ACCENT)

func _note(text: String) -> Label:
	return _mk(text, BattleUITheme.font_regular(), 11, Color(0.68, 0.62, 0.78))

func _line(text: String) -> Label:
	return _mk(text, BattleUITheme.font_regular(), 13, BattleUITheme.TEXT_PRIMARY)

func _mk(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if font: l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _gap() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 6)
	return c
