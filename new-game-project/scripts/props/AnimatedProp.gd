@tool
class_name AnimatedProp
extends Node2D

## A looping animated prop — torch, campfire, fountain, banner.
##
## Same foot-anchored contract as StaticProp (position = where it meets the
## ground, not y-sorted internally) plus two things baked in:
##
##  * **Desync.** Every instance starts on a random frame at a slightly randomised
##    speed, so a wall of torches flickers like separate fires instead of one
##    fire copied eight times. This is the difference between "animated" and
##    "obviously looping".
##  * **Real light.** An optional PointLight2D instead of a glow painted into the
##    sprite. A baked halo is what made the first candle look fuzzy; a light is
##    crisp, spills onto neighbouring props, and can ride the time-of-day clock.

signal loop_finished   ## emitted for non-looping props (chest opening, etc.)

## Where tools/import_animation.gd writes its trimmed, downscaled loops.
const ANIM_DIR := "res://assets/props/animated/"

## Pick an imported animation by name; the frames load themselves. Leave empty
## to drive this node from an explicit `frames` resource instead.
@export var prop_name: String = "":
	set(v):
		prop_name = v
		_load_named_frames()
		_rebuild()

## Names of every imported animation, i.e. the folders under ANIM_DIR. Used to
## turn prop_name into a dropdown so placing one is a pick, not a typed path.
static func available() -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(ANIM_DIR)
	if d == null:
		return out
	for sub in d.get_directories():
		if ResourceLoader.exists(ANIM_DIR + sub + "/frame_01.png"):
			out.append(sub)
	out.sort()
	return out

func _validate_property(property: Dictionary) -> void:
	if property.name == "prop_name":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(available())

func _load_named_frames() -> void:
	if prop_name == "":
		return
	var dir := ANIM_DIR + prop_name
	if not ResourceLoader.exists(dir + "/frame_01.png"):
		return
	frames = frames_from_dir(dir, animation_name, fps, loop)

@export var frames: SpriteFrames = null:
	set(v):
		frames = v
		_rebuild()
@export var animation_name: String = "default":
	set(v):
		animation_name = v
		_rebuild()
@export var fps: float = 12.0:
	set(v):
		fps = v
		_rebuild()
@export var loop: bool = true:
	set(v):
		loop = v
		_rebuild()

## World-space height in pixels. 0 = use the frame's native size.
@export var height_override: float = 0.0:
	set(v):
		height_override = v
		_rebuild()

@export_group("Desync")
## Start on a random frame so identical props don't animate in lockstep.
@export var random_start_frame: bool = true
## Per-instance speed jitter, e.g. 0.12 = +/-12%.
@export_range(0.0, 0.5) var speed_jitter: float = 0.12

@export_group("Shadow")
@export var shadow_enabled: bool = false:
	set(v):
		shadow_enabled = v
		_rebuild()
@export_range(0.0, 2.0) var shadow_width: float = 0.7:
	set(v):
		shadow_width = v
		_rebuild()
@export_range(0.05, 1.0) var shadow_flatten: float = 0.3:
	set(v):
		shadow_flatten = v
		_rebuild()
@export_range(0.0, 1.0) var shadow_opacity: float = 0.3:
	set(v):
		shadow_opacity = v
		_rebuild()

@export_group("Light")
@export var light_enabled: bool = false:
	set(v):
		light_enabled = v
		_rebuild()
@export var light_color: Color = Color(1.0, 0.72, 0.36):
	set(v):
		light_color = v
		_rebuild()
@export var light_energy: float = 0.9:
	set(v):
		light_energy = v
		_rebuild()
## Light radius in world pixels.
@export var light_radius: float = 110.0:
	set(v):
		light_radius = v
		_rebuild()
## Height above the foot where the flame actually sits.
@export var light_offset_y: float = -40.0:
	set(v):
		light_offset_y = v
		_rebuild()

var _sprite: AnimatedSprite2D = null
var _shadow: Sprite2D = null
var _light: PointLight2D = null

func _ready() -> void:
	y_sort_enabled = false
	# Frames are not serialised with the node, so a named prop reloads them on
	# every open/run rather than baking 32 texture refs into the scene file.
	if frames == null:
		_load_named_frames()
	_rebuild()
	if not Engine.is_editor_hint():
		_desync()

