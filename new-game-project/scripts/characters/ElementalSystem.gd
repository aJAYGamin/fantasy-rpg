class_name ElementalSystem
extends RefCounted

## ElementalSystem.gd
## Handles elemental types, weaknesses, resistances, and damage multipliers

enum Element {
	NORMAL,
	FIRE,
	WATER,
	NATURE,
	ICE,
	LIGHTNING,
	EARTH,
	WIND,
	SOUND,
	PSYCHIC,
	SPIRIT,
	DRAGON,
	METAL,
	LIGHT,
	DARK,
	AMETHYST,
}

# Damage multipliers
const WEAKNESS_MULTIPLIER   = 2.0   # Super effective
const RESISTANCE_MULTIPLIER = 0.5   # Not very effective
const IMMUNITY_MULTIPLIER   = 0.0   # No effect
const NORMAL_MULTIPLIER     = 1.0   # Neutral

## Full elemental chart
## _weakness_chart[ATTACKER][DEFENDER] = multiplier
static var _chart: Dictionary = {
	Element.NORMAL: {
		Element.SPIRIT: 0.0,    # Normal attacks have no effect on spirit
		Element.METAL: 0.5      # Normal attacks are resisted by metal
	},
	Element.FIRE: {
		Element.FIRE:  0.5,     # Fire resists fire
		Element.WATER: 0.5,     # Fire is doused by water
		Element.NATURE: 2.0,    # Fire burns nature
		Element.ICE:   2.0,     # Fire melts ice
		Element.EARTH: 0.5,     # Fire is smothered by earth
		Element.DRAGON: 0.5,    # Fire is resisted by dragons
		Element.METAL: 2.0      # Fire heats metal
	},
	Element.WATER: {
		Element.FIRE:  2.0,     # Water douses fire
		Element.WATER: 0.5,     # Water resists water
		Element.NATURE: 0.0,    # Water nourishes nature
		Element.LIGHTNING: 0.5, # Water conducts lightning
		Element.EARTH: 2.0,     # Water erodes earth
		Element.DRAGON: 0.5,    # Water is resisted by dragons
		Element.METAL: 0.5      # Water rusts metal
	},
	Element.NATURE: {
		Element.FIRE:  0.5,     # Nature is burned by fire
		Element.WATER: 2.0,     # Nature thrives with water
		Element.NATURE: 0.5,    # Nature resists nature
		Element.ICE:   0.5,     # Nature is frozen by ice
		Element.EARTH: 2.0,     # Nature grows in earth
		Element.WIND:  0.5,     # Nature is blown by wind
		Element.DRAGON: 0.5,    # Nature is resisted by dragons
		Element.METAL: 0.0      # Nature is cut by metal
	},
	Element.ICE: {
		Element.FIRE:  0.5,     # Ice is melted by fire
		Element.WATER: 2.0,     # Ice is frozen water
		Element.NATURE: 2.0,    # Ice freezes nature
		Element.ICE:   0.5,     # Ice resists ice
		Element.EARTH: 2.0,     # Ice cracks earth
		Element.DRAGON: 2.0,    # Ice is effective against dragons
		Element.METAL: 0.5      # Ice is cut by metal
	},
	Element.LIGHTNING: {
		Element.WATER: 2.0,     # Lightning conducts through water
		Element.LIGHTNING: 0.5, # Lightning resists lightning
		Element.EARTH: 0.0,     # Earth absorbs lightning
		Element.DRAGON: 0.5,    # Lightning is resisted by dragons
		Element.METAL: 2.0      # Lightning shocks metal
	},
	Element.EARTH: {
		Element.FIRE:  2.0,     # Earth smothers fire
		Element.WATER: 0.5,     # Earth absorbs water
		Element.NATURE: 0.5,    # Earth resists nature
		Element.EARTH: 0.5,     # Earth resists earth
		Element.WIND:  0.0,     # Earth blocks wind
		Element.LIGHTNING: 2.0, # Earth absorbs lightning
		Element.METAL: 2.0      # Earth contains metal
	},
	Element.WIND: {
		Element.WATER: 2.0,     # Wind disperses water
		Element.NATURE: 2.0,    # Wind spreads nature
		Element.LIGHTNING: 2.0, # Wind conducts lightning
		Element.WIND:  0.5,     # Wind resists wind
		Element.DRAGON: 0.5,    # Wind is resisted by dragons
		Element.METAL: 0.5      # Wind is resisted by metal
	},
	Element.SOUND: {
		Element.WATER: 2.0,     # Sound travels through water
		Element.NATURE: 2.0,    # Sound rustles nature
		Element.ICE: 2.0,       # Sound shatters ice
		Element.SOUND: 0.5,     # Sound resists sound
		Element.PSYCHIC: 0.5,   # Sound disrupts psychic
		Element.SPIRIT: 0.5,    # Sound disturbs spirit
		Element.METAL: 0.5      # Sound is muffled by metal
	},
	Element.PSYCHIC: {
		Element.EARTH: 0.5,     # Psychic is grounded by earth
		Element.SOUND: 2.0,     # Psychic is disrupted by sound
		Element.PSYCHIC: 0.5,   # Psychic resists psychic
		Element.SPIRIT: 2.0,    # Psychic affects spirit
		Element.METAL: 0.5,     # Psychic is resisted by metal
	},
	Element.SPIRIT: {
		Element.NATURE: 2.0,    # Spirit animates nature
		Element.EARTH: 2.0,     # Spirit is grounded by earth
		Element.SOUND: 0.5,     # Spirit is disturbed by sound
		Element.PSYCHIC: 2.0,   # Spirit is affected by psychic
		Element.SPIRIT: 2.0,    # Spirit resists spirit
		Element.METAL: 2.0,     # Spirit is resisted by metal
		Element.LIGHT: 0.0,     # Spirit is effective against light
		Element.DARK: 0.0       # Spirit is effective against dark
	},
	Element.DRAGON: {
		Element.DRAGON: 2.0,    # Dragons are strong against other dragons
		Element.METAL: 0.5      # Dragons are resistant to metal
	},
	Element.METAL: {
		Element.FIRE:  0.5,     # Metal is heated by fire
		Element.WATER: 0.5,     # Metal is rusted by water
		Element.NATURE: 2.0,    # Metal cuts nature
		Element.ICE:   2.0,     # Metal shatters ice
		Element.LIGHTNING: 0.5, # Metal conducts lightning
		Element.EARTH: 0.5,     # Metal is contained by earth
		Element.WIND:  2.0,     # Metal resists wind
		Element.SOUND: 0.5,     # Metal resonates with sound
		Element.METAL: 0.5      # Metal resists metal
	},
	Element.LIGHT: {
		Element.DARK:  2.0,   # Light banishes dark
		Element.LIGHT: 0.5,
	},
	Element.DARK: {
		Element.LIGHT: 2.0,   # Darkness swallows light
		Element.DARK:  0.5,
	},
	Element.AMETHYST: {
		Element.FIRE: 2.0,    # Amethyst is effective against fire
		Element.WATER: 2.0,   # Amethyst is effective against water
		Element.NATURE: 2.0,  # Amethyst is effective against nature
		Element.ICE: 2.0,     # Amethyst is effective against ice
		Element.LIGHTNING: 2.0,# Amethyst is effective against lightning
		Element.EARTH: 2.0,   # Amethyst is effective against earth
		Element.WIND: 2.0,    # Amethyst is effective against wind
		Element.SOUND: 2.0,   # Amethyst is effective against sound
		Element.PSYCHIC: 2.0, # Amethyst is effective against psychic
		Element.SPIRIT: 2.0,  # Amethyst is effective against spirit
		Element.DRAGON: 2.0,  # Amethyst is effective against dragons
		Element.METAL: 2.0,   # Amethyst is effective against metal
		Element.LIGHT: 2.0,   # Amethyst is effective against light
		Element.DARK: 2.0     # Amethyst is effective against dark
	}
}

