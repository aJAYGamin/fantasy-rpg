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
# STATUS: heals, buffs, or debuffs — sub-category set via status_type — does NOT build resonance
enum SkillType {
	DAMAGE,
	STATUS
}

# StatusType — sub-category for SkillType.STATUS skills
enum StatusType {
	HEAL,
	BUFF,
	DEBUFF
}

@export var skill_name: String = "Attack"
@export var description: String = ""
@export var mp_cost: int = 0
@export var skill_type: SkillType = SkillType.DAMAGE
@export var attack_type: AttackType = AttackType.STRIKE
@export var status_type: StatusType = StatusType.HEAL
@export var target_type: TargetType = TargetType.SINGLE_ENEMY
@export var power: float = 1.0
@export var element: ElementalSystem.Element = ElementalSystem.Element.NORMAL
# Optional second element for dual-element skills (e.g. combined resonance attacks
# like Aquatic Pyre = Fire + Water). NORMAL means "single-typed".
@export var secondary_element: ElementalSystem.Element = ElementalSystem.Element.NORMAL
@export var status_to_apply: String = ""
@export var status_chance: float = 0.0
# Resonance override — -1.0 means "use default 10% per damage skill"
# Set positive like 20.0 for +20%, or negative like -10.0 for -10%
@export var resonance_gain_override: float = -1.0

# P8: the character level at which this skill becomes usable. 1 means "known
# from the start", which is the default — so enemy skills and every existing
# .tres are unaffected and only heroes opt into a learning curve.
@export var unlock_level: int = 1

# Which battle menu this skill belongs to. Character.skills is a mixed POOL of
# everything a hero can learn (up to Character.MAX_SKILLS), so the menu a skill
# belongs to can no longer be inferred from its index the way it was when every
# hero had exactly 4 attacks then 4 specials.
enum SkillCategory { ATTACK, SPECIAL }
@export var category: SkillCategory = SkillCategory.ATTACK

## The library file this move was loaded from ("" for a move with no file).
## Set on each hero's own copy; read by SaveSerializer to save the move by
## reference, so an edited move file reaches existing saves. Library files
## themselves leave it empty.
@export var source_path: String = ""

# --- Spec B: move options ----------------------------------------------------
# Every option below defaults to "off", so a move that does not set it behaves
# exactly as before. These DESCRIBE a move; the resolver keeps all per-use
# state on the Character / BattleManager — a Skill is read-only at runtime
# (enemies share the library's cached objects).

enum BonusCondition { NONE, TARGET_AFFLICTED, USER_HP_LOW }
enum ScaleWith { NONE, HP, MP, RESONANCE }

## USER_HP_LOW holds while the user's HP fraction is strictly below this.
const LOW_HP_THRESHOLD := 0.3
## Scaling runs between these multipliers.
const SCALE_MIN := 0.75
const SCALE_MAX := 1.5

@export_group("Costs")
## The user pays this % of their MAX HP, rounded up. It can never knock them
## out — the move is unusable instead. Enemies pay it too.
@export var hp_cost_percent: float = 0.0
## Heroes spend this much of the 0–100 resonance meter. Enemies ignore it.
@export var resonance_cost: float = 0.0

@export_group("Hits")
## Damage moves strike each target this many times.
@export var hit_count: int = 1
## Fraction (0–1) of the target's DEF (physical) or ARC (magic) ignored.
@export var pierce: float = 0.0

@export_group("Extra")
## After the hits, heals every living member of the user's side by MAG × this.
@export var ally_heal_power: float = 0.0

@export_group("Conditional")
@export var bonus_condition: BonusCondition = BonusCondition.NONE
## Damage multiplier while bonus_condition holds.
@export var bonus_multiplier: float = 1.5
## The one defender element this move treats differently. NORMAL = no override
## (the codebase's existing "not set" convention for elements).
@export var override_element: ElementalSystem.Element = ElementalSystem.Element.NORMAL
## false: effective (1x) against override_element. true: super-effective (2x).
@export var override_super: bool = false

@export_group("Scaling")
## The user's own pool this move's damage scales with.
@export var scale_with: ScaleWith = ScaleWith.NONE
## true: a fuller pool hits harder. false: an emptier pool hits harder.
@export var scale_more_is_stronger: bool = true

@export_group("Trade-offs")
## A stat ("attack"/"defense"/"magic"/"arcane"/"speed") lowered on the user
## after the move.
@export var self_debuff: String = ""
## The user takes this % of the damage the move dealt. Never knocks them out.
@export var recoil_percent: float = 0.0
## The move's own chance (0–1) to miss each opponent, separate from dodging.
@export var miss_chance: float = 0.0
## A stat raised on every target the move hit.
@export var target_buff: String = ""
@export_group("")

