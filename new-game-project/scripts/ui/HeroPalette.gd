class_name HeroPalette
extends RefCounted

## HeroPalette — single source of truth for per-hero accent colors and the
## derived palette (border, panel bg, subtitle tint, button states, separator)
## used by the level-up screen, the in-battle hero panels, and any future
## hero-themed UI.
##
## Usage:
##   var p := HeroPalette.for_hero("Aria")
##   panel_style.border_color = p.accent
##   panel_style.bg_color     = p.panel_bg
##   name_lbl.add_theme_color_override("font_color", p.accent)

# Base accent per hero. Add new heroes here as they're introduced.
const HERO_BASE_COLORS: Dictionary = {
	"Aria": Color(0.30, 0.65, 1.00),   # blue / light blue (water mage)
	"Kael": Color(0.95, 0.30, 0.30),   # red / crimson
	"Lyra": Color(0.55, 0.95, 0.45),   # lime / green
}
const DEFAULT_HERO_COLOR := Color(0.75, 0.7, 0.95)

# Returns the raw accent color (no palette derivation). Useful when you only
# need the tint.
static func accent_for(hero_name: String) -> Color:
	return HERO_BASE_COLORS.get(hero_name, DEFAULT_HERO_COLOR)

# Returns the full palette dict. Same shape LevelUpScreen used before — pure
# function, same color in, same dict out.
static func for_hero(hero_name: String) -> Dictionary:
	var base: Color = accent_for(hero_name)
	var dark := Color(0.04, 0.03, 0.07)
	return {
		"accent": base,
		"subtitle": base.lerp(Color(1, 1, 1), 0.45),
		"label": base.lerp(Color(1, 1, 1), 0.40),
		"value": Color(0.96, 0.94, 1.0),         # always near-white for readability
		"increment": Color(0.45, 1.00, 0.55),    # universal positive-change green
		"border": base.lerp(dark, 0.35),
		"panel_bg": base.lerp(dark, 0.88),
		"button_bg": base.lerp(dark, 0.92),
		"button_hover_bg": base.lerp(dark, 0.65),
		"button_pressed_bg": base.lerp(dark, 0.55),
		"separator": base.lerp(dark, 0.55),
	}
