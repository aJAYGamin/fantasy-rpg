extends TestSuite

## GameManager is an autoload singleton. Each test snapshots and restores the
## fields it touches so suites stay isolated and the editor session isn't polluted.

func suite_name() -> String:
	return "GameManager"

func test_gold_clamps_at_zero() -> void:
	var saved = GameManager.gold
	GameManager.gold = 100
	GameManager.gold = -50
	assert_eq(GameManager.gold, 0, "gold setter clamps negatives to 0")
	GameManager.gold = saved

func test_spend_gold() -> void:
	var saved = GameManager.gold
	GameManager.gold = 100
	assert_true(GameManager.spend_gold(30), "spend with enough gold succeeds")
	assert_eq(GameManager.gold, 70, "gold deducted")
	assert_false(GameManager.spend_gold(999), "spend without enough gold fails")
	assert_eq(GameManager.gold, 70, "gold unchanged on failed spend")
	GameManager.gold = saved

func test_party_max_size() -> void:
	var saved = GameManager.party.duplicate()
	GameManager.party = [] as Array[Character]
	for i in range(GameManager.MAX_PARTY_SIZE):
		assert_true(GameManager.add_to_party(Character.new()), "add member %d" % i)
	assert_false(GameManager.add_to_party(Character.new()), "cannot exceed MAX_PARTY_SIZE")
	assert_eq(GameManager.party.size(), GameManager.MAX_PARTY_SIZE, "party capped")
	GameManager.party = saved

func test_award_rewards_does_not_apply_exp() -> void:
	var saved_party = GameManager.party.duplicate()
	var saved_gold = GameManager.gold
	var hero = Character.new()
	hero.experience = 0
	hero.experience_to_next = 100
	hero.current_hp = hero.max_hp()
	GameManager.party = [hero] as Array[Character]
	GameManager.gold = 0
	GameManager.award_rewards({"gold": 25, "exp": 500})
	assert_eq(GameManager.gold, 25, "award_rewards adds gold")
	assert_eq(hero.experience, 0, "award_rewards does NOT apply exp (VictoryScreen owns that)")
	GameManager.party = saved_party
	GameManager.gold = saved_gold

func test_species_memory_recording() -> void:
	var saved = GameManager.species_memory.duplicate()
	GameManager.species_memory = {}
	assert_eq(GameManager.get_species_memory("Goblin"), 0, "unseen species -> 0")
	GameManager.record_battle_against("Goblin")
	GameManager.record_battle_against("Goblin")
	assert_eq(GameManager.get_species_memory("Goblin"), 2, "recorded twice -> 2")
	GameManager.species_memory = saved

func test_revive_party_sets_half_hp() -> void:
	var saved = GameManager.party.duplicate()
	var c = Character.new()
	c.base_hp = 100
	c.level = 1
	c.current_hp = 0  # dead
	GameManager.party = [c] as Array[Character]
	GameManager.revive_party()
	assert_eq(c.current_hp, int(c.max_hp() * 0.5), "dead member revived to 50% HP")
	GameManager.party = saved

func test_ensure_default_party_populates_when_empty() -> void:
	var saved = GameManager.party.duplicate()
	GameManager.party = [] as Array[Character]
	GameManager.ensure_default_party()
	assert_eq(GameManager.party.size(), 3, "default party has 3 heroes")
	GameManager.party = saved
