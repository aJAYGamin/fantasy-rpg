# On-screen Keyboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a controller-only player rename their controller keybind profiles through a themed QWERTY on-screen keyboard that opens from the Controller page's Rename field, leaving keyboard and mouse use of both Rename fields exactly as they are.

**Architecture:** A new `OnScreenKeyboard` control (its own file, its own focus scope) holds a draft name and the key grid, and reads its own pad and key presses in `_input`, taking every press it uses before anything behind it and passing only directions and Confirm on to the GUI. `SettingsScreen` opens it as its last child when the pad's Confirm lands on the Controller page's Rename field, or when the stick cursor clicks that field (the cursor now says when a click is its own: `VirtualCursor.pad_click`), and sends the finished name through the existing `_on_profile_renamed` path. `GameManager.note_input_device` lets the panel keep the highlight/cursor switch working for presses it swallows.

**Tech Stack:** Godot 4.6.1, GDScript, the project's headless `TestSuite` runner.

**Spec:** `.claude/docs/superpowers/specs/2026-10-17-onscreen-keyboard-design.md` — **look:** `.claude/docs/superpowers/specs/2026-10-17-onscreen-keyboard-mockup.html` (open it in a browser). Executors read both.

## Global Constraints

- Work on branch `onscreen-keyboard`, created off the latest `main` **after `themed-cursor` is merged into it**, inside the main checkout. Never commit to `main`; never use worktrees. Never stage `.DS_Store` or `.superpowers/`.
- Commits: `git commit -F <file>` — subject line, blank line, body, blank line, `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Tests: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/TestRunner.tscn --quit-after 5` from `new-game-project/` — headless only. Must end `0 failed` **and** have zero `SCRIPT ERROR` lines, and every suite touched must assert more than before. A new `class_name` file needs `/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path . --quit-after 3` once. New suites go in `tests/TestRunner.gd` `SUITE_PATHS`. Tests are synchronous; any test touching `GameManager` state restores it; any test that saves input config wraps itself in `test_settings`' `_protect()` / `_restore()` (or the same idea).
- Play-test flags (`PartyFactory.TEST_UNLOCK_ALL_SKILLS`, `GameManager.REST_REFRESH_BATTLES`, `BattleScene.TEST_SHOW_ENEMY_HP`) stay at shipping values in every commit.
- Only the **Controller** page's Rename field (`SettingsScreen._pad_profile_name`) opens the panel. The Keyboard page's field (`_kb_profile_name`) is unchanged.
- Key rows, exactly: number row `1234567890`; letter rows `QWERTYUIOP`, `ASDFGHJKL'`, then `⇧` + `ZXCVBNM-` + `⌫`; bottom row `! ?` (2 wide), `Space` (4 wide), `✕ Cancel` (2 wide), `✓ Done` (2 wide) on a 10-column grid. Symbols page rows (replacing the three letter rows, key for key): `!?.,&+#()/`, `:;"@%*=_~'`, `<>[]{}$-`; the `! ?` key reads `ABC` there.
- Name length cap: `InputProfiles.MAX_NAME_LENGTH` (18). Count line `"%d / %d"`.
- Pad buttons: the player's **Confirm** (`ui_accept`) presses the highlighted key; **Cancel / Back** (`ui_cancel`) deletes the last letter; **Pause / Menu** (`pause`) finishes; fixed `JOY_BUTTON_X` cancels, `JOY_BUTTON_Y` adds a space, `JOY_BUTTON_LEFT_SHOULDER` toggles capitals. A fixed button that is also a Confirm / Cancel / Pause binding acts as that binding instead.
- Keyboard in the panel: a printable character types itself, Space types a space, Backspace (echo too) deletes, Enter / keypad Enter finishes, Esc cancels; arrow keys move the highlight.
- Capitals start **off** and stay on until toggled (a lock). The highlight starts on **Q**. After Done or Cancel the highlight returns to the Rename field.
- Look (all from `BattleUITheme`, nothing default-themed): full-screen dim `Color(0, 0, 0, 0.55)`; centred panel ≈ 470 base px wide, `panel_style(PANEL_BORDER, PANEL_BG, 2, 12)`; title `"✦ Rename Profile ✦"` in `font_bold()`, size 16, `SettingsScreen.ACCENT`; name box `panel_style(PANEL_BORDER, BUTTON_HOVER_BG, 2, 6)`, text `TEXT_PRIMARY` size 17 with a caret after the draft; count in `SettingsScreen.NOTE_COLOR` size 11; keys via `BattleUITheme.make_button` (letters 14, action keys 12 in `TEXT_SUBTITLE`), at least 32 px tall, 5 px gaps; legend in `NOTE_COLOR` size 10–11 with button names in `TEXT_SUBTITLE`, up to two lines.
- `PROCESS_MODE_ALWAYS` (the pause menu pauses the tree).
- Never read the OS mouse position (CLAUDE.md, Themed cursor). Nothing outside `scripts/cursor/` reads the mouse another way.
- A test written below as a name plus a comment body is specified by that comment: write it as assertions on exactly the observable the comment states.

