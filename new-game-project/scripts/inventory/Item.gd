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
@export var quantity: int = 1

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
			target.remove_status("poison")
			target.remove_status("burn")
			result["action"] = "antidote"
			result["value"] = 0
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
func get_category() -> ItemCategory:
	match item_type:
		ItemType.HP_RESTORE, ItemType.MP_RESTORE, ItemType.REVIVAL, ItemType.ANTIDOTE:
			return ItemCategory.HEALING
		ItemType.DAMAGE, ItemType.BUFF, ItemType.DEBUFF, ItemType.DODGE_BUFF:
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
