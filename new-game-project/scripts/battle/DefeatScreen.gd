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

	# Themed buttons. Continue reloads the last save, so label it accordingly.
	continue_btn.text = "Load Last Save"
	quit_btn.text = "Quit to Main Menu"
	BattleUITheme.style_button(continue_btn, 14)
	BattleUITheme.style_button(quit_btn, 14)
	continue_btn.custom_minimum_size = Vector2(240, 42)
	quit_btn.custom_minimum_size = Vector2(240, 42)
	continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

func show_defeat():
	# "Load Last Save" is only possible if there's a loadable save in the active
	# slot — otherwise grey it out and leave only Quit to Main Menu.
	var can_load: bool = GameManager.has_active_save()
	continue_btn.disabled = not can_load
	continue_btn.modulate.a = 1.0 if can_load else 0.45

	await get_tree().create_timer(1.0).timeout
	show()

	overlay.modulate.a = 0.0
	var fade_target = _card if _card != null else content
	fade_target.modulate.a = 0.0
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(overlay, "modulate:a", 1.0, 0.6)
	tween.tween_property(fade_target, "modulate:a", 1.0, 0.9)
	# Central focus guard maintains controller focus on the buttons while shown.
	# (The guard skips disabled buttons, so focus lands on Quit when Continue is off.)
	GameManager.register_focus_scope(self)

func _exit_tree() -> void:
	GameManager.unregister_focus_scope(self)

func _on_continue():
	# Load the last save and return to where it was made. If there's nothing to
	# load (shouldn't happen — the button is disabled then), fall back to the menu.
	emit_signal("continue_from_save")
	# Clear the battle-handoff flag so the overworld spawns from the save, not the
	# stale "returning from battle" position.
	GameManager.in_overworld_battle = false
	var path: String = GameManager.load_active_slot()
	if path == "":
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		return
	get_tree().change_scene_to_file(path)

func _on_quit():
	emit_signal("quit_to_menu")
	GameManager.in_overworld_battle = false
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
