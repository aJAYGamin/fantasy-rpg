class_name Inventory
extends Resource

## Signals
signal item_added(item: Item)
signal item_removed(item: Item)
signal equipment_changed(slot: String)

const MAX_ITEMS = 20  # Max items in bag

# Bag: holds consumables and misc items
var items: Array[Dictionary] = []  # [{item: Item, quantity: int}]

# Equipment slots
var equipped: Dictionary = {
	"weapon": null,
	"armor": null,
	"accessory": null
}

# --- Item Management ---
func add_item(item: Item, quantity: int = 1) -> bool:
	# Check if item already exists in inventory
	for entry in items:
		if entry["item"].item_name == item.item_name:
			entry["quantity"] += quantity
			emit_signal("item_added", item)
			return true

	# Add new entry
	if items.size() < MAX_ITEMS:
		items.append({"item": item, "quantity": quantity})
		emit_signal("item_added", item)
		return true

	print("Inventory is full!")
	return false

func remove_item(item: Item, quantity: int = 1) -> bool:
	for i in range(items.size()):
		if items[i]["item"].item_name == item.item_name:
			items[i]["quantity"] -= quantity
			if items[i]["quantity"] <= 0:
				items.remove_at(i)
			emit_signal("item_removed", item)
			return true
	return false

func has_item(item_name: String) -> bool:
	for entry in items:
		if entry["item"].item_name == item_name:
			return entry["quantity"] > 0
	return false

func get_quantity(item_name: String) -> int:
	for entry in items:
		if entry["item"].item_name == item_name:
			return entry["quantity"]
	return 0

func get_consumables() -> Array[Dictionary]:
	return items.filter(func(e): return e["item"].item_type == Item.ItemType.CONSUMABLE)

func get_equipment_items() -> Array[Dictionary]:
	return items.filter(func(e): return e["item"].item_type != Item.ItemType.CONSUMABLE)

# --- Equipment ---
func equip(item: Item) -> Item:
	var slot = item.equipment_slot
	if slot == "":
		return null

	var previously_equipped = equipped[slot]
	equipped[slot] = item
	emit_signal("equipment_changed", slot)
	return previously_equipped  # Return what was unequipped

func unequip(slot: String) -> Item:
	var item = equipped[slot]
	equipped[slot] = null
	emit_signal("equipment_changed", slot)
	return item

func get_weapon_attack() -> int:
	if equipped["weapon"] != null:
		return equipped["weapon"].attack_bonus
	return 0

func get_armor_defense() -> int:
	if equipped["armor"] != null:
		return equipped["armor"].defense_bonus
	return 0

func get_accessory() -> Item:
	return equipped["accessory"]

func get_summary() -> String:
	var text = "--- Inventory (%d/%d) ---\n" % [items.size(), MAX_ITEMS]
	for entry in items:
		text += "  %s x%d\n" % [entry["item"].item_name, entry["quantity"]]
	text += "\n--- Equipment ---\n"
	for slot in equipped:
		var e = equipped[slot]
		text += "  %s: %s\n" % [slot.capitalize(), e.item_name if e else "None"]
	return text
