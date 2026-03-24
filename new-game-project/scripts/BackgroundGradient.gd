extends Control

var shift: float = 0.0

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(self, "shift", 1.0, 8.0)
	tween.tween_property(self, "shift", 0.0, 8.0)

func _process(_delta):
	queue_redraw()

func _draw():
	var w = size.x
	var h = size.y

	# Bottom center — 20 layers, tiny alpha steps, no visible edges
	# Matches: radial-gradient(ellipse 80% 60% at 50% 100%, #1a0a3a 0%, transparent 70%)
	for i in range(20):
		var t = float(i) / 20.0
		var radius = h * (0.65 - t * 0.55)
		var alpha = (0.18 - t * 0.18) * (1.0 + shift * 0.05)
		if alpha > 0:
			draw_circle(
				Vector2(w * 0.5, h * 1.02),
				radius * 1.4,  # wider than tall to mimic ellipse
				Color(0.10, 0.04, 0.23, alpha)
			)

	# Bottom-left — 15 layers
	# Matches: radial-gradient(ellipse 60% 40% at 30% 80%, #0d1a3a 0%, transparent 60%)
	for i in range(15):
		var t = float(i) / 15.0
		var radius = h * (0.48 - t * 0.42)
		var alpha = 0.14 - t * 0.14
		if alpha > 0:
			draw_circle(
				Vector2(w * 0.28, h * 0.88),
				radius,
				Color(0.05, 0.10, 0.23, alpha)
			)
			