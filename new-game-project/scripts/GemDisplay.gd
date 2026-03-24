extends Control

## GemDisplay.gd
## Draws the glowing purple diamond gem above the title
## Set Custom Minimum Size to x: 80, y: 90 in Inspector

var glow_alpha: float = 0.6
var glow_growing: bool = true

func _ready():
	_animate_glow()

func _animate_glow():
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(self, "glow_alpha", 1.0, 2.0)
	tween.tween_property(self, "glow_alpha", 0.5, 2.0)

func _process(_delta):
	queue_redraw()

func _draw():
	var w = size.x
	var h = size.y
	var cx = w / 2.0
	var cy = h / 2.0

	# --- Outer glow (soft radial blobs) ---
	for i in range(6):
		var glow_size = 55.0 - i * 7.0
		var alpha = (glow_alpha * 0.12) - i * 0.015
		if alpha > 0:
			draw_circle(
				Vector2(cx, cy - 5),
				glow_size,
				Color(0.55, 0.1, 0.85, alpha)
			)

	# --- Gem shape (diamond polygon) ---
	# Top facet (lighter purple)
	var top_facet = PackedVector2Array([
		Vector2(cx, cy - 38),       # top point
		Vector2(cx + 22, cy - 8),   # right
		Vector2(cx, cy + 5),        # center
		Vector2(cx - 22, cy - 8),   # left
	])
	draw_colored_polygon(top_facet, Color(0.65, 0.3, 0.95, 0.95))

	# Right facet (medium purple)
	var right_facet = PackedVector2Array([
		Vector2(cx + 22, cy - 8),
		Vector2(cx + 16, cy + 30),
		Vector2(cx, cy + 42),
		Vector2(cx, cy + 5),
	])
	draw_colored_polygon(right_facet, Color(0.38, 0.1, 0.65, 0.95))

	# Left facet (dark purple)
	var left_facet = PackedVector2Array([
		Vector2(cx - 22, cy - 8),
		Vector2(cx, cy + 5),
		Vector2(cx, cy + 42),
		Vector2(cx - 16, cy + 30),
	])
	draw_colored_polygon(left_facet, Color(0.28, 0.07, 0.50, 0.95))

	# Bottom center facet
	var bottom_facet = PackedVector2Array([
		Vector2(cx, cy + 5),
		Vector2(cx + 16, cy + 30),
		Vector2(cx, cy + 42),
		Vector2(cx - 16, cy + 30),
	])
	draw_colored_polygon(bottom_facet, Color(0.50, 0.18, 0.78, 0.95))

	# --- Gem outline ---
	var outline = PackedVector2Array([
		Vector2(cx, cy - 38),
		Vector2(cx + 22, cy - 8),
		Vector2(cx + 16, cy + 30),
		Vector2(cx, cy + 42),
		Vector2(cx - 16, cy + 30),
		Vector2(cx - 22, cy - 8),
	])
	draw_polyline(outline, Color(0.78, 0.55, 1.0, 0.7), 1.0, true)

	# --- Inner highlight line ---
	draw_line(
		Vector2(cx, cy - 38),
		Vector2(cx, cy + 5),
		Color(0.9, 0.8, 1.0, 0.4),
		0.8
	)
