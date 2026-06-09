class_name RoamingEnemy
extends CharacterBody2D

## A visible overworld enemy (Mario & Luigi style). It wanders inside its own
## territory (home_rect) and chases the player only while the player is within that
## territory; if the player leaves, it gives up and returns home. Touching the
## player starts that enemy's specific battle (its EncounterGroup), tagged with
## `spawn_id` so the overworld can remove it permanently after a win.
##
## No art yet — drawn as a colored square placeholder. OverworldScene owns
## spawning/persistence; this node only handles its own motion and reports contact
## via the `touched_player` signal.

signal touched_player(enemy: RoamingEnemy)

const WANDER_SPEED := 70.0          # a touch slower than the player (SPEED 180) ...
const CHASE_SPEED := 130.0          # ... but faster when actively chasing
const DETECT_RADIUS := 220.0        # start chasing within this distance
const LOSE_RADIUS := 360.0          # stop chasing past this distance
const WANDER_REPICK_MIN := 0.8
const WANDER_REPICK_MAX := 2.2
const SIZE := Vector2(30, 30)
const FADED_ALPHA := 0.4            # while the player has flee i-frames

var spawn_id: int = -1
var group_index: int = -1           # index into the area's encounter_groups (for persistence)
var encounter_group: EncounterGroup = null
# Territory this enemy is bound to (world space). It never wanders or chases
# outside it. Defaults huge so an unset roamer still moves.
var home_rect: Rect2 = Rect2(-100000, -100000, 200000, 200000)

var _player: Node2D = null
var _chasing := false
var _wander_dir := Vector2.ZERO
var _repick_timer := 0.0
var _active := true                 # false while a battle is in flight (freeze)

func setup(id: int, group: EncounterGroup, gindex: int, player: Node2D, territory: Rect2) -> void:
	spawn_id = id
	encounter_group = group
	group_index = gindex
	_player = player
	home_rect = territory

func _ready() -> void:
	_build_visuals()
	_pick_new_wander_dir()

func _build_visuals() -> void:
	# Crimson square placeholder so roamers read as hostile vs the blue player.
	var sprite := ColorRect.new()
	sprite.name = "Sprite"
	sprite.color = Color(0.85, 0.25, 0.25)
	sprite.size = SIZE
	sprite.position = -SIZE / 2.0
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sprite)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = SIZE
	shape.shape = rect
	add_child(shape)

func freeze() -> void:
	_active = false
	velocity = Vector2.ZERO

# Visually fade the roamer while the player is invulnerable (flee i-frames).
func set_faded(faded: bool) -> void:
	var sprite := get_node_or_null("Sprite")
	if sprite is ColorRect:
		(sprite as ColorRect).modulate.a = FADED_ALPHA if faded else 1.0

# Whether the player is currently inside this enemy's territory (with a small
# Strictly inside the territory — no grow margin. If the player isn't standing in
# the enemy's home area, the enemy can't track or chase them at all (even if the
# player is within sight range just outside the border).
func _player_in_territory() -> bool:
	if _player == null:
		return false
	return home_rect.has_point(_player.global_position)

func _physics_process(delta: float) -> void:
	if not _active or _player == null or not is_instance_valid(_player):
		return

	var to_player := _player.global_position - global_position
	var dist := to_player.length()

	# Chase only while the player is inside this enemy's territory. Hysteresis:
	# start inside DETECT_RADIUS, stop past LOSE_RADIUS or when player leaves home.
	if _chasing:
		if dist > LOSE_RADIUS or not _player_in_territory():
			_chasing = false
			_pick_new_wander_dir()
	elif dist <= DETECT_RADIUS and _player_in_territory():
		_chasing = true

	if _chasing:
		velocity = to_player.normalized() * CHASE_SPEED
	else:
		_repick_timer -= delta
		if _repick_timer <= 0.0:
			_pick_new_wander_dir()
		velocity = _wander_dir * WANDER_SPEED

	move_and_slide()

	# Keep inside the territory: clamp position and steer back if pushed to an edge.
	var clamped := _clamp_to_home(global_position)
	if clamped != global_position:
		global_position = clamped
		if not _chasing:
			_pick_new_wander_dir()

	# If we slid into a wall, repick a direction.
	if not _chasing and velocity.length() > 0.0 and get_slide_collision_count() > 0:
		_pick_new_wander_dir()

	# Contact with the player → ask the overworld to start this enemy's battle.
	# Only when the player is actually inside the enemy's territory (so an enemy
	# pinned at its border can't grab a player just outside it). We do NOT freeze
	# here: the overworld may decline (e.g. during the player's flee i-frames), and
	# freezing would stop _physics_process so we'd never re-check contact when the
	# grace window ends. The overworld calls freeze() itself once it accepts.
	if _player_in_territory() and to_player.length() <= (SIZE.x * 0.5 + 22.0):
		touched_player.emit(self)

# Clamps a position to within the home territory (accounting for the sprite size).
func _clamp_to_home(p: Vector2) -> Vector2:
	var half := SIZE * 0.5
	var lo := home_rect.position + half
	var hi := home_rect.position + home_rect.size - half
	# Guard against a territory smaller than the sprite.
	if lo.x > hi.x: lo.x = hi.x
	if lo.y > hi.y: lo.y = hi.y
	return Vector2(clampf(p.x, lo.x, hi.x), clampf(p.y, lo.y, hi.y))

func _pick_new_wander_dir() -> void:
	# Bias the wander direction back toward home center when near an edge so the
	# enemy naturally stays within its territory instead of hugging the border.
	var to_center := (home_rect.position + home_rect.size * 0.5) - global_position
	var ang := randf() * TAU
	var rand_dir := Vector2(cos(ang), sin(ang))
	if to_center.length() > home_rect.size.length() * 0.25:
		_wander_dir = (rand_dir + to_center.normalized() * 1.5).normalized()
	else:
		_wander_dir = rand_dir
	_repick_timer = randf_range(WANDER_REPICK_MIN, WANDER_REPICK_MAX)
