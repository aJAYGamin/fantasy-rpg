class_name Item
extends Resource

enum ItemType {
	CONSUMABLE,
	WEAPON,
	ARMOR,
	ACCESSORY,
	KEY_ITEM
}

@export var item_name: String = "Item"
@export var description: String = ""
@export var item_type: ItemType = ItemType.CONSUMABLE
@export var icon: Texture2D
@export var value: int = 0

# Equipment stats
@export var equipment_slot: String = ""
@export var attack_bonus: int = 0
@export var defense_bonus: int = 0
@export var magic_bonus: int = 0
@export var speed_bonus: int = 0

# Consumable effect
@export var heal_hp: int = 0
@export var heal_mp: int = 0
@export var status_to_cure: String = ""

func use(target) -> Dictionary:
	var result = {"action": "item", "item": self, "target": target}
	if heal_hp > 0:
		var healed = target.heal(heal_hp)
		result["hp_restored"] = healed
	if heal_mp > 0:
		var restored = target.restore_mp(heal_mp)
		result["mp_restored"] = restored
	if status_to_cure != "":
		target.remove_status(status_to_cure)
		result["cured"] = status_to_cure
	return result

func can_use_in_battle() -> bool:
	return item_type == ItemType.CONSUMABLE

func get_stat_description() -> String:
	var parts = []
	if attack_bonus != 0: parts.append("ATK +%d" % attack_bonus)
	if defense_bonus != 0: parts.append("DEF +%d" % defense_bonus)
	if magic_bonus != 0: parts.append("MAG +%d" % magic_bonus)
	if heal_hp != 0: parts.append("Heal %d HP" % heal_hp)
	if heal_mp != 0: parts.append("Restore %d MP" % heal_mp)
	return ", ".join(parts) if parts else description
