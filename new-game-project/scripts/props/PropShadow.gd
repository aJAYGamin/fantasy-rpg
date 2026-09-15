class_name PropShadow
extends RefCounted

## Builds the soft elliptical contact shadow that grounds a prop on the terrain.
##
## Without it, props read as stickers pasted on the map — the single biggest
## "sits in the world" cue, and it costs no art. One texture is generated on
## first use and shared by every prop in the game.

const TEX_SIZE := 128
## Falloff exponent — higher keeps the core dark and fades the rim faster.
const FALLOFF := 1.6

static var _cached: Texture2D = null

## A radial black-to-transparent blob, drawn once and reused. Props squash it
## into an ellipse via scale, so one square texture serves every footprint.
static func texture() -> Texture2D:
	if _cached != null:
		return _cached
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var c := TEX_SIZE * 0.5
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var dx := (float(x) - c) / c
			var dy := (float(y) - c) / c
			var d: float = sqrt(dx * dx + dy * dy)
			var v: float = clampf(1.0 - d, 0.0, 1.0)
			# Slightly green-black reads better over grass than pure black.
			img.set_pixel(x, y, Color(0.05, 0.06, 0.03, pow(v, FALLOFF)))
	_cached = ImageTexture.create_from_image(img)
	return _cached

## Test hook: drop the cached texture so a suite can rebuild it cleanly.
static func clear_cache() -> void:
	_cached = null
