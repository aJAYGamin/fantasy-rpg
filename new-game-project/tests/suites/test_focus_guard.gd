extends TestSuite

## GameManager's centralized controller-focus guard: scope register/unregister,
## topmost-visible scope selection, and focusability gating by input mode.
## These drive the guard directly (no real frames) and clean up after themselves.

func suite_name() -> String:
	return "FocusGuard"

func _make_scope() -> Control:
	var root := Control.new()
	var b := Button.new()
	b.text = "Action"
	root.add_child(b)
	GameManager.add_child(root)
	return root

func _cleanup(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			GameManager.unregister_focus_scope(n)
			n.queue_free()

func test_register_and_unregister() -> void:
	var a := _make_scope()
	GameManager.register_focus_scope(a)
	assert_true(GameManager.has_focus_scope(a), "scope registered")
	GameManager.unregister_focus_scope(a)
	assert_false(GameManager.has_focus_scope(a), "scope unregistered")
	_cleanup([a])

func test_register_is_deduped() -> void:
	var a := _make_scope()
	GameManager.register_focus_scope(a)
	GameManager.register_focus_scope(a)
	assert_eq(GameManager.focus_scope_count(a), 1, "double-register keeps a single entry")
	_cleanup([a])

func test_topmost_visible_scope() -> void:
	var a := _make_scope()
	var b := _make_scope()
	GameManager.register_focus_scope(a)
	GameManager.register_focus_scope(b)
	assert_eq(GameManager.top_focus_scope(), b, "most recently registered, visible scope is on top")
	b.visible = false
	assert_eq(GameManager.top_focus_scope(), a, "hidden top scope is skipped for the one below")
	_cleanup([a, b])

func test_controller_mode_makes_scope_focusable() -> void:
	var a := _make_scope()
	var btn: Button = a.get_child(0)
	GameManager.register_focus_scope(a)

	GameManager.set_controller_mode_for_test(true)
	GameManager.update_focus_guard_for_test()
	assert_eq(btn.focus_mode, Control.FOCUS_ALL, "controller mode makes scope buttons focusable")

	GameManager.set_controller_mode_for_test(false)
	GameManager.update_focus_guard_for_test()
	assert_eq(btn.focus_mode, Control.FOCUS_NONE, "pure-mouse mode makes scope buttons click-only")

	GameManager.set_controller_mode_for_test(false)
	_cleanup([a])

func test_keyboard_nav_makes_scope_focusable() -> void:
	# Keyboard navigation uses the same focus path as the controller, so menus are
	# arrow-key navigable (not just mouse-click).
	var a := _make_scope()
	var btn: Button = a.get_child(0)
	GameManager.register_focus_scope(a)

	GameManager.set_keyboard_nav_for_test(true)
	assert_true(GameManager.focus_nav_active(), "keyboard counts as focus-navigation mode")
	assert_false(GameManager.is_controller_mode(), "keyboard nav does not report as a gamepad")
	GameManager.update_focus_guard_for_test()
	assert_eq(btn.focus_mode, Control.FOCUS_ALL, "keyboard mode makes scope buttons focusable")

	# Switching to pure mouse releases focusability again.
	GameManager.set_keyboard_nav_for_test(false)
	GameManager.update_focus_guard_for_test()
	assert_eq(btn.focus_mode, Control.FOCUS_NONE, "mouse mode returns scope buttons to click-only")

	GameManager.set_controller_mode_for_test(false)
	_cleanup([a])

func test_button_in_hidden_container_not_focused() -> void:
	# A button inside a hidden container must NOT be grabbed (it would steal the
	# controller's A press, e.g. during the level-up spin when the picker is hidden).
	var a := Control.new()
	var hidden_box := VBoxContainer.new()
	hidden_box.visible = false
	var hidden_btn := Button.new()
	hidden_btn.text = "Pick"
	hidden_box.add_child(hidden_btn)
	a.add_child(hidden_box)
	GameManager.add_child(a)
	GameManager.register_focus_scope(a)

	GameManager.set_controller_mode_for_test(true)
	GameManager.update_focus_guard_for_test()
	var owner := a.get_viewport().gui_get_focus_owner()
	assert_ne(owner, hidden_btn, "button in a hidden container is never focused")

	GameManager.set_controller_mode_for_test(false)
	_cleanup([a])

func test_grabs_button_made_visible_later() -> void:
	# Mirrors the Victory screen: a scope registers while its only button is still
	# hidden, then the button is shown — the guard must grab it (not stay stuck).
	var a := Control.new()
	var btn := Button.new()
	btn.text = "Continue"
	btn.visible = false
	a.add_child(btn)
	GameManager.add_child(a)
	GameManager.set_controller_mode_for_test(true)
	GameManager.register_focus_scope(a)
	GameManager.update_focus_guard_for_test()   # nothing focusable yet
	btn.visible = true
	GameManager.update_focus_guard_for_test()    # now it should grab Continue
	var owner := a.get_viewport().gui_get_focus_owner()
	assert_eq(owner, btn, "guard grabs a button revealed after the scope registered")
	GameManager.set_controller_mode_for_test(false)
	_cleanup([a])

func test_no_focus_tag_excluded() -> void:
	var a := Control.new()
	var tab := Button.new()
	tab.text = "Tab"
	BattleUITheme.mark_no_focus(tab)
	var action := Button.new()
	action.text = "Action"
	a.add_child(tab)
	a.add_child(action)
	GameManager.add_child(a)
	GameManager.register_focus_scope(a)

	GameManager.set_controller_mode_for_test(true)
	GameManager.update_focus_guard_for_test()
	assert_eq(tab.focus_mode, Control.FOCUS_NONE, "no_focus-tagged tab stays unfocusable")
	assert_eq(action.focus_mode, Control.FOCUS_ALL, "normal button becomes focusable")

	GameManager.set_controller_mode_for_test(false)
	_cleanup([a])

# --- Disabled options are stepped over ----------------------------------------
# Godot's neighbor search only skips FOCUS_NONE controls, so a greyed button left
# focusable becomes a dead end. The main menu's disabled Continue blocked every
# option beneath it.

## A vertical stack of buttons, positioned BY HAND rather than with a
## VBoxContainer: focus neighbors are found geometrically, and a container only
## lays its children out on the next frame, so a container here would leave every
## button at rect (0,0,0,0) and the neighbor search with nothing to find.
func _list_scope(specs: Array) -> Dictionary:
	var root := Control.new()
	root.size = Vector2(200, 44 * specs.size())
	var buttons: Array[Button] = []
	var y := 0.0
	for spec in specs:
		var b := Button.new()
		b.text = spec[0]
		b.disabled = spec[1]
		b.position = Vector2(0, y)
		b.size = Vector2(200, 40)
		root.add_child(b)
		buttons.append(b)
		y += 44.0
	GameManager.add_child(root)
	return {"root": root, "buttons": buttons}

func test_disabled_button_is_not_focusable() -> void:
	var s := _list_scope([["Continue", true], ["New Game", false], ["Quit", false]])
	var root: Control = s["root"]
	var btns: Array = s["buttons"]
	GameManager.register_focus_scope(root)
	GameManager.set_controller_mode_for_test(true)
	GameManager.update_focus_guard_for_test()

	assert_eq(btns[0].focus_mode, Control.FOCUS_NONE, "the greyed-out option is taken out of navigation")
	assert_eq(btns[1].focus_mode, Control.FOCUS_ALL, "an enabled option stays navigable")
	assert_eq(btns[2].focus_mode, Control.FOCUS_ALL, "the option under it is reachable")

	GameManager.set_controller_mode_for_test(false)
	_cleanup([root])

func test_focus_never_lands_on_a_disabled_option() -> void:
	var s := _list_scope([["Continue", true], ["New Game", false], ["Quit", false]])
	var root: Control = s["root"]
	var btns: Array = s["buttons"]
	GameManager.register_focus_scope(root)
	GameManager.set_controller_mode_for_test(true)
	GameManager.update_focus_guard_for_test()

	var owner := root.get_viewport().gui_get_focus_owner()
	assert_ne(owner, btns[0], "the guard does not hand focus to a greyed option")
	assert_eq(owner, btns[1], "it starts on the first usable one")
	# And the neighbor walk can't reach it either.
	assert_ne(btns[1].find_valid_focus_neighbor(SIDE_TOP), btns[0],
		"navigating up steps over the greyed option instead of stalling on it")

	GameManager.set_controller_mode_for_test(false)
	_cleanup([root])

func test_enabling_a_button_makes_it_navigable_again() -> void:
	# Continue becomes usable once a save exists, without the menu being rebuilt.
	var s := _list_scope([["Continue", true], ["New Game", false]])
	var root: Control = s["root"]
	var btns: Array = s["buttons"]
	GameManager.register_focus_scope(root)
	GameManager.set_controller_mode_for_test(true)
	GameManager.update_focus_guard_for_test()
	assert_eq(btns[0].focus_mode, Control.FOCUS_NONE, "starts locked out")

	btns[0].disabled = false
	GameManager.update_focus_guard_for_test()
	assert_eq(btns[0].focus_mode, Control.FOCUS_ALL, "becomes navigable once enabled")

	GameManager.set_controller_mode_for_test(false)
	_cleanup([root])

func test_content_built_after_the_scope_is_still_governed() -> void:
	# Menus rebuild their contents constantly (item tabs, the next hero's page).
	# A walk that only ran on scope change left fresh controls at whatever
	# focus_mode they were born with — which is why the Items "?" buttons were
	# reachable in one tab and not another.
	var s := _list_scope([["First", false]])
	var root: Control = s["root"]
	GameManager.register_focus_scope(root)
	GameManager.set_controller_mode_for_test(true)
	GameManager.update_focus_guard_for_test()

	var late := Button.new()
	late.text = "Built Later"
	late.disabled = true
	root.add_child(late)
	GameManager.update_focus_guard_for_test()
	assert_eq(late.focus_mode, Control.FOCUS_NONE, "a control added later is governed too")

	late.disabled = false
	GameManager.update_focus_guard_for_test()
	assert_eq(late.focus_mode, Control.FOCUS_ALL, "and keeps being re-evaluated")

	GameManager.set_controller_mode_for_test(false)
	_cleanup([root])

# --- Remembered focus (menu -> sub-view -> back) -------------------------------

func test_preferred_focus_is_honored() -> void:
	var s := _list_scope([["Resume", false], ["Stats", false], ["Items", false]])
	var root: Control = s["root"]
	var btns: Array = s["buttons"]
	GameManager.register_focus_scope(root)
	GameManager.set_controller_mode_for_test(true)
	GameManager.update_focus_guard_for_test()

	# Coming back from the Items sub-view should land on Items, not the top.
	GameManager.set_preferred_focus(root, btns[2])
	root.get_viewport().gui_get_focus_owner().release_focus()
	GameManager.update_focus_guard_for_test()
	assert_eq(root.get_viewport().gui_get_focus_owner(), btns[2],
		"focus returns to the entry the player left from")

	GameManager.set_controller_mode_for_test(false)
	_cleanup([root])

func test_preferred_focus_is_one_shot() -> void:
	# Otherwise an ordinary rebuild inside the scope would keep yanking focus back.
	var s := _list_scope([["Resume", false], ["Stats", false]])
	var root: Control = s["root"]
	var btns: Array = s["buttons"]
	GameManager.register_focus_scope(root)
	GameManager.set_controller_mode_for_test(true)
	GameManager.update_focus_guard_for_test()

	GameManager.set_preferred_focus(root, btns[1])
	root.get_viewport().gui_get_focus_owner().release_focus()
	GameManager.update_focus_guard_for_test()
	assert_eq(root.get_viewport().gui_get_focus_owner(), btns[1], "used once")
	assert_false(GameManager.has_preferred_focus(root), "and consumed")

	root.get_viewport().gui_get_focus_owner().release_focus()
	GameManager.update_focus_guard_for_test()
	assert_eq(root.get_viewport().gui_get_focus_owner(), btns[0], "the next re-grab starts at the top again")

	GameManager.set_controller_mode_for_test(false)
	_cleanup([root])

func test_preferred_focus_falls_back_when_unusable() -> void:
	var s := _list_scope([["Resume", false], ["Save", false]])
	var root: Control = s["root"]
	var btns: Array = s["buttons"]
	GameManager.register_focus_scope(root)
	GameManager.set_controller_mode_for_test(true)
	GameManager.update_focus_guard_for_test()

	# The remembered entry got disabled while the sub-view was open.
	btns[1].disabled = true
	GameManager.set_preferred_focus(root, btns[1])
	root.get_viewport().gui_get_focus_owner().release_focus()
	GameManager.update_focus_guard_for_test()
	assert_eq(root.get_viewport().gui_get_focus_owner(), btns[0],
		"an unusable remembered entry falls back to the first option")

	GameManager.set_controller_mode_for_test(false)
	_cleanup([root])

func test_preferred_focus_is_dropped_with_its_scope() -> void:
	var s := _list_scope([["Resume", false], ["Stats", false]])
	var root: Control = s["root"]
	var btns: Array = s["buttons"]
	GameManager.register_focus_scope(root)
	GameManager.set_preferred_focus(root, btns[1])
	GameManager.unregister_focus_scope(root)
	assert_false(GameManager.has_preferred_focus(root), "closing the menu forgets its remembered focus")
	_cleanup([root])

# --- Held-direction auto-repeat ------------------------------------------------
# Godot moves focus once per press; holding a direction did nothing more, so a
# long list meant one tap per row. The repeat drives the same neighbor search a
# real press uses, so it inherits the disabled/no-focus skipping above.

## Hold `action` for `seconds` and return how many times focus actually moved.
func _hold_direction(root: Control, action: String, seconds: float) -> int:
	var moves := 0
	var last := root.get_viewport().gui_get_focus_owner()
	var delta := 1.0 / 60.0
	var t := 0.0
	Input.action_press(action)
	while t < seconds:
		GameManager.update_nav_repeat_for_test(delta)
		var now := root.get_viewport().gui_get_focus_owner()
		if now != last:
			moves += 1
			last = now
		t += delta
	Input.action_release(action)
	# Tick once more with the action up, the way the next real frame would, so the
	# hold clock is cleared. Without it the state leaks into whatever runs next
	# and the following press is mistaken for a hold already in progress.
	GameManager.update_nav_repeat_for_test(delta)
	return moves

func _nav_scope(count: int) -> Dictionary:
	var specs: Array = []
	for i in count:
		specs.append(["Row %d" % i, false])
	return _list_scope(specs)

func test_holding_down_keeps_moving_focus() -> void:
	var s := _nav_scope(8)
	var root: Control = s["root"]
	var btns: Array = s["buttons"]
	GameManager.register_focus_scope(root)
	GameManager.set_controller_mode_for_test(true)
	GameManager.update_focus_guard_for_test()
	btns[0].grab_focus()

	var moves := _hold_direction(root, "ui_down", 1.5)
	assert_true(moves >= 2, "holding down walks the list instead of stopping (moved %d)" % moves)
	assert_ne(root.get_viewport().gui_get_focus_owner(), btns[0], "focus left the first row")

	GameManager.set_controller_mode_for_test(false)
	_cleanup([root])

func test_a_brief_press_does_not_repeat() -> void:
	var s := _nav_scope(6)
	var root: Control = s["root"]
	var btns: Array = s["buttons"]
	GameManager.register_focus_scope(root)
	GameManager.set_controller_mode_for_test(true)
	GameManager.update_focus_guard_for_test()
	btns[0].grab_focus()

	# Shorter than the initial delay: Godot's own handling of the press is the
	# only movement, and this repeat must not add to it.
	var moves := _hold_direction(root, "ui_down", HoldRepeat.INITIAL_DELAY * 0.5)
	assert_eq(moves, 0, "a tap is not amplified into a scroll")

	GameManager.set_controller_mode_for_test(false)
	_cleanup([root])

func test_repeat_skips_disabled_rows() -> void:
	var s := _list_scope([
		["Top", false], ["Greyed", true], ["Greyed Too", true], ["Bottom", false],
	])
	var root: Control = s["root"]
	var btns: Array = s["buttons"]
	GameManager.register_focus_scope(root)
	GameManager.set_controller_mode_for_test(true)
	GameManager.update_focus_guard_for_test()
	btns[0].grab_focus()

	_hold_direction(root, "ui_down", 1.0)
	var owner := root.get_viewport().gui_get_focus_owner()
	assert_ne(owner, btns[1], "a held direction never parks on a greyed row")
	assert_ne(owner, btns[2], "nor on the next greyed row")
	assert_eq(owner, btns[3], "it lands on the next usable row")

	GameManager.set_controller_mode_for_test(false)
	_cleanup([root])

func test_repeat_is_off_in_mouse_mode() -> void:
	# Pure mouse play is click-only; a held key must not move a focus ring that
	# isn't supposed to exist.
	var s := _nav_scope(6)
	var root: Control = s["root"]
	var btns: Array = s["buttons"]
	GameManager.register_focus_scope(root)
	GameManager.set_controller_mode_for_test(true)
	GameManager.update_focus_guard_for_test()
	btns[0].grab_focus()
	GameManager.set_controller_mode_for_test(false)

	var moves := _hold_direction(root, "ui_down", 1.5)
	assert_eq(moves, 0, "no auto-repeat while the game is in mouse mode")
	_cleanup([root])

func test_repeat_ignores_focus_outside_the_active_scope() -> void:
	# Otherwise a held direction could wander into a background menu.
	var bg := _nav_scope(4)
	var fg := _nav_scope(4)
	var bg_root: Control = bg["root"]
	var fg_root: Control = fg["root"]
	GameManager.register_focus_scope(bg_root)
	GameManager.register_focus_scope(fg_root)
	GameManager.set_controller_mode_for_test(true)
	GameManager.update_focus_guard_for_test()

	# Force focus onto the background scope, which the guard does not own.
	(bg["buttons"][0] as Button).focus_mode = Control.FOCUS_ALL
	(bg["buttons"][0] as Button).grab_focus()
	var moves := _hold_direction(bg_root, "ui_down", 1.0)
	assert_eq(moves, 0, "the repeat leaves focus outside the active scope alone")

	GameManager.set_controller_mode_for_test(false)
	_cleanup([bg_root, fg_root])