func is_attack_category() -> bool:
	return category == SkillCategory.ATTACK

func is_special_category() -> bool:
	return category == SkillCategory.SPECIAL

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
		SkillType.STATUS:
			if status_type == StatusType.HEAL:
				return int(user.magic_power() * power)
			return 0
	return 0

## HP this move costs `user`, rounded up; 0 when it has no HP cost.
func hp_cost(user: Character) -> int:
	if hp_cost_percent <= 0.0:
		return 0
	return ceili(user.max_hp() * hp_cost_percent / 100.0)

func can_use(user: Character) -> bool:
	if user.is_status("stun"):
		return false
	# An HP cost may never knock the user out — on either side, since enemies
	# have HP too. The move greys out instead.
	if hp_cost_percent > 0.0 and user.current_hp <= hp_cost(user):
		return false
	# Enemies ignore MP and resonance costs entirely — they have neither pool —
	# and may use any skill they own. Only heroes pay MP and resonance.
	if user is Enemy:
		return true
	if resonance_cost > 0.0 and user.resonance_meter < resonance_cost:
		return false
	return user.current_mp >= mp_cost

func get_resonance_gain() -> float:
	# A move that SPENDS resonance builds none, or it would refund its own cost.
	if resonance_cost > 0.0:
		return 0.0
	if resonance_gain_override >= 0.0:
		return resonance_gain_override
	if skill_type == SkillType.DAMAGE:
		return 10.0
	return 0.0

func is_physical() -> bool:
	return skill_type == SkillType.DAMAGE and (attack_type == AttackType.STRIKE or attack_type == AttackType.RANGED)

func is_magic() -> bool:
	return skill_type == SkillType.DAMAGE and attack_type == AttackType.MAGIC

func is_heal() -> bool:
	return skill_type == SkillType.STATUS and status_type == StatusType.HEAL

func is_buff() -> bool:
	return skill_type == SkillType.STATUS and status_type == StatusType.BUFF

func is_debuff() -> bool:
	return skill_type == SkillType.STATUS and status_type == StatusType.DEBUFF

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
		SkillType.STATUS:
			match status_type:
				StatusType.HEAL: return "Heal"
				StatusType.BUFF: return "Buff"
				StatusType.DEBUFF: return "Debuff"
	return ""

func get_element_display() -> String:
	return "%s %s" % [
		ElementalSystem.get_element_icon(element),
		ElementalSystem.get_element_name(element)
	]

# --- Spec B: maths for the resolver -------------------------------------------

## The damage multiplier from this move's scaling, read from the user's OWN
## pool: SCALE_MIN at one end, SCALE_MAX at the other. A pool the user lacks
## (an enemy's MP or resonance) gives 1x.
func scale_factor(user: Character) -> float:
	var fill := 0.0
	match scale_with:
		ScaleWith.NONE:
			return 1.0
		ScaleWith.HP:
			fill = float(user.current_hp) / float(maxi(1, user.max_hp()))
		ScaleWith.MP:
			if user is Enemy or user.max_mp() <= 0:
				return 1.0
			fill = float(user.current_mp) / float(user.max_mp())
		ScaleWith.RESONANCE:
			if user is Enemy:
				return 1.0
			fill = user.resonance_meter / 100.0
	fill = clampf(fill, 0.0, 1.0)
	if not scale_more_is_stronger:
		fill = 1.0 - fill
	return lerpf(SCALE_MIN, SCALE_MAX, fill)

## The damage multiplier from this move's condition against `target`.
## `user_hp_fraction` is measured before the move's costs are paid.
func condition_multiplier(user_hp_fraction: float, target: Character) -> float:
	match bonus_condition:
		BonusCondition.TARGET_AFFLICTED:
			return bonus_multiplier if is_afflicted(target) else 1.0
		BonusCondition.USER_HP_LOW:
			return bonus_multiplier if user_hp_fraction < LOW_HP_THRESHOLD else 1.0
	return 1.0

## True when `c` has an active status (poison, stun, …) or any stat debuff.
static func is_afflicted(c: Character) -> bool:
	if StatusSystem.get_active_mutex_status(c) != "":
		return true
	for stat in StatusSystem.BUFFABLE_STATS:
		if StatusSystem.is_effectively_debuffed(c, stat):
			return true
	return false

