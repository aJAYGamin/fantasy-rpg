extends TestSuite

## Tests for ItemsScreen pure helpers + Inventory category filtering (Phase P2).
## Exercises categorize(), can_field_use(), can_target_hero(), effect_text() and
## the Inventory.get_battle_items()/get_items_by_category() filters — all without
## a scene tree.

func suite_name() -> String:
	return "ItemsScreen"

func _item(name: String, type: int, value: int, qty: int, target: int = Item.TargetType.SINGLE_ALLY) -> Item:
	var it := Item.new()
	it.item_name = name
	it.item_type = type
	it.effect_value = value
	it.quantity = qty
	it.target_type = target
	return it

func _hero(base_hp: int = 100, base_mp: int = 50) -> Character:
	var c := Character.new()
	c.character_name = "Tester"
	c.base_hp = base_hp
	c.base_mp = base_mp
	c.current_hp = c.max_hp()
	c.current_mp = c.max_mp()
	return c

func _full_inventory() -> Inventory:
	var inv := Inventory.new()
	inv.add_item(_item("Potion", Item.ItemType.HP_RESTORE, 50, 3))
	inv.add_item(_item("Ether", Item.ItemType.MP_RESTORE, 30, 2))
	inv.add_item(_item("Fire Bomb", Item.ItemType.DAMAGE, 40, 2, Item.TargetType.ALL_ENEMIES))
	inv.add_item(_item("Amethyst Shard", Item.ItemType.KEY, 0, 1))
	inv.add_item(_item("Monster Fang", Item.ItemType.GENERAL, 0, 4))
	return inv

# --- categorize ---------------------------------------------------------------

func test_categorize_buckets() -> void:
	var buckets := ItemsScreen.categorize(_full_inventory())
	assert_eq(buckets[Item.ItemCategory.HEALING].size(), 2, "healing bucket has potion + ether")
	assert_eq(buckets[Item.ItemCategory.BATTLE].size(), 1, "battle bucket has fire bomb")
	assert_eq(buckets[Item.ItemCategory.KEY].size(), 1, "key bucket has shard")
	assert_eq(buckets[Item.ItemCategory.GENERAL].size(), 1, "general bucket has fang")

func test_categorize_null_inventory() -> void:
	var buckets := ItemsScreen.categorize(null)
	assert_eq(buckets[Item.ItemCategory.HEALING].size(), 0, "null inventory yields empty healing bucket")
	assert_eq(buckets.size(), 4, "all four category keys present")

func test_categorize_skips_zero_quantity() -> void:
	var inv := Inventory.new()
	var depleted := _item("Used Up", Item.ItemType.HP_RESTORE, 50, 0)
	inv.items.append(depleted)
	var buckets := ItemsScreen.categorize(inv)
	assert_eq(buckets[Item.ItemCategory.HEALING].size(), 0, "quantity-0 items excluded")

# --- can_field_use ------------------------------------------------------------

func test_field_use_potion_when_hurt() -> void:
	var hero := _hero()
	hero.current_hp = 10
	var potion := _item("Potion", Item.ItemType.HP_RESTORE, 50, 1)
	assert_true(ItemsScreen.can_field_use(potion, [hero]), "HP potion usable when ally hurt")

func test_field_use_potion_blocked_at_full_hp() -> void:
	var hero := _hero()  # full HP from _init
	var potion := _item("Potion", Item.ItemType.HP_RESTORE, 50, 1)
	assert_false(ItemsScreen.can_field_use(potion, [hero]), "HP potion blocked when all at full HP")

func test_field_use_blocked_at_zero_quantity() -> void:
	var hero := _hero()
	hero.current_hp = 10
	var potion := _item("Potion", Item.ItemType.HP_RESTORE, 50, 0)
	assert_false(ItemsScreen.can_field_use(potion, [hero]), "zero-quantity item not usable")

func test_field_use_battle_item_never_field_usable() -> void:
	var hero := _hero()
	var bomb := _item("Fire Bomb", Item.ItemType.DAMAGE, 40, 3, Item.TargetType.ALL_ENEMIES)
	assert_false(ItemsScreen.can_field_use(bomb, [hero]), "battle item never field-usable")

func test_field_use_revival_needs_ko() -> void:
	var alive := _hero()
	var revive := _item("Phoenix Down", Item.ItemType.REVIVAL, 50, 1)
	assert_false(ItemsScreen.can_field_use(revive, [alive]), "revive blocked with no KO'd ally")
	var ko := _hero()
	ko.current_hp = 0
	assert_true(ItemsScreen.can_field_use(revive, [alive, ko]), "revive usable when an ally is KO'd")

func test_cleansers_are_never_field_usable() -> void:
	# Statuses are battle-temp and cleared when a fight ends, so a cleanse used
	# in the overworld could never have anything to cure. Cleansers are BATTLE
	# items; they used to sit in the Healing tab with a permanently greyed Use
	# button, which just looked broken.
	var hero := _hero()
	var antidote := _item("Antidote", Item.ItemType.ANTIDOTE, 0, 1)
	antidote.cures = [StatusSystem.POISON]
	assert_false(ItemsScreen.can_field_use(antidote, [hero]), "blocked with no status")
	hero.add_status("poison")
	assert_false(ItemsScreen.can_field_use(antidote, [hero]),
		"and still blocked WITH one — cleansing belongs in battle")
	assert_eq(antidote.get_category(), Item.ItemCategory.BATTLE, "it lives in the Battle tab")

# --- can_target_hero ----------------------------------------------------------

