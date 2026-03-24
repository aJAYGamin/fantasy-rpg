extends Control

## StarField.gd
## Add this as a child of MainMenu, behind everything else
## Set its Anchor Preset to Full Rect

const STAR_COUNT = 80

func _ready():
	_spawn_stars()

func _spawn_stars():
	var screen = get_viewport_rect().size
	for i in range(STAR_COUNT):
		var star = ColorRect.new()
		var size = randf_range(1.0, 3.0)
		star.size = Vector2(size, size)
		star.position = Vector2(
			randf() * screen.x,
			randf() * screen.y
		)
		# Mix of white and soft purple stars
		if randf() > 0.6:
			star.color = Color(0.8, 0.7, 1.0, randf_range(0.3, 0.9))
		else:
			star.color = Color(1.0, 1.0, 1.0, randf_range(0.2, 0.8))
		add_child(star)
		_animate_star(star)

func _animate_star(star: ColorRect):
	var tween = create_tween()
	tween.set_loops()
	var duration = randf_range(1.5, 4.0)
	var delay = randf_range(0.0, 4.0)
	# Start invisible
	star.modulate.a = 0.0
	tween.tween_interval(delay)
	tween.tween_property(star, "modulate:a", 1.0, duration)
	tween.tween_property(star, "modulate:a", 0.0, duration)
