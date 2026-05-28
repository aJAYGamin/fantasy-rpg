extends Control

## DefeatScreen.gd
## Attach to a Control node inside BattleUI/UIRoot
## Set Anchor Preset to Full Rect, initially hidden

signal continue_from_save
signal quit_to_menu

@onready var overlay       = $Overlay
@onready var content       = $Content
@onready var defeat_label  = $Content/DefeatLabel
@onready var continue_btn  = $Content/ContinueButton
@onready var quit_btn      = $Content/QuitButton

var _card: Control = null  # themed card wrapping Content (set in _apply_theme)

func _ready():
	hide()
	continue_btn.pressed.connect(_on_continue)
	quit_btn.pressed.connect(_on_quit)
	_apply_theme()

# Wraps the centered content in a themed crimson-bordered card and styles the
# title + buttons to match the rest of the battle UI.
func _apply_theme():
	var accent := Color(0.90, 0.30, 0.30)  # defeat crimson

	overlay.color = Color(0.04, 0.01, 0.02, 0.78)

	var center := CenterContainer.new()
	center.name = "CardCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var card := PanelContainer.new()
	card.name = "ThemedCard"
	var style := BattleUITheme.panel_style(accent, BattleUITheme.PANEL_BG, 3, 16)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	style.shadow_size = 10
	card.add_theme_stylebox_override("panel", style)
	center.add_child(card)
	_card = card

	if content.get_parent() != null:
		content.get_parent().remove_child(content)
	card.add_child(content)

	# Spacing between the title and the two buttons.
	content.add_theme_constant_override("separation", 18)

	# Title — crimson with a drop shadow + decorative stars.
	defeat_label.text = "✦  Defeat  ✦"
	defeat_label.add_theme_color_override("font_color", accent)
	defeat_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	defeat_label.add_theme_constant_override("shadow_offset_x", 2)
	defeat_label.add_theme_constant_override("shadow_offset_y", 2)

	# Themed buttons.
	BattleUITheme.style_button(continue_btn, 14)
	BattleUITheme.style_button(quit_btn, 14)
	continue_btn.custom_minimum_size = Vector2(240, 42)
	quit_btn.custom_minimum_size = Vector2(240, 42)
	continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

func show_defeat():
	await get_tree().create_timer(1.0).timeout
	show()

	overlay.modulate.a = 0.0
	var fade_target = _card if _card != null else content
	fade_target.modulate.a = 0.0
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(overlay, "modulate:a", 1.0, 0.6)
	tween.tween_property(fade_target, "modulate:a", 1.0, 0.9)

func _on_continue():
	emit_signal("continue_from_save")
	if GameManager.in_overworld_battle:
		# Phase 2c: revive party at 50% HP and return to overworld at saved position.
		# Proper game-over with save-reload flow comes once save points exist.
		GameManager.revive_party()
		var path: String = GameManager.pending_overworld_scene_path
		if path == "":
			path = "res://scenes/OverworldScene.tscn"
		get_tree().change_scene_to_file(path)
	elif GameManager.load_game():
		get_tree().change_scene_to_file("res://scenes/BattleScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_quit():
	emit_signal("quit_to_menu")
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
