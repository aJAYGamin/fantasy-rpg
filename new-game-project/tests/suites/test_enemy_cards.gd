extends TestSuite

## Enemy cards across the top of the battle screen, and the move-name preview
## that appears under the card of the enemy whose turn it is.
##
## The preview used to find its card by POSITION — "the i-th card belongs to the
## i-th living enemy". When an enemy died, its card lingered for the 0.4s HP
## drain and then the whole row was rebuilt, so for that window the positions
## were off by one: the next enemy's preview went under the dead enemy's card,
## the rebuild freed that card, and the preview gave up. Wolves (fragile, fast,
## often acting right after a kill) lost their move names most of the time.

func suite_name() -> String:
	return "EnemyCards"

var _made: Array = []

func _scene(count: int) -> BattleScene:
	var scene := BattleScene.new()
	var bm := BattleManager.new()
	var foes: Array[Character] = []
	for i in count:
		var e := Enemy.new()
		e.character_name = "Foe%d" % i
		e.base_hp = 50
		e.level = 1
		e.current_hp = e.max_hp()
		foes.append(e)
	bm.enemies = foes
	scene.battle_manager = bm
	scene.enemy_info_row = HBoxContainer.new()
	for e in foes:
		scene.enemy_info_row.add_child(scene._create_enemy_card(e))
	_made.append_array([scene.enemy_info_row, bm, scene])
	return scene

func _cleanup() -> void:
	for n in _made:
		if is_instance_valid(n):
			n.free()
	_made.clear()

func test_each_enemy_knows_its_own_card() -> void:
	var scene := _scene(3)
	for i in 3:
		assert_eq(scene.card_for(scene.battle_manager.enemies[i]), scene.enemy_info_row.get_child(i), "Foe%d's card" % i)
	_cleanup()

func test_a_rebuild_after_a_death_leaves_only_the_living_cards() -> void:
	var scene := _scene(3)
	var foes: Array[Character] = scene.battle_manager.enemies
	foes[0].current_hp = 0
	scene._rebuild_enemy_cards()
	assert_eq(scene.enemy_info_row.get_child_count(), 2, "the dead enemy's card is gone at once, not at the end of the frame")
	assert_eq(scene.card_for(foes[1]), scene.enemy_info_row.get_child(0), "the next enemy's preview finds ITS card")
	assert_eq(scene.card_for(foes[2]), scene.enemy_info_row.get_child(1), "and so does the one after it")
	assert_eq(scene.card_for(foes[0]), null, "a dead enemy has no card")
	_cleanup()

func test_a_card_waiting_to_be_freed_is_not_anyones_card() -> void:
	var scene := _scene(2)
	var foe: Character = scene.battle_manager.enemies[0]
	scene.card_for(foe).queue_free()
	assert_eq(scene.card_for(foe), null, "a card on its way out is never used for a preview")
	_cleanup()
