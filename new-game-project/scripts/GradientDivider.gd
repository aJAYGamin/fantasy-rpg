extends Control

## GradientDivider.gd
## Draws a horizontal line that fades from transparent at edges to solid in center
## Set Custom Minimum Size to x: 200, y: 6 in Inspector
## Set Mouse Filter to Ignore

@export var line_color: Color = Color(0.49, 0.37, 0.63, 0.8)  # 7d5fa0

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw():
	var w = size.x
	var cy = size.y / 2.0
	var steps = 80

	for i in range(steps):
		var t = float(i) / float(steps)
		# Bell curve alpha — peaks at center, fades to 0 at edges
		var alpha = sin(t * PI)
		# Line thickness also varies — thicker in center
		var thickness = 1.0 + alpha * 1.2
		var x = t * w
		var color = Color(line_color.r, line_color.g, line_color.b, line_color.a * alpha)
		draw_line(Vector2(x, cy), Vector2(x + w / steps, cy), color, thickness)
