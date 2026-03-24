extends Control

var glow_alpha: float = 0.6
var float_offset: float = 0.0

# Particles
var particles: Array = []
const PARTICLE_COUNT = 12

class Particle:
	var pos: Vector2
	var velocity: Vector2
	var alpha: float
	var size: float
	var life: float
	var max_life: float

func _ready():
	_animate_glow()
	_animate_float()
	_init_particles()

func _animate_glow():
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(self, "glow_alpha", 1.0, 2.0)
	tween.tween_property(self, "glow_alpha", 0.5, 2.0)

func _animate_float():
	var tween = create_tween()
	tween.set_loops()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "float_offset", -8.0, 1.8)
	tween.tween_property(self, "float_offset", 0.0, 1.8)

func _init_particles():
	for i in range(PARTICLE_COUNT):
		var p = Particle.new()
		_reset_particle(p, true)
		particles.append(p)

func _reset_particle(p: Particle, random_life: bool = false):
	var cx = size.x / 2.0
	var cy = size.y / 2.0
	# Spawn around the gem center
	var angle = randf() * TAU
	var radius = randf_range(8.0, 28.0)
	p.pos = Vector2(cx + cos(angle) * radius, cy + sin(angle) * radius + float_offset)
	p.velocity = Vector2(randf_range(-8.0, 8.0), randf_range(-18.0, -6.0))
	p.size = randf_range(1.0, 2.5)
	p.max_life = randf_range(1.0, 2.5)
	p.life = randf_range(0.0, p.max_life) if random_life else 0.0
	p.alpha = 0.0

func _process(delta):
	for p in particles:
		p.life += delta
		if p.life >= p.max_life:
			_reset_particle(p)
			continue
		var t = p.life / p.max_life
		# Fade in then out
		p.alpha = sin(t * PI) * 0.7
		p.pos += p.velocity * delta
	queue_redraw()

func _draw():
	var w = size.x
	var h = size.y
	var cx = w / 2.0
	var cy = h / 2.0 + float_offset

	# --- Outer glow ---
	for i in range(6):
		var glow_size = 55.0 - i * 7.0
		var alpha = (glow_alpha * 0.12) - i * 0.015
		if alpha > 0:
			draw_circle(Vector2(cx, cy - 5), glow_size, Color(0.55, 0.1, 0.85, alpha))

	# --- Particles ---
	for p in particles:
		if p.alpha > 0:
			draw_circle(p.pos, p.size, Color(0.78, 0.5, 1.0, p.alpha))

	# --- Gem points ---
	var top    = Vector2(cx, cy - 38)
	var right  = Vector2(cx + 22, cy - 8)
	var left   = Vector2(cx - 22, cy - 8)
	var center = Vector2(cx, cy + 5)
	var bot_r  = Vector2(cx + 16, cy + 30)
	var bot_l  = Vector2(cx - 16, cy + 30)
	var bottom = Vector2(cx, cy + 42)

	# --- Facets ---
	draw_colored_polygon(PackedVector2Array([top, right, center, left]), Color(0.65, 0.3, 0.95, 0.95))
	draw_colored_polygon(PackedVector2Array([right, bot_r, bottom, center]), Color(0.38, 0.1, 0.65, 0.95))
	draw_colored_polygon(PackedVector2Array([left, center, bottom, bot_l]), Color(0.28, 0.07, 0.50, 0.95))
	draw_colored_polygon(PackedVector2Array([center, bot_r, bottom, bot_l]), Color(0.50, 0.18, 0.78, 0.95))

	# --- Outline ---
	var outline_color = Color(0.82, 0.58, 1.0, 0.9)
	var thickness = 1.4
	draw_line(top, right, outline_color, thickness)
	draw_line(top, left, outline_color, thickness)
	draw_line(right, bot_r, outline_color, thickness)
	draw_line(left, bot_l, outline_color, thickness)
	draw_line(bot_r, bottom, outline_color, thickness)
	draw_line(bot_l, bottom, outline_color, thickness)

	# --- Inner detail ---
	draw_line(top, center, Color(0.9, 0.8, 1.0, 0.35), 0.8)
	draw_line(right, center, Color(0.9, 0.8, 1.0, 0.2), 0.6)
	draw_line(left, center, Color(0.9, 0.8, 1.0, 0.2), 0.6)
	
