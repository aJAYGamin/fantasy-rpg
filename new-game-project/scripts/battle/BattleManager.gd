class_name BattleManager
extends Node

signal battle_started(party: Array, enemies: Array)
signal enemy_move_preview(enemy: Character, move_name: String)
signal turn_started(character: Character)
# Fires AFTER skip/wake resolution — UI uses this to show the action menu so
# it doesn't flash visible during stun/sleep/paralysis skip animations.
signal turn_ready_for_action(character: Character)
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

# Turns a "regenerate" skill heals for (transient heal-over-time, not a status).
const REGEN_TURNS := 3

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

	# Defend lasts until the defender's next turn — it protected them through the
	# intervening enemy turns, so clear it now that they're acting again.
	current_actor.clear_defend()

	var status_results = current_actor.process_status_effects()
	for result in status_results:
		emit_signal("status_effect_triggered", current_actor, result)
		if not current_actor.is_alive():
			handle_defeat(current_actor)
			current_turn_index += 1
			_next_turn()
			return

	emit_signal("turn_started", current_actor)

	# Skip-turn resolution. StatusSystem owns the rules:
	#   stun       -> always skip + auto-clear
	#   sleep      -> probabilistic skip (100% -> 75% -> ...) or wake-and-act
	#   paralysis  -> 25% skip per turn (does NOT clear; persists until healed)
	# Returns { skip: <name or "">, woke_up: bool }.
	# Note: turn_ready_for_action (and therefore the action menu) is deliberately
	# NOT emitted until skip/wake banners finish — keeps the menu from flashing
	# visible during the skip animation.
	var skip_result: Dictionary = StatusSystem.resolve_turn_skip(current_actor)

	# Wake-up banner: sleep was active and resolved to "wake", actor will act
	# THIS same turn after the banner finishes. Wait long enough for the banner
	# to play fully (BattleScene.BANNER_DURATION_WAKE = 1.55) plus a small
	# buffer so the action menu doesn't appear mid-fade.
	if skip_result.get("woke_up", false):
		emit_signal("status_effect_triggered", current_actor, {
			"type": "woke_up",
			"value": 0,
			"name": current_actor.character_name,
		})
		await get_tree().create_timer(1.75).timeout

	# Skip banner: actor cannot act this turn. Wait for the banner to finish
	# (BattleScene.BANNER_DURATION_SKIP = 1.70) before advancing to next actor.
	var skip_status: String = skip_result.get("skip", "")
	if skip_status != "":
		emit_signal("status_effect_triggered", current_actor, {
			"type": skip_status,
			"value": 0,
			"skipped": true,
			"name": current_actor.character_name,
		})
		await get_tree().create_timer(1.90).timeout
		current_turn_index += 1
		_next_turn()
		return

	# Actor is ready — UI shows action menu / starts enemy AI.
	emit_signal("turn_ready_for_action", current_actor)

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
	# Memory Echo: enemies with high species memory may dodge.
	if EnemyAI.try_dodge(target):
		emit_signal("action_performed", {
			"action": "dodge",
			"actor": attacker,
			"target": target,
			"is_first_target": true,
			"value": 0,
			"target_alive": target.is_alive(),
		})
		end_player_turn()
		return
	# take_damage now returns a Dictionary with damage, multiplier, effectiveness
	var dmg_result = target.take_damage(attacker.attack_power(), attacker.element, attacker.secondary_element)
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

		if skill.skill_type == Skill.SkillType.DAMAGE:
			# Memory Echo: enemies with high species memory may dodge damage skills.
			if EnemyAI.try_dodge(target):
				result["action"] = "dodge"
				result["value"] = 0
				result["target_alive"] = target.is_alive()
				emit_signal("action_performed", result)
				continue
			match skill.attack_type:
				Skill.AttackType.STRIKE, Skill.AttackType.RANGED:
					var dmg_result = target.take_damage(value, skill.element, skill.secondary_element)
					result["action"] = "skill_physical"
					result["value"] = dmg_result.get("damage", 0)
					result["multiplier"] = dmg_result.get("multiplier", 1.0)
					result["effectiveness"] = dmg_result.get("effectiveness", "")
					result["effectiveness_color"] = dmg_result.get("effectiveness_color", Color.WHITE)
				Skill.AttackType.MAGIC:
					var dmg_result = target.take_magic_damage(value, skill.element, skill.secondary_element)
					result["action"] = "skill_magic"
					result["value"] = dmg_result.get("damage", 0)
					result["multiplier"] = dmg_result.get("multiplier", 1.0)
					result["effectiveness"] = dmg_result.get("effectiveness", "")
					result["effectiveness_color"] = dmg_result.get("effectiveness_color", Color.WHITE)
		elif skill.skill_type == Skill.SkillType.STATUS:
			match skill.status_type:
				Skill.StatusType.HEAL:
					var healed = target.heal(value)
					result["action"] = "heal"
					result["value"] = healed
				Skill.StatusType.BUFF:
					# A skill's status_to_apply token can be a stat-buff ("attack_buff"),
					# a stat-debuff ("magic_debuff"), or a legacy named status
					# ("regenerate"). Default to "regenerate" if no token specified.
					var token: String = skill.status_to_apply if skill.status_to_apply != "" else StatusSystem.REGENERATE
					_apply_skill_status(target, token)
					result["action"] = "buff"
					result["value"] = 0
				Skill.StatusType.DEBUFF:
					if skill.status_to_apply != "":
						_apply_skill_status(target, skill.status_to_apply)
					result["action"] = "debuff"
					result["value"] = 0

		# Status chance only applies on damage skills
		if skill.skill_type == Skill.SkillType.DAMAGE and skill.status_to_apply != "" and randf() < skill.status_chance:
			_apply_skill_status(target, skill.status_to_apply)

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
	# Enemies have no MP pool — skip the deduction. Skill.can_use() already
	# short-circuits MP cost for Enemy instances.
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
		if skill.skill_type == Skill.SkillType.DAMAGE:
			match skill.attack_type:
				Skill.AttackType.STRIKE, Skill.AttackType.RANGED:
					var dmg_result = target.take_damage(value, skill.element, skill.secondary_element)
					result["action"] = "attack"
					result["value"] = dmg_result.get("damage", 0)
					result["multiplier"] = dmg_result.get("multiplier", 1.0)
					result["effectiveness"] = dmg_result.get("effectiveness", "")
					result["effectiveness_color"] = dmg_result.get("effectiveness_color", Color.WHITE)
				Skill.AttackType.MAGIC:
					var dmg_result = target.take_magic_damage(value, skill.element, skill.secondary_element)
					result["action"] = "skill_magic"
					result["value"] = dmg_result.get("damage", 0)
					result["multiplier"] = dmg_result.get("multiplier", 1.0)
					result["effectiveness"] = dmg_result.get("effectiveness", "")
					result["effectiveness_color"] = dmg_result.get("effectiveness_color", Color.WHITE)
		elif skill.skill_type == Skill.SkillType.STATUS:
			match skill.status_type:
				Skill.StatusType.HEAL:
					var healed = target.heal(value)
					result["action"] = "heal"
					result["value"] = healed
				Skill.StatusType.BUFF:
					var token: String = skill.status_to_apply if skill.status_to_apply != "" else StatusSystem.REGENERATE
					_apply_skill_status(target, token)
					result["action"] = "buff"
					result["value"] = 0
				Skill.StatusType.DEBUFF:
					if skill.status_to_apply != "":
						_apply_skill_status(target, skill.status_to_apply)
					result["action"] = "debuff"
					result["value"] = 0
		if skill.skill_type == Skill.SkillType.DAMAGE and skill.status_to_apply != "" and randf() < skill.status_chance:
			_apply_skill_status(target, skill.status_to_apply)
		result["target_alive"] = target.is_alive()
		emit_signal("action_performed", result)
		if not target.is_alive():
			handle_defeat(target)