## Review Focus

1. **The press that opens the panel must not type, and the press that closes it must not leak.** The pad's A press (and its release, which lands on the Q key) types nothing; Start / X / Esc pressed in the panel never re-open or close the pause menu or back the Settings page out. → tests in Task 3.
2. **A pad button the panel swallows still brings the highlight back.** `GameManager` is an autoload, so its `_input` runs *after* scene nodes and never sees a press the panel marks handled; a player using the stick cursor who presses B would be left with neither cursor nor highlight. → test in Task 2.
3. **A player who remapped Confirm to X.** X must type the highlighted key, not throw the name away, and the legend must not promise "X Cancel". → test in Task 2.
4. **Space and Enter on a real keyboard.** Both are the keyboard's Confirm (`ui_accept`); in the panel Space types a space and Enter finishes, and neither presses the highlighted key. → test in Task 2.
5. **A page rebuild while the panel is open** (a controller connecting, anything calling `_build`) leaves no stray panel or focus scope, and the next A on the field opens a fresh one. → test in Task 3.

---

## File map

| File | Responsibility |
|---|---|
| Create `scripts/ui/OnScreenKeyboard.gd` | The panel: draft name, key grid, capitals/symbols pages, legend, its own input, focus scope, `finished` / `cancelled`. |
| Modify `scripts/GameManager.gd` | `note_input_device(event)`, the mode switch `_input` makes, callable for presses a screen handles first. |
| Modify `scripts/cursor/VirtualCursor.gd` | `pad_click`: true while delivering a click Cursor Click made. |
| Modify `scripts/ui/SettingsScreen.gd` | Open the panel from the Controller page's Rename field (pad Confirm, stick-cursor click), save through `_on_profile_renamed`, hand focus back, close on rebuild. |
| Tests | `tests/suites/test_onscreen_keyboard.gd` (new); `test_settings.gd`, `test_virtual_cursor.gd` (extended); `tests/TestRunner.gd` (register). |
| Docs | `new-game-project/CLAUDE.md`; `.claude/docs/superpowers/notes/2026-10-17-every-screen-every-input.md`. |

All paths below are relative to `new-game-project/` unless they start with `.claude/`.

---

### Before Task 1: branch and design files

- [ ] Confirm `git log main --oneline` includes the `themed-cursor` merge. If not, stop and wait.
- [ ] `git checkout main && git pull && git checkout -b onscreen-keyboard`.
- [ ] Add the spec, the mockup and this plan at `.claude/docs/superpowers/specs/2026-10-17-onscreen-keyboard-design.md`, `.claude/docs/superpowers/specs/2026-10-17-onscreen-keyboard-mockup.html`, `.claude/docs/superpowers/plans/2026-10-17-onscreen-keyboard.md`; commit them alone — "Add the on-screen keyboard design, mockup and plan".

---

### Task 1: The keyboard panel — keys and editing

**Files:**
- Create: `scripts/ui/OnScreenKeyboard.gd`
- Create: `tests/suites/test_onscreen_keyboard.gd`
- Modify: `tests/TestRunner.gd` (`SUITE_PATHS`: add `"res://tests/suites/test_onscreen_keyboard.gd"`)

