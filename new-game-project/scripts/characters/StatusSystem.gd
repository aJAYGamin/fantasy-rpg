class_name StatusSystem
extends RefCounted

## Central registry for status effects and stat buff/debuff bookkeeping.
##
## Two systems live here:
##   1. Mutex statuses (stun/poison/paralysis/sleep/scorched/frostbite). A
##      character can have at most ONE of these at a time. Applying a new one
##      replaces any existing mutex status. Each has bespoke per-turn behavior
##      (tick damage, skip chance, stat penalty) defined here.
##   2. Buff/debuff per stat (atk/def/mag/arc/spd). Each stat can independently
##      be buffed (x2.0) or debuffed (x0.5), or have BOTH (which cancel to x1.0
##      with no indicator). Stacking is intentionally disabled — re-applying a
##      buff to an already-buffed stat is a no-op.
##
## Both are CLEARED at battle end (BattleScene._on_battle_ended).

# --- Mutex status name constants ---
const STUN := "stun"
const POISON := "poison"
const PARALYSIS := "paralysis"
const SLEEP := "sleep"
const SCORCHED := "scorched"
const FROSTBITE := "frostbite"
# Positive/legacy non-mutex statuses (kept for compatibility — items, future skills)
const REGENERATE := "regenerate"
const DEFENDING := "defending"

const MUTEX_STATUSES := [STUN, POISON, PARALYSIS, SLEEP, SCORCHED, FROSTBITE]

# --- Stat name constants (used by buff/debuff dicts and skill .tres) ---
const STAT_ATK := "attack"
const STAT_DEF := "defense"
const STAT_MAG := "magic"
const STAT_ARC := "arcane"
const STAT_SPD := "speed"

const BUFFABLE_STATS := [STAT_ATK, STAT_DEF, STAT_MAG, STAT_ARC, STAT_SPD]

# Display labels for the UI chips. Keep short — chips have limited width.
const STAT_SHORT := {
	STAT_ATK: "ATK",
	STAT_DEF: "DEF",
	STAT_MAG: "MAG",
	STAT_ARC: "ARC",
	STAT_SPD: "SPD",
}

# --- Skill.status_to_apply tokens that route to apply_buff/debuff instead of
# add_status. Format is "<stat>_buff" / "<stat>_debuff". ---
const BUFF_SUFFIX := "_buff"
const DEBUFF_SUFFIX := "_debuff"

# --- Color palette per mutex status (used by chip backgrounds) ---
const STATUS_COLORS := {
	STUN: Color(1.00, 0.92, 0.30),       # bright yellow
	POISON: Color(0.62, 0.30, 0.85),     # toxic purple
	PARALYSIS: Color(0.95, 0.75, 0.20),  # amber
	SLEEP: Color(0.50, 0.65, 1.00),      # dream blue
	SCORCHED: Color(0.95, 0.40, 0.18),   # ember orange-red
	FROSTBITE: Color(0.60, 0.85, 1.00),  # ice blue
	REGENERATE: Color(0.40, 1.00, 0.55), # vital green
	DEFENDING: Color(0.75, 0.75, 0.85),  # steel grey-blue
}

const STATUS_LABELS := {
	STUN: "Stun",
	POISON: "Poison",
	PARALYSIS: "Paralysis",
	SLEEP: "Sleep",
	SCORCHED: "Scorched",
	FROSTBITE: "Frostbite",
	REGENERATE: "Regen",
	DEFENDING: "Defend",
}

# Compact icon glyph per status (single char, shown in chip).
const STATUS_ICONS := {
	STUN: "⚡",
	POISON: "☠",
	PARALYSIS: "✦",
	SLEEP: "z",
	SCORCHED: "🔥",
	FROSTBITE: "❄",
	REGENERATE: "♥",
	DEFENDING: "🛡",
}

# Tick damage fraction-of-max-HP at start of affected actor's turn.
# Statuses not listed here do no tick damage.
const TICK_FRACTIONS := {
	POISON: 0.10,      # 1/10
	SCORCHED: 0.05,    # 1/20
	FROSTBITE: 0.05,   # 1/20
}

# Per-status stat penalty multipliers applied ON TOP of buff/debuff multipliers.
# Status penalties don't compose linearly with buffs — they're a separate axis.
# Returns 1.0 when stat is unaffected by the character's current status.
static func get_status_stat_multiplier(character, stat: String) -> float:
	if character == null:
		return 1.0
	if character.is_status(SCORCHED) and stat == STAT_ATK:
		return 0.5
	if character.is_status(FROSTBITE) and stat == STAT_MAG:
		return 0.5
	if character.is_status(PARALYSIS) and stat == STAT_SPD:
		return 0.75
	return 1.0

# Buff/debuff multiplier. Cancels to 1.0 when both are present (per design).
# Buffs cannot stack — at most one of each per stat.
static func get_buff_multiplier(character, stat: String) -> float:
	if character == null:
		return 1.0
	var is_buffed: bool = bool(character.buffs.get(stat, false))
	var is_debuffed: bool = bool(character.debuffs.get(stat, false))
	if is_buffed and is_debuffed:
		return 1.0
	if is_buffed:
		return 2.0
	if is_debuffed:
		return 0.5
	return 1.0

# Convenience: combined multiplier (buff * status) applied to a base stat value.
static func compose_stat(base_value: int, character, stat: String) -> int:
	var m := get_buff_multiplier(character, stat) * get_status_stat_multiplier(character, stat)
	return max(0, int(round(base_value * m)))

