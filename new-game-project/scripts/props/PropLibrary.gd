class_name PropLibrary
extends RefCounted

## Named registry of the overworld prop art (assets/props/static).
##
## Props are generated at 512x512 with the subject scaled to fill most of the
## canvas, so relative size is NOT baked into the art: a daisy and an oak are
## both ~430px tall. `height` below is therefore the source of truth for how
## tall each prop should be IN WORLD UNITS, and StaticProp scales to match.
##
## Heights are tuned against Fallster Plains at its 1:1 render scale, where the
## player is 32 units and the painted trees read ~130 units tall.

const PROP_DIR := "res://assets/props/static/"

## name -> { file, height, category }
## `category` groups props for scattering (see names_in_category).
const DEFS := {
	# --- trees & large vegetation ---
	"tree_oak":       {"file": "tree_oak.png",       "height": 135.0, "category": "tree"},
	"tree_pine":      {"file": "tree_pine.png",      "height": 150.0, "category": "tree"},
	"tree_dead":      {"file": "tree_dead.png",      "height": 120.0, "category": "tree"},
	"tree_birch":     {"file": "tree_birch.png",     "height": 130.0, "category": "tree"},
	"tree_willow":    {"file": "tree_willow.png",    "height": 132.0, "category": "tree"},
	"tree_maple":     {"file": "tree_maple.png",     "height": 134.0, "category": "tree"},
	"tree_sapling":   {"file": "tree_sapling.png",   "height": 70.0,  "category": "tree"},
	"tree_forest":    {"file": "tree_forest.png",    "height": 140.0, "category": "tree"},
	"log_fallen":     {"file": "log_fallen.png",     "height": 55.0,  "category": "debris"},

	# --- ground cover ---
	"flowers_pink":   {"file": "flowers_pink.png",   "height": 44.0,  "category": "flower"},
	"flowers_yellow": {"file": "flowers_yellow.png", "height": 42.0,  "category": "flower"},
	"flowers_white":  {"file": "flowers_white.png",  "height": 43.0,  "category": "flower"},
	"flowers_blue":   {"file": "flowers_blue.png",   "height": 42.0,  "category": "flower"},
	"grass_tuft":     {"file": "grass_tuft.png",     "height": 40.0,  "category": "ground"},
	"bush":           {"file": "bush.png",           "height": 58.0,  "category": "ground"},
	"wheat_patch":    {"file": "wheat_patch.png",    "height": 60.0,  "category": "crop"},
	"reeds":          {"file": "reeds.png",          "height": 62.0,  "category": "water_edge"},
	"mushrooms_red":  {"file": "mushrooms_red.png",  "height": 34.0,  "category": "ground"},

	# --- rock ---
	"rock_boulders":  {"file": "rock_boulders.png",  "height": 72.0,  "category": "rock"},
	"rock_small":     {"file": "rock_small.png",     "height": 26.0,  "category": "rock"},

	# --- rustic structures ---
	"fence_wood":     {"file": "fence_wood.png",     "height": 56.0,  "category": "structure"},
	"signpost":       {"file": "signpost.png",       "height": 86.0,  "category": "structure"},
	"well":           {"file": "well.png",           "height": 96.0,  "category": "structure"},
	"bridge_wood":    {"file": "bridge_wood.png",    "height": 100.0, "category": "structure"},
	"cart":           {"file": "cart.png",           "height": 70.0,  "category": "structure"},
	"stump":          {"file": "stump.png",          "height": 42.0,  "category": "debris"},
	"firewood":       {"file": "firewood.png",       "height": 46.0,  "category": "debris"},

	# --- fire & light ---
	# All nine are Sprite Motion inputs and light sources: pair each with an
	# AnimatedProp loop plus a PointLight2D rather than baking a glow in.
	"candle":         {"file": "candle.png",         "height": 18.0,  "category": "light"},
	"torch_wall":     {"file": "torch_wall.png",     "height": 58.0,  "category": "light"},
	"campfire":       {"file": "campfire.png",       "height": 52.0,  "category": "light"},
	"brazier":        {"file": "brazier.png",        "height": 68.0,  "category": "light"},
	"lamp_post":      {"file": "lamp_post.png",      "height": 105.0, "category": "light"},
	"fireplace":      {"file": "fireplace.png",      "height": 80.0, "category": "light"},
	"lantern_hanging":{"file": "lantern_hanging.png","height": 48.0,  "category": "light"},
	"forge":          {"file": "forge.png",          "height": 90.0, "category": "light"},
	"cauldron":       {"file": "cauldron.png",       "height": 48.0,  "category": "light"},
}

static func has_prop(prop_name: String) -> bool:
	return DEFS.has(prop_name)

static func path_for(prop_name: String) -> String:
	if not DEFS.has(prop_name):
		return ""
	return PROP_DIR + String(DEFS[prop_name]["file"])

## Default world-space height for a prop, or 0.0 if the name is unknown.
static func height_for(prop_name: String) -> float:
	if not DEFS.has(prop_name):
		return 0.0
	return float(DEFS[prop_name]["height"])

static func category_for(prop_name: String) -> String:
	if not DEFS.has(prop_name):
		return ""
	return String(DEFS[prop_name]["category"])

static func names() -> Array[String]:
	var out: Array[String] = []
	for k in DEFS.keys():
		out.append(String(k))
	out.sort()
	return out

static func names_in_category(category: String) -> Array[String]:
	var out: Array[String] = []
	for k in DEFS.keys():
		if String(DEFS[k]["category"]) == category:
			out.append(String(k))
	out.sort()
	return out

## Loads a prop texture by name. Returns null for unknown names or missing files
## so callers can skip gracefully rather than crashing a whole scene.
static func texture_for(prop_name: String) -> Texture2D:
	var p := path_for(prop_name)
	if p == "" or not ResourceLoader.exists(p):
		return null
	return load(p) as Texture2D
