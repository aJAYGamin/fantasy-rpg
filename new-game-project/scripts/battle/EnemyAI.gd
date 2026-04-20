class_name EnemyAI
extends RefCounted

## EnemyAI.gd
## Handles enemy decision making with Memory Echo integration
## Dodge system applies to both heroes and enemies

# Memory Echo thresholds
const ECHO_TIER_1 = 10   # Notices patterns — 5% dodge
const ECHO_TIER_2 = 15   # Adapting — 10% dodge
const ECHO_TIER_3 = 20   # Fully adapted — 15% dodge

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
		# Heroes can have dodge from buffs/items
		dodge_chance = target.get_meta("dodge_chance", 0.0)
	return randf() < dodge_chance

static func choose_action(enemy: Character, party: Array[Character], enemies: Array[Character]) -> Dictionary:
	var alive_party = party.filter(func(h): return h.is_alive())
	if alive_party.is_empty():
		return {}

	var encounters = _get_encounters(enemy) if enemy is Enemy else 0
	var echo_tier = _get_echo_tier(encounters)

	# Low HP enrage — always use strongest attack
	var hp_pct = float(enemy.current_hp) / float(enemy.max_hp())
	var is_enraged = hp_pct < 0.25

	# Choose skill
	var chosen_skill = _choose_skill(enemy, alive_party, echo_tier, is_enraged)

	# Choose target
	var target = _choose_target(enemy, alive_party, enemies, chosen_skill, echo_tier)

	return {
		"skill": chosen_skill,
		"target": target,
		"is_enraged": is_enraged,
		"echo_tier": echo_tier
	}

static func _get_echo_tier(encounters: int) -> int:
	if encounters >= ECHO_TIER_3: return 3
	elif encounters >= ECHO_TIER_2: return 2
	elif encounters >= ECHO_TIER_1: return 1
	return 0

static func _choose_skill(enemy: Character, alive_party: Array, echo_tier: int, is_enraged: bool) -> Skill:
	if enemy.skills.is_empty():
		return null

	var usable = enemy.skills.filter(func(s): return s.can_use(enemy))
	if usable.is_empty():
		return null

	var hp_pct = float(enemy.current_hp) / float(enemy.max_hp())

	# Consider healing only if below 75% HP
	var heal_skills = usable.filter(func(s): return s.skill_type == Skill.SkillType.HEAL)
	if not heal_skills.is_empty() and hp_pct < 0.75:
		# Below 30% HP — 50% chance to heal (max odds)
		if hp_pct < 0.3 and randf() < 0.5:
			return heal_skills[randi() % heal_skills.size()]
		# Below 50% HP with Echo tier 1+ — 25% chance to heal
		elif echo_tier >= 1 and hp_pct < 0.5 and randf() < 0.25:
			return heal_skills[randi() % heal_skills.size()]

	# Enraged — always pick highest power damaging skill
	if is_enraged:
		var dmg_skills = usable.filter(func(s):
			return s.skill_type == Skill.SkillType.DAMAGE
		)
		if not dmg_skills.is_empty():
			dmg_skills.sort_custom(func(a, b): return a.power > b.power)
			return dmg_skills[0]

	# Echo tier 2+ — prefer super effective skills
	if echo_tier >= 2:
		var effective_skills = usable.filter(func(s):
			if s.skill_type == Skill.SkillType.HEAL or s.skill_type == Skill.SkillType.BUFF:
				return false
			for hero in alive_party:
				if ElementalSystem.get_multiplier(s.element, hero.element) >= 2.0:
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
		if skill.skill_type == Skill.SkillType.HEAL:
			if skill.target_type == Skill.TargetType.SELF:
				return enemy
			# Target most wounded ally
			var alive_enemies = enemies.filter(func(e): return e.is_alive())
			if not alive_enemies.is_empty():
				alive_enemies.sort_custom(func(a, b): return a.current_hp < b.current_hp)
				return alive_enemies[0]
		elif skill.skill_type == Skill.SkillType.BUFF:
			if skill.target_type == Skill.TargetType.SELF:
				return enemy
			var alive_enemies = enemies.filter(func(e): return e.is_alive())
			if not alive_enemies.is_empty():
				return alive_enemies[randi() % alive_enemies.size()]

	# Echo tier 2+ — target hero weak to skill element
	if echo_tier >= 2 and skill != null and skill.element != ElementalSystem.Element.NONE:
		var weak_heroes = alive_party.filter(func(h):
			return ElementalSystem.get_multiplier(skill.element, h.element) >= 2.0
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