func player_defend(character: Character):
	character.start_defend()
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
			var dmg_result = target.take_damage(enemy.attack_power(), enemy.element, enemy.secondary_element)
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
	var dropped_equipment: Array[Equipment] = []
	# Hard mode caps healing/battle item stacks and refuses to drop more once the
	# player is at the cap.
	var hard_caps: bool = GameManager.settings.hard_item_caps()
	for enemy in enemies:
		total_exp += enemy.level * 20 + 10
		total_gold += enemy.level * 5 + randi() % 10
		# Roll each defeated enemy's drop table once per entry, routing the name
		# to ItemFactory (consumables, which stack) or EquipmentFactory (gear,
		# distinct pieces). Identical item drops stack so the victory list stays
		# compact; equipment is always listed per piece.
		if enemy is Enemy:
			for entry in enemy.drop_table:
				if randf() >= float(entry.get("chance", 0.0)):
					continue
				var drop_name := String(entry.get("item_name", ""))
				var qty: int = max(1, int(entry.get("quantity", 1)))
				if ItemFactory.has_item(drop_name):
					var it := ItemFactory.create(drop_name, qty)
					if it == null:
						continue
					if hard_caps and _is_capped_item(it):
						var room: int = _drop_room_for(it, dropped_items)
						if room <= 0:
							continue   # already at cap — no drop
						it.quantity = min(it.quantity, room)
					_stack_drop(dropped_items, it)
				elif EquipmentFactory.has_equipment(drop_name):
					for i in range(qty):
						var eq := EquipmentFactory.create(drop_name)
						if eq != null:
							dropped_equipment.append(eq)
	# Difficulty reward multiplier (Hard gives a little more gold & XP).
	var rmult: float = GameManager.settings.reward_mult()
	if not is_equal_approx(rmult, 1.0):
		total_exp = roundi(total_exp * rmult)
		total_gold = roundi(total_gold * rmult)
	return {"exp": total_exp, "gold": total_gold, "items": dropped_items, "equipment": dropped_equipment}

