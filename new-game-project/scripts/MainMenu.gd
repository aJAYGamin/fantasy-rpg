extends Control

@onready var new_game_btn = $LayoutContainer/CenterContainer/VBoxContainer/NewGameButton
@onready var continue_btn = $LayoutContainer/CenterContainer/VBoxContainer/ContinueButton
@onready var settings_btn = $LayoutContainer/CenterContainer/VBoxContainer/SettingsButton
@onready var quit_btn     = $LayoutContainer/CenterContainer/VBoxContainer/QuitButton
@onready var music_player = $MusicPlayer
@onready var hover_sound  = $HoverSound

const GAME_SCENE = "res://scenes/BattleScene.tscn"

func _ready():
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 1.0)

	continue_btn.disabled = not FileAccess.file_exists("user://savegame.json")
	if continue_btn.disabled:
		continue_btn.modulate.a = 0.4

	new_game_btn.pressed.connect(_on_new_game)
	continue_btn.pressed.connect(_on_continue)
	settings_btn.pressed.connect(_on_settings)
	quit_btn.pressed.connect(_on_quit)

	for btn in [new_game_btn, continue_btn, settings_btn, quit_btn]:
		btn.mouse_entered.connect(_on_button_hover)

	if music_player.stream != null:
		music_player.volume_db = -10.0
		music_player.play()

func _on_button_hover():
	if hover_sound.stream != null:
		hover_sound.play()

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
	if music_player.stream != null:
		var music_tween = create_tween()
		music_tween.tween_property(music_player, "volume_db", -40.0, 0.8)
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.8)
	tween.tween_callback(func(): get_tree().change_scene_to_file(scene_path))
	