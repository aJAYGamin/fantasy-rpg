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
	assert_eq(btn.focus_mode, Control.FOCUS_NONE, "keyboard+mouse mode makes scope buttons click-only")

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
