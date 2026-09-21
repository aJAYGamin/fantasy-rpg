extends TestSuite

## Item/Equipment pricing, ShopFactory inventories, and the GameManager buy/sell/inn
## flow. GameManager tests snapshot & restore party + gold per the testing policy.

func suite_name() -> String:
	return "Shop"

# --- Pricing ------------------------------------------------------------------

func test_item_price_and_sell() -> void:
	var potion := ItemFactory.create("Health Potion")
	assert_eq(potion.price, 30, "health potion buy price")
	assert_eq(potion.sell_price(), 15, "sells at half its price")
	assert_eq(ItemFactory.create("Amethyst Shard").sell_price(), 0, "key items aren't sellable")

func test_equipment_price_derived() -> void:
	var sword := EquipmentFactory.create("Worn Shortsword")
	assert_true(sword.price > 0, "equipment gets a derived price")
	assert_eq(sword.sell_price(), int(sword.price * 0.5), "sells at half its price")

# --- ShopFactory --------------------------------------------------------------

func test_shop_inventories() -> void:
	assert_true(ShopFactory.has_shop("apothecary"), "apothecary exists")
	assert_true("Health Potion" in ShopFactory.item_names("apothecary"), "apothecary stocks potions")
	assert_true(ShopFactory.item_names("armory").is_empty(), "armory stocks no items")
	assert_false(ShopFactory.equipment_names("armory").is_empty(), "armory stocks gear")
	assert_false(ShopFactory.has_shop("nope"), "unknown shop id")

# --- Buy / sell / inn (snapshot/restore globals) ------------------------------

func test_buy_item() -> void:
	var saved_party := GameManager.party
	var saved_gold := GameManager.gold
	var hero: Character = PartyFactory.create_default_party()[0]
	hero.inventory = Inventory.new()
	GameManager.party = [hero]
	GameManager.gold = 100

	assert_true(GameManager.buy_item("Health Potion"), "buy succeeds with enough gold")
	assert_eq(GameManager.gold, 70, "gold deducted by the price (30)")
	assert_true(hero.inventory.has_item("Health Potion"), "item added to inventory")

	GameManager.gold = 5
	assert_false(GameManager.buy_item("Health Potion"), "can't buy when short on gold")
	assert_eq(GameManager.gold, 5, "gold unchanged on a failed buy")

	GameManager.party = saved_party
	GameManager.gold = saved_gold

func test_sell_item() -> void:
	var saved_party := GameManager.party
	var saved_gold := GameManager.gold
	var hero: Character = PartyFactory.create_default_party()[0]
	hero.inventory = Inventory.new()
	var potion := ItemFactory.create("Health Potion", 2)
	hero.inventory.add_item(potion)
	GameManager.party = [hero]
	GameManager.gold = 0

	assert_eq(GameManager.sell_item(potion), 15, "selling yields half the price")
	assert_eq(GameManager.gold, 15, "gold credited")
	assert_eq(potion.quantity, 1, "one removed from the stack")

	var key := ItemFactory.create("Amethyst Shard")
	hero.inventory.add_item(key)
	assert_eq(GameManager.sell_item(key), 0, "key items can't be sold")

	GameManager.party = saved_party
	GameManager.gold = saved_gold

func test_inn_rest() -> void:
	var saved_party := GameManager.party
	var saved_gold := GameManager.gold
	var hero: Character = PartyFactory.create_default_party()[0]
	hero.current_hp = 1
	hero.current_mp = 0
	GameManager.party = [hero]
	var cost := GameManager.inn_rest_cost()
	assert_true(cost >= 20, "inn cost has a floor")

	GameManager.gold = cost
	assert_true(GameManager.inn_rest(), "rest succeeds when affordable")
	assert_eq(GameManager.gold, 0, "inn cost paid")
	assert_eq(hero.current_hp, hero.max_hp(), "HP fully restored")
	assert_eq(hero.current_mp, hero.max_mp(), "MP fully restored")

	GameManager.gold = 0
	assert_false(GameManager.inn_rest(), "can't rest when broke")

	GameManager.party = saved_party
	GameManager.gold = saved_gold

func test_inn_cost_story_tier() -> void:
	# The inn is a flat 20 gold and only rises at story milestones (inn_cost_tier),
	# never with party level.
	var saved_tier := GameManager.inn_cost_tier
	GameManager.inn_cost_tier = 0
	assert_eq(GameManager.inn_rest_cost(), 20, "inn starts at 20 gold")
	GameManager.inn_cost_tier = 1
	assert_eq(GameManager.inn_rest_cost(), 40, "story tier 1 raises the inn price")
	GameManager.inn_cost_tier = 3
	assert_eq(GameManager.inn_rest_cost(), 80, "higher story tiers raise it further")
	GameManager.inn_cost_tier = saved_tier
