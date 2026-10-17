class_name EnemyAI
extends RefCounted

## EnemyAI.gd
## Handles enemy decision making with Memory Echo integration
## Dodge system applies to both heroes and enemies

# Memory Echo thresholds — must match Enemy.gd's MEMORY_THRESHOLD_* values
const ECHO_TIER_1 = 3    # Notices patterns — 5% dodge
const ECHO_TIER_2 = 7    # Adapting — 10% dodge
const ECHO_TIER_3 = 15   # Fully adapted — 15% dodge

const DODGE_CHANCE_T1 = 0.05
const DODGE_CHANCE_T2 = 0.10
const DODGE_CHANCE_T3 = 0.15

static func _get_encounters(enemy: Character) -> int:
	if enemy is Enemy and GameManager.species_memory.has(enemy.species):
		return GameManager.species_memory[enemy.species]
	return 0

static func get_dodge_chance(enemy: Character) -> float:
	var encounters = _get_encounters(enemy)
	if encounters >= ECHO_TIER_3:
		return DODGE_CHANCE_T3
	elif encounters >= ECHO_TIER_2:
		return DODGE_CHANCE_T2
	elif encounters >= ECHO_TIER_1:
		return DODGE_CHANCE_T1
	return 0.0

static func try_dodge(target: Character, is_resonance: bool = false, can_miss: bool = true) -> bool:
	# Resonance attacks and can't-miss moves always hit
	if is_resonance or not can_miss:
		return false
	var dodge_chance = 0.0
	if target is Enemy:
		dodge_chance = get_dodge_chance(target)
	else:
		# Heroes dodge only while Smoke Veil lasts
		dodge_chance = target.dodge_chance
	return randf() < dodge_chance

static func choose_action(enemy: Character, party: Array[Character], enemies: Array[Character]) -> Dictionary:
	var alive_party = party.filter(func(h): return h.is_alive())
	if alive_party.is_empty():
		return {}

	var encounters = _get_encounters(enemy) if enemy is Enemy else 0
	var echo_tier = _get_echo_tier(encounters)

	# Echo memory steers every enemy's choice, boss or not. Low HP never forces
	# a move (there is no "enrage"); a boss changes how it fights through its
	# phase data instead.
	var chosen_skill = _choose_skill(enemy, alive_party, enemies, echo_tier)

	# Choose target
	var target = _choose_target(enemy, alive_party, enemies, chosen_skill, echo_tier)

	return {
		"skill": chosen_skill,
		"target": target,
		"echo_tier": echo_tier
	}

static func _get_echo_tier(encounters: int) -> int:
	if encounters >= ECHO_TIER_3: return 3
	elif encounters >= ECHO_TIER_2: return 2
	elif encounters >= ECHO_TIER_1: return 1
	return 0

## The skills an enemy may draw from this turn. A boss in a phase that supplies
## its own list uses that list; everything else uses the enemy's own skills.
## Tolerates current_phase() being null — a boss whose first phase is authored
## below full HP is in no phase at all until it takes damage.
static func usable_skills(enemy: Character) -> Array:
	if enemy is Enemy and (enemy as Enemy).is_boss():
		var phase := (enemy as Enemy).current_phase()
		if phase != null and not phase.skills.is_empty():
			return phase.skills
	return enemy.skills

## True for a move that would change nothing if used now, so picking it would
## waste the turn: a heal with nobody it can reach hurt, or a buff or debuff
## that is already on, in full, on everyone it can reach.
static func would_waste_turn(skill: Skill, enemy: Character, allies: Array, foes: Array) -> bool:
	if skill.is_heal():
		return hurt_heal_targets(skill, enemy, allies).is_empty()
	if skill.is_buff() or skill.is_debuff():
		return effect_targets(skill, enemy, allies, foes).is_empty()
	return false

## Everyone still standing that a buff or debuff move can reach and would change.
static func effect_targets(skill: Skill, enemy: Character, allies: Array, foes: Array) -> Array:
	var reach: Array
	match skill.target_type:
		Skill.TargetType.SELF:
			reach = [enemy]
		Skill.TargetType.SINGLE_ALLY, Skill.TargetType.ALL_ALLIES:
			reach = allies
		_:
			reach = foes
	return reach.filter(func(c): return c.is_alive() and _effect_would_change(skill, c))

## Whether a buff or debuff move's effect would change anything on `target`.
static func _effect_would_change(skill: Skill, target: Character) -> bool:
	var parsed := StatusSystem.parse_apply_token(skill.applied_effect())
	match parsed["kind"]:
		"none":
			return false
		"buff":
			return target.stat_effect_would_change(parsed["value"], true, skill.effect_turns)
		"debuff":
			return target.stat_effect_would_change(parsed["value"], false, skill.effect_turns)
	if parsed["value"] == StatusSystem.REGENERATE:
		return target.regen_would_change(BattleManager.REGEN_TURNS)
	return target.status_would_land(parsed["value"])

