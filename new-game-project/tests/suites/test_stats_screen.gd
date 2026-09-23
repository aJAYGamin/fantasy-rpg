extends TestSuite

## Tests for StatsScreen.build_hero_view_model (Phase P1).
## Exercises the pure view-model builder against PartyFactory heroes — no scene
## tree needed. Confirms stat values, skill split (attacks 0-3 / specials 4+),
## resonance + bio metadata, and element affinity surface correctly.

func suite_name() -> String:
	return "StatsScreen"

func _aria() -> Character:
	for h in PartyFactory.create_default_party():
		if h.character_name == "Aria":
			return h
	return null

func test_basic_fields() -> void:
	var aria := _aria()
	var vm := StatsScreen.build_hero_view_model(aria)
	assert_eq(vm["name"], "Aria", "name surfaced")
	assert_eq(vm["class"], "Mage", "class surfaced")
	assert_eq(vm["level"], aria.level, "level surfaced")
	assert_eq(vm["element_name"], "Water", "element name surfaced")

func test_stats_match_getters() -> void:
	var aria := _aria()
	var vm := StatsScreen.build_hero_view_model(aria)
	assert_eq(vm["attack"], aria.attack_power(), "ATK matches getter")
	assert_eq(vm["defense"], aria.defense_power(), "DEF matches getter")
	assert_eq(vm["magic"], aria.magic_power(), "MAG matches getter")
	assert_eq(vm["arcane"], aria.arcane_power(), "ARC matches getter")
	assert_eq(vm["speed"], aria.speed(), "SPD matches getter")
	assert_eq(vm["max_hp"], aria.max_hp(), "max HP matches getter")
	assert_eq(vm["max_mp"], aria.max_mp(), "max MP matches getter")

func test_hp_mp_exp_text() -> void:
	var aria := _aria()
	var vm := StatsScreen.build_hero_view_model(aria)
	assert_eq(vm["hp_text"], "%d / %d" % [aria.current_hp, aria.max_hp()], "HP text formatted")
	assert_eq(vm["mp_text"], "%d / %d" % [aria.current_mp, aria.max_mp()], "MP text formatted")
	assert_eq(vm["exp_text"], "%d / %d" % [aria.experience, aria.experience_to_next], "XP text formatted")

func test_skill_split() -> void:
	# The page lists the EQUIPPED kit, not the whole learned pool: a move with no
	# slot has no order to rearrange, and swapping the pool belongs to a camp or
	# a trainer.
	var aria := _aria()
	var vm := StatsScreen.build_hero_view_model(aria)
	var attacks: Array = vm["attacks"]
	var specials: Array = vm["specials"]
	assert_eq(attacks.size(), aria.equipped_skills(false).size(), "equipped attacks listed")
	assert_eq(specials.size(), aria.equipped_skills(true).size(), "equipped specials listed")
	assert_true(attacks.size() < 6, "the unequipped rest of the pool is not shown")
	assert_eq(attacks[0]["name"], "Aqua Slash", "Aria's first attack is Aqua Slash")
	assert_eq(specials[0]["name"], "Tidal Requiem", "Aria's first special is Tidal Requiem")
	# Each entry knows its slot so a click can reorder it.
	assert_eq(int(attacks[0]["slot"]), 0, "first attack reports slot 0")
	assert_false(bool(attacks[0]["is_special"]), "and which list it belongs to")

func test_skill_view_model_shape() -> void:
	var aria := _aria()
	var vm := StatsScreen.build_hero_view_model(aria)
	var frost: Dictionary = vm["attacks"][1]  # Frost Bolt — MAGIC/ICE, 12 MP
	assert_eq(frost["name"], "Frost Bolt", "skill name surfaced")
	assert_eq(frost["mp_cost"], 12, "skill mp_cost surfaced")
	assert_eq(frost["element_name"], "Ice", "skill element surfaced")
	assert_true(str(frost["description"]) != "", "skill has a description")

func test_resonance_metadata() -> void:
	var aria := _aria()
	var vm := StatsScreen.build_hero_view_model(aria)
	assert_eq(vm["resonance_name"], "Tidal Requiem", "solo resonance name from meta")
	assert_true(str(vm["resonance_desc"]) != "", "solo resonance has a description")

func test_resonance_meter_surfaced() -> void:
	var aria := _aria()
	aria.resonance_meter = 42.0
	var vm := StatsScreen.build_hero_view_model(aria)
	assert_near(vm["resonance_meter"], 42.0, 0.01, "resonance meter surfaced")