## The multiplier the element override uses for its one pairing.
func override_multiplier() -> float:
	return ElementalSystem.WEAKNESS_MULTIPLIER if override_super else 1.0

# --- Spec B: what menus show ------------------------------------------------------

## The move's costs as labelled pieces for the menus, in MP, HP, resonance
## order — e.g. [{"kind": "mp", "text": "12 MP"}]. A free move returns [].
func cost_parts() -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	if mp_cost > 0:
		parts.append({"kind": "mp", "text": "%d MP" % mp_cost})
	if hp_cost_percent > 0.0:
		parts.append({"kind": "hp", "text": "%s%% HP" % _num(hp_cost_percent)})
	if resonance_cost > 0.0:
		parts.append({"kind": "resonance", "text": "%s ✦" % _num(resonance_cost)})
	return parts

## The costs joined for menus that show one label ("12 MP · 15% HP").
func cost_text() -> String:
	var texts: Array[String] = []
	for p in cost_parts():
		texts.append(p["text"])
	return " · ".join(texts)

## A short line generated from the move's options — e.g. "2 hits · Ignores
## ARC". Generated from data, so it can never promise what the move does not
## do (hand-written descriptions drifting from the data is how the five
## "honest skill" gaps happened).
func effect_tags() -> Array[String]:
	var tags: Array[String] = []
	var def_name := "ARC" if attack_type == AttackType.MAGIC else "DEF"
	if skill_type == SkillType.DAMAGE and hit_count > 1:
		tags.append("%d hits" % hit_count)
	if pierce >= 1.0:
		tags.append("Ignores %s" % def_name)
	elif pierce > 0.0:
		tags.append("Ignores %d%% %s" % [int(round(pierce * 100.0)), def_name])
	if skill_type == SkillType.DAMAGE and status_to_apply != "" and status_chance > 0.0:
		tags.append("%d%% chance: %s" % [int(round(status_chance * 100.0)), _effect_phrase(status_to_apply)])
	if skill_type == SkillType.STATUS and status_type == StatusType.HEAL and status_to_apply != "":
		tags.append(_effect_phrase(status_to_apply))
	if ally_heal_power > 0.0:
		tags.append("Heals allies")
	match bonus_condition:
		BonusCondition.TARGET_AFFLICTED:
			tags.append("×%s vs afflicted" % _num(bonus_multiplier))
		BonusCondition.USER_HP_LOW:
			tags.append("×%s below %d%% HP" % [_num(bonus_multiplier), int(round(LOW_HP_THRESHOLD * 100.0))])
	if override_element != ElementalSystem.Element.NORMAL:
		tags.append("%s vs %s" % ["Super-effective" if override_super else "Effective",
				ElementalSystem.get_element_name(override_element)])
	if scale_with != ScaleWith.NONE:
		var pool: String = {ScaleWith.HP: "HP", ScaleWith.MP: "MP", ScaleWith.RESONANCE: "resonance"}[scale_with]
		tags.append("Stronger with %s %s" % ["more" if scale_more_is_stronger else "less", pool])
	if recoil_percent > 0.0:
		tags.append("%s%% recoil" % _num(recoil_percent))
	if miss_chance > 0.0:
		tags.append("%d%% miss chance" % int(round(miss_chance * 100.0)))
	if self_debuff != "":
		tags.append("Lowers your %s" % StatusSystem.STAT_SHORT.get(self_debuff, self_debuff.to_upper()))
	if target_buff != "":
		tags.append("Raises target's %s" % StatusSystem.STAT_SHORT.get(target_buff, target_buff.to_upper()))
	return tags

## The tags joined for display.
func effect_text() -> String:
	return " · ".join(effect_tags())

## 12.0 -> "12", 12.5 -> "12.5", 1.75 -> "1.75" (up to two decimals, no
## trailing zeros). String.num(v, 2) already drops the zeros from 12.50 but
## leaves a whole number as "12.0", so that last ".0" is trimmed here.
static func _num(v: float) -> String:
	return String.num(v, 2).trim_suffix(".0")

## "Lowers SPD", "Raises ATK", "Regenerates", or a status name ("Scorched").
static func _effect_phrase(token: String) -> String:
	if token == StatusSystem.REGENERATE:
		return "Regenerates"
	for stat in StatusSystem.BUFFABLE_STATS:
		if token == stat + "_debuff":
			return "Lowers %s" % StatusSystem.STAT_SHORT[stat]
		if token == stat + "_buff":
			return "Raises %s" % StatusSystem.STAT_SHORT[stat]
	return StatusSystem.STATUS_LABELS.get(token, token.capitalize())
