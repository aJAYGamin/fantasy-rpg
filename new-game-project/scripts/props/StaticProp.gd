@tool
class_name StaticProp
extends Node2D

## A single piece of overworld set dressing — a tree, bush, flower cluster.
##
## The node's POSITION IS THE PROP'S FOOT (where it meets the ground), not its
## centre. That matters for two reasons: it is the point the contact shadow sits
## on, and it is the Y the scene's y-sort uses to decide whether the player walks
## in front of or behind it. Drop one at the base of a tree and depth just works.
##
## This node is deliberately NOT y_sort_enabled: it must sort as a single unit at
## its foot. If it sorted internally, Godot would flatten the sprite into the
## parent sort by the SPRITE's own (treetop) Y and draw the player in front of
## trees — the same trap DepthOverlay documents.

@export var prop_name: String = "":
	set(v):
		prop_name = v
		_rebuild()

## Turns prop_name into a dropdown of everything in PropLibrary, so placing a
## prop by hand is a pick from a list rather than a string you can typo.
func _validate_property(property: Dictionary) -> void:
	if property.name == "prop_name":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(PropLibrary.names())

## World-space height in pixels. 0 = use PropLibrary's default for this prop.
@export var height_override: float = 0.0:
	set(v):
		height_override = v
		_rebuild()

@export var flip_h: bool = false:
	set(v):
		flip_h = v
		_rebuild()

@export_group("Shadow")
@export var shadow_enabled: bool = true:
	set(v):
		shadow_enabled = v
		_rebuild()
## Shadow width as a fraction of the sprite's width.
@export_range(0.0, 2.0) var shadow_width: float = 0.72:
	set(v):
		shadow_width = v
		_rebuild()
## Shadow height as a fraction of its width — low values read as ground contact.
@export_range(0.05, 1.0) var shadow_flatten: float = 0.30:
	set(v):
		shadow_flatten = v
		_rebuild()
@export_range(0.0, 1.0) var shadow_opacity: float = 0.34:
	set(v):
		shadow_opacity = v
		_rebuild()

@export_group("Tone")
## Slight darkening settles the props' bolder outlines into the painted map.
@export var tint: Color = Color(0.96, 0.97, 0.96, 1.0):
	set(v):
		tint = v
		_rebuild()

var _sprite: Sprite2D = null
var _shadow: Sprite2D = null

func _ready() -> void:
	y_sort_enabled = false
	_rebuild()

## Pure geometry for a foot-anchored prop — no scene tree required, so the
## anchoring contract can be unit-tested directly.
##
## Returns { scale, width, height, offset }: `offset` is the sprite's local
## position under `centered = false`, chosen so the art's bottom-centre lands
## exactly on the node origin (the foot).
static func layout(tex_size: Vector2, prop_name_in: String, height_override_in: float = 0.0) -> Dictionary:
	var h := height_override_in
	if h <= 0.0:
		h = PropLibrary.height_for(prop_name_in)
	if h <= 0.0:
		h = tex_size.y
	var s := 0.0 if tex_size.y <= 0.0 else h / tex_size.y
	var w := tex_size.x * s
	return {
		"scale": s,
		"width": w,
		"height": h,
		"offset": Vector2(-w * 0.5, -h),
	}

## Ellipse dimensions for the contact shadow under a prop of the given width.
static func shadow_size(sprite_width: float, width_ratio: float, flatten: float) -> Vector2:
	var sw := sprite_width * width_ratio
	return Vector2(sw, sw * flatten)

## Builds (or refreshes) the shadow + sprite children. Safe to call repeatedly —
## it reuses the nodes rather than churning them, so editor tweaks stay cheap.
func _rebuild() -> void:
	if not is_inside_tree():
		return
	var tex := PropLibrary.texture_for(prop_name)
	if tex == null:
		if _sprite != null:
			_sprite.visible = false
		if _shadow != null:
			_shadow.visible = false
		return

	var lay := layout(tex.get_size(), prop_name, height_override)
	var s: float = lay["scale"]
	var w: float = lay["width"]

	# --- shadow first so it draws beneath the prop ---
	# Resolve by name before creating: after a scene reload the script's node
	# refs are null, and blindly adding would stack a fresh pair of children on
	# every load. These children are deliberately left unowned so they are never
	# written into the .tscn — the prop rebuilds itself from prop_name instead.
	if _shadow == null:
		_shadow = get_node_or_null("Shadow") as Sprite2D
	if _shadow == null:
		_shadow = Sprite2D.new()
		_shadow.name = "Shadow"
		add_child(_shadow)
	_shadow.texture = PropShadow.texture()
	_shadow.visible = shadow_enabled
	if shadow_enabled:
		var sz := shadow_size(w, shadow_width, shadow_flatten)
		var st := _shadow.texture.get_size()
		_shadow.scale = Vector2(sz.x / st.x, sz.y / st.y)
		_shadow.position = Vector2.ZERO          # centred on the foot
		_shadow.modulate = Color(1, 1, 1, shadow_opacity)

	# --- the prop itself, standing on the foot point ---
	if _sprite == null:
		_sprite = get_node_or_null("Sprite") as Sprite2D
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite"
		add_child(_sprite)
	_sprite.visible = true
	_sprite.texture = tex
	_sprite.centered = false
	_sprite.scale = Vector2(s, s)
	# Anchor bottom-centre: shift left by half a width and up by a full height.
	_sprite.position = lay["offset"]
	_sprite.flip_h = flip_h
	_sprite.modulate = tint
	# Painted art, not pixel art — linear filtering is correct here.
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

## Convenience for code-spawned props (the scatter uses this).
static func create(p_name: String, pos: Vector2, height: float = 0.0, flip: bool = false) -> StaticProp:
	var p := StaticProp.new()
	p.prop_name = p_name
	p.height_override = height
	p.flip_h = flip
	p.position = pos
	return p
