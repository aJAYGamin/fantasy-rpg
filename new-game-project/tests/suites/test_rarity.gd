extends TestSuite

func suite_name() -> String:
	return "Rarity"

func test_exp_multiplier_increasing() -> void:
	var T = Rarity.Tier
	assert_near(Rarity.get_exp_multiplier(T.COMMON), 1.0, 0.01, "COMMON exp x1.0")
	assert_near(Rarity.get_exp_multiplier(T.RARE), 1.7, 0.01, "RARE exp x1.7")
	assert_true(
		Rarity.get_exp_multiplier(T.LEGENDARY) > Rarity.get_exp_multiplier(T.EPIC),
		"LEGENDARY exp > EPIC exp"
	)

func test_loot_multiplier_increasing() -> void:
	var T = Rarity.Tier
	assert_near(Rarity.get_loot_multiplier(T.COMMON), 1.0, 0.01, "COMMON loot x1.0")
	assert_near(Rarity.get_loot_multiplier(T.UNCOMMON), 1.5, 0.01, "UNCOMMON loot x1.5")
	assert_true(
		Rarity.get_loot_multiplier(T.CELESTIAL) > Rarity.get_loot_multiplier(T.LEGENDARY),
		"CELESTIAL loot > LEGENDARY loot"
	)

func test_name_and_color() -> void:
	var T = Rarity.Tier
	assert_ne(Rarity.tier_name(T.COMMON), "", "COMMON has a name")
	assert_ne(Rarity.tier_name(T.LEGENDARY), "", "LEGENDARY has a name")
	# Colors should differ across tiers
	assert_ne(Rarity.get_color(T.COMMON), Rarity.get_color(T.LEGENDARY), "tier colors differ")