# UI helpers — should this stat show a buff-up chip / debuff-down chip?
# Cancelled (both present) shows nothing.
static func is_effectively_buffed(character, stat: String) -> bool:
	if character == null:
		return false
	return bool(character.buffs.get(stat, false)) and not bool(character.debuffs.get(stat, false))

static func is_effectively_debuffed(character, stat: String) -> bool:
	if character == null:
		return false
	return bool(character.debuffs.get(stat, false)) and not bool(character.buffs.get(stat, false))

# Returns the active mutex status name, or "" if none. Used by UI to render
# the single status chip.
static func get_active_mutex_status(character) -> String:
	if character == null:
		return ""
	for status in MUTEX_STATUSES:
		if character.is_status(status):
			return status
	return ""

# --- Turn-start resolution ---

# Resolves all per-turn-start "do I act?" rules. Returns a Dictionary:
#   { "skip": "stun"|"sleep"|"paralysis"|"", "woke_up": bool }
# MUTATES the character (stun auto-clears; sleep counter advances; sleep wake
# clears the status).
#
# Resolution order:
#   stun       → always skip, auto-clear (consumed)
#   sleep      → roll wake chance; if still asleep -> skip + advance counter;
#                if awake -> clear status, set woke_up=true, fall through and
#                act this same turn (skip stays "")
#   paralysis  → 25% skip roll (no auto-clear, no counter)
static func resolve_turn_skip(character) -> Dictionary:
	var out := {"skip": "", "woke_up": false}
	if character == null:
		return out
	if character.is_status(STUN):
		character.remove_status(STUN)
		out["skip"] = STUN
		return out
	if character.is_status(SLEEP):
		# sleep_turn = 0 -> 100% sleep, +1 each consecutive sleep -> 75/50/25/0%
		var sleep_chance: float = max(0.0, 1.0 - 0.25 * float(character.sleep_turn))
		if randf() < sleep_chance:
			character.sleep_turn += 1
			out["skip"] = SLEEP
			return out
		# Wake up — clear, reset counter, mark woke_up so the UI can banner it.
		character.remove_status(SLEEP)
		character.sleep_turn = 0
		out["woke_up"] = true
	if character.is_status(PARALYSIS):
		if randf() < 0.25:
			out["skip"] = PARALYSIS
			return out
	return out

# Returns tick damage to deal at start of this character's turn (0 if none).
# Dead characters tick 0.
static func get_tick_damage(character) -> int:
	if character == null or not character.is_alive():
		return 0
	for status in TICK_FRACTIONS:
		if character.is_status(status):
			return max(1, int(character.max_hp() * float(TICK_FRACTIONS[status])))
	return 0

# Returns the status name responsible for the current tick (poison/scorched/
# frostbite), or "" if no ticking status. Used by UI to label tick damage.
static func get_active_tick_status(character) -> String:
	if character == null:
		return ""
	for status in TICK_FRACTIONS:
		if character.is_status(status):
			return status
	return ""

# --- Banner phrase helpers ---
# Centralized so BattleScene + tests use the same wording.

# Banner shown the moment a status lands on a target.
# Example: "Aria was Poisoned!", "Kael fell Asleep!".
static func applied_phrase(character_name: String, status_name: String) -> String:
	match status_name:
		POISON:    return "%s was Poisoned!" % character_name
		SCORCHED:  return "%s was Scorched!" % character_name
		FROSTBITE: return "%s was Frostbitten!" % character_name
		SLEEP:     return "%s fell Asleep!" % character_name
		STUN:      return "%s was Stunned!" % character_name
		PARALYSIS: return "%s was Paralyzed!" % character_name
		_:         return "%s is %s!" % [character_name, status_name.capitalize()]

# Banner shown on a turn the actor cannot act because of a status.
# Stun reads as "reoriented themself" — they were dazed but recover; the
# others stay punchier since those conditions persist.
static func skipped_phrase(character_name: String, status_name: String) -> String:
	match status_name:
		STUN:      return "%s reoriented themself" % character_name
		SLEEP:     return "%s is Asleep!" % character_name
		PARALYSIS: return "%s is Paralyzed!" % character_name
		_:         return "%s is %s!" % [character_name, status_name.capitalize()]

# Banner shown when sleep wears off and the actor will act this same turn.
static func woke_phrase(character_name: String) -> String:
	return "%s woke up!" % character_name

# --- Skill token parsing ---
# Returns {"kind": "buff"|"debuff"|"status"|"none", "value": <stat_name or status_name>}
# for use by BattleManager/Skill when consuming Skill.status_to_apply.
static func parse_apply_token(token: String) -> Dictionary:
	if token == "":
		return {"kind": "none", "value": ""}
	if token.ends_with(DEBUFF_SUFFIX):
		var stat := token.substr(0, token.length() - DEBUFF_SUFFIX.length())
		if stat in BUFFABLE_STATS:
			return {"kind": "debuff", "value": stat}
	if token.ends_with(BUFF_SUFFIX):
		var stat := token.substr(0, token.length() - BUFF_SUFFIX.length())
		if stat in BUFFABLE_STATS:
			return {"kind": "buff", "value": stat}
	# Otherwise treat as a mutex/legacy status name
	return {"kind": "status", "value": token}
