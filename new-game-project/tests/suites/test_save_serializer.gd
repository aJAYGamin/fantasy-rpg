extends TestSuite

## Tests for SaveSerializer + GameManager slot save system (Phase S1).
## Uses slot 2 for write tests so it stays out of the way of the user's
## real saves (slots 0 and 1); cleans up after itself either way.

const TEST_SLOT: int = 2

func suite_name() -> String:
	return "SaveSerializer / Slots"

func _make_skill() -> Skill:
	var s = Skill.new()
	s.skill_name = "Test Slash"
	s.description = "test"
	s.mp_cost = 8
	s.skill_type = Skill.SkillType.DAMAGE
	s.attack_type = Skill.AttackType.STRIKE
	s.status_type = Skill.StatusType.HEAL
	s.target_type = Skill.TargetType.SINGLE_ENEMY
	s.power = 1.4
	s.element = ElementalSystem.Element.FIRE
	s.status_to_apply = "burn"
	s.status_chance = 0.3
	s.resonance_gain_override = -1.0
	return s

func _make_character() -> Character:
	var c = Character.new()
	c.character_name = "Tester"
	c.character_class = "Mage"
	c.base_hp = 150
	c.base_mp = 80
	c.base_attack = 9
	c.base_defense = 6
	c.base_magic = 14
	c.base_arcane = 9
	c.base_speed = 11
	c.element = ElementalSystem.Element.WATER
	c.level = 3
	c.experience = 25
	c.experience_to_next = 225
	c.current_hp = 80
	c.current_mp = 30
	c.skills = [_make_skill()] as Array[Skill]
	c.add_status("poison")
	c.set_meta("ultimate_name", "Test Ult")
	c.set_meta("ultimate_desc", "test desc")
	return c

# --- Skill ---
func test_skill_roundtrip() -> void:
	var s = _make_skill()
	var back = SaveSerializer.deserialize_skill(SaveSerializer.serialize_skill(s))
	assert_eq(back.skill_name, s.skill_name, "name preserved")
	assert_eq(back.mp_cost, s.mp_cost, "mp_cost preserved")
	assert_eq(back.skill_type, s.skill_type, "skill_type preserved")
	assert_eq(back.attack_type, s.attack_type, "attack_type preserved")
	assert_eq(back.status_type, s.status_type, "status_type preserved")
	assert_eq(back.target_type, s.target_type, "target_type preserved")
	assert_near(back.power, s.power, 0.0001, "power preserved")
	assert_eq(back.element, s.element, "element preserved")
	assert_eq(back.status_to_apply, s.status_to_apply, "status_to_apply preserved")
	assert_near(back.status_chance, s.status_chance, 0.0001, "status_chance preserved")
	assert_near(back.resonance_gain_override, s.resonance_gain_override, 0.0001, "override preserved")

# --- Item / Inventory ---
func test_item_roundtrip() -> void:
	var i = Item.new()
	i.item_name = "Test Potion"
	i.description = "heals"
	i.item_type = Item.ItemType.HP_RESTORE
	i.target_type = Item.TargetType.SINGLE_ALLY
	i.effect_value = 50
	i.quantity = 3
	var back = SaveSerializer.deserialize_item(SaveSerializer.serialize_item(i))
	assert_eq(back.item_name, "Test Potion", "name preserved")
	assert_eq(back.effect_value, 50, "effect_value preserved")
	assert_eq(back.quantity, 3, "quantity preserved")

func test_inventory_roundtrip() -> void:
	var inv = Inventory.new()
	var i = Item.new()
	i.item_name = "P"
	i.quantity = 2
	inv.add_item(i)
	var back = SaveSerializer.deserialize_inventory(SaveSerializer.serialize_inventory(inv))
	assert_eq(back.items.size(), 1, "inventory size preserved")
	assert_eq(back.items[0].quantity, 2, "item quantity preserved")

