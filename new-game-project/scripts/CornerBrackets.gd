extends Control

## CornerBrackets.gd
## Draws decorative corner brackets over the full screen
## Set Anchor Preset to Full Rect, mouse_filter to MOUSE_FILTER_IGNORE

const BRACKET_SIZE = 28.0
const BRACKET_THICKNESS = 1.2
const BRACKET_COLOR = Color(0.28, 0.18, 0.42, 0.7)
const MARGIN = 16.0

func _draw():
	var w = size.x
	var h = size.y

	# Top-left
	draw_line(Vector2(MARGIN, MARGIN), Vector2(MARGIN + BRACKET_SIZE, MARGIN), BRACKET_COLOR, BRACKET_THICKNESS)
	draw_line(Vector2(MARGIN, MARGIN), Vector2(MARGIN, MARGIN + BRACKET_SIZE), BRACKET_COLOR, BRACKET_THICKNESS)

	# Top-right
	draw_line(Vector2(w - MARGIN, MARGIN), Vector2(w - MARGIN - BRACKET_SIZE, MARGIN), BRACKET_COLOR, BRACKET_THICKNESS)
	draw_line(Vector2(w - MARGIN, MARGIN), Vector2(w - MARGIN, MARGIN + BRACKET_SIZE), BRACKET_COLOR, BRACKET_THICKNESS)

	# Bottom-left
	draw_line(Vector2(MARGIN, h - MARGIN), Vector2(MARGIN + BRACKET_SIZE, h - MARGIN), BRACKET_COLOR, BRACKET_THICKNESS)
	draw_line(Vector2(MARGIN, h - MARGIN), Vector2(MARGIN, h - MARGIN - BRACKET_SIZE), BRACKET_COLOR, BRACKET_THICKNESS)

	# Bottom-right
	draw_line(Vector2(w - MARGIN, h - MARGIN), Vector2(w - MARGIN - BRACKET_SIZE, h - MARGIN), BRACKET_COLOR, BRACKET_THICKNESS)
	draw_line(Vector2(w - MARGIN, h - MARGIN), Vector2(w - MARGIN, h - MARGIN - BRACKET_SIZE), BRACKET_COLOR, BRACKET_THICKNESS)

func _ready():
	# Make sure this doesn't block mouse clicks
	mouse_filter = Control.MOUSE_FILTER_IGNORE
