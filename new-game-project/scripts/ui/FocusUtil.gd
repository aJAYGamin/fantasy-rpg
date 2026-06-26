class_name FocusUtil
extends RefCounted

## Input helpers shared by menus.
##
## Menu FOCUS is centralized in GameManager's focus guard (menus register a scope;
## the guard makes its controls focusable for keyboard/controller, maintains focus,
## and locks out background scopes). This file only holds the category-cycle
## detection used by Stats/Items/Equipment, which switch heroes / item tabs with
## the controller shoulder buttons (L1/R1) or the keyboard Q/E keys — the tabs
## themselves are not focusable, so arrow-key focus navigation stays free to move
## between the actual item/slot buttons.

static func is_prev_category(event: InputEvent) -> bool:
	if event is InputEventJoypadButton and event.pressed \
			and event.button_index == JOY_BUTTON_LEFT_SHOULDER:
		return true
	return event is InputEventKey and event.pressed and not event.echo \
		and event.keycode == KEY_Q

static func is_next_category(event: InputEvent) -> bool:
	if event is InputEventJoypadButton and event.pressed \
			and event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
		return true
	return event is InputEventKey and event.pressed and not event.echo \
		and event.keycode == KEY_E
