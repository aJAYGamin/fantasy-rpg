class_name BossPhase
extends Resource

## One phase of a boss fight. Every field except `enter_at_hp` is optional — an
## omitted field means "this phase does not use that power", which is what lets
## one boss be a pure stat-check and another a summoner.

## The phase becomes active at or below this fraction of max HP.
@export var enter_at_hp: float = 1.0
@export var phase_name: String = ""
## Shown as a banner on entry. "" transitions silently.
@export var banner_text: String = ""

## Replaces the boss's usable moveset while this phase is active. [] = keep base.
@export var skills: Array[Skill] = []

## {"attack": 1.5, "speed": 1.2}. Only the five combat stats; max_hp is
## deliberately NOT accepted here — see max_hp_multiplier below.
@export var stat_multipliers: Dictionary = {}

## [{"path": "res://data/enemies/x.tres", "count": 2, "level": 8}]
@export var summons: Array[Dictionary] = []

## Stats the boss buffs on ITSELF when it enters this phase — ON ENTRY ONLY,
## never repeated per turn. Valid entries are the five buffable combat stats:
## "attack", "defense", "magic", "arcane", "speed".
##
## This is how an ordinary (non-transforming) phase is meant to get stronger.
## It goes through the game's normal buff system, so each one shows as a chip
## under the boss's HP bar and uses the same x2.0 maths every other buff does —
## visible and answerable, unlike the raw stat_multipliers that only a
## transformation may use.
@export var self_buffs: Array[String] = []

## StatusSystem apply-token rolled on the boss's own turn.
@export var turn_effect: String = ""
@export var turn_effect_chance: float = 0.0

## > 0 makes this phase a TRANSFORMATION: max HP scales by this factor.
@export var max_hp_multiplier: float = 0.0
## Refill to the new maximum on entry.
@export var restore_hp: bool = false

func is_transformation() -> bool:
	return max_hp_multiplier > 0.0
