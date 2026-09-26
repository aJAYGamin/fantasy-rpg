extends TestSuite

## StatusChipFactory builds the status/buff/debuff chips under every hero panel
## and enemy card. The panels size themselves to their content, so anything
## that makes a chip row momentarily wider makes the whole panel jump.

func suite_name() -> String:
	return "StatusChips"

func _hero() -> Character:
	var c := Character.new()
	c.character_name = "ChipProbe"
	c.base_hp = 100
	c.level = 1
	c.current_hp = c.max_hp()
	return c

func test_rebuilding_twice_in_one_frame_leaves_one_set_of_chips() -> void:
	# An area attack emits one action_performed per target, all in the same
	# frame, and each one refreshes every panel. queue_free() alone kept the old
	# chips as children until the end of the frame, so a hero with two chips
	# briefly had eight and the panel widened for a frame on every enemy attack.
	var hero := _hero()
	hero.apply_debuff("attack")
	hero.apply_buff("defense")
	var row := HBoxContainer.new()
	StatusChipFactory.populate_row(row, hero)
	StatusChipFactory.populate_row(row, hero)
	StatusChipFactory.populate_row(row, hero)
	assert_eq(row.get_child_count(), 2, "only the current chips are children")
	row.free()

## Chips only know their width once they are in the tree (their fonts come from
## the theme cache), so these tests measure a row that is actually in it. It
## hangs off GameManager because the root is still busy setting up its children
## while the runner's _ready executes, and add_child there silently fails.
func _row_in_tree() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	GameManager.add_child(row)
	return row

func _crowded_hero() -> Character:
	var hero := _hero()
	hero.add_status(StatusSystem.POISON)
	for stat in StatusSystem.BUFFABLE_STATS:
		hero.apply_debuff(stat)
	return hero

func test_a_crowded_row_never_grows_past_its_room() -> void:
	# Six effects on one hero used to widen that hero's panel — and shove its
	# neighbours sideways — for as long as the effects lasted.
	var row := _row_in_tree()
	StatusChipFactory.populate_row(row, _crowded_hero(), 150.0)
	assert_true(row.get_combined_minimum_size().x <= 150.0, "the row fits the room it was given")
	var more := row.get_child(row.get_child_count() - 1) as Control
	var shown := row.get_child_count() - 1
	assert_eq(more.get_meta("hidden_count", -1), 6 - shown, "the last chip counts what it hides")
	assert_true(shown >= 1, "at least one real chip still shows")
	assert_eq(more.tooltip_text.split("\n").size(), 6 - shown, "its tooltip lists each hidden effect")
	row.free()

func test_a_row_with_room_shows_every_chip() -> void:
	var row := _row_in_tree()
	StatusChipFactory.populate_row(row, _crowded_hero())
	assert_eq(row.get_child_count(), 6, "no limit given: all six chips, no overflow chip")
	row.free()

func test_clearing_a_row_removes_its_chips_immediately() -> void:
	var hero := _hero()
	hero.apply_debuff("attack")
	var row := HBoxContainer.new()
	StatusChipFactory.populate_row(row, hero)
	hero.clear_battle_effects()
	StatusChipFactory.populate_row(row, hero)
	assert_eq(row.get_child_count(), 0, "no stale chip survives the rebuild")
	assert_false(row.visible, "and the empty row hides")
	row.free()
