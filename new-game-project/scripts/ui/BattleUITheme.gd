class_name BattleUITheme
extends RefCounted

## Shared visual constants + style builders for the battle UI so the action
## menu, turn order indicator, enemy cards, portrait placeholders, and any
## ad-hoc panels share the same look:
##   - dark plum background
##   - amethyst border, rounded corners
##   - drop shadow
## Hero-themed surfaces (hero panels, level-up screen, target highlight on
## allies) still use HeroPalette for per-hero accents — call them together to
## get a hero-tinted panel via the same builder.

# --- Default amethyst palette ---
const PANEL_BG := Color(0.07, 0.05, 0.12, 0.94)
const PANEL_BORDER := Color(0.55, 0.35, 0.95)
const SUBPANEL_BG := Color(0.10, 0.07, 0.16, 0.92)

const BUTTON_BG := Color(0.14, 0.10, 0.20, 0.95)
const BUTTON_HOVER_BG := Color(0.22, 0.16, 0.32, 1.0)
const BUTTON_PRESSED_BG := Color(0.30, 0.22, 0.45, 1.0)
const BUTTON_BORDER := Color(0.50, 0.35, 0.80, 0.85)

const TEXT_PRIMARY := Color(0.92, 0.86, 1.00)
const TEXT_SUBTITLE := Color(0.78, 0.65, 0.95)
const TEXT_ACCENT := Color.WHITE

# Returns a Cinzel font if available, else null. Centralized so font swaps
# require one edit.
static func font_regular() -> FontFile:
	if ResourceLoader.exists("res://fonts/Cinzel-Regular.ttf"):
		return load("res://fonts/Cinzel-Regular.ttf")
	return null

static func font_bold() -> FontFile:
	if ResourceLoader.exists("res://fonts/Cinzel-Bold.ttf"):
		return load("res://fonts/Cinzel-Bold.ttf")
	return null

# Panel style — rounded amethyst-bordered dark panel. Override border/bg for
# hero-tinted panels (pass HeroPalette values).
static func panel_style(border_color: Color = PANEL_BORDER, bg: Color = PANEL_BG,
		border_width: int = 2, corner_radius: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border_color
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(corner_radius)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 4
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

# Applies the themed look to an EXISTING Button (e.g., one defined in a .tscn).
# Use this when you can't replace the button — only restyle it.
static func style_button(b: Button, font_size: int = 11) -> void:
	if b == null:
		return
	var f := font_bold()
	if f: b.add_theme_font_override("font", f)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", TEXT_PRIMARY)
	b.add_theme_color_override("font_hover_color", TEXT_ACCENT)
	b.add_theme_color_override("font_pressed_color", TEXT_ACCENT)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.45, 0.6, 0.6))

	var normal := StyleBoxFlat.new()
	normal.bg_color = BUTTON_BG
	normal.border_color = BUTTON_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5
	b.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.bg_color = BUTTON_HOVER_BG
	hover.border_color = PANEL_BORDER
	b.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate()
	pressed.bg_color = BUTTON_PRESSED_BG
	pressed.border_color = PANEL_BORDER
	b.add_theme_stylebox_override("pressed", pressed)

	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.10, 0.08, 0.14, 0.85)
	disabled.border_color = Color(0.30, 0.25, 0.40, 0.5)
	b.add_theme_stylebox_override("disabled", disabled)

# Builds a fresh themed Button.
static func make_button(text: String, font_size: int = 11) -> Button:
	var b := Button.new()
	b.text = text
	style_button(b, font_size)
	return b

# Themed PanelContainer wrapping arbitrary content.
static func make_panel(border_color: Color = PANEL_BORDER, bg: Color = PANEL_BG) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(border_color, bg))
	return p
