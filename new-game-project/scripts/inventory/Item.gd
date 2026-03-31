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
	DODGE_BUFF   # Gives hero a chance to dodge attacks for one turn
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
