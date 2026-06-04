class_name FocusUtil
extends RefCounted

## Input helpers shared by menus.
##
## Controller menu FOCUS is centralized in GameManager's focus guard (menus
## register a scope; the guard makes its controls focusable in controller mode,
## maintains focus, and locks out background scopes). This file only holds the
## L1/R1 category-cycle detection used by Stats/Items/Equipment, which switch
## heroes / item tabs with the shoulder buttons (the tabs are not focusable).

static func is_prev_category(event: InputEvent) -> bool:
	return event is InputEventJoypadButton and event.pressed \
		and event.button_index == JOY_BUTTON_LEFT_SHOULDER

static func is_next_category(event: InputEvent) -> bool:
	return event is InputEventJoypadButton and event.pressed \
		and event.button_index == JOY_BUTTON_RIGHT_SHOULDER
