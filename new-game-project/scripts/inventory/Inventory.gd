class_name Inventory
extends Resource

var items: Array[Item] = []

func add_item(item: Item):
	# Stack if same item exists
	for existing in items:
		if existing.item_name == item.item_name:
			existing.quantity += item.quantity
			return
	items.append(item)

func remove_item(item: Item, amount: int = 1):
	item.quantity -= amount
	if item.quantity <= 0:
		items.erase(item)

func get_battle_items() -> Array[Item]:
	# Return all items that can be used in battle
	var battle_items: Array[Item] = []
	for item in items:
		if item.quantity > 0:
			battle_items.append(item)
	return battle_items

func get_items_by_type(type: Item.ItemType) -> Array[Item]:
	var result: Array[Item] = []
	for item in items:
		if item.item_type == type and item.quantity > 0:
			result.append(item)
	return result

func has_item(item_name: String) -> bool:
	for item in items:
		if item.item_name == item_name and item.quantity > 0:
			return true
	return false

func get_item(item_name: String) -> Item:
	for item in items:
		if item.item_name == item_name:
			return item
	return null

func get_weapon_attack() -> int:
	return 0  # Will return equipped weapon bonus when equipment system is built

func get_armor_defense() -> int:
	return 0  # Will return equipped armor bonus when equipment system is built