# --- Character ---
func test_character_roundtrip() -> void:
	var c = _make_character()
	# Give the test character a secondary element to verify dual-type round-trip.
	c.secondary_element = ElementalSystem.Element.DRAGON
	c.resonance_meter = 47.5
	var back = SaveSerializer.deserialize_character(SaveSerializer.serialize_character(c))
	assert_eq(back.secondary_element, c.secondary_element, "secondary_element preserved")
	assert_eq(back.base_arcane, 9, "base_arcane preserved")
	assert_near(back.resonance_meter, 47.5, 0.01, "resonance_meter preserved")
	assert_eq(back.character_name, c.character_name, "name preserved")
	assert_eq(back.level, c.level, "level preserved")
	assert_eq(back.experience, c.experience, "exp preserved")
	assert_eq(back.current_hp, c.current_hp, "current_hp preserved")
	assert_eq(back.current_mp, c.current_mp, "current_mp preserved")
	assert_eq(back.base_attack, c.base_attack, "base_attack preserved")
	assert_eq(back.element, c.element, "element preserved")
	assert_true(back.is_status("poison"), "status effect preserved")
	assert_eq(back.skills.size(), 1, "skills preserved")
	assert_eq(back.skills[0].skill_name, "Test Slash", "skill name preserved")
	assert_eq(back.get_meta("ultimate_name", ""), "Test Ult", "ultimate_name meta preserved")
	assert_eq(back.get_meta("ultimate_desc", ""), "test desc", "ultimate_desc meta preserved")

func test_party_roundtrip() -> void:
	var party = [_make_character(), _make_character()]
	var back = SaveSerializer.deserialize_party(SaveSerializer.serialize_party(party))
	assert_eq(back.size(), 2, "party size preserved")
	assert_eq(back[0].character_name, "Tester", "first hero preserved")

# --- Slot save/load ---
func _snapshot_gm() -> Dictionary:
	return {
		"party": GameManager.party.duplicate(),
		"gold": GameManager.gold,
		"active_slot": GameManager.active_slot,
		"species": GameManager.species_memory.duplicate(),
		"path": GameManager.save_overworld_scene_path,
		"pos": GameManager.save_overworld_position,
	}

func _restore_gm(snap: Dictionary) -> void:
	GameManager.party = snap["party"]
	GameManager.gold = snap["gold"]
	GameManager.active_slot = snap["active_slot"]
	GameManager.species_memory = snap["species"]
	GameManager.save_overworld_scene_path = snap["path"]
	GameManager.save_overworld_position = snap["pos"]

func test_slot_save_load_roundtrip() -> void:
	var snap = _snapshot_gm()
	if GameManager.slot_exists(TEST_SLOT):
		GameManager.delete_slot(TEST_SLOT)

	GameManager.party = [_make_character()] as Array[Character]
	GameManager.gold = 1234
	GameManager.species_memory = {"Slime": 5}
	GameManager.save_overworld_scene_path = "res://scenes/OverworldScene.tscn"
	GameManager.save_overworld_position = Vector2(100, 200)

	var ok = GameManager.save_to_slot(TEST_SLOT)
	assert_true(ok, "save_to_slot succeeded")
	assert_true(GameManager.slot_exists(TEST_SLOT), "slot file exists")
	assert_eq(GameManager.active_slot, TEST_SLOT, "active_slot updated")

	# Corrupt the live state so load has something real to restore
	GameManager.gold = 0
	GameManager.party = [] as Array[Character]
	GameManager.species_memory = {}
	GameManager.save_overworld_position = Vector2.ZERO

	var loaded = GameManager.load_from_slot(TEST_SLOT)
	assert_true(loaded, "load_from_slot succeeded")
	assert_eq(GameManager.gold, 1234, "gold restored")
	assert_eq(GameManager.party.size(), 1, "party restored")
	assert_eq(GameManager.party[0].character_name, "Tester", "hero name restored")
	assert_eq(GameManager.party[0].level, 3, "hero level restored")
	assert_eq(GameManager.party[0].current_hp, 80, "hero HP restored")
	assert_eq(GameManager.species_memory.get("Slime"), 5, "species memory restored")
	assert_near(GameManager.save_overworld_position.x, 100.0, 0.001, "position x restored")
	assert_near(GameManager.save_overworld_position.y, 200.0, 0.001, "position y restored")

	GameManager.delete_slot(TEST_SLOT)
	assert_false(GameManager.slot_exists(TEST_SLOT), "slot deleted")
	_restore_gm(snap)

func test_slot_metadata() -> void:
	var snap = _snapshot_gm()
	if GameManager.slot_exists(TEST_SLOT):
		GameManager.delete_slot(TEST_SLOT)

	GameManager.party = [_make_character()] as Array[Character]
	GameManager.save_to_slot(TEST_SLOT)
	var meta = GameManager.get_slot_metadata(TEST_SLOT)
	assert_true(meta.has("max_party_level"), "metadata has max_party_level")
	assert_eq(meta.get("max_party_level"), 3, "max_party_level matches hero level")
	assert_true(meta.has("party_size"), "metadata has party_size")
	assert_eq(meta.get("party_size"), 1, "party_size matches")
	assert_true(meta.has("timestamp"), "metadata has timestamp")

	GameManager.delete_slot(TEST_SLOT)
	_restore_gm(snap)