## Get damage multiplier between attack element and target element.
## NORMAL is a real type now (no NONE), so we always do chart lookup.
static func get_multiplier(attack_element: Element, target_element: Element) -> float:
	if _chart.has(attack_element):
		var row = _chart[attack_element]
		if row.has(target_element):
			return row[target_element]
	return NORMAL_MULTIPLIER

## Get a text description of the interaction
static func get_effectiveness_text(multiplier: float) -> String:
	if multiplier == WEAKNESS_MULTIPLIER:
		return "It's super effective!"
	elif multiplier == NORMAL_MULTIPLIER:
		return "It's effective!"
	elif multiplier == IMMUNITY_MULTIPLIER:
		return "It has no effect..."
	elif multiplier == RESISTANCE_MULTIPLIER:
		return "It's not very effective..."
	return ""

## Get display color for effectiveness
static func get_effectiveness_color(multiplier: float) -> Color:
	if multiplier == WEAKNESS_MULTIPLIER:
		return Color(0.40, 0.60, 1.00)   # Blue for super-effective
	elif multiplier == NORMAL_MULTIPLIER:
		return Color(0.35, 0.85, 0.45)   # Green for effective (normal hit)
	elif multiplier == IMMUNITY_MULTIPLIER:
		return Color(0.50, 0.50, 0.50)   # Grey for immune
	elif multiplier == RESISTANCE_MULTIPLIER:
		return Color(1.00, 0.40, 0.10)   # Red for resisted
	return Color.WHITE