# Healing/battle items are the ones Hard mode caps at Inventory.HARD_ITEM_CAP.
func _is_capped_item(it: Item) -> bool:
	var c := it.get_category()
	return c == Item.ItemCategory.HEALING or c == Item.ItemCategory.BATTLE

# How many more of `it` can drop before hitting the Hard cap, counting what the
# party already holds plus what's already queued in this battle's drops.
func _drop_room_for(it: Item, dropped_items: Array[Item]) -> int:
	var have := 0
	if not GameManager.party.is_empty() and GameManager.party[0].inventory != null:
		for existing in GameManager.party[0].inventory.items:
			if existing.item_name == it.item_name:
				have = existing.quantity
				break
	for d in dropped_items:
		if d.item_name == it.item_name:
			have += d.quantity
			break
	return Inventory.HARD_ITEM_CAP - have

# Merges a dropped item into the running list, stacking by name.
func _stack_drop(dropped: Array[Item], item: Item) -> void:
	for existing in dropped:
		if existing.item_name == item.item_name:
			existing.quantity += item.quantity
			return
	dropped.append(item)

func get_alive_party() -> Array[Character]:
	return party.filter(func(c): return c.is_alive())

func get_alive_enemies() -> Array[Character]:
	return enemies.filter(func(c): return c.is_alive())

# Resolves a Skill.status_to_apply token against a target. Buff/debuff tokens
# (e.g. "attack_buff", "magic_debuff") route to apply_buff/apply_debuff so the
# cancel-on-opposite rule fires; everything else falls through to add_status
# which handles the mutex-first-come-first-served rule.
# When a mutex status actually LANDS (target had no prior mutex status, no
# duplicate), we emit status_effect_triggered with applied=true so the UI can
# banner "[Name] was Poisoned!" etc.
func _apply_skill_status(target: Character, token: String):
	if token == "":
		return
	var parsed = StatusSystem.parse_apply_token(token)
	match parsed["kind"]:
		"buff":
			target.apply_buff(parsed["value"])
		"debuff":
			target.apply_debuff(parsed["value"])
		_:
			var status_name: String = parsed["value"]
			# Regenerate is a transient heal-over-time, not a status chip.
			if status_name == StatusSystem.REGENERATE:
				target.start_regen(REGEN_TURNS)
				return
			var was_active: bool = target.is_status(status_name)
			target.add_status(status_name)
			# Banner only when this call is what actually put the status on the
			# target. Re-applying a duplicate, or mutex-blocked attempts, stay
			# silent.
			if not was_active and target.is_status(status_name) \
					and status_name in StatusSystem.MUTEX_STATUSES:
				emit_signal("status_effect_triggered", target, {
					"type": status_name,
					"value": 0,
					"applied": true,
					"name": target.character_name,
				})
