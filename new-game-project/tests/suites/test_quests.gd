extends TestSuite

## Quest data model + QuestFactory + QuestLog + the GameManager quest flow (accept,
## report progress, turn-in rewards, completed tracking). GameManager tests snapshot
## & restore the global quest_log / gold / party per the testing policy.

func suite_name() -> String:
	return "Quests"

# --- QuestFactory -------------------------------------------------------------

func test_factory_creates_known_quest() -> void:
	var q := QuestFactory.create("cull_goblins")
	assert_ne(q, null, "factory builds a known quest")
	assert_eq(q.id, "cull_goblins", "id set")
	assert_true(q.has_counter(), "is a counter quest")
	assert_eq(q.objective_target, 3, "target read from the def")
	assert_false(q.is_objective_met(), "not met at 0 progress")

func test_factory_unknown_is_null() -> void:
	assert_false(QuestFactory.has_quest("nope_not_real"), "has_quest false for unknown")
	assert_eq(QuestFactory.create("nope_not_real"), null, "unknown id -> null")

# --- Quest model --------------------------------------------------------------

func test_quest_counter_advance_and_clamp() -> void:
	var q := QuestFactory.create("cull_goblins")
	q.advance(1)
	assert_eq(q.objective_progress, 1, "advanced by 1")
	assert_false(q.is_objective_met(), "1/3 not met")
	q.advance(5)
	assert_eq(q.objective_progress, 3, "clamped to the target")
	assert_true(q.is_objective_met(), "3/3 met")

func test_quest_progress_and_reward_text() -> void:
	var q := QuestFactory.create("cull_goblins")
	q.advance(2)
	assert_true(q.progress_text().contains("2/3"), "progress text shows the count")
	assert_true(q.reward_text().contains("Gold"), "reward text lists gold")

func test_reward_items_stack_by_count() -> void:
	# Duplicates collapse to "Name xN" (first-seen order), never listed separately.
	var stacked := Quest.stack_names(["Potion", "Potion", "Ether"])
	assert_eq(stacked.size(), 2, "two distinct entries")
	assert_eq(stacked[0], "Potion x2", "duplicates collapse with a count")
	assert_eq(stacked[1], "Ether", "single item keeps no count")
	# cull_goblins rewards two Potions -> shown as "Potion x2", not "Potion • Potion".
	assert_true(QuestFactory.create("cull_goblins").reward_text().contains("Potion x2"), "reward text stacks duplicate items")

func test_quest_to_dict_roundtrip() -> void:
	var q := QuestFactory.create("cull_goblins")
	q.advance(2)
	var q2 := QuestFactory.create("cull_goblins")
	q2.apply_progress_dict(q.to_dict())
	assert_eq(q2.objective_progress, 2, "progress restored from dict")

func test_reward_received_text_stacks() -> void:
	var t := QuestFactory.create("cull_goblins").reward_received_text()
	assert_true(t.contains("150 Gold"), "gold listed")
	assert_true(t.contains("Potion x2"), "duplicate items stacked, not separated")
	assert_true(t.contains("and"), "reads as a natural-language list")

# --- QuestLog -----------------------------------------------------------------

func test_log_accept_side_and_auto_active() -> void:
	var qlog := QuestLog.new()
	assert_true(qlog.accept_side(QuestFactory.create("cull_goblins")), "accept side succeeds")
	assert_true(qlog.is_active("cull_goblins"), "now active")
	assert_eq(qlog.active_side_id, "cull_goblins", "first accepted side auto-selected as active")
	assert_false(qlog.accept_side(QuestFactory.create("cull_goblins")), "double-accept rejected")
	qlog.accept_side(QuestFactory.create("wolf_trouble"))
	assert_eq(qlog.active_side_id, "cull_goblins", "a later accept doesn't steal the active slot")
	assert_eq(qlog.incomplete_sides().size(), 2, "both side quests are in progress")

func test_log_select_active_side() -> void:
	var qlog := QuestLog.new()
	qlog.accept_side(QuestFactory.create("cull_goblins"))
	qlog.accept_side(QuestFactory.create("wolf_trouble"))
	assert_true(qlog.select_active_side("wolf_trouble"), "select switches the active side quest")
	assert_eq(qlog.active_side().id, "wolf_trouble", "active side updated")
	assert_false(qlog.select_active_side("nope"), "unknown id rejected")

func test_log_report_advances_all_accepted() -> void:
	var qlog := QuestLog.new()
	qlog.accept_side(QuestFactory.create("cull_goblins"))   # active
	qlog.accept_side(QuestFactory.create("wolf_trouble"))   # not active, but still tracks
	qlog.report("defeat:dire")
	assert_eq(qlog.get_side("wolf_trouble").objective_progress, 1, "a non-active side quest still progresses")
	qlog.report("defeat:goblin", 3)
	assert_eq(qlog.get_side("cull_goblins").objective_progress, 3, "the active side quest progresses too")

func test_log_story_is_always_active() -> void:
	var qlog := QuestLog.new()
	qlog.set_story(QuestFactory.create("amethyst_awakening"))
	assert_ne(qlog.story, null, "story set")
	assert_true(qlog.story.is_story(), "kind is story")
	assert_true(qlog.story.is_active(), "story quest is active")