## Get element icon character for UI display
static func get_element_icon(element: Element) -> String:
	match element:
		Element.NORMAL:    return "◇"       # neutral glyph so Normal still reads as a type
		Element.FIRE:      return "🔥"
		Element.WATER:     return "💧"
		Element.NATURE:    return "🌿"
		Element.ICE:       return "❄"
		Element.LIGHTNING: return "⚡"
		Element.EARTH:     return "🪨"
		Element.WIND:      return "🌀"
		Element.SOUND:     return "🔊"
		Element.PSYCHIC:   return "🧠"
		Element.SPIRIT:    return "👻"
		Element.DRAGON:    return "🐉"
		Element.METAL:     return "⚙"
		Element.LIGHT:     return "✨"
		Element.DARK:      return "🌑"
		Element.AMETHYST:  return "🔮"
		_:                 return ""

## Get element name string
static func get_element_name(element: Element) -> String:
	match element:
		Element.NORMAL:    return "Normal"
		Element.FIRE:      return "Fire"
		Element.WATER:     return "Water"
		Element.NATURE:    return "Nature"
		Element.ICE:       return "Ice"
		Element.LIGHTNING: return "Lightning"
		Element.EARTH:     return "Earth"
		Element.WIND:      return "Wind"
		Element.SOUND:     return "Sound"
		Element.PSYCHIC:   return "Psychic"
		Element.SPIRIT:    return "Spirit"
		Element.DRAGON:    return "Dragon"
		Element.METAL:     return "Metal"
		Element.LIGHT:     return "Light"
		Element.DARK:      return "Dark"
		Element.AMETHYST:  return "Amethyst"
		_:                 return "Normal"

## Get element color for UI theming
static func get_element_color(element: Element) -> Color:
	match element:
		Element.NORMAL:    return Color(0.75, 0.75, 0.78)
		Element.FIRE:      return Color(1.00, 0.30, 0.10)
		Element.WATER:     return Color(0.20, 0.55, 1.00)
		Element.NATURE:    return Color(0.40, 0.85, 0.40)
		Element.ICE:       return Color(0.50, 0.90, 1.00)
		Element.LIGHTNING: return Color(1.00, 0.90, 0.10)
		Element.EARTH:     return Color(0.60, 0.40, 0.10)
		Element.WIND:      return Color(0.65, 1.00, 0.70)
		Element.SOUND:     return Color(0.95, 0.85, 0.45)
		Element.PSYCHIC:   return Color(0.90, 0.40, 0.85)
		Element.SPIRIT:    return Color(0.78, 0.78, 1.00)
		Element.DRAGON:    return Color(0.85, 0.50, 0.20)
		Element.METAL:     return Color(0.70, 0.72, 0.78)
		Element.LIGHT:     return Color(1.00, 1.00, 0.70)
		Element.DARK:      return Color(0.40, 0.10, 0.60)
		Element.AMETHYST:  return Color(0.65, 0.35, 0.95)
		_:                 return Color.WHITE

## Dual-element damage calculation — multiplies ALL pairwise multipliers.
## - Attacker may have 1 or 2 attack elements (secondary = NORMAL means "single typed").
## - Defender may have 1 or 2 defense elements (same sentinel rule).
##
## Example: Aquatic Pyre (Fire+Water) vs Fire Drake (Fire+Dragon):
##   water_vs_fire * water_vs_dragon * fire_vs_fire * fire_vs_dragon
##   = 2.0 * 0.5 * 0.5 * 0.5 = 0.25
## Every pair counts: weaknesses and resistances both stack.
## NORMAL is the "no secondary type" sentinel unless the primary itself is NORMAL.
static func get_combined_multiplier(
		atk_primary: Element, atk_secondary: Element,
		def_primary: Element, def_secondary: Element) -> float:
	var attackers: Array = [atk_primary]
	if atk_secondary != Element.NORMAL and atk_secondary != atk_primary:
		attackers.append(atk_secondary)
	var defenders: Array = [def_primary]
	if def_secondary != Element.NORMAL and def_secondary != def_primary:
		defenders.append(def_secondary)

	var result: float = 1.0
	for a in attackers:
		for d in defenders:
			result *= get_multiplier(a, d)
	return result