## Randomises this instance's phase and rate. Called on ready; exposed so a test
## (or a pooled respawn) can re-roll it deterministically.
func _desync() -> void:
	if _sprite == null or frames == null:
		return
	if speed_jitter > 0.0:
		_sprite.speed_scale = 1.0 + randf_range(-speed_jitter, speed_jitter)
	if random_start_frame and frames.has_animation(animation_name):
		var n := frames.get_frame_count(animation_name)
		if n > 1:
			_sprite.frame = randi() % n
	_sprite.play(animation_name)

func _rebuild() -> void:
	if not is_inside_tree():
		return

	if _sprite == null:
		_sprite = get_node_or_null("Sprite") as AnimatedSprite2D
	if _sprite == null:
		_sprite = AnimatedSprite2D.new()
		_sprite.name = "Sprite"
		_sprite.animation_finished.connect(_on_finished)
		add_child(_sprite)

	if frames == null:
		_sprite.visible = false
		if _shadow != null: _shadow.visible = false
		if _light != null: _light.visible = false
		return
	_sprite.visible = true

	if frames.has_animation(animation_name):
		frames.set_animation_loop(animation_name, loop)
		frames.set_animation_speed(animation_name, fps)
	_sprite.sprite_frames = frames
	_sprite.animation = animation_name

	# Size from the first frame; every frame in a loop shares its dimensions.
	var h := height_override
	var w := 0.0
	var tex := _first_frame()
	if tex != null:
		# Fall back to the library height so an animated candle matches a static
		# one; only then to the raw frame size.
		if h <= 0.0 and prop_name != "":
			h = PropLibrary.height_for(prop_name)
		if h <= 0.0:
			h = float(tex.get_height())
		var s := h / float(tex.get_height())
		w = float(tex.get_width()) * s
		_sprite.scale = Vector2(s, s)
	_sprite.centered = false
	_sprite.offset = Vector2(-float(tex.get_width()) * 0.5, -float(tex.get_height())) if tex != null else Vector2.ZERO
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	# --- shadow ---
	if shadow_enabled:
		if _shadow == null:
			_shadow = get_node_or_null("Shadow") as Sprite2D
		if _shadow == null:
			_shadow = Sprite2D.new()
			_shadow.name = "Shadow"
			add_child(_shadow)
			move_child(_shadow, 0)   # beneath the sprite
		_shadow.texture = PropShadow.texture()
		_shadow.visible = true
		var sw := w * shadow_width
		var sh := sw * shadow_flatten
		var st := _shadow.texture.get_size()
		_shadow.scale = Vector2(sw / st.x, sh / st.y) if st.x > 0.0 else Vector2.ONE
		_shadow.modulate = Color(1, 1, 1, shadow_opacity)
	elif _shadow != null:
		_shadow.visible = false

	# --- light ---
	if light_enabled:
		if _light == null:
			_light = get_node_or_null("Light") as PointLight2D
		if _light == null:
			_light = PointLight2D.new()
			_light.name = "Light"
			add_child(_light)
		_light.texture = PropShadow.texture()   # same radial falloff, used as glow
		_light.visible = true
		_light.color = light_color
		_light.energy = light_energy
		_light.position = Vector2(0, light_offset_y)
		var lt := _light.texture.get_size()
		var d := light_radius * 2.0
		_light.texture_scale = d / lt.x if lt.x > 0.0 else 1.0
	elif _light != null:
		_light.visible = false

func _first_frame() -> Texture2D:
	if frames == null or not frames.has_animation(animation_name):
		return null
	if frames.get_frame_count(animation_name) == 0:
		return null
	return frames.get_frame_texture(animation_name, 0)

func _on_finished() -> void:
	if not loop:
		loop_finished.emit()

## Builds a SpriteFrames from numbered PNGs exported by SpriteFlow — the
## `frame_01.png … frame_NN.png` ZIP layout. Missing files stop the scan, so a
## partial export still yields a usable loop instead of erroring.
static func frames_from_dir(dir_path: String, anim: String = "default", p_fps: float = 12.0, p_loop: bool = true) -> SpriteFrames:
	var sf := SpriteFrames.new()
	if sf.has_animation("default") and anim != "default":
		sf.remove_animation("default")
	if not sf.has_animation(anim):
		sf.add_animation(anim)
	sf.set_animation_speed(anim, p_fps)
	sf.set_animation_loop(anim, p_loop)
	var base := dir_path
	if not base.ends_with("/"):
		base += "/"
	for i in range(1, 100):
		var p := "%sframe_%02d.png" % [base, i]
		if not ResourceLoader.exists(p):
			break
		var t := load(p) as Texture2D
		if t == null:
			break
		sf.add_frame(anim, t)
	return sf
