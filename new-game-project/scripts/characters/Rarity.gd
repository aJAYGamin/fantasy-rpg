class_name Rarity
extends RefCounted

enum Tier {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	MYTHIC,
	LEGENDARY,
	CELESTIAL
}

static func get_color(tier: Tier) -> Color:
	match tier:
		Tier.COMMON:    return Color(0.60, 0.60, 0.60)  # Grey
		Tier.UNCOMMON:  return Color(0.20, 0.80, 0.20)  # Green
		Tier.RARE:      return Color(0.20, 0.50, 1.00)  # Blue
		Tier.EPIC:      return Color(0.65, 0.20, 1.00)  # Purple
		Tier.MYTHIC:    return Color(0.90, 0.15, 0.15)  # Red
		Tier.LEGENDARY: return Color(1.00, 0.75, 0.00)  # Gold
		Tier.CELESTIAL: return Color(0.95, 0.95, 1.00)  # White/Silver
	return Color.WHITE

static func get_name(tier: Tier) -> String:
	match tier:
		Tier.COMMON:    return "Common"
		Tier.UNCOMMON:  return "Uncommon"
		Tier.RARE:      return "Rare"
		Tier.EPIC:      return "Epic"
		Tier.MYTHIC:    return "Mythic"
		Tier.LEGENDARY: return "Legendary"
		Tier.CELESTIAL: return "Celestial"
	return ""

static func get_loot_multiplier(tier: Tier) -> float:
	match tier:
		Tier.COMMON:    return 1.0
		Tier.UNCOMMON:  return 1.5
		Tier.RARE:      return 2.0
		Tier.EPIC:      return 3.0
		Tier.MYTHIC:    return 4.5
		Tier.LEGENDARY: return 6.0
		Tier.CELESTIAL: return 10.0
	return 1.0

static func get_exp_multiplier(tier: Tier) -> float:
	match tier:
		Tier.COMMON:    return 1.0
		Tier.UNCOMMON:  return 1.3
		Tier.RARE:      return 1.7
		Tier.EPIC:      return 2.5
		Tier.MYTHIC:    return 3.5
		Tier.LEGENDARY: return 5.0
		Tier.CELESTIAL: return 8.0
	return 1.0
