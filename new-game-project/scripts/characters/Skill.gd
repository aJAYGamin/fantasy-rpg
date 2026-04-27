class_name Skill
extends Resource

enum TargetType {
	SINGLE_ENEMY,
	ALL_ENEMIES,
	SINGLE_ALLY,
	ALL_ALLIES,
	SELF
}

# AttackType — used for gear bonuses and resonance building
# STRIKE: melee physical (swords, axes, fists) — scales with ATK
# RANGED: ranged physical (bows, thrown weapons) — scales with ATK
# MAGIC:  spells (fireballs, ice shards) — scales with MAG
# STATUS: applies status effects, deals no damage — doesn't scale
enum AttackType {
	STRIKE,
	RANGED,
	MAGIC,
	STATUS
}

# SkillType — high-level category for behavior
# DAMAGE: deals damage — builds resonance when used
# HEAL:   restores HP — does NOT build resonance
# BUFF:   enhances allies — does NOT build resonance
enum SkillType {
	DAMAGE,
	HEAL,
	BUFF
}

@export var skill_name: String = "Attack"
@export var description: String = ""
@export var mp_cost: int = 0
@export var skill_type: SkillType = SkillType.DAMAGE
@export var attack_type: AttackType = AttackType.STRIKE
@export var target_type: TargetType = TargetType.SINGLE_ENEMY
@export var power: float = 1.0
@export var element: ElementalSystem.Element = ElementalSystem.Element.NONE
@export var status_to_apply: String = ""
@export var status_chance: float = 0.0
# Resonance override — -1.0 means "use default 10% per damage skill"
# Set positive like 20.0 for +20%, or negative like -10.0 for -10%
@export var resonance_gain_override: float = -1.0

func calculate_value(user: Character) -> int:
	match skill_type:
		SkillType.DAMAGE:
			match attack_type:
				AttackType.STRIKE, AttackType.RANGED:
					return int(user.attack_power() * power)
				AttackType.MAGIC:
					return int(user.magic_power() * power)
				AttackType.STATUS:
					return 0
		SkillType.HEAL:
			return int(user.magic_power() * power)
		SkillType.BUFF:
			return int(user.magic_power() * power)
	return 0

func can_use(user: Character) -> bool:
	return user.current_mp >= mp_cost and not user.is_status("stun")

# Returns the resonance percentage this skill grants on use
# 10% default for damage skills, 0% for heal/buff, override if set
func get_resonance_gain() -> float:
	if resonance_gain_override >= 0.0:
		return resonance_gain_override
	if skill_type == SkillType.DAMAGE:
		return 10.0
	return 0.0

func is_physical() -> bool:
	return skill_type == SkillType.DAMAGE and (attack_type == AttackType.STRIKE or attack_type == AttackType.RANGED)

func is_magic() -> bool:
	return skill_type == SkillType.DAMAGE and attack_type == AttackType.MAGIC

func get_target_description() -> String:
	match target_type:
		TargetType.SINGLE_ENEMY: return "One Enemy"
		TargetType.ALL_ENEMIES:  return "All Enemies"
		TargetType.SINGLE_ALLY:  return "One Ally"
		TargetType.ALL_ALLIES:   return "All Allies"
		TargetType.SELF:         return "Self"
	return ""

func get_attack_type_display() -> String:
	match attack_type:
		AttackType.STRIKE: return "Strike"
		AttackType.RANGED: return "Ranged"
		AttackType.MAGIC:  return "Magic"
		AttackType.STATUS: return "Status"
	return ""

# Returns a display string for the skill's high-level type
func get_skill_type_display() -> String:
	match skill_type:
		SkillType.DAMAGE:
			return get_attack_type_display()
		SkillType.HEAL:
			return "Heal"
		SkillType.BUFF:
			return "Buff"
	return ""

func get_element_display() -> String:
	if element == ElementalSystem.Element.NONE:
		return ""
	return "%s %s" % [
		ElementalSystem.get_element_icon(element),
		ElementalSystem.get_element_name(element)
	]
