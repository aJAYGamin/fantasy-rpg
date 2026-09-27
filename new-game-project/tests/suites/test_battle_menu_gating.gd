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
