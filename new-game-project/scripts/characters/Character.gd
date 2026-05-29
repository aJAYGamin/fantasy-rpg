class_name Character
extends Resource

## Base class for all playable characters and enemies

@export var character_name: String = "Unknown"
@export var character_class: String = "Warrior"
@export var portrait: Texture2D

# --- Core Stats ---
@export var base_hp: int = 100
@export var base_mp: int = 50
@export var base_attack: int = 10
@export var base_defense: int = 5
@export var base_magic: int = 5     # Magic attack power
@export var base_arcane: int = 5     # Magic resistance — reduces incoming magic damage like DEF reduces physical
@export var base_speed: int = 10

# --- Elemental Affinity ---
# Characters can be single- or dual-typed. secondary_element = NORMAL means
# single-typed (NORMAL acts as the "no secondary" sentinel except when the
# primary itself is intentionally NORMAL).
@export var element: ElementalSystem.Element = ElementalSystem.Element.NORMAL
@export var secondary_element: ElementalSystem.Element = ElementalSystem.Element.NORMAL
@export var extra_weakness: ElementalSystem.Element = ElementalSystem.Element.NORMAL
@export var extra_resistance: ElementalSystem.Element = ElementalSystem.Element.NORMAL

# --- Runtime State ---
var current_hp: int
var current_mp: int
# Amethyst Resonance meter (0–100). Persists across battles like current HP/MP —
# only resonance attacks reset it (or future "drain"-style enemy effects).
var resonance_meter: float = 0.0
const XP_BASE := 100      # XP needed for the first level-up (Lv 1 → 2)
const XP_GROWTH := 1.5    # each level requires 50% more than the previous
@export var level: int = 1
var experience: int = 0
var experience_to_next: int = XP_BASE

# --- Inventory ---
var inventory: Inventory

# --- Skills ---
@export var skills: Array[Skill] = []

# --- Status Effects ---
var status_effects: Array[String] = []
# Per-stat buff/debuff state — keys are StatusSystem stat names (attack/defense/
# magic/arcane/speed), values are bool. A stat with BOTH buffs[stat]==true AND
# debuffs[stat]==true is "cancelled" — they net to 1.0x and render no chip.
# Cleared at battle end via clear_battle_effects().
var buffs: Dictionary = {}
var debuffs: Dictionary = {}
# Sleep tracker — increments each turn the actor stays asleep. Used by
# StatusSystem.resolve_turn_skip() to ramp wake chance: 0 -> 100% sleep,
# 1 -> 75%, 2 -> 50%, 3 -> 25%, 4 -> guaranteed wake.
var sleep_turn: int = 0

func _init():
	current_hp = max_hp()
	current_mp = max_mp()
	inventory = Inventory.new()

# --- Stat Calculations ---
func max_hp() -> int:
	return base_hp + (level - 1) * 15

func max_mp() -> int:
	return base_mp + (level - 1) * 8

func attack_power() -> int:
	var weapon_bonus = inventory.get_weapon_attack()
	var raw = base_attack + (level - 1) * 2 + weapon_bonus
	return StatusSystem.compose_stat(raw, self, StatusSystem.STAT_ATK)

func defense_power() -> int:
	var armor_bonus = inventory.get_armor_defense()
	var raw = base_defense + (level - 1) * 1 + armor_bonus
	return StatusSystem.compose_stat(raw, self, StatusSystem.STAT_DEF)

func magic_power() -> int:
	var raw = base_magic + (level - 1) * 2
	return StatusSystem.compose_stat(raw, self, StatusSystem.STAT_MAG)

# Magic resistance — analogous to defense_power() but for magic damage.
func arcane_power() -> int:
	var raw = base_arcane + (level - 1) * 1
	return StatusSystem.compose_stat(raw, self, StatusSystem.STAT_ARC)

func speed() -> int:
	var raw = base_speed + (level - 1) * 1
	return StatusSystem.compose_stat(raw, self, StatusSystem.STAT_SPD)

func is_alive() -> bool:
	return current_hp > 0

