class_name LoadoutEditor
extends RefCounted

## The rules behind changing a character's moves, separated from any screen so
## they can be tested directly and reused by the pause page, the town NPC and
## the campfire — three surfaces with three different permissions.
##
## Only EQUIPPING costs an allowance. Clearing a slot and reordering slots are
## free everywhere, because neither changes what a character can actually do:
## one is undoing a choice, the other is cosmetic ordering.
##
##   PAUSE    — rearrange only. Look but don't re-kit.
##   CAMPFIRE — rearrange, clear, and up to GameManager.REST_SWAP_ALLOWANCE equips.
##   TRAINER  — everything, unlimited.

enum Mode { PAUSE, CAMPFIRE, TRAINER }

var mode: Mode = Mode.TRAINER

func _init(p_mode: Mode = Mode.TRAINER) -> void:
	mode = p_mode

## Rearranging is allowed everywhere, including the pause menu.
func can_rearrange() -> bool:
	return true

## Clearing a slot is free, but the pause page is look-only beyond reordering.
func can_clear() -> bool:
	return mode != Mode.PAUSE

## Equipping is the budgeted operation.
func can_equip() -> bool:
	match mode:
		Mode.PAUSE:
			return false
		Mode.CAMPFIRE:
			return GameManager.can_spend_rest_swap()
		Mode.TRAINER:
			return true
	return false

## Swaps left, or -1 when the surface is unlimited. Screens show this.
func swaps_remaining() -> int:
	if mode == Mode.CAMPFIRE:
		return GameManager.rest_swaps_remaining
	return -1

## Why equipping is currently unavailable, for the screen to display. Empty when
## it is available.
func equip_blocked_reason() -> String:
	if mode == Mode.PAUSE:
		return "Moves can only be changed at a camp or a trainer."
	if mode == Mode.CAMPFIRE and not GameManager.can_spend_rest_swap():
		return "No swaps left at this camp."
	return ""

## Puts a pool move into a slot, charging the allowance where one applies.
## Returns true only when the loadout actually changed, so a caller can refresh
## on true and show `equip_blocked_reason()` on false.
func equip(c: Character, is_special: bool, slot: int, pool_index: int) -> bool:
	if c == null or not can_equip():
		return false
	if pool_index < 0 or pool_index >= c.skills.size():
		return false
	# Re-equipping the move already in that slot is a no-op and must not be
	# charged — otherwise a stray double-click costs the player a swap.
	if c.equipped_skill(is_special, slot) == c.skills[pool_index]:
		return false
	if not c.equip_skill(is_special, slot, pool_index):
		return false
	if mode == Mode.CAMPFIRE:
		GameManager.spend_rest_swap()
	return true

func clear(c: Character, is_special: bool, slot: int) -> bool:
	if c == null or not can_clear():
		return false
	return c.unequip_slot(is_special, slot)

func rearrange(c: Character, is_special: bool, from_slot: int, to_slot: int) -> bool:
	if c == null or not can_rearrange():
		return false
	return c.swap_slots(is_special, from_slot, to_slot)
