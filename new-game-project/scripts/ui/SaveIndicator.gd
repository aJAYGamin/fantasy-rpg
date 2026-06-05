class_name SaveIndicator
extends Control

## Small amethyst-themed auto-save status badge, pinned bottom-right.
## Listens to GameManager.autosave_started / autosave_finished:
##   • on start  -> fades in "✦ Saving Game…"
##   • on finish -> switches to "✦ Saved Game", holds briefly, fades out.
## Built in code with BattleUITheme styling so it matches the rest of the UI.

const MARGIN := 24.0
const HOLD_TIME := 1.4

var _panel: PanelContainer
var _label: Label
var _tween: Tween

func _ready() -> void:
	# Screen-space, non-blocking, survives pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Under a CanvasLayer there is no Control parent, so FULL_RECT anchors resolve
	# against a 0x0 rect and the bottom-right panel lands off-screen. Size this
	# root to the viewport explicitly (and track resizes).
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_resize_to_viewport()
	get_viewport().size_changed.connect(_resize_to_viewport)
	_build()
	if not GameManager.autosave_started.is_connected(_on_started):
		GameManager.autosave_started.connect(_on_started)
	if not GameManager.autosave_finished.is_connected(_on_finished):
		GameManager.autosave_finished.connect(_on_finished)

func _resize_to_viewport() -> void:
	size = get_viewport_rect().size

func _build() -> void:
	_panel = BattleUITheme.make_panel()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pstyle := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	if pstyle:
		pstyle.content_margin_left = 16
		pstyle.content_margin_right = 16
		pstyle.content_margin_top = 8
		pstyle.content_margin_bottom = 8
	# Pin to the bottom-right corner.
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = -MARGIN
	_panel.offset_top = -MARGIN
	_panel.offset_right = -MARGIN
	_panel.offset_bottom = -MARGIN
	add_child(_panel)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := BattleUITheme.font_bold()
	if f: _label.add_theme_font_override("font", f)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", BattleUITheme.TEXT_SUBTITLE)
	_panel.add_child(_label)

	_panel.modulate.a = 0.0

func _on_started() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_label.text = "✦  Saving Game…"
	_label.add_theme_color_override("font_color", BattleUITheme.TEXT_SUBTITLE)
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.25)

func _on_finished(success: bool) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_label.text = "✦  Saved Game" if success else "✦  Save Failed"
	_label.add_theme_color_override("font_color",
		Color(0.6, 1.0, 0.65) if success else Color(1.0, 0.55, 0.5))
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.2)
	_tween.tween_interval(HOLD_TIME)
	_tween.tween_property(_panel, "modulate:a", 0.0, 0.5)