## The hurt characters a heal could mend: the user alone for a self-heal,
## otherwise every ally still standing who is below full HP.
static func hurt_heal_targets(skill: Skill, enemy: Character, allies: Array) -> Array:
	var reach: Array = [enemy] if skill.target_type == Skill.TargetType.SELF \
			else allies.filter(func(a): return a.is_alive())
	return reach.filter(func(c): return c.current_hp < c.max_hp())

static func _choose_skill(enemy: Character, alive_party: Array, allies: Array, echo_tier: int) -> Skill:
	if usable_skills(enemy).is_empty():
		return null

	# With nothing worth using, no skill: the enemy makes a basic attack.
	var usable = usable_skills(enemy).filter(func(s):
		return s.can_use(enemy) and not would_waste_turn(s, enemy, allies, alive_party))
	if usable.is_empty():
		return null

	var hp_pct = float(enemy.current_hp) / float(enemy.max_hp())

	# Consider healing only if below 75% HP
	var heal_skills = usable.filter(func(s): return s.is_heal())
	if not heal_skills.is_empty() and hp_pct < 0.75:
		# Below 30% HP — 50% chance to heal (max odds)
		if hp_pct < 0.3 and randf() < 0.5:
			return heal_skills[randi() % heal_skills.size()]
		# Below 50% HP with Echo tier 1+ — 25% chance to heal
		elif echo_tier >= 1 and hp_pct < 0.5 and randf() < 0.25:
			return heal_skills[randi() % heal_skills.size()]

	# Echo tier 2+ — prefer super effective skills
	if echo_tier >= 2:
		var effective_skills = usable.filter(func(s):
			if s.skill_type == Skill.SkillType.STATUS:
				return false
			for hero in alive_party:
				if ElementalSystem.get_multiplier(s.element, hero.element) >= ElementalSystem.WEAKNESS_MULTIPLIER:
					return true
			return false
		)
		if not effective_skills.is_empty() and randf() < 0.65:
			return effective_skills[randi() % effective_skills.size()]

	# Echo tier 1 — slightly prefer damaging skills
	if echo_tier >= 1:
		var damage_skills = usable.filter(func(s):
			return s.skill_type == Skill.SkillType.DAMAGE
		)
		if not damage_skills.is_empty() and randf() < 0.5:
			return damage_skills[randi() % damage_skills.size()]

	# Default — fully random among all usable skills
	return usable[randi() % usable.size()]

static func _choose_target(enemy: Character, alive_party: Array, enemies: Array, skill: Skill, echo_tier: int) -> Character:
	# Heal/buff skills — target self or lowest HP ally
	if skill != null:
		if skill.is_heal():
			if skill.target_type == Skill.TargetType.SELF:
				return enemy
			# The most wounded hurt ally, by share of HP lost — never one at
			# full HP, where the heal would do nothing.
			var hurt := hurt_heal_targets(skill, enemy, enemies)
			if not hurt.is_empty():
				hurt.sort_custom(func(a, b):
					return float(a.current_hp) / a.max_hp() < float(b.current_hp) / b.max_hp())
				return hurt[0]
		elif skill.is_buff():
			if skill.target_type == Skill.TargetType.SELF:
				return enemy
			# An ally the buff would change, never one that already has it.
			var changed := effect_targets(skill, enemy, enemies, alive_party)
			if not changed.is_empty():
				return changed[randi() % changed.size()]
		elif skill.is_debuff():
			# Only a hero the debuff would change; echo memory picks among them.
			var changed := effect_targets(skill, enemy, enemies, alive_party)
			if not changed.is_empty():
				alive_party = changed

	# Echo tier 2+ — target hero weak to skill element
	if echo_tier >= 2 and skill != null and skill.element != ElementalSystem.Element.NORMAL:
		var weak_heroes = alive_party.filter(func(h):
			return ElementalSystem.get_multiplier(skill.element, h.element) >= ElementalSystem.WEAKNESS_MULTIPLIER
		)
		if not weak_heroes.is_empty() and randf() < 0.7:
			return weak_heroes[randi() % weak_heroes.size()]

	# Echo tier 1 — sometimes target lowest HP hero
	if echo_tier >= 1 and randf() < 0.4:
		var sorted = alive_party.duplicate()
		sorted.sort_custom(func(a, b): return a.current_hp < b.current_hp)
		return sorted[0]

	# Default — random hero
	return alive_party[randi() % alive_party.size()]