func test_invalid_slot_indices() -> void:
	assert_false(GameManager.slot_exists(-1), "slot -1 doesn't exist")
	assert_false(GameManager.slot_exists(GameManager.SAVE_SLOT_COUNT), "out-of-range slot doesn't exist")
	assert_false(GameManager.save_to_slot(-1), "cannot save to -1")
	assert_false(GameManager.save_to_slot(99), "cannot save to 99")
	assert_false(GameManager.load_from_slot(-1), "cannot load from -1")
	assert_false(GameManager.load_from_slot(99), "cannot load from 99")
	assert_eq(GameManager.get_slot_metadata(-1).size(), 0, "metadata empty for invalid slot")

func test_metadata_includes_heroes() -> void:
	var snap = _snapshot_gm()
	if GameManager.slot_exists(TEST_SLOT):
		GameManager.delete_slot(TEST_SLOT)
	var h1 = _make_character()
	h1.character_name = "HeroOne"
	h1.character_class = "Mage"
	h1.level = 2
	var h2 = _make_character()
	h2.character_name = "HeroTwo"
	h2.character_class = "Warrior"
	h2.level = 5
	GameManager.party = [h1, h2] as Array[Character]
	GameManager.save_to_slot(TEST_SLOT)
	var meta = GameManager.get_slot_metadata(TEST_SLOT)
	assert_true(meta.has("heroes"), "metadata has heroes list")
	var heroes: Array = meta.get("heroes", [])
	assert_eq(heroes.size(), 2, "two heroes in metadata")
	assert_eq(heroes[0].get("name", ""), "HeroOne", "first hero name preserved")
	assert_eq(heroes[0].get("class", ""), "Mage", "first hero class preserved")
	assert_eq(heroes[1].get("level", 0), 5, "second hero level preserved")
	GameManager.delete_slot(TEST_SLOT)
	_restore_gm(snap)

func test_copy_slot() -> void:
	var snap = _snapshot_gm()
	# Use slot 2 as source, find an empty destination
	var src_slot = TEST_SLOT
	var dst_slot: int = -1
	for s in range(GameManager.SAVE_SLOT_COUNT):
		if s != src_slot and not GameManager.slot_exists(s):
			dst_slot = s
			break
	if dst_slot < 0:
		# All other slots occupied; skip cleanly to avoid clobbering user saves
		_restore_gm(snap)
		return

	if GameManager.slot_exists(src_slot):
		GameManager.delete_slot(src_slot)

	GameManager.party = [_make_character()] as Array[Character]
	GameManager.gold = 4242
	GameManager.save_to_slot(src_slot)

	var ok = GameManager.copy_slot(src_slot, dst_slot)
	assert_true(ok, "copy_slot succeeded")
	assert_true(GameManager.slot_exists(dst_slot), "destination slot now exists")

	# Mutate src to verify the destination was a real copy, not a reference
	GameManager.gold = 1
	GameManager.save_to_slot(src_slot)
	GameManager.load_from_slot(dst_slot)
	assert_eq(GameManager.gold, 4242, "copy preserved original gold")

	GameManager.delete_slot(src_slot)
	GameManager.delete_slot(dst_slot)
	_restore_gm(snap)

func test_copy_slot_rejects_invalid() -> void:
	assert_false(GameManager.copy_slot(0, 0), "cannot copy slot to itself")
	assert_false(GameManager.copy_slot(-1, 1), "cannot copy from invalid slot")
	assert_false(GameManager.copy_slot(0, 99), "cannot copy to invalid slot")

func test_slots_are_isolated() -> void:
	var snap = _snapshot_gm()
	if GameManager.slot_exists(TEST_SLOT):
		GameManager.delete_slot(TEST_SLOT)
	# Slot 1 is unused if user hasn't saved there; skip if it exists to avoid clobbering
	var other_slot: int = 1
	var skip_other := GameManager.slot_exists(other_slot)

	GameManager.party = [_make_character()] as Array[Character]
	GameManager.gold = 7777
	GameManager.save_to_slot(TEST_SLOT)

	if not skip_other:
		GameManager.gold = 1111
		GameManager.save_to_slot(other_slot)
		# Now reload TEST_SLOT and verify its gold (7777) is intact
		GameManager.load_from_slot(TEST_SLOT)
		assert_eq(GameManager.gold, 7777, "TEST_SLOT untouched by other_slot save")
		GameManager.delete_slot(other_slot)

	GameManager.delete_slot(TEST_SLOT)
	_restore_gm(snap)