func test_target_mp_restore() -> void:
	var hero := _hero()
	var ether := _item("Ether", Item.ItemType.MP_RESTORE, 30, 1)
	assert_false(ItemsScreen.can_target_hero(ether, hero), "MP item invalid at full MP")
	hero.current_mp = 0
	assert_true(ItemsScreen.can_target_hero(ether, hero), "MP item valid when MP missing")

func test_target_revival_rejects_living() -> void:
	var hero := _hero()
	var revive := _item("Phoenix Down", Item.ItemType.REVIVAL, 50, 1)
	assert_false(ItemsScreen.can_target_hero(revive, hero), "cannot revive a living ally")

# --- effect_text --------------------------------------------------------------

func test_effect_text_variants() -> void:
	assert_eq(ItemsScreen.effect_text(_item("P", Item.ItemType.HP_RESTORE, 50, 1)), "+50 HP", "HP effect text")
	assert_eq(ItemsScreen.effect_text(_item("E", Item.ItemType.MP_RESTORE, 30, 1)), "+30 MP", "MP effect text")
	assert_eq(ItemsScreen.effect_text(_item("K", Item.ItemType.KEY, 0, 1)), "", "key items show no effect text")

# --- Inventory filters --------------------------------------------------------

func test_battle_items_exclude_key_and_general() -> void:
	var items := _full_inventory().get_battle_items()
	for it in items:
		assert_ne(it.get_category(), Item.ItemCategory.KEY, "battle list excludes key items")
		assert_ne(it.get_category(), Item.ItemCategory.GENERAL, "battle list excludes general items")

func test_get_items_by_category_healing() -> void:
	var healing := _full_inventory().get_items_by_category(Item.ItemCategory.HEALING)
	assert_eq(healing.size(), 2, "inventory healing filter matches categorize")

# --- Field-use flow (the UI rebuild is deferred to avoid wedging the GUI; the
# data effects below must stay immediate). ------------------------------------
func test_apply_field_item_decrements_quantity() -> void:
	var screen := ItemsScreen.new()
	var inv := Inventory.new()
	var potion := _item("Potion", Item.ItemType.HP_RESTORE, 50, 2)
	inv.items.append(potion)
	var hero := _hero()
	hero.current_hp = 1
	screen._inventory = inv
	screen._party = [hero]
	screen._apply_field_item(potion, [hero])
	assert_eq(potion.quantity, 1, "use decrements the item quantity immediately")
	assert_true(inv.items.has(potion), "item stays in inventory while quantity remains")
	assert_true(hero.current_hp > 1, "the heal was applied to the target")
	screen.free()

func test_apply_field_item_erases_at_zero() -> void:
	var screen := ItemsScreen.new()
	var inv := Inventory.new()
	var potion := _item("Potion", Item.ItemType.HP_RESTORE, 50, 1)
	inv.items.append(potion)
	var hero := _hero()
	hero.current_hp = 1
	screen._inventory = inv
	screen._party = [hero]
	screen._apply_field_item(potion, [hero])
	assert_eq(potion.quantity, 0, "last use zeroes the quantity")
	assert_false(inv.items.has(potion), "item removed from inventory at zero quantity")
	screen.free()

# --- Controller reachability of the "?" description toggles --------------------
# The "?" used to be marked no-focus so vertical navigation landed on Use. But
# three of the four tabs hold items with no Use button at all, so their rows had
# nothing a controller could reach and the description was mouse-only.

func _open_items() -> ItemsScreen:
	var screen := ItemsScreen.new()
	GameManager.add_child(screen)
	screen.setup(GameManager.party)
	return screen

func _close_items(screen: ItemsScreen) -> void:
	GameManager.unregister_focus_scope(screen)
	screen.queue_free()

func _focusable_question_marks(n: Node, out: Array) -> void:
	if n is Button and (n as Button).text == "?" and (n as Button).focus_mode != Control.FOCUS_NONE:
		out.append(n)
	for c in n.get_children():
		_focusable_question_marks(c, out)

func _count_question_marks(n: Node) -> int:
	var found: Array = []
	_focusable_question_marks(n, found)
	return found.size()

func test_question_marks_are_controller_reachable_in_every_tab() -> void:
	GameManager.ensure_default_party()
	var screen := _open_items()
	GameManager.set_controller_mode_for_test(true)
	var checked := 0
	for tab in ItemsScreen.TAB_DEFS.size():
		screen.call("_select_tab", tab)
		GameManager.update_focus_guard_for_test()
		var host: Control = screen.get("_content_host")
		# Tabs with no items have nothing to reach, which is fine.
		var items: Array = ItemsScreen.categorize(screen.get("_inventory"))[ItemsScreen.TAB_DEFS[tab][1]]
		if items.is_empty():
			continue
		checked += 1
		assert_eq(_count_question_marks(host), items.size(),
			"tab %d: every item's description toggle is reachable" % tab)
	assert_true(checked >= 2, "checked at least two populated tabs (checked %d)" % checked)
	GameManager.set_controller_mode_for_test(false)
	_close_items(screen)

func test_a_row_without_a_use_button_is_still_reachable() -> void:
	# The regression that made three tabs dead ends on a controller.
	GameManager.ensure_default_party()
	var screen := _open_items()
	GameManager.set_controller_mode_for_test(true)
	for tab in ItemsScreen.TAB_DEFS.size():
		screen.call("_select_tab", tab)
		GameManager.update_focus_guard_for_test()
		var host: Control = screen.get("_content_host")
		var items: Array = ItemsScreen.categorize(screen.get("_inventory"))[ItemsScreen.TAB_DEFS[tab][1]]
		if items.is_empty():
			continue
		assert_true(_count_question_marks(host) > 0,
			"tab %d has at least one control a controller can land on" % tab)
	GameManager.set_controller_mode_for_test(false)
	_close_items(screen)
