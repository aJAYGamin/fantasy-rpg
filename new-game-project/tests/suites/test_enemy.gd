extends TestSuite

func suite_name() -> String:
	return "Enemy"

func _make(tier := Rarity.Tier.COMMON, lv := 1) -> Enemy:
	var e = Enemy.new()
	e.species = "Test Slime"
	e.rarity = tier
	e.base_exp_reward = 20
	e.base_gold_reward = 10
	e.level = lv
	e.current_hp = e.max_hp()
	return e

func test_exp_reward_scales_with_rarity() -> void:
	var common = _make(Rarity.Tier.COMMON)
	var rare = _make(Rarity.Tier.RARE)
	assert_eq(common.get_exp_reward(), 20, "COMMON Lv1 exp = 20*1.0*1.0")
	assert_eq(rare.get_exp_reward(), int(20 * 1.7), "RARE Lv1 exp = 20*1.7")

func test_exp_reward_scales_with_level() -> void:
	var e = _make(Rarity.Tier.COMMON, 11)
	# 20 * 1.0 * (1 + 10*0.1) = 20 * 2.0 = 40
	assert_eq(e.get_exp_reward(), 40, "Lv11 COMMON exp = 40")

func test_gold_reward_scales() -> void:
	var common = _make(Rarity.Tier.COMMON)
	var unc = _make(Rarity.Tier.UNCOMMON)
	assert_eq(common.get_gold_reward(), 10, "COMMON Lv1 gold = 10")
	assert_eq(unc.get_gold_reward(), int(10 * 1.5), "UNCOMMON Lv1 gold = 15")

func test_memory_description_thresholds() -> void:
	var e = _make()
	e.memory_level = 0
	assert_eq(e.get_memory_description(), "", "no memory -> empty description")
	e.memory_level = 5
	assert_ne(e.get_memory_description(), "", "mid memory -> has description")
	e.memory_level = 20
	assert_ne(e.get_memory_description(), "", "high memory -> has description")

func test_damage_reduction_bonus_increases() -> void:
	var e = _make()
	e.memory_level = 0
	assert_near(e.get_damage_reduction_bonus(), 0.0, 0.001, "no memory -> 0 reduction")
	e.memory_level = 15
	assert_true(e.get_damage_reduction_bonus() > 0.0, "fully adapted -> >0 reduction")

func test_enemy_is_a_character() -> void:
	var e = _make()
	assert_true(e is Character, "Enemy extends Character")
