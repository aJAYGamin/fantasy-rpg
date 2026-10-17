extends TestSuite

## How the moveset screen lays out a hero's learned moves.

func suite_name() -> String:
	return "LoadoutScreen"

## A trainer screen on `hero` with a special slot picked, so the Known Moves
## list shows the specials — the longer of a hero's two lists. Built without
## setup(), which would pause the tree the tests run in.
func _open_on(hero: Character) -> LoadoutScreen:
	GameManager.party = [hero] as Array[Character]
	var screen := LoadoutScreen.new()
	screen._editor = LoadoutEditor.new(LoadoutEditor.Mode.TRAINER)
	screen._selected_slot = 0
	screen._selected_is_special = true
	GameManager.add_child(screen)
	screen._build()
	return screen

func _find_scroll(n: Node) -> ScrollContainer:
	if n is ScrollContainer:
		return n
	for c in n.get_children():
		var found := _find_scroll(c)
		if found != null:
			return found
	return null

func _level_20_kael() -> Character:
	for h in PartyFactory.create_default_party():
		if h.character_name == "Kael":
			h.level = 20
			return h
	return null

func test_every_learned_special_fits_without_scrolling() -> void:
	var saved: Array[Character] = GameManager.party
	var kael := _level_20_kael()
	assert_eq(kael.learned_pool_indices(true).size(), 10, "a level-20 hero knows all ten specials")
	var screen := _open_on(kael)
	var scroll := _find_scroll(screen)
	var list: Control = scroll.get_child(0)
	assert_eq(list.get_child_count(), 10, "the list holds every learned special")
	assert_true(scroll.custom_minimum_size.y >= list.get_combined_minimum_size().y,
		"the list is tall enough that none of them hides below the fold")
	screen.free()
	GameManager.party = saved

func test_the_list_scrolls_to_a_row_reached_by_keyboard_or_controller() -> void:
	# An open details panel can still push the list past its height; a row
	# focused below the fold must scroll into view.
	var saved: Array[Character] = GameManager.party
	var screen := _open_on(_level_20_kael())
	assert_true(_find_scroll(screen).follow_focus, "the Known Moves list follows focus")
	screen.free()
	GameManager.party = saved
