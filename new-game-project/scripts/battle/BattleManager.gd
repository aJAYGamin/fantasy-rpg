class_name BattleManager
extends Node

signal battle_started(party: Array, enemies: Array)
signal enemy_move_preview(enemy: Character, move_name: String)
signal turn_started(character: Character)
signal action_performed(result: Dictionary)
signal character_defeated(character: Character)
signal battle_ended(player_won: bool, rewards: Dictionary)
signal status_effect_triggered(character: Character, result: Dictionary)

enum BattleState {
	IDLE,
	CHOOSING_ACTION,
	CHOOSING_TARGET,
	EXECUTING_ACTION,
	ENEMY_TURN,
	BATTLE_OVER
}

var state: BattleState = BattleState.IDLE
var party: Array[Character] = []
var enemies: Array[Character] = []
var turn_order: Array[Character] = []
var current_turn_index: int = 0
var current_actor: Character

func start_battle(player_party: Array[Character], enemy_group: Array[Character]):
	party = player_party
	enemies = enemy_group
	state = BattleState.IDLE
	_build_turn_order()
	emit_signal("battle_started", party, enemies)
	_next_turn()

func _build_turn_order():
	turn_order.clear()
	for c in party:
		if c.is_alive():
			turn_order.append(c)
	for e in enemies:
		if e.is_alive():
			turn_order.append(e)
	turn_order.sort_custom(func(a, b): return a.speed() > b.speed())

func _next_turn():
	while current_turn_index < turn_order.size():
		var actor = turn_order[current_turn_index]
		if actor.is_alive():
			break
		current_turn_index += 1

	if current_turn_index >= turn_order.size():
		_start_new_round()
		return

	current_actor = turn_order[current_turn_index]

	var status_results = current_actor.process_status_effects()
	for result in status_results:
		emit_signal("status_effect_triggered", current_actor, result)
		if not current_actor.is_alive():
			handle_defeat(current_actor)
			current_turn_index += 1
			_next_turn()
			return

	emit_signal("turn_started", current_actor)

	if current_actor in party:
		state = BattleState.CHOOSING_ACTION
	else:
		state = BattleState.ENEMY_TURN
		_execute_enemy_turn()

func _start_new_round():
	current_turn_index = 0
	_build_turn_order()
	_next_turn()

# --- Player Actions ---
func player_attack(attacker: Character, target: Character):
	if state != BattleState.CHOOSING_ACTION and state != BattleState.CHOOSING_TARGET:
		return
	# take_damage now returns a Dictionary with damage, multiplier, effectiveness
	var dmg_result = target.take_damage(attacker.attack_power(), attacker.element)
	var result = {
		"action": "attack",
		"actor": attacker,
		"target": target,
		"is_first_target": true,
		"value": dmg_result.get("damage", 0),
		"multiplier": dmg_result.get("multiplier", 1.0),
		"effectiveness": dmg_result.get("effectiveness", ""),
		"effectiveness_color": dmg_result.get("effectiveness_color", Color.WHITE),
		"target_alive": target.is_alive()
	}
	emit_signal("action_performed", result)
	if not target.is_alive():
		handle_defeat(target)
	end_player_turn()

func player_use_skill(user: Character, skill: Skill, targets: Array[Character]):
	if state != BattleState.CHOOSING_ACTION and state != BattleState.CHOOSING_TARGET:
		return
	if not skill.can_use(user):
		return

	user.use_mp(skill.mp_cost)

	var first_target = true
	for target in targets:
		# Skip already defeated targets
		if not target.is_alive():
			continue
		var value = skill.calculate_value(user)
		var result = {"actor": user, "target": target, "skill": skill, "is_first_target": first_target}
		first_target = false

		match skill.skill_type:
			Skill.SkillType.DAMAGE:
				# STRIKE/RANGED use physical damage, MAGIC uses magic damage, STATUS deals none
				match skill.attack_type:
					Skill.AttackType.STRIKE, Skill.AttackType.RANGED:
						var dmg_result = target.take_damage(value, skill.element)
						result["action"] = "skill_physical"
						result["value"] = dmg_result.get("damage", 0)
						result["multiplier"] = dmg_result.get("multiplier", 1.0)
						result["effectiveness"] = dmg_result.get("effectiveness", "")
						result["effectiveness_color"] = dmg_result.get("effectiveness_color", Color.WHITE)
					Skill.AttackType.MAGIC:
						var dmg_result = target.take_magic_damage(value, skill.element)
						result["action"] = "skill_magic"
						result["value"] = dmg_result.get("damage", 0)
						result["multiplier"] = dmg_result.get("multiplier", 1.0)
						result["effectiveness"] = dmg_result.get("effectiveness", "")
						result["effectiveness_color"] = dmg_result.get("effectiveness_color", Color.WHITE)
					Skill.AttackType.STATUS:
						result["action"] = "status"
						result["value"] = 0
			Skill.SkillType.HEAL:
				var healed = target.heal(value)
				result["action"] = "heal"
				result["value"] = healed
			Skill.SkillType.BUFF:
				target.add_status("regenerate")
				result["action"] = "buff"
				result["value"] = 0

		if skill.status_to_apply != "" and randf() < skill.status_chance:
			target.add_status(skill.status_to_apply)

		result["target_alive"] = target.is_alive()
		emit_signal("action_performed", result)
		if not target.is_alive():
			handle_defeat(target)

	end_player_turn()

func player_use_item(user: Character, item: Item, target: Character):
	if state != BattleState.CHOOSING_ACTION:
		return
	var result = item.use(target)
	result["actor"] = user
	emit_signal("action_performed", result)
	end_player_turn()