func test_all_heroes_have_bio() -> void:
	for h in PartyFactory.create_default_party():
		var vm := StatsScreen.build_hero_view_model(h)
		assert_true(str(vm["bio"]) != "", "%s has a non-empty bio" % h.character_name)

func test_resonance_fallbacks_without_meta() -> void:
	var c := Character.new()
	c.character_name = "Nameless"
	var vm := StatsScreen.build_hero_view_model(c)
	assert_eq(vm["resonance_name"], "Ultimate", "resonance name falls back without meta")
	assert_eq(vm["bio"], "", "bio is empty without meta")

# --- reorder wiring (regression) ----------------------------------------------
# These build the REAL screen and press the buttons found in the built tree,
# rather than calling _on_card_pressed directly. The reorder logic was always
# correct; what broke was that nothing reachable was wired to it, so a test that
# calls the handler itself would have passed while the screen sat dead.

func _collect_hit_buttons(n: Node, out: Array) -> void:
	if n is Button and String((n as Button).tooltip_text).contains("swap"):
		out.append(n)
	for c in n.get_children():
		_collect_hit_buttons(c, out)

func _open_screen(party: Array) -> StatsScreen:
	var screen := StatsScreen.new()
	GameManager.add_child(screen)
	screen.setup(party, 0)
	return screen

func _close_screen(screen: StatsScreen) -> void:
	GameManager.unregister_focus_scope(screen)
	screen.queue_free()

func _attack_names(h: Character) -> Array:
	var names: Array = []
	for s in h.equipped_skills(false):
		names.append(s.skill_name)
	return names

func test_every_equipped_card_has_a_click_target() -> void:
	var party := PartyFactory.create_default_party()
	var screen := _open_screen(party)
	var hits: Array = []
	_collect_hit_buttons(screen, hits)
	var expected: int = party[0].equipped_skills(false).size() + party[0].equipped_skills(true).size()
	assert_eq(hits.size(), expected, "one click target per equipped move (%d)" % expected)
	for b in hits:
		assert_false((b as Button).disabled, "the card's click target is enabled")
		assert_true((b as Button).is_visible_in_tree(), "the card's click target is visible")
	_close_screen(screen)

func test_pressing_two_cards_swaps_them() -> void:
	var party := PartyFactory.create_default_party()
	var hero: Character = party[0]
	var before := _attack_names(hero)
	if before.size() < 2:
		assert_true(true, "hero needs two equipped attacks to swap (skipped)")
		return
	var screen := _open_screen(party)

	var hits: Array = []
	_collect_hit_buttons(screen, hits)
	hits[0].emit_signal("pressed")

	# The press rebuilds the grid, so the old buttons are gone — re-find them the
	# way a second real click would land on the freshly built card.
	hits.clear()
	_collect_hit_buttons(screen, hits)
	hits[1].emit_signal("pressed")

	var after := _attack_names(hero)
	assert_eq(after[0], before[1], "first slot now holds what was in the second")
	assert_eq(after[1], before[0], "second slot now holds what was in the first")
	_close_screen(screen)

func test_pressing_the_same_card_twice_cancels() -> void:
	var party := PartyFactory.create_default_party()
	var hero: Character = party[0]
	var before := _attack_names(hero)
	var screen := _open_screen(party)

	var hits: Array = []
	_collect_hit_buttons(screen, hits)
	hits[0].emit_signal("pressed")
	hits.clear()
	_collect_hit_buttons(screen, hits)
	hits[0].emit_signal("pressed")

	assert_eq(_attack_names(hero), before, "selecting then deselecting changes nothing")
	_close_screen(screen)

func test_rebuild_detaches_old_cards_immediately() -> void:
	# A deferred queue_free leaves the outgoing cards laid out on top of the new
	# ones for a frame, which would swallow the second click of a swap.
	var party := PartyFactory.create_default_party()
	var screen := _open_screen(party)
	var hits: Array = []
	_collect_hit_buttons(screen, hits)
	var stale: Button = hits[0]
	assert_true(stale.is_inside_tree(), "the card is live before the rebuild")
	stale.emit_signal("pressed")
	# Its own card is still its parent; what matters is that the card was detached
	# from the screen, so the whole subtree is out of the SceneTree right away.
	assert_false(stale.is_inside_tree(), "the rebuilt-away card leaves the tree at once")
	_close_screen(screen)

# --- Controller reordering -----------------------------------------------------
# The card's click target is an overlay Button, so a controller could already
# reach it and press A — but with an empty "focus" stylebox the card gave no sign
# of where focus was, which made reordering unusable with a pad.

