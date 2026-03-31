extends Label

## DamageNumber.gd
## Spawned dynamically during battle — floats upward and fades out

const FADE_TIME = 0.9
const FLOAT_DISTANCE = 60.0

func setup(amount: int, multiplier: float = 1.0):
	var cinzel = load("res://fonts/Cinzel-Regular.ttf")
	if cinzel:
		add_theme_font_override("font", cinzel)

	# Dark background for readability
	add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	add_theme_constant_override("shadow_offset_x", 2)
	add_theme_constant_override("shadow_offset_y", 2)
	add_theme_constant_override("shadow_outline_size", 4)

	if multiplier >= 2.0:
		text = "%d\nCritical!" % amount
		add_theme_color_override("font_color", Color(0.2, 0.9, 0.9))
		add_theme_font_size_override("font_size", 20)
	elif multiplier > 1.0:
		text = "%d" % amount
		add_theme_color_override("font_color", Color.WHITE)
		add_theme_font_size_override("font_size", 16)
	elif multiplier <= 0.0:
		text = "Immune"
		add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		add_theme_font_size_override("font_size", 14)
	elif multiplier < 1.0:
		text = "%d\nResisted" % amount
		add_theme_color_override("font_color", Color(0.95, 0.35, 0.15))
		add_theme_font_size_override("font_size", 16)
	else:
		text = "%d" % amount
		add_theme_color_override("font_color", Color.WHITE)
		add_theme_font_size_override("font_size", 16)

	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_animate()

func setup_heal(amount: int):
	var cinzel = load("res://fonts/Cinzel-Regular.ttf")
	if cinzel:
		add_theme_font_override("font", cinzel)
	add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	add_theme_constant_override("shadow_offset_x", 2)
	add_theme_constant_override("shadow_offset_y", 2)
	add_theme_constant_override("shadow_outline_size", 4)
	text = "%d\nHealed" % amount
	add_theme_color_override("font_color", Color(0.2, 0.9, 0.4))
	add_theme_font_size_override("font_size", 16)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_animate()

func setup_dodge():
	var cinzel = load("res://fonts/Cinzel-Regular.ttf")
	if cinzel:
		add_theme_font_override("font", cinzel)
	add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	add_theme_constant_override("shadow_offset_x", 2)
	add_theme_constant_override("shadow_offset_y", 2)
	add_theme_constant_override("shadow_outline_size", 4)
	text = "Dodged!"
	add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	add_theme_font_size_override("font_size", 14)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_animate()

func _animate():
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - FLOAT_DISTANCE, FADE_TIME)\
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME)\
		.set_trans(Tween.TRANS_LINEAR)
	tween.chain().tween_callback(queue_free)