func is_status(effect: String) -> bool:
	return effect in status_effects

# --- Combat ---
# Both functions accept an optional `attack_secondary_element` so dual-element
# attackers/skills (e.g. resonance attacks Fire+Water) compute the full
# dual-type multiplier against this character's primary + secondary elements.
func take_damage(amount: int, attack_element: ElementalSystem.Element = ElementalSystem.Element.NORMAL,
		attack_secondary_element: ElementalSystem.Element = ElementalSystem.Element.NORMAL) -> Dictionary:
	var multiplier = ElementalSystem.get_combined_multiplier(
		attack_element, attack_secondary_element, element, secondary_element)

	if extra_weakness != ElementalSystem.Element.NORMAL and attack_element == extra_weakness:
		multiplier *= 1.5
	if extra_resistance != ElementalSystem.Element.NORMAL and attack_element == extra_resistance:
		multiplier *= 0.6

	var base_damage = max(1, amount - defense_power())
	var final_damage = max(1, int(base_damage * multiplier))
	current_hp = max(0, current_hp - final_damage)

	return {
		"damage": final_damage,
		"multiplier": multiplier,
		"effectiveness": ElementalSystem.get_effectiveness_text(multiplier),
		"effectiveness_color": ElementalSystem.get_effectiveness_color(multiplier)
	}

func take_magic_damage(amount: int, attack_element: ElementalSystem.Element = ElementalSystem.Element.NORMAL,
		attack_secondary_element: ElementalSystem.Element = ElementalSystem.Element.NORMAL) -> Dictionary:
	var multiplier = ElementalSystem.get_combined_multiplier(
		attack_element, attack_secondary_element, element, secondary_element)

	if extra_weakness != ElementalSystem.Element.NORMAL and attack_element == extra_weakness:
		multiplier *= 1.5
	if extra_resistance != ElementalSystem.Element.NORMAL and attack_element == extra_resistance:
		multiplier *= 0.6

	# Mirror physical damage: subtract the defender's arcane (magic resistance)
	# before applying the element multiplier.
	var base_damage = max(1, amount - arcane_power())
	var final_damage = max(1, int(base_damage * multiplier))
	current_hp = max(0, current_hp - final_damage)

	return {
		"damage": final_damage,
		"multiplier": multiplier,
		"effectiveness": ElementalSystem.get_effectiveness_text(multiplier),
		"effectiveness_color": ElementalSystem.get_effectiveness_color(multiplier)
	}

func heal(amount: int) -> int:
	var actual_heal = min(amount, max_hp() - current_hp)
	current_hp += actual_heal
	return actual_heal

func restore_mp(amount: int) -> int:
	var actual_restore = min(amount, max_mp() - current_mp)
	current_mp += actual_restore
	return actual_restore

func use_mp(amount: int) -> bool:
	if current_mp >= amount:
		current_mp -= amount
		return true
	return false

func add_status(effect: String):
	# Mutex statuses are first-come-first-served — if the character already has
	# ANY mutex status, the new one is rejected. This gives the player a window
	# to cleanse before stacking up; statuses can't pile on top of each other.
	# Non-mutex statuses (regenerate, defending) are unaffected.
	if effect in StatusSystem.MUTEX_STATUSES:
		for existing in StatusSystem.MUTEX_STATUSES:
			if is_status(existing):
				# Already has a mutex status — drop the new application entirely.
				return
		# No mutex status active yet — applying a fresh sleep starts the wake
		# counter at 0 (= 100% sleep on first turn).
		if effect == StatusSystem.SLEEP:
			sleep_turn = 0
	if not is_status(effect):
		status_effects.append(effect)

func has_status(effect: String) -> bool:
	return effect in status_effects

func remove_status(effect: String):
	status_effects.erase(effect)
	# Reset sleep counter when sleep is cleared (heal, wake, status replaced).
	if effect == StatusSystem.SLEEP:
		sleep_turn = 0

