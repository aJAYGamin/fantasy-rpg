extends Control

@onready var new_game_btn = $LayoutContainer/CenterContainer/VBoxContainer/NewGameButton
@onready var continue_btn = $LayoutContainer/CenterContainer/VBoxContainer/ContinueButton
@onready var settings_btn = $LayoutContainer/CenterContainer/VBoxContainer/SettingsButton
@onready var quit_btn     = $LayoutContainer/CenterContainer/VBoxContainer/QuitButton
@onready var music_player = $MusicPlayer

const GAME_SCENE = "res://scenes/OverworldScene.tscn"
const SAVE_SLOT_MENU_SCENE = "res://scenes/SaveSlotMenu.tscn"

var _slot_menu: Control = null
# Tracks which flow opened the slot menu so _on_slot_chosen knows how to dispatch.
var _slot_picker_mode: String = "new"
var _settings_overlay: SettingsScreen = null

func _ready():
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 1.0)

	_refresh_continue_button()

	new_game_btn.pressed.connect(_on_new_game)
	continue_btn.pressed.connect(_on_continue)
	settings_btn.pressed.connect(_on_settings)
	quit_btn.pressed.connect(_on_quit)

	# Hover/click SFX is now handled globally for every button by GameManager
	# (same misc_menu_4.wav), so no per-button hover wiring is needed here.

	# Themed focus ring. Focus navigation only engages with a controller; in
	# keyboard+mouse mode the menu is click-only. The central focus guard
	# (GameManager) makes these focusable and maintains focus; opening an overlay
	# (settings/slot picker) registers its own scope on top, locking these out.
	for b in [new_game_btn, continue_btn, settings_btn, quit_btn]:
		var focus := StyleBoxFlat.new()
		focus.bg_color = Color(0.85, 0.7, 1.0, 0.12)
		focus.border_color = Color(0.95, 0.85, 1.0)
		focus.set_border_width_all(2)
		focus.set_corner_radius_all(6)
		b.add_theme_stylebox_override("focus", focus)
	GameManager.register_focus_scope(self)

	# Route the menu music through the settings-controlled Music bus.
	music_player.bus = SettingsModel.BUS_MUSIC

	if music_player.stream != null:
		music_player.volume_db = -10.0
		# Loop the menu theme for as long as we're on this scene. Prefer the
		# stream's own loop flag; fall back to replaying on finish.
		if "loop" in music_player.stream:
			music_player.stream.loop = true
		else:
			music_player.finished.connect(func(): music_player.play())
		music_player.play()

func _refresh_continue_button():
	# Continue is enabled if ANY save slot has a file. If multiple exist, clicking
	# Continue opens a load picker; if exactly one exists, it loads directly.
	var any_exists := false
	for s in range(GameManager.SAVE_SLOT_COUNT):
		if GameManager.slot_exists(s):
			any_exists = true
			break
	continue_btn.disabled = not any_exists
	continue_btn.modulate.a = 1.0 if any_exists else 0.4

func _occupied_slots() -> Array[int]:
	var out: Array[int] = []
	for s in range(GameManager.SAVE_SLOT_COUNT):
		if GameManager.slot_exists(s):
			out.append(s)
	return out

func _ensure_slot_menu() -> Control:
	if _slot_menu == null:
		_slot_menu = load(SAVE_SLOT_MENU_SCENE).instantiate()
		add_child(_slot_menu)
		_slot_menu.slot_chosen.connect(_on_slot_chosen)
		_slot_menu.menu_closed.connect(_on_slot_menu_closed)
	return _slot_menu


func _on_new_game():
	_slot_picker_mode = "new"
	_ensure_slot_menu().open("new")

func _on_continue():
	var occupied := _occupied_slots()
	if occupied.is_empty():
		return  # button should have been disabled
	if occupied.size() == 1:
		# Single save — load directly, no picker.
		_load_slot_and_transition(occupied[0])
		return
	# Multiple saves — let the user pick which one.
	_slot_picker_mode = "load"
	_ensure_slot_menu().open("load")

func _on_slot_chosen(slot: int):
	if _slot_picker_mode == "load":
		_load_slot_and_transition(slot)
	else:
		GameManager.start_new_game(slot)
		_transition_to(GAME_SCENE)

func _load_slot_and_transition(slot: int):
	if not GameManager.load_from_slot(slot):
		push_warning("Continue failed — slot %d unreadable" % slot)
		_refresh_continue_button()
		return
	GameManager.resuming_from_save = true
	var path: String = GameManager.save_overworld_scene_path
	if path == "":
		path = GAME_SCENE
	_transition_to(path)

func _on_slot_menu_closed():
	# Refresh in case Copy/Delete changed slot state (e.g. user deleted their
	# only save and Continue should disable).
	_refresh_continue_button()

func _on_settings():
	if _settings_overlay != null and is_instance_valid(_settings_overlay):
		return
	var screen := SettingsScreen.new()
	_settings_overlay = screen
	screen.back_requested.connect(_close_settings)
	add_child(screen)
	screen.setup(true)

func _close_settings():
	if _settings_overlay != null and is_instance_valid(_settings_overlay):
		_settings_overlay.queue_free()
	_settings_overlay = null

func _on_quit():
	get_tree().quit()

func _transition_to(scene_path: String):
	if music_player.stream != null:
		var music_tween = create_tween()
		music_tween.tween_property(music_player, "volume_db", -40.0, 0.8)
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.8)
	tween.tween_callback(func(): get_tree().change_scene_to_file(scene_path))
