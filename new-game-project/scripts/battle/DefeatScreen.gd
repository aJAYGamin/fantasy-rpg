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

func _ready():
	hide()
	continue_btn.pressed.connect(_on_continue)
	quit_btn.pressed.connect(_on_quit)

func show_defeat():
	await get_tree().create_timer(1.0).timeout
	show()

	overlay.modulate.a = 0.0
	content.modulate.a = 0.0
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(overlay, "modulate:a", 1.0, 0.6)
	tween.tween_property(content, "modulate:a", 1.0, 0.9)

func _on_continue():
	emit_signal("continue_from_save")
	if GameManager.load_game():
		get_tree().change_scene_to_file("res://scenes/BattleScene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_quit():
	emit_signal("quit_to_menu")
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
