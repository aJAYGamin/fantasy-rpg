class_name Inventory
extends Resource

const ACCESSORY_SLOTS := 3

var items: Array[Item] = []

# --- Equipment ---
# Unequipped gear pool. By convention the party shares party[0].inventory.equipment
# (same pattern as items). Equipped pieces live in the slots below, per hero.
var equipment: Array[Equipment] = []
var equipped_weapon: Equipment = null
var equipped_armor: Equipment = null
var equipped_accessories: Array[Equipment] = [null, null, null]

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
	# Items usable in battle = everything except Key and General (those carry no
	# combat/heal effect). Healing consumables are usable in battle too.
	var battle_items: Array[Item] = []
	for item in items:
		if item.quantity > 0 and item.get_category() != Item.ItemCategory.KEY \
				and item.get_category() != Item.ItemCategory.GENERAL:
			battle_items.append(item)
	return battle_items

func get_items_by_type(type: Item.ItemType) -> Array[Item]:
	var result: Array[Item] = []
	for item in items:
		if item.item_type == type and item.quantity > 0:
			result.append(item)
	return result

func get_items_by_category(category: Item.ItemCategory) -> Array[Item]:
	var result: Array[Item] = []
	for item in items:
		if item.get_category() == category and item.quantity > 0:
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

# --- Equipment: bonuses & slot access ----------------------------------------

# Summed bonus for `stat` (attack/defense/magic/arcane/speed/max_hp/max_mp)
# across every equipped piece. Character stat getters call this.
func equipment_bonus(stat: String) -> int:
	var total := 0
	for eq in equipped_list():
		total += eq.bonus(stat)
	return total

func equipped_list() -> Array[Equipment]:
	var out: Array[Equipment] = []
	if equipped_weapon != null:
		out.append(equipped_weapon)
	if equipped_armor != null:
		out.append(equipped_armor)
	for a in equipped_accessories:
		if a != null:
			out.append(a)
	return out

func get_equipped(slot: Equipment.Slot, accessory_index: int = 0) -> Equipment:
	match slot:
		Equipment.Slot.WEAPON:
			return equipped_weapon
		Equipment.Slot.ARMOR:
			return equipped_armor
		Equipment.Slot.ACCESSORY:
			if accessory_index >= 0 and accessory_index < equipped_accessories.size():
				return equipped_accessories[accessory_index]
	return null

# Sets a slot to `eq` (null clears it) and returns the piece previously there.
# Does NOT touch the unequipped pool — callers manage that via equip_from_pool /
# unequip_to_pool below.
func set_equipped(slot: Equipment.Slot, eq: Equipment, accessory_index: int = 0) -> Equipment:
	var prev: Equipment = null
	match slot:
		Equipment.Slot.WEAPON:
			prev = equipped_weapon
			equipped_weapon = eq
		Equipment.Slot.ARMOR:
			prev = equipped_armor
			equipped_armor = eq
		Equipment.Slot.ACCESSORY:
			if accessory_index >= 0 and accessory_index < equipped_accessories.size():
				prev = equipped_accessories[accessory_index]
				equipped_accessories[accessory_index] = eq
	return prev

func add_equipment(eq: Equipment) -> void:
	equipment.append(eq)

func remove_equipment(eq: Equipment) -> void:
	equipment.erase(eq)

func first_empty_accessory() -> int:
	for i in range(equipped_accessories.size()):
		if equipped_accessories[i] == null:
			return i
	return -1

# --- Equipment: equip / unequip orchestration ---------------------------------
# Static so they can move a piece between a shared pool inventory and a hero's
# own equipped slots (the two may be the same Inventory for party[0]). Both clamp
# the hero's vitals afterward (max HP/MP can change with gear).

# Equips `eq` (must currently live in `pool.equipment`) onto `hero`, honoring
# restrictions. Any displaced piece returns to the pool. Returns false if `eq`
# can't be equipped by this hero.
static func equip_from_pool(hero: Character, pool: Inventory, eq: Equipment, accessory_index: int = -1) -> bool:
	if not eq.can_equip(hero):
		return false
	var inv := hero.inventory
	var idx := accessory_index
	if eq.slot == Equipment.Slot.ACCESSORY and idx < 0:
		idx = inv.first_empty_accessory()
		if idx < 0:
			idx = 0  # all accessory slots full — replace the first
	pool.remove_equipment(eq)
	var displaced := inv.set_equipped(eq.slot, eq, idx)
	if displaced != null:
		pool.add_equipment(displaced)
	hero.clamp_vitals()
	return true

# Removes the piece in `slot` from `hero` and returns it to `pool`. Returns the
# removed piece (or null if the slot was empty).
static func unequip_to_pool(hero: Character, pool: Inventory, slot: Equipment.Slot, accessory_index: int = 0) -> Equipment:
	var removed := hero.inventory.set_equipped(slot, null, accessory_index)
	if removed != null:
		pool.add_equipment(removed)
	hero.clamp_vitals()
	return removed