func test_card_shows_a_focus_ring() -> void:
	var party := PartyFactory.create_default_party()
	var screen := _open_screen(party)
	var hits: Array = []
	_collect_hit_buttons(screen, hits)
	assert_true(hits.size() > 0, "there are cards to focus")
	var box: StyleBox = (hits[0] as Button).get_theme_stylebox("focus")
	assert_true(box != null, "the card defines a focus stylebox")
	assert_false(box is StyleBoxEmpty, "and it is not invisible — the pad needs to see where it is")
	_close_screen(screen)

func test_cards_are_focusable_on_a_controller() -> void:
	var party := PartyFactory.create_default_party()
	var screen := _open_screen(party)
	GameManager.set_controller_mode_for_test(true)
	GameManager.update_focus_guard_for_test()

	var hits: Array = []
	_collect_hit_buttons(screen, hits)
	for b in hits:
		assert_ne((b as Button).focus_mode, Control.FOCUS_NONE,
			"every move card can be reached with a controller")
	GameManager.set_controller_mode_for_test(false)
	_close_screen(screen)

func test_controller_can_reorder_with_the_focused_card() -> void:
	# The same two-step swap a mouse does, driven through the focused control.
	var party := PartyFactory.create_default_party()
	var hero: Character = party[0]
	var before := _attack_names(hero)
	if before.size() < 2:
		assert_true(true, "hero needs two equipped attacks to swap (skipped)")
		return
	var screen := _open_screen(party)
	GameManager.set_controller_mode_for_test(true)
	GameManager.update_focus_guard_for_test()

	var hits: Array = []
	_collect_hit_buttons(screen, hits)
	hits[0].grab_focus()
	var focused := screen.get_viewport().gui_get_focus_owner()
	assert_eq(focused, hits[0], "the controller is on the first card")
	# A press on the focused card, then on the next one.
	(focused as Button).emit_signal("pressed")
	hits.clear()
	_collect_hit_buttons(screen, hits)
	hits[1].grab_focus()
	(screen.get_viewport().gui_get_focus_owner() as Button).emit_signal("pressed")

	var after := _attack_names(hero)
	assert_eq(after[0], before[1], "the two moves traded places from a controller")
	assert_eq(after[1], before[0], "both slots updated")
	GameManager.set_controller_mode_for_test(false)
	_close_screen(screen)

func test_focus_ring_lines_up_with_the_card_border() -> void:
	# A PanelContainer lays children into its CONTENT rect, so without expand
	# margins the ring drew inset from the card's border instead of on it. Checked
	# against the stylebox rather than live rects so it does not depend on a
	# layout pass having run.
	var party := PartyFactory.create_default_party()
	var screen := _open_screen(party)
	var hits: Array = []
	_collect_hit_buttons(screen, hits)
	assert_true(hits.size() > 0, "there are cards to check")

	var hit: Button = hits[0]
	var card := hit.get_parent() as PanelContainer
	assert_true(card != null, "the click target sits directly in the card panel")
	var panel: StyleBox = card.get_theme_stylebox("panel")
	var ring: StyleBox = hit.get_theme_stylebox("focus")

	assert_eq(ring.expand_margin_left, panel.content_margin_left, "ring reaches the card's left border")
	assert_eq(ring.expand_margin_right, panel.content_margin_right, "ring reaches the right border")
	assert_eq(ring.expand_margin_top, panel.content_margin_top, "ring reaches the top border")
	assert_eq(ring.expand_margin_bottom, panel.content_margin_bottom, "ring reaches the bottom border")
	_close_screen(screen)

func test_move_cards_loop_on_a_controller() -> void:
	var party := PartyFactory.create_default_party()
	var screen := _open_screen(party)
	GameManager.set_controller_mode_for_test(true)
	GameManager.update_focus_guard_for_test()

	var hits: Array = []
	_collect_hit_buttons(screen, hits)
	# Walk down from the first card far enough to run off the bottom of the grid.
	var cur: Control = hits[0]
	var visited: Array = []
	for i in hits.size() * 2 + 4:
		if cur == null:
			break
		visited.append(cur)
		cur = cur.find_valid_focus_neighbor(SIDE_BOTTOM)
	assert_true(visited.size() > hits.size(),
		"navigation keeps going past the last card instead of dead-ending (%d steps over %d cards)"
			% [visited.size(), hits.size()])

	GameManager.set_controller_mode_for_test(false)
	_close_screen(screen)
