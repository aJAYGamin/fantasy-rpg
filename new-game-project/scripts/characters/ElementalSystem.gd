class_name ElementalSystem
extends RefCounted

## ElementalSystem.gd
## Handles elemental types, weaknesses, resistances, and damage multipliers

enum Element {
	NONE,
	FIRE,
	ICE,
	LIGHTNING,
	EARTH,
	WIND,
	WATER,
	LIGHT,
	DARK,
	ARCANE   # Amethyst-specific magic type
}

# Damage multipliers
const WEAKNESS_MULTIPLIER   = 2.0   # Super effective
const RESISTANCE_MULTIPLIER = 0.5   # Not very effective
const IMMUNITY_MULTIPLIER   = 0.0   # No effect
const NORMAL_MULTIPLIER     = 1.0   # Neutral

## Full elemental chart
## _weakness_chart[ATTACKER][DEFENDER] = multiplier
static var _chart: Dictionary = {
	Element.FIRE: {
		Element.ICE:   2.0,   # Fire melts ice
		Element.WIND:  0.5,   # Wind spreads but weakens fire
		Element.WATER: 0.5,   # Water douses fire
		Element.EARTH: 1.5,   # Fire scorches earth
		Element.FIRE:  0.5,   # Fire resists fire
	},
	Element.ICE: {
		Element.FIRE:  0.5,   # Ice melts in fire
		Element.EARTH: 1.5,   # Ice freezes earth
		Element.WIND:  2.0,   # Ice freezes wind
		Element.WATER: 1.5,   # Ice freezes water
		Element.ICE:   0.5,   # Ice resists ice
	},
	Element.LIGHTNING: {
		Element.WATER: 2.0,   # Lightning electrifies water
		Element.WIND:  1.5,   # Lightning rides wind
		Element.EARTH: 0.5,   # Earth grounds lightning
		Element.LIGHTNING: 0.5,
	},
	Element.WATER: {
		Element.FIRE:  2.0,   # Water douses fire
		Element.EARTH: 1.5,   # Water erodes earth
		Element.ICE:   0.5,   # Water resists ice
		Element.LIGHTNING: 0.5,
		Element.WATER: 0.5,
	},
	Element.EARTH: {
		Element.LIGHTNING: 2.0,  # Earth absorbs lightning
		Element.FIRE:  0.5,
		Element.ICE:   0.5,
		Element.WIND:  1.5,
		Element.EARTH: 0.5,
	},
	Element.WIND: {
		Element.EARTH: 2.0,   # Wind erodes earth
		Element.FIRE:  1.5,
		Element.LIGHTNING: 0.5,
		Element.WIND:  0.5,
	},
	Element.LIGHT: {
		Element.DARK:  2.0,   # Light banishes dark
		Element.LIGHT: 0.5,
		Element.ARCANE: 1.5,
	},
	Element.DARK: {
		Element.LIGHT: 2.0,   # Darkness swallows light
		Element.ARCANE: 1.5,
		Element.DARK:  0.5,
	},
	Element.ARCANE: {
		Element.DARK:  1.5,
		Element.LIGHT: 1.5,
		Element.ARCANE: 0.75,
	},
}

## Get damage multiplier between attack element and target element
static func get_multiplier(attack_element: Element, target_element: Element) -> float:
	if attack_element == Element.NONE or target_element == Element.NONE:
		return NORMAL_MULTIPLIER
	if _chart.has(attack_element):
		var row = _chart[attack_element]
		if row.has(target_element):
			return row[target_element]
	return NORMAL_MULTIPLIER

## Get a text description of the interaction
static func get_effectiveness_text(multiplier: float) -> String:
	if multiplier >= 2.0:
		return "It's super effective!"
	elif multiplier > 1.0:
		return "It's effective!"
	elif multiplier == IMMUNITY_MULTIPLIER:
		return "It has no effect..."
	elif multiplier <= 0.5:
		return "It's not very effective..."
	return ""

## Get display color for effectiveness
static func get_effectiveness_color(multiplier: float) -> Color:
	if multiplier >= 2.0:
		return Color(1.0, 0.4, 0.1)   # Orange-red for super effective
	elif multiplier > 1.0:
		return Color(1.0, 0.8, 0.2)   # Yellow for effective
	elif multiplier == IMMUNITY_MULTIPLIER:
		return Color(0.5, 0.5, 0.5)   # Grey for immune
	elif multiplier <= 0.5:
		return Color(0.4, 0.6, 1.0)   # Blue for not effective
	return Color.WHITE

## Get element icon character for UI display
static func get_element_icon(element: Element) -> String:
	match element:
		Element.FIRE:      return "🔥"
		Element.ICE:       return "❄"
		Element.LIGHTNING: return "⚡"
		Element.WATER:     return "💧"
		Element.EARTH:     return "🪨"
		Element.WIND:      return "🌀"
		Element.LIGHT:     return "✨"
		Element.DARK:      return "🌑"
		Element.ARCANE:    return "💜"
		_:                 return ""

## Get element name string
static func get_element_name(element: Element) -> String:
	match element:
		Element.FIRE:      return "Fire"
		Element.ICE:       return "Ice"
		Element.LIGHTNING: return "Lightning"
		Element.WATER:     return "Water"
		Element.EARTH:     return "Earth"
		Element.WIND:      return "Wind"
		Element.LIGHT:     return "Light"
		Element.DARK:      return "Dark"
		Element.ARCANE:    return "Arcane"
		_:                 return "None"

## Get element color for UI theming
static func get_element_color(element: Element) -> Color:
	match element:
		Element.FIRE:      return Color(1.0, 0.3, 0.1)
		Element.ICE:       return Color(0.5, 0.9, 1.0)
		Element.LIGHTNING: return Color(1.0, 0.9, 0.1)
		Element.WATER:     return Color(0.1, 0.5, 1.0)
		Element.EARTH:     return Color(0.6, 0.4, 0.1)
		Element.WIND:      return Color(0.6, 1.0, 0.6)
		Element.LIGHT:     return Color(1.0, 1.0, 0.7)
		Element.DARK:      return Color(0.4, 0.1, 0.6)
		Element.ARCANE:    return Color(0.8, 0.4, 1.0)
		_:                 return Color.WHITE
