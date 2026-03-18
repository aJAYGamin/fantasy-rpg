class_name Skill
extends Resource

enum TargetType {
	SINGLE_ENEMY,
	ALL_ENEMIES,
	SINGLE_ALLY,
	ALL_ALLIES,
	SELF
}

enum SkillType {
	PHYSICAL,  # Uses attack stat
	MAGIC,     # Uses magic stat
	HEAL,      # Restores HP
	BUFF,      # Applies positive effect
	DEBUFF     # Applies negative effect
}

@export var skill_name: String = "Attack"
@export var description: String = ""
@export var mp_cost: int = 0
@export var skill_type: SkillType = SkillType.PHYSICAL
@export var target_type: TargetType = TargetType.SINGLE_ENEMY
@export var power: float = 1.0       # Damage/heal multiplier
@export var status_to_apply: String = ""  # Optional status effect
@export var status_chance: float = 0.0    # 0.0 - 1.0

## Calculate the effect value based on the user's stats
func calculate_value(user: Character) -> int:
	match skill_type:
		SkillType.PHYSICAL:
			return int(user.attack_power() * power)
		SkillType.MAGIC, SkillType.DEBUFF:
			return int(user.magic_power() * power)
		SkillType.HEAL, SkillType.BUFF:
			return int(user.magic_power() * power)
	return 0

func can_use(user: Character) -> bool:
	return user.current_mp >= mp_cost and not user.is_status("stun")

func get_target_description() -> String:
	match target_type:
		TargetType.SINGLE_ENEMY: return "One Enemy"
		TargetType.ALL_ENEMIES: return "All Enemies"
		TargetType.SINGLE_ALLY: return "One Ally"
		TargetType.ALL_ALLIES: return "All Allies"
		TargetType.SELF: return "Self"
	return ""