# --- Buff / Debuff ---
# Each stat can be buffed (x2.0) or debuffed (x0.5). Both present cancels
# to x1.0 (no chip). Applying a buff to a debuffed stat removes the debuff
# (and vice versa) — net is unbuffed. Stacking is intentionally disabled.
# Returns a Dictionary describing the outcome for UI/log messages.
func apply_buff(stat: String) -> Dictionary:
	if not (stat in StatusSystem.BUFFABLE_STATS):
		return {"action": "invalid", "stat": stat}
	if debuffs.get(stat, false):
		debuffs[stat] = false
		return {"action": "cancelled_debuff", "stat": stat}
	if buffs.get(stat, false):
		return {"action": "noop", "stat": stat}
	buffs[stat] = true
	return {"action": "buffed", "stat": stat}

func apply_debuff(stat: String) -> Dictionary:
	if not (stat in StatusSystem.BUFFABLE_STATS):
		return {"action": "invalid", "stat": stat}
	if buffs.get(stat, false):
		buffs[stat] = false
		return {"action": "cancelled_buff", "stat": stat}
	if debuffs.get(stat, false):
		return {"action": "noop", "stat": stat}
	debuffs[stat] = true
	return {"action": "debuffed", "stat": stat}

# Clears all temporary battle state. Call this at end of every battle so
# status/buffs/debuffs do NOT leak into the next encounter.
func clear_battle_effects():
	status_effects.clear()
	buffs.clear()
	debuffs.clear()
	sleep_turn = 0

# Per-turn status processing.
# Returns Array of events for UI to render (e.g. tick damage, regen heal).
# Tick damage from poison/scorched/frostbite is resolved here. Sleep/paralysis
# skip-checks are NOT here — they're handled in StatusSystem.resolve_turn_skip
# at the BattleManager turn-start (separate from tick damage).
func process_status_effects() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	# Damage-over-time statuses (mutex group — at most one applies)
	var tick_status := StatusSystem.get_active_tick_status(self)
	if tick_status != "":
		var dmg := StatusSystem.get_tick_damage(self)
		if dmg > 0:
			current_hp = max(0, current_hp - dmg)
			results.append({"type": tick_status, "value": dmg})
	# Positive non-mutex statuses (kept independent so they CAN coexist with
	# the mutex pool — a poisoned hero can still regenerate from an item).
	if is_status(StatusSystem.REGENERATE):
		var heal_amt: int = max(1, max_hp() / 8)
		heal(heal_amt)
		results.append({"type": StatusSystem.REGENERATE, "value": heal_amt})
	return results

# --- Leveling ---
func gain_experience(amount: int) -> bool:
	experience += amount
	var leveled = false
	# Handle multiple level ups from one batch of EXP
	while experience >= experience_to_next:
		level_up()
		leveled = true
	return leveled

func level_up():
	level += 1
	# Carry over remaining EXP to next level
	experience -= experience_to_next
	# Scale EXP requirement — each level needs 50% more than the last
	experience_to_next = int(experience_to_next * XP_GROWTH)
	# Current HP/MP intentionally NOT restored — leveling raises max but keeps current.
	_learn_skills_at_level()

func _learn_skills_at_level():
	pass

# Total XP earned across this character's whole life: every threshold crossed to
# reach the current level, plus current progress toward the next. Mirrors the
# XP_BASE × XP_GROWTH progression in level_up() (int-truncated each step).
func total_experience_earned() -> int:
	var total := experience
	var threshold := XP_BASE
	for _i in range(level - 1):
		total += threshold
		threshold = int(threshold * XP_GROWTH)
	return total

func get_stats_summary() -> Dictionary:
	return {
		"name": character_name,
		"class": character_class,
		"level": level,
		"hp": "%d/%d" % [current_hp, max_hp()],
		"mp": "%d/%d" % [current_mp, max_mp()],
		"attack": attack_power(),
		"defense": defense_power(),
		"magic": magic_power(),
		"arcane": arcane_power(),
		"speed": speed(),
		"element": ElementalSystem.get_element_name(element),
		"exp": "%d/%d" % [experience, experience_to_next]
	}
