class_name OverworldPlayer
extends CharacterBody2D

const SPEED: float = 180.0

func _physics_process(_delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# Left-stick sensitivity scales analog tilt (keyboard input is already full
	# magnitude, so limit_length keeps it at normal speed).
	var sens: float = GameManager.settings.stick_sensitivity_left
	if not is_equal_approx(sens, 1.0):
		input_dir = (input_dir * sens).limit_length(1.0)
	velocity = input_dir * SPEED
	move_and_slide()
