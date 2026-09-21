extends CanvasLayer

## ClockOverlay — a small styled clock shown top-left during overworld exploration.
## Shows the current phase icon (Dawn/Day/Dusk/Night) + name + time (e.g. "1:24 PM").
## Phase icons cross-fade when the phase changes so transitions are seamless; if an
## icon is missing it falls back to a colored dot. Created by GameManager; reads the
## live clock each frame.
##
## NOTE: reaches GameManager via get_parent() as an UNTYPED ref so the parser never
## resolves the GameManager autoload type while this script is being load()-compiled
## from within GameManager._ready (the re-entrant trap the dialogue box hit).

# Phase int (TimeOfDay.Phase: 0=Dawn,1=Day,2=Dusk,3=Night) -> icon path.
const ICON_PATHS := {
	0: "res://assets/icons/Dawn.png",
	1: "res://assets/icons/Day.png",
	2: "res://assets/icons/Dusk.png",
	3: "res://assets/icons/Night.png",
}
# Wider than tall: the Dawn/Dusk half-suns are landscape, so a wide slot lets them
# fill it at a consistent visual size next to the square Day/Night icons.
const ICON_SLOT := Vector2(46, 40)
const FADE_TIME := 0.6

var _gm = null
var _root: Control
var _icon_slot: Control
var _icon_cur: TextureRect
var _icon_prev: TextureRect
var _dot: Label                       # fallback when an icon is missing
var _phase_lbl: Label
var _time_lbl: Label
var _phase_textures := {}
var _shown_phase: int = -1

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_gm = get_parent()
	_load_icons()
	_build()

func _load_icons() -> void:
	for phase in ICON_PATHS:
		var path: String = ICON_PATHS[phase]
		if ResourceLoader.exists(path):
			var tex = load(path)
			if tex is Texture2D:
				_phase_textures[phase] = tex

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var panel := BattleUITheme.make_panel()
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.offset_left = 18
	panel.offset_top = 16
	var pstyle := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if pstyle:
		pstyle.content_margin_left = 12
		pstyle.content_margin_right = 16
		pstyle.content_margin_top = 8
		pstyle.content_margin_bottom = 8
	_root.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(row)

	# Icon slot: two stacked TextureRects (for cross-fade) + a fallback dot.
	_icon_slot = Control.new()
	_icon_slot.custom_minimum_size = ICON_SLOT
	_icon_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_icon_slot)
	_icon_prev = _make_icon_rect()
	_icon_slot.add_child(_icon_prev)
	_icon_cur = _make_icon_rect()
	_icon_slot.add_child(_icon_cur)
	_dot = Label.new()
	_dot.text = "●"
	_dot.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dot.add_theme_font_size_override("font_size", 24)
	_dot.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.08, 0.9))
	_dot.add_theme_constant_override("outline_size", 4)
	_dot.visible = false
	_icon_slot.add_child(_dot)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	_phase_lbl = _label("Day", BattleUITheme.font_bold(), 15, BattleUITheme.TEXT_ACCENT)
	col.add_child(_phase_lbl)
	_time_lbl = _label("8:00 AM", BattleUITheme.font_regular(), 13, BattleUITheme.TEXT_SUBTITLE)
	col.add_child(_time_lbl)

func _make_icon_rect() -> TextureRect:
	var r := TextureRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.modulate.a = 0.0
	return r

func _process(_delta: float) -> void:
	if _gm == null or _root == null:
		return
	var show_clock: bool = _gm.time_clock_visible()
	_root.visible = show_clock
	if not show_clock:
		return
	var c = _gm.clock
	_phase_lbl.text = c.phase_name()
	_time_lbl.text = c.clock_text()
	var phase: int = c.phase()
	if phase != _shown_phase:
		_set_phase_icon(phase, _shown_phase != -1)   # animate only after the first set
		_shown_phase = phase

# Swaps the phase icon, cross-fading from the previous one when `animate` is true.
func _set_phase_icon(phase: int, animate: bool) -> void:
	var tex = _phase_textures.get(phase)
	if tex == null:
		# No icon for this phase — show the colored dot instead.
		_dot.visible = true
		_dot.add_theme_color_override("font_color", _gm.clock.phase_color())
		_icon_cur.modulate.a = 0.0
		_icon_prev.modulate.a = 0.0
		return
	_dot.visible = false
	if animate and _icon_cur.texture != null:
		_icon_prev.texture = _icon_cur.texture
		_icon_prev.modulate.a = 1.0
		_icon_cur.texture = tex
		_icon_cur.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_icon_prev, "modulate:a", 0.0, FADE_TIME).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_icon_cur, "modulate:a", 1.0, FADE_TIME).set_trans(Tween.TRANS_SINE)
	else:
		_icon_cur.texture = tex
		_icon_cur.modulate.a = 1.0
		_icon_prev.modulate.a = 0.0

func _label(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	if font:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