func test_log_turn_in_frees_active_slot() -> void:
	var qlog := QuestLog.new()
	qlog.accept_side(QuestFactory.create("cull_goblins"))
	assert_false(qlog.can_turn_in("cull_goblins"), "not turn-in-able yet")
	assert_eq(qlog.mark_completed("cull_goblins"), null, "can't complete an unmet quest")
	qlog.report("defeat:goblin", 3)
	var done := qlog.mark_completed("cull_goblins")
	assert_ne(done, null, "mark_completed returns the quest")
	assert_true(qlog.is_completed("cull_goblins"), "now completed")
	assert_eq(qlog.active_side_id, "", "active slot freed on completion")
	assert_eq(qlog.active_side(), null, "no active side after completion")
	assert_eq(qlog.get_side("cull_goblins").state, Quest.State.COMPLETED, "kept in the side list as completed")

func test_log_save_roundtrip() -> void:
	var qlog := QuestLog.new()
	qlog.set_story(QuestFactory.create("amethyst_awakening"))
	qlog.accept_side(QuestFactory.create("cull_goblins"))
	qlog.accept_side(QuestFactory.create("wolf_trouble"))
	qlog.select_active_side("wolf_trouble")
	qlog.report("defeat:goblin", 2)
	var qlog2 := QuestLog.new()
	qlog2.from_save(qlog.to_save())
	assert_ne(qlog2.story, null, "story restored")
	assert_eq(qlog2.active_side_id, "wolf_trouble", "active selection restored")
	assert_eq(qlog2.side_quests.size(), 2, "both side quests restored")
	assert_eq(qlog2.get_side("cull_goblins").objective_progress, 2, "side progress survives the round-trip")

# --- Waypoints ----------------------------------------------------------------

func test_waypoint_points_at_turn_in_npc() -> void:
	# cull_goblins has no objective location, so the marker sits on the turn-in
	# person (Townsperson) the whole time — both before and after it's ready.
	var q := QuestFactory.create("cull_goblins")
	assert_eq(String(q.current_waypoint().get("npc")), "Townsperson", "marks the turn-in NPC while in progress")
	q.advance(3)
	assert_eq(String(q.current_waypoint().get("npc")), "Townsperson", "still the turn-in NPC once ready")

func test_waypoint_kind_for_npc() -> void:
	var qlog := QuestLog.new()
	assert_eq(qlog.waypoint_kind_for_npc("Townsperson"), "", "no marker before accepting")
	qlog.accept_side(QuestFactory.create("cull_goblins"))   # auto-active
	assert_eq(qlog.waypoint_kind_for_npc("Townsperson"), "side", "active side quest marks its turn-in NPC (blue)")
	assert_eq(qlog.waypoint_kind_for_npc("Someone Else"), "", "unrelated NPC has no marker")
	qlog.report("defeat:goblin", 3)
	qlog.mark_completed("cull_goblins")
	assert_eq(qlog.waypoint_kind_for_npc("Townsperson"), "", "marker clears once the quest is completed")

# --- GameManager flow (snapshot/restore global state) -------------------------

func test_gm_accept_report_turnin_grants_gold() -> void:
	var saved_log := GameManager.quest_log
	var saved_gold := GameManager.gold
	var saved_party := GameManager.party
	GameManager.quest_log = QuestLog.new()
	GameManager.party = []
	GameManager.gold = 0

	var q := GameManager.accept_quest("cull_goblins")
	assert_ne(q, null, "GameManager accepts the side quest")
	assert_true(GameManager.quest_log.is_active("cull_goblins"), "active in the GM log")
	assert_eq(GameManager.accept_quest("cull_goblins"), null, "re-accepting is rejected")

	GameManager.report_quest_event("defeat:goblin", 3)
	assert_true(GameManager.can_turn_in_quest("cull_goblins"), "objective met via GM report")
	var done := GameManager.turn_in_quest("cull_goblins")
	assert_ne(done, null, "turned in")
	assert_eq(GameManager.gold, 150, "gold reward granted on turn-in")
	assert_true(GameManager.is_quest_done("cull_goblins"), "marked complete")
	assert_false(GameManager.quest_log.is_active("cull_goblins"), "no longer active")

	GameManager.quest_log = saved_log
	GameManager.gold = saved_gold
	GameManager.party = saved_party

func test_gm_set_story_quest() -> void:
	var saved_log := GameManager.quest_log
	GameManager.quest_log = QuestLog.new()
	GameManager.set_story_quest("amethyst_awakening")
	assert_ne(GameManager.quest_log.story, null, "GM sets the story quest")
	assert_true(GameManager.quest_log.story.is_story(), "it's flagged as a story quest")
	GameManager.quest_log = saved_log

func test_quests_never_grant_xp() -> void:
	var saved_log := GameManager.quest_log
	var saved_party := GameManager.party
	GameManager.quest_log = QuestLog.new()
	var hero: Character = PartyFactory.create_default_party()[0]
	var xp_before := hero.experience
	GameManager.party = [hero]
	GameManager.accept_quest("cull_goblins")
	GameManager.report_quest_event("defeat:goblin", 3)
	GameManager.turn_in_quest("cull_goblins")
	assert_eq(hero.experience, xp_before, "turning in a quest grants no XP")
	# Reward text carries no XP either.
	assert_false(QuestFactory.create("cull_goblins").reward_text().contains("XP"), "reward text has no XP")
	GameManager.quest_log = saved_log
	GameManager.party = saved_party