**Interfaces:**
- Consumes: `BattleUITheme` (`make_button`, `panel_style`, `font_bold`, colours), `SettingsScreen.ACCENT` / `NOTE_COLOR`, `GameManager.register_focus_scope` / `unregister_focus_scope` / `set_preferred_focus`.
- Produces (`class_name OnScreenKeyboard extends Control`):
  - `signal finished(text: String)` — the draft as typed (not cleaned; the caller cleans it).
  - `signal cancelled`
  - `const NUMBER_ROW := "1234567890"`, `const LETTER_ROWS := ["QWERTYUIOP", "ASDFGHJKL'", "ZXCVBNM-"]`, `const SYMBOL_ROWS := ["!?.,&+#()/", ":;\"@%*=_~'", "<>[]{}$-"]`
  - `var caps := false`, `var symbols := false`
  - `func open(initial: String, max_length: int) -> void` — call once the panel is in the tree: builds the dim + panel, sets the draft, registers the panel as a focus scope and `set_preferred_focus(self, key_button("Q"))`.
  - `func get_text() -> String`
  - `func type_char(c: String) -> void` — appends unless the draft is already `max_length` long.
  - `func delete_last() -> void` — no-op on an empty draft.
  - `func toggle_caps() -> void`, `func toggle_symbols() -> void` — relabel the keys.
  - `func finish() -> void` / `func cancel() -> void` — emit once, then close: unregister the focus scope and `queue_free()`. A second call does nothing. `_exit_tree` also unregisters (a rebuild frees the panel without either).
  - `func key_button(id: String) -> Button` — ids: a character as written in `NUMBER_ROW` / `LETTER_ROWS` (`"Q"`, `"'"`, `"1"`; a letter-row key keeps its letter's id on the symbols page), or `"shift"`, `"backspace"`, `"symbols"`, `"space"`, `"cancel"`, `"done"`.
  - A letter key types `SYMBOL_ROWS[r][c]` on the symbols page, else its letter (upper case when `caps`, lower otherwise); its text always shows what it will type.

- [ ] **Step 1: Write the failing tests** (each test's panel goes under a `CanvasLayer` (layer 150) under `GameManager`, as `test_virtual_cursor` does, and is freed at the end; restore the input mode).

```gdscript
func test_opening_shows_the_current_name_and_its_count() -> void:
	# open("Couch", 18): get_text() == "Couch"; the name box's label text starts with "Couch";
	# the count label reads "5 / 18"; process_mode == PROCESS_MODE_ALWAYS

func test_letters_type_lowercase_until_capitals_are_on() -> void:
	# open("", 18); press key_button("Q") (emit pressed) → "q"; key_button("W").text == "w";
	# toggle_caps() → key_button("W").text == "W"; press W, then E → "qWE" (the lock stays on);
	# toggle_caps() → press R → "qWEr"

func test_space_delete_and_the_length_cap() -> void:
	# open("ab", 4): "space" key → "ab "; "backspace" → "ab"; delete_last() twice → ""; once more → ""
	# type to "abcd" → pressing "Z" leaves "abcd" and the count reads "4 / 4"

func test_the_symbols_page_swaps_only_the_letter_rows() -> void:
	# toggle_symbols(): key_button("Q").text == "!" and pressing it types "!"; key_button("'") types "'"
	# (SYMBOL_ROWS[1][9]); key_button("1").text == "1"; key_button("symbols").text == "ABC";
	# toggle_symbols() → key_button("Q").text == "q", key_button("symbols").text == "! ?"

func test_done_and_cancel_report_once_and_let_go_of_the_highlight() -> void:
	# open("Couch", 18), GameManager.has_focus_scope(panel) is true; finish() twice → finished emitted once
	# with "Couch"; has_focus_scope false. A second panel: cancel() → cancelled once, finished never.
	# The "done" and "cancel" keys do the same as finish() / cancel().

func test_the_highlight_starts_on_q() -> void:
	# controller mode (set_controller_mode_for_test(true)); open; update_focus_guard_for_test()
	# → the viewport's focus owner is key_button("Q")

func test_every_key_is_a_themed_button_in_the_mockup_rows() -> void:
	# 44 key Buttons (4 rows of 10 + 4); each has a "normal" stylebox override (BattleUITheme);
	# key_button("space") is twice as wide as key_button("cancel") (± a gap)
```

- [ ] **Step 2: Run the class-cache rescan, then the tests — expect FAIL** (`OnScreenKeyboard` missing or methods missing).
- [ ] **Step 3: Implement `OnScreenKeyboard.gd`** to the interface above and the Global Constraints' look. Rows are `HBoxContainer`s of buttons with `size_flags_horizontal = SIZE_EXPAND_FILL` and `size_flags_stretch_ratio` 2 / 4 for the wide keys, so the d-pad's geometric neighbour search walks the grid. The dim takes mouse clicks (`MOUSE_FILTER_STOP`) so nothing behind can be clicked. `⇧ ⌫ ✕ ✓` come from Godot's system-font fallback, as `✦` and `←` already do.
- [ ] **Step 4: Run — PASS, 0 `SCRIPT ERROR`.**
- [ ] **Step 5: Commit** — "Add the on-screen keyboard panel".

---

### Task 2: The keyboard panel — pad buttons, a real keyboard, and the legend

**Files:**
- Modify: `scripts/ui/OnScreenKeyboard.gd` (`_input`, `_process`, `step_hold`, `legend_entries`, legend label)
- Modify: `scripts/GameManager.gd` (`note_input_device`; `_input` calls it)
- Test: `tests/suites/test_onscreen_keyboard.gd`

**Interfaces:**
- Consumes: Task 1's API; `InputMapConfig.describe_controller(action)` / `joy_button_name(idx)`; `HoldRepeat`.
- Produces:
  - `GameManager.note_input_device(event: InputEvent) -> void` — exactly the mode switch and activity stamps `_input` does today (key → keyboard nav, mouse/gesture → mouse, pad button press or stick > 0.5 → controller); `_input` becomes a call to it.
  - `OnScreenKeyboard._input(event)`: pressed pad events — `pause` → `finish()`; `ui_cancel` → `delete_last()`; `ui_accept` → **not handled** (the focused key's Button presses itself); then fixed X → `cancel()`, Y → `type_char(" ")`, LB → `toggle_caps()`; any other pressed pad button is swallowed. Pad directions (`ui_up/down/left/right`) and all releases pass through. Pressed keys — Esc → `cancel()`, Enter / KP Enter → `finish()`, Backspace (echo too) → `delete_last()`, arrow keys pass through, a key with a printable `unicode` (≥ 32) and no Ctrl/Cmd/Alt → `type_char(char(unicode))`, anything else swallowed. Every event it acts on or swallows: `GameManager.note_input_device(event)` then `get_viewport().set_input_as_handled()`. Mouse events pass through.
  - `func step_hold(cancel_held: bool, delta: float) -> void` — a `HoldRepeat` (default timing); each repeat calls `delete_last()`. `_process(delta)` calls it with whether any connected pad holds a button bound to `ui_cancel`.
  - `static func legend_entries() -> Array` — `[name, verb]` pairs in the order Type, Delete, Cancel, Space, Caps, Done; Type / Delete / Done use `InputMapConfig.describe_controller("confirm" / "cancel" / "pause")`; Cancel / Space / Caps use `joy_button_name(JOY_BUTTON_X / Y / LEFT_SHOULDER)` and are left out when that button is bound to confirm, cancel or pause. The legend label shows them, names in `TEXT_SUBTITLE`.

- [ ] **Step 1: Write the failing tests.** Deliver events with `GameManager.get_viewport().push_input(ev)`. An `InputReader` (an inner class like `test_virtual_cursor`'s) added to `GameManager` **before** the panel's layer hears only what the panel lets through.

```gdscript
func test_pad_buttons_edit_and_close() -> void:
	# open("Couch", 18): B press → "Couc"; Y → "Couc "; LB → caps true; Start → finished("Couc ");
	# a second panel: X → cancelled. The reader heard none of these presses.

func test_confirm_presses_the_highlighted_key_and_directions_move_it() -> void:
	# controller mode, focus on key_button("Q"): A press + release → "q" appended;
	# d-pad right press → focus owner is key_button("W")

func test_holding_the_pad_delete_keeps_deleting() -> void:  # Claude's call 8
	# open("abcdef", 18): step_hold(true, 0.40) → "abcdef"; step_hold(true, 0.05) → "abcde";
	# step_hold(true, 0.16) → "abcd"; step_hold(false, 0.016) then step_hold(true, 0.40) → still "abcd"

func test_a_real_keyboard_types_into_the_panel() -> void:  # Review Focus 4
	# focus on key_button("Q"): key "c" (unicode 99) → "...c"; Space key → " " added and Q NOT typed;
	# Backspace, then an echo Backspace → two deleted; Enter → finished. A second panel: Esc → cancelled.
	# Right arrow → focus moves to W. The reader heard none of c / Space / Backspace / Enter / Esc.

func test_a_remapped_confirm_on_x_types_instead_of_cancelling() -> void:  # Review Focus 3
	# bind confirm (and mirror to ui_accept via InputMapConfig) to JOY_BUTTON_X only; focus on Q;
	# X press + release → "q" typed, cancelled not emitted; legend_entries()[0] == ["X / Square", "Type"]
	# and no entry has verb "Cancel". Restore the bindings (InputMapConfig + input_profiles.sync_from_input_map()).

func test_the_legend_names_the_players_buttons() -> void:
	# defaults: legend_entries() == [["A / Cross","Type"],["B / Circle","Delete"],["X / Square","Cancel"],
	# ["Y / Triangle","Space"],["LB / L1","Caps"],["Start / Options","Done"]]

func test_buttons_the_panel_takes_still_switch_to_the_highlight() -> void:  # Review Focus 2
	# GameManager in mouse mode (set_controller_mode_for_test(false)); B press → is_controller_mode() true;
	# back to mouse mode, key "c" → focus_nav_active() true and not is_controller_mode()

func test_other_pad_buttons_stop_at_the_panel() -> void:
	# RB, Back/Select, L3 presses: draft unchanged, reader heard none
```

- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement** to the interface above.
- [ ] **Step 4: Run — PASS (the existing `test_focus_guard`, `test_virtual_cursor` and `test_settings` suites too), 0 `SCRIPT ERROR`.**
- [ ] **Step 5: Commit** — "Drive the on-screen keyboard with the pad's buttons and a real keyboard".

---

### Task 3: Opening it from the Controller page

**Files:**
- Modify: `scripts/cursor/VirtualCursor.gd` (`var pad_click := false`, set around the push in `_push_click`)
- Modify: `scripts/ui/SettingsScreen.gd` (`_keyboard_panel`, `_open_name_keyboard`, `_input`, the pad field's `gui_input`, `_build`)
- Test: `tests/suites/test_settings.gd`, `tests/suites/test_virtual_cursor.gd`

**Interfaces:**
- Consumes: Task 1–2's `OnScreenKeyboard`; `_on_profile_renamed(keyboard: bool, text: String)`; `InputProfiles.MAX_NAME_LENGTH`; `GameManager.set_preferred_focus`.
- Produces:
  - `VirtualCursor.pad_click: bool` — true only while `_push_click` delivers a press or release; false for every real mouse event and afterwards.
  - `SettingsScreen._keyboard_panel: OnScreenKeyboard` (null when closed) and `func _open_name_keyboard() -> void` — adds the panel as the screen's last child, `open(profiles.name_for(false, active), InputProfiles.MAX_NAME_LENGTH)`; `finished` → `_on_profile_renamed(false, text)`; either signal → `_keyboard_panel = null` and `GameManager.set_preferred_focus(self, _pad_profile_name)`.
  - `_input`: returns at once while `_keyboard_panel` is open; after the `_listening` check, a pressed pad event (`InputEventJoypadButton` or `InputEventJoypadMotion`) that `is_action_pressed("ui_accept")` while `_pad_profile_name` has focus → `note_input_device`, `_open_name_keyboard()`, handled.
  - `_pad_profile_name.gui_input`: a left-button press while `GameManager.virtual_cursor.pad_click` → `_open_name_keyboard()` and `accept_event()`. A real mouse press is left alone (caret, as today).
  - `_build()` sets `_keyboard_panel = null` (the panel is freed with the other children).

- [ ] **Step 1: Write the failing tests.**

In `test_settings.gd` (wrap each in `_protect()` / `_restore()`; keep and restore the controller profile's name):

```gdscript
func test_confirm_on_the_controller_rename_field_opens_the_keyboard() -> void:  # Review Focus 1
	# _open("controller"), controller mode, _pad_profile_name.grab_focus(); push a pad A press →
	# _keyboard_panel is valid and get_text() == the active controller profile's name;
	# update_focus_guard_for_test() → focus on its key_button("Q"); push the A release → get_text() unchanged

func test_the_keyboard_page_field_never_opens_it() -> void:
	# _open("keyboard"), focus _kb_profile_name, pad A press → no OnScreenKeyboard under the screen

func test_done_saves_through_the_profile_rules_and_returns_the_highlight() -> void:
	# open the panel; panel.finish() after setting the draft to "  Couch  " (delete_last to empty, type_char each)
	# → _pad_profile_name.text == "Couch", the picker's active item text == "Couch",
	# input_profiles.name_for(false, active) == "Couch"; update_focus_guard_for_test() → focus owner is _pad_profile_name.
	# Again with an empty draft → InputProfiles.default_name(active)

func test_cancel_leaves_the_name() -> void:
	# open, type "zzz", panel.cancel() → name_for(false, active) and the field unchanged; _keyboard_panel == null

func test_nothing_behind_the_keyboard_hears_its_buttons() -> void:  # Review Focus 1
	# an InputReader added to GameManager before the screen; open the panel; push Start, B, X presses and an Esc key
	# → the reader heard none; screen._view is still "controller"; the screen is still open

func test_a_rebuild_while_open_closes_the_keyboard() -> void:  # Review Focus 5
	# open the panel; screen._build() → _keyboard_panel == null, no OnScreenKeyboard under the screen,
	# GameManager.has_focus_scope(old panel) false (check before it is freed: hold a weakref);
	# focus the field again, pad A press → a new panel opens
```

In `test_virtual_cursor.gd` (use `_begin()` / `_end()`):

```gdscript
func test_a_stick_click_says_it_came_from_the_pad() -> void:
	# InputReader records vc.pad_click when it receives a left press: _stick_click() → true; _click() → false;
	# vc.pad_click is false after each

func test_the_stick_cursor_opens_the_rename_keyboard_and_the_mouse_does_not() -> void:
	# a SettingsScreen on the test layer, view "controller"; _motion_to(the Rename field's centre);
	# _click() → no panel (the field has focus, as today); _stick_click() → screen._keyboard_panel is valid
```

- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement** to the interface above.
- [ ] **Step 4: Run — PASS, 0 `SCRIPT ERROR`; `test_settings`, `test_virtual_cursor` and `test_onscreen_keyboard` each assert more than before Task 1.**
- [ ] **Step 5: Commit** — "Open the on-screen keyboard from the Controller page's Rename field".

---

### Task 4: The record, the play-test steps and CLAUDE.md

**Files:**
- Modify: `.claude/docs/superpowers/notes/2026-10-17-every-screen-every-input.md`
- Modify: `new-game-project/CLAUDE.md`

- [ ] **Step 1: Full headless run.** Record the totals; grep the output for `SCRIPT ERROR` (none).
- [ ] **Step 2: The record.** Settings — Keyboard row, Controller (highlight) cell: name field "by design, keyboard only — a pad player has no reason to rename keyboard profiles (user, 2026-10-17)"; stick-cursor cell the same. Settings — Controller row, Controller (highlight) and stick-cursor cells: name field **fixed (<Task 3 commit>)** — A or a stick click opens the on-screen keyboard, naming the tests. "Open gaps" item 1: closed, pointing at the spec. Add play-test steps under a new **On-screen keyboard** heading:
  - Pad only, Settings → Controls → Controller → Rename: A opens the panel over the dimmed page with the current name and the highlight on Q; type "Couch" with the d-pad and A, B deletes, Y adds a space, LB switches capitals, Start saves; the dropdown and the field show the new name, the highlight is back on Rename; quit and restart — the name is still there.
  - The same, but X instead of Start: the old name stays.
  - From the pause menu: Start and B pressed in the panel never close or re-open the pause menu.
  - Stick cursor: click the field (R3) — the panel opens; click keys, ✕ Cancel and ✓ Done with R3.
  - Mouse: click the Controller page's field — the caret goes in, no panel; type and Enter, as before.
  - The panel matches the mockup (`2026-10-17-onscreen-keyboard-mockup.html`); `⇧ ⌫ ✕ ✓` draw as symbols, not boxes (if one is a box, report it — the fix is the words Caps / Del).
- [ ] **Step 3: CLAUDE.md.** Themed cursor's "Open: renaming a keybind profile still needs a keyboard" line and the Deferred list item → done, pointing at the spec; a short **On-screen keyboard** entry beside the Settings description (what opens it, the buttons, `OnScreenKeyboard`, `VirtualCursor.pad_click`, `GameManager.note_input_device`); the test count and suite list (`onscreen_keyboard`).
- [ ] **Step 4: Commit** — "Record the on-screen keyboard in the every-screen pass and CLAUDE.md".

---

## After the tasks

Hand the branch to the user for a play-test with the checklist above. Merge into `main` and delete the branch only when they say it is good.
