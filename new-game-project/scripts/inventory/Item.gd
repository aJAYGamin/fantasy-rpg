class_name Item
extends Resource

enum ItemType {
	HP_RESTORE,
	MP_RESTORE,
	REVIVAL,
	BUFF,
	ANTIDOTE,
	DAMAGE,
	DEBUFF,
	DODGE_BUFF,  # Gives hero a chance to dodge attacks for one turn
	# Appended after the action types so existing enum values (and saved item_type
	# ints) stay valid. These two carry no battle/heal effect:
	KEY,         # story/event item — never consumed, never used
	GENERAL,     # misc item (materials, trinkets) — not usable yet
}

# Pause-menu Items screen tabs. Derived from item_type via get_category().
enum ItemCategory {
	GENERAL,
	HEALING,
	BATTLE,
	KEY,
}

enum TargetType {
	SINGLE_ALLY,
	SINGLE_ENEMY,
	ALL_ALLIES,
	ALL_ENEMIES,
	ALL
}

@export var item_name: String = ""
@export var description: String = ""
@export var item_type: ItemType = ItemType.HP_RESTORE
@export var target_type: TargetType = TargetType.SINGLE_ALLY
@export var effect_value: int = 0
@export var effect_stat: String = ""

## Status names an ANTIDOTE-type item removes, e.g. ["scorched"] or every mutex
## status for a Panacea. Empty on every other item type. Driving cleansing off a
## list rather than the item's name means a new cure is a data change, and the
## menus can ask "would this help?" without knowing any item by name.
@export var cures: Array[String] = []
@export var quantity: int = 1
@export var price: int = 0   # shop buy price (gold); 0 = not sold/worthless

# Gold the player gets for selling one of these — half the buy price (rounded down).
func sell_price() -> int:
	return int(price * 0.5)

func use(target: Character) -> Dictionary:
	# NOTE: quantity is managed by BattleScene, not here
	var result = {"action": "item", "target": target, "value": 0}
	match item_type:
		ItemType.HP_RESTORE:
			var healed = target.heal(effect_value)
			result["action"] = "heal"
			result["value"] = healed
		ItemType.MP_RESTORE:
			var restored = target.restore_mp(effect_value)
			result["action"] = "mp_restore"
			result["value"] = restored
		ItemType.REVIVAL:
			if not target.is_alive():
				target.current_hp = int(target.max_hp() * (effect_value / 100.0))
				result["action"] = "revival"
				result["value"] = target.current_hp
		ItemType.BUFF:
			target.add_status("buff_%s_%d" % [effect_stat.to_lower(), effect_value])
			result["action"] = "buff"
			result["value"] = effect_value
		ItemType.ANTIDOTE:
			# Clears every status this item is defined to cure. `cures` is the
			# whole story: a Burn Salve lists one status, a Panacea lists them
			# all. Nothing here hard-codes a status name.
			var cleared: Array[String] = []
			for status in cures:
				if target.is_status(status):
					target.remove_status(status)
					cleared.append(status)
			result["action"] = "antidote"
			result["value"] = cleared.size()
			result["cured"] = cleared
		ItemType.DAMAGE:
			var dmg_result = target.take_damage(effect_value, ElementalSystem.Element.FIRE)
			result["action"] = "attack"
			result["value"] = dmg_result.get("damage", effect_value)
			result["multiplier"] = dmg_result.get("multiplier", 1.0)
		ItemType.DEBUFF:
			target.add_status(effect_stat.to_lower())
			result["action"] = "debuff"
			result["value"] = 0
		ItemType.DODGE_BUFF:
			# effect_value is dodge chance as percentage (e.g. 20 = 20%)
			target.set_meta("dodge_chance", effect_value / 100.0)
			result["action"] = "dodge_buff"
			result["value"] = effect_value
	return result

# Which Items-screen tab this item belongs to. Derived from item_type so callers
# never have to keep a separate category field in sync.
## True when `character` currently has at least one status this item cures —
## i.e. using it now would actually accomplish something. Menus gate their Use
## button on this instead of naming statuses themselves.
func can_cleanse(character) -> bool:
	if character == null or cures.is_empty():
		return false
	for status in cures:
		if character.is_status(status):
			return true
	return false

func get_category() -> ItemCategory:
	match item_type:
		ItemType.HP_RESTORE, ItemType.MP_RESTORE, ItemType.REVIVAL:
			return ItemCategory.HEALING
		# ANTIDOTE (status cleansing) is a BATTLE item, not a healing one:
		# statuses are battle-temp and cleared when a fight ends, so a cleanse
		# used in the overworld can never have anything to cure. It used to sit
		# in the Healing tab where its Use button was permanently greyed.
		ItemType.ANTIDOTE, ItemType.DAMAGE, ItemType.BUFF, ItemType.DEBUFF, ItemType.DODGE_BUFF:
			return ItemCategory.BATTLE
		ItemType.KEY:
			return ItemCategory.KEY
	return ItemCategory.GENERAL

# True for items the player can use from the overworld (pause-menu Items screen).
# Only healing-type consumables apply outside battle; battle items need combat,
# and key/general items aren't usable.
func is_field_usable() -> bool:
	return get_category() == ItemCategory.HEALING

func get_category_name() -> String:
	match get_category():
		ItemCategory.HEALING: return "Healing"
		ItemCategory.BATTLE:  return "Battle"
		ItemCategory.KEY:     return "Key"
	return "Item"
