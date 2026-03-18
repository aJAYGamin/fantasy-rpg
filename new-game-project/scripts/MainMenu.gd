extends Control

## MainMenu.gd — The Amethyst Requiem

@onready var new_game_btn = $LayoutContainer/CenterContainer/VBoxContainer/NewGameButton
@onready var continue_btn = $LayoutContainer/CenterContainer/VBoxContainer/ContinueButton
@onready var settings_btn = $LayoutContainer/CenterContainer/VBoxContainer/SettingsButton
@onready var quit_btn     = $LayoutContainer/CenterContainer/VBoxContainer/QuitButton
@onready var title_label  = $LayoutContainer/TitleLabel

const GAME_SCENE = "res://scenes/BattleScene.tscn"

func _ready():
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 1.2)

	continue_btn.disabled = not FileAccess.file_exists("user://savegame.json")
	if continue_btn.disabled:
		continue_btn.modulate.a = 0.4

	new_game_btn.pressed.connect(_on_new_game)
	continue_btn.pressed.connect(_on_continue)
	settings_btn.pressed.connect(_on_settings)
	quit_btn.pressed.connect(_on_quit)

func _on_new_game():
	_transition_to(GAME_SCENE)

func _on_continue():
	if GameManager.load_game():
		_transition_to(GAME_SCENE)

func _on_settings():
	print("Settings coming soon!")

func _on_quit():
	get_tree().quit()

func _transition_to(scene_path: String):
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.8)
	tween.tween_callback(func(): get_tree().change_scene_to_file(scene_path))
