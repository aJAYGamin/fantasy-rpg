extends TestSuite

## The action menu may only come back when the battle is actually waiting for a
## hero to choose. Each battle menu announces its choice and THEN closes itself,
## and the choice resolves the whole turn first — so by the time the menu's
## "closed" signal re-shows the action menu, the next actor's turn has begun.
## If that actor was a stunned/asleep/paralysed hero, the menu popped back up
## for them during their skip banner (and likewise during a wake-up banner or a
## boss's HP refill), letting the player act on a turn that was being skipped.

func suite_name() -> String:
	return "BattleMenuGating"

var _made: Array = []

func _scene(state: BattleManager.BattleState) -> BattleScene:
	var scene := BattleScene.new()
	var bm := BattleManager.new()
	var hero := Character.new()
	hero.character_name = "Gated"
	hero.base_hp = 100
	hero.current_hp = hero.max_hp()
	var party: Array[Character] = [hero]
	bm.party = party
	bm.state = state
	scene.battle_manager = bm
	scene.current_actor = hero
	scene.action_menu = PanelContainer.new()
	scene.action_menu.visible = false
	_made.append_array([scene.action_menu, bm, scene])
	return scene

func _cleanup() -> void:
	for n in _made:
		if is_instance_valid(n):
			n.free()
	_made.clear()

func test_closing_a_menu_during_a_skipped_hero_turn_keeps_the_menu_hidden() -> void:
	# end_player_turn leaves the manager IDLE; a skip never moves it on.
	var scene := _scene(BattleManager.BattleState.IDLE)
	scene._on_attack_menu_closed()
	assert_false(scene.action_menu.visible, "no action menu while the hero's turn is being skipped")
	_cleanup()

func test_closing_a_menu_during_an_enemy_turn_keeps_the_menu_hidden() -> void:
	var scene := _scene(BattleManager.BattleState.ENEMY_TURN)
	scene._on_attack_menu_closed()
	assert_false(scene.action_menu.visible, "no action menu during an enemy's turn")
	_cleanup()

func test_backing_out_of_a_menu_on_your_turn_brings_the_menu_back() -> void:
	var scene := _scene(BattleManager.BattleState.CHOOSING_ACTION)
	scene._on_attack_menu_closed()
	assert_true(scene.action_menu.visible, "Back from Attack/Items/Resonance still returns to the action menu")
	_cleanup()

func test_a_finished_battle_never_brings_the_menu_back() -> void:
	var scene := _scene(BattleManager.BattleState.CHOOSING_ACTION)
	scene._battle_over = true
	scene._on_attack_menu_closed()
	assert_false(scene.action_menu.visible, "not after the battle ends")
	_cleanup()

# --------------------------------------------------- Choosing an ally
# Single-ally moves (Restoring Breeze, Mend, Wind Barrier) used to go straight
# to the first living hero — the player could never pick who they healed.

func _attack_menu(alive: int) -> Control:
	var bm := BattleManager.new()
	var p: Array[Character] = []
	for i in 2:
		var h := Character.new()
		h.character_name = "Ally%d" % i
		h.base_hp = 100
		h.current_hp = h.max_hp() if i < alive else 0
		p.append(h)
	bm.party = p
	var menu := Control.new()
	menu.set_script(load("res://scripts/battle/AttackMenu.gd"))
	menu.setup(bm, null)
	_made.append_array([menu, bm])
	return menu

func _single_ally_move() -> Skill:
	var s := Skill.new()
	s.skill_name = "Mend"
	s.skill_type = Skill.SkillType.STATUS
	s.status_type = Skill.StatusType.HEAL
	s.target_type = Skill.TargetType.SINGLE_ALLY
	return s

func test_a_single_ally_move_lets_the_player_choose() -> void:
	var menu := _attack_menu(2)
	var picked := []
	menu.move_selected.connect(func(_s, t): picked.append(t))
	menu._on_skill_selected(_single_ally_move())
	assert_eq(picked, [[]], "no target yet — the battle asks who to heal")
	_cleanup()

func test_a_single_ally_move_with_one_hero_standing_needs_no_choice() -> void:
	var menu := _attack_menu(1)
	var picked := []
	menu.move_selected.connect(func(_s, t): picked.append(t))
	menu._on_skill_selected(_single_ally_move())
	assert_eq(picked.size(), 1, "chosen at once")
	assert_eq(picked[0][0].character_name, "Ally0", "the only hero standing")
	_cleanup()

func test_a_single_ally_skill_is_aimed_at_the_party() -> void:
	var foe_move := _single_ally_move()
	foe_move.target_type = Skill.TargetType.SINGLE_ENEMY
	assert_eq(BattleScene.target_mode_for(_single_ally_move()), "skill_ally", "pick from the hero panels")
	assert_eq(BattleScene.target_mode_for(foe_move), "skill", "pick from the enemy cards")

func test_each_hero_panel_targets_its_own_hero() -> void:
	# Panels are fixed per party slot. The picker used to pair panel i with the
	# i-th LIVING hero, so with the first hero down, Kael's panel healed Lyra.
	var p: Array[Character] = []
	for i in 3:
		var h := Character.new()
		h.character_name = "Slot%d" % i
		h.base_hp = 100
		h.current_hp = 0 if i == 0 else h.max_hp()
		p.append(h)
	var got := BattleScene.ally_panel_targets(p)
	assert_eq(got, [null, p[1], p[2]], "a downed hero's panel offers nothing; the others offer their own hero")

func test_the_move_details_say_who_a_move_targets() -> void:
	var breeze: Skill = load("res://data/skills/restoring_breeze.tres")
	var text: String = load("res://scripts/battle/AttackMenu.gd").description_text(breeze)
	assert_true(text.contains("One Ally"), "single-target heal says so (got %s)" % text)
	assert_true(text.contains("Regenerates"), "and keeps its effect line")
	var sweep := _single_ally_move()
	sweep.target_type = Skill.TargetType.ALL_ALLIES
	assert_true(load("res://scripts/battle/AttackMenu.gd").description_text(sweep).contains("All Allies"), "a team heal says so")