func enemy_use_skill(enemy: Character, skill: Skill, targets: Array[Character]):
	if not skill.can_use(enemy):
		return
	enemy.use_mp(skill.mp_cost)
	# Override target for SELF skills
	var actual_targets = targets
	if skill.target_type == Skill.TargetType.SELF:
		actual_targets = [enemy]
	var first_target = true
	for target in actual_targets:
		if not target.is_alive():
			continue
		var value = skill.calculate_value(enemy)
		var result = {"actor": enemy, "target": target, "skill": skill, "is_first_target": first_target}
		first_target = false
		match skill.skill_type:
			Skill.SkillType.DAMAGE:
				match skill.attack_type:
					Skill.AttackType.STRIKE, Skill.AttackType.RANGED:
						var dmg_result = target.take_damage(value, skill.element)
						result["action"] = "attack"
						result["value"] = dmg_result.get("damage", 0)
						result["multiplier"] = dmg_result.get("multiplier", 1.0)
						result["effectiveness"] = dmg_result.get("effectiveness", "")
						result["effectiveness_color"] = dmg_result.get("effectiveness_color", Color.WHITE)
					Skill.AttackType.MAGIC:
						var dmg_result = target.take_magic_damage(value, skill.element)
						result["action"] = "skill_magic"
						result["value"] = dmg_result.get("damage", 0)
						result["multiplier"] = dmg_result.get("multiplier", 1.0)
						result["effectiveness"] = dmg_result.get("effectiveness", "")
						result["effectiveness_color"] = dmg_result.get("effectiveness_color", Color.WHITE)
					Skill.AttackType.STATUS:
						result["action"] = "status"
						result["value"] = 0
			Skill.SkillType.HEAL:
				var healed = target.heal(value)
				result["action"] = "heal"
				result["value"] = healed
			Skill.SkillType.BUFF:
				target.add_status("regenerate")
				result["action"] = "buff"
				result["value"] = 0
		if skill.status_to_apply != "" and randf() < skill.status_chance:
			target.add_status(skill.status_to_apply)
		result["target_alive"] = target.is_alive()
		emit_signal("action_performed", result)
		if not target.is_alive():
			handle_defeat(target)

func player_defend(character: Character):
	character.add_status("defending")
	var result = {"action": "defend", "actor": character, "value": 0}
	emit_signal("action_performed", result)
	end_player_turn()

func end_player_turn():
	state = BattleState.IDLE
	if check_battle_end():
		return
	current_turn_index += 1
	_next_turn()

# --- Enemy AI ---
func _execute_enemy_turn():
	await get_tree().create_timer(0.4).timeout

	var enemy = current_actor
	var alive_party = party.filter(func(c): return c.is_alive())
	if alive_party.is_empty():
		return

	# Use EnemyAI to decide action
	var decision = EnemyAI.choose_action(enemy, party, enemies)
	var target: Character = decision.get("target", alive_party[0])
	var skill = decision.get("skill", null)

	# Show move name under enemy card before executing
	var move_name = skill.skill_name if skill != null else "Attack"
	emit_signal("enemy_move_preview", enemy, move_name)

	# Delay before executing
	await get_tree().create_timer(1.0).timeout

	# Clear move preview
	emit_signal("enemy_move_preview", enemy, "")

	if skill != null:
		if EnemyAI.try_dodge(target):
			var dodge_result = {
				"action": "dodge",
				"actor": enemy,
				"target": target,
				"value": 0,
				"target_alive": target.is_alive()
			}
			emit_signal("action_performed", dodge_result)
		else:
			enemy_use_skill(enemy, skill, [target])
	else:
		if EnemyAI.try_dodge(target):
			var dodge_result = {
				"action": "dodge",
				"actor": enemy,
				"target": target,
				"value": 0,
				"target_alive": target.is_alive()
			}
			emit_signal("action_performed", dodge_result)
		else:
			var dmg_result = target.take_damage(enemy.attack_power(), enemy.element)
			var result = {
				"action": "attack",
				"actor": enemy,
				"target": target,
				"value": dmg_result.get("damage", 0),
				"multiplier": dmg_result.get("multiplier", 1.0),
				"effectiveness": dmg_result.get("effectiveness", ""),
				"effectiveness_color": dmg_result.get("effectiveness_color", Color.WHITE),
				"target_alive": target.is_alive()
			}
			emit_signal("action_performed", result)
			if not target.is_alive():
				handle_defeat(target)

	if check_battle_end():
		return
	current_turn_index += 1
	_next_turn()

# --- Helpers ---
func handle_defeat(character: Character):
	emit_signal("character_defeated", character)

func check_battle_end() -> bool:
	var party_alive = party.any(func(c): return c.is_alive())
	var enemies_alive = enemies.any(func(c): return c.is_alive())

	if not enemies_alive:
		state = BattleState.BATTLE_OVER
		var rewards = _calculate_rewards()
		emit_signal("battle_ended", true, rewards)
		return true
	elif not party_alive:
		state = BattleState.BATTLE_OVER
		emit_signal("battle_ended", false, {})
		return true
	return false

func _calculate_rewards() -> Dictionary:
	var total_exp = 0
	var total_gold = 0
	var dropped_items: Array[Item] = []
	for enemy in enemies:
		total_exp += enemy.level * 20 + 10
		total_gold += enemy.level * 5 + randi() % 10
	return {"exp": total_exp, "gold": total_gold, "items": dropped_items}

func get_alive_party() -> Array[Character]:
	return party.filter(func(c): return c.is_alive())

func get_alive_enemies() -> Array[Character]:
	return enemies.filter(func(c): return c.is_alive())
