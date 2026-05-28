extends TestSuite

func suite_name() -> String:
	return "HeroPalette"

func test_known_heroes_have_distinct_accents() -> void:
	var aria := HeroPalette.accent_for("Aria")
	var kael := HeroPalette.accent_for("Kael")
	var lyra := HeroPalette.accent_for("Lyra")
	# Aria blue: B channel dominant
	assert_true(aria.b > aria.r, "Aria's accent is blue-dominant")
	# Kael red: R channel dominant
	assert_true(kael.r > kael.g and kael.r > kael.b, "Kael's accent is red-dominant")
	# Lyra green: G channel dominant
	assert_true(lyra.g > lyra.r and lyra.g > lyra.b, "Lyra's accent is green-dominant")

func test_unknown_hero_falls_back_to_default() -> void:
	var p := HeroPalette.for_hero("UnknownHero")
	# Default is purplish — assert keys exist and accent is non-black.
	assert_true(p.has("accent"), "palette has accent")
	assert_true(p.has("panel_bg"), "palette has panel_bg")
	assert_true(p["accent"].r + p["accent"].g + p["accent"].b > 0.5, "fallback accent is non-black")

func test_palette_has_required_keys() -> void:
	var p := HeroPalette.for_hero("Aria")
	for key in ["accent", "subtitle", "label", "value", "increment",
			"border", "panel_bg", "button_bg", "button_hover_bg",
			"button_pressed_bg", "separator"]:
		assert_true(p.has(key), "palette has key: %s" % key)

func test_panel_bg_is_darker_than_accent() -> void:
	# Sanity: panel background should be a dark tinted version of the accent,
	# not the accent itself (or chrome would be unreadable).
	var p := HeroPalette.for_hero("Kael")
	var accent_brightness: float = p["accent"].r + p["accent"].g + p["accent"].b
	var bg_brightness: float = p["panel_bg"].r + p["panel_bg"].g + p["panel_bg"].b
	assert_true(bg_brightness < accent_brightness, "panel_bg darker than accent")
