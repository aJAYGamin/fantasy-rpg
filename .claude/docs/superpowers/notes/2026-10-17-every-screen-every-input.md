# Every screen, every input — the pass (themed cursor, Task 10)

**Date:** 2026-10-17 · **Branch:** `themed-cursor` · **Spec:**
`.claude/docs/superpowers/specs/2026-10-17-themed-cursor-design.md` ("Every screen, every input")

## What was checked, and how

Every screen in the spec's list was checked with four ways of playing:

- **Mouse** — every control can be clicked (or dragged, or scrolled), and nothing
  works only from the keyboard (a row you can highlight but not click, a confirm
  that only listens for Enter, a target you can only pick with arrows).
- **Keyboard** — every control can be reached with the arrow keys, used with
  Enter/Space (and left/right where a control has a value), and **Esc goes back**.
- **Controller (highlight)** — the same with the d-pad / left stick, A and **B to go back**.
- **Controller (stick cursor)** — the right stick moves the themed cursor and its
  press (Cursor Click, R3 by default) clicks.

Keyboard and highlight both run through the `ui_*` actions and GameManager's focus
guard (`GameManager._update_focus_guard`, `GameManager.gd:319`), so a screen is
fine for both when it registers a focus scope, leaves nothing it needs at
`FOCUS_NONE` (only the deliberate L1/R1 / Q/E tabs and click-only arrows are), and
answers `ui_cancel`. The guard itself is pinned by `test_focus_guard`
(`test_keyboard_nav_makes_scope_focusable`, `test_controller_mode_makes_scope_focusable`,
`test_focus_never_lands_on_a_disabled_option`, `test_last_entry_wraps_to_the_first`, …).

**How the stick-cursor column was settled.** The stick cursor is not a second
input path: `VirtualCursor` turns the stick into `InputEventMouseMotion` (with a
speed) and Cursor Click into a left `InputEventMouseButton`, and pushes them into
the root exactly as it pushes the real mouse (`VirtualCursor.step_stick`
`VirtualCursor.gd:116`, `_push_click`, `_deliver` → `root.push_input`
`VirtualCursor.gd:269`). So **anything that works with the mouse works with the
stick cursor**, unless a screen reads the mouse some other way. A search of
`scripts/` and `scenes/` for `get_mouse_position`, `get_global_mouse_position`,
`mouse_get_position`, `is_mouse_button_pressed`, `get_mouse_button_mask`,
`input_pickable`, `physics_object_picking`, `_input_event(`, `warp_mouse` and
`mouse_mode` finds **nothing outside `scripts/cursor/`**, and no script filters
input by `device`. The only scripts that look at mouse events directly —
`GameManager._input` (`GameManager.gd:752`, switches to mouse mode),
`LevelUpScreen._input` (`LevelUpScreen.gd:51`, a press stops the spin) and
`DialogueBox._is_advance` (`DialogueBox.gd:234`, a left press advances) — read the
pushed event itself, so they see the stick's clicks too. Pinned by
`test_virtual_cursor` (`test_the_stick_press_clicks_where_the_cursor_points`,
`test_holding_the_stick_press_drags_a_slider`, `test_a_dropdown_works_from_the_stick`,
`test_a_physical_click_reaches_input_readers_exactly_once`). The one real
difference: **the stick has no wheel**, so a long list scrolls by holding Cursor
Click on its scrollbar and dragging (or clicking the scrollbar's track). Every list
that can scroll has the themed, draggable bar (`BattleUITheme.make_scroll`;
the battle Items menu styles its own).

Cells say `fine (where / which test)`, `fixed (commit)`, `play-test` (needs a
person with the real mouse, pad or screen — every one is in the checklist below),
or `open` (a gap left for a decision).

## The table

| Screen | Mouse | Keyboard | Controller (highlight) | Controller (stick cursor) |
|---|---|---|---|---|
| **Main menu** (New Game / Continue / Settings / Quit) | play-test — all four are Buttons; real-mouse click + hover sound to confirm | fine — scope `MainMenu.gd:43`; greyed Continue is skipped (`test_focus_never_lands_on_a_disabled_option`); top level, so no Back | fine — same scope; wraps (`test_last_entry_wraps_to_the_first`) | fine — shared path |
| **Save-slot menu** (Load / Overwrite & Start / Copy / Delete / Start New Game, copy picker, confirms) | fine — every action is a Button; confirms are themed Buttons (`SaveSlotMenu.gd:465`) | fine — picker + each modal register scopes (`SaveSlotMenu.gd:64`, `:381`); Copy↔Delete neighbours wired by hand (`:208`); Esc closes the top modal, then the picker (`:46`) | fine — same; B closes the top modal, then the picker | fine — shared path |
| **Pause menu** and its Quit confirm | play-test — Buttons; real-mouse click + hover to confirm | fine — scope `PauseMenu.gd:49`, confirm scope `:391`; Esc backs out one layer at a time (`:70`); focus returns to the entry you left (`:326`, `test_preferred_focus_is_honored`) | fine — same; B backs out one layer | fine — shared path |
| **Settings — root and Controls hub** | fine — category Buttons + "← Back" | fine — scope `SettingsScreen.gd:59`; Esc steps up a level (`:65`); returns to the entry you came from (`test_backing_out_of_the_mouse_page_returns_to_the_mouse_entry`) | fine — same | fine — shared path |
| **Settings — Game** (Difficulty dropdown, Auto-Save toggle) | fine — OptionButton + CheckButton | fine — Enter opens the list, arrows pick, Esc closes it; Enter toggles | fine — same with A / d-pad / B | fine — shared path (`test_a_dropdown_works_from_the_stick`) |
| **Settings — Keyboard** (status, profile picker, profile name, 7 bindings, ↺, reset) | **fixed (03a5e4b)** — bindings and ↺ are Buttons; name field clicks/selects (Task 5). Clicking "← Back" (or anything that rebuilds the page) mid-wait ended the wait but left the page out of the focus guard, so the arrows / d-pad then found no highlight — or, over the main menu, one behind the panel; a rebuild now hands it back (`test_backing_out_mid_wait_hands_the_page_back_to_the_focus_guard`) | **fixed (558a0a5, 03a5e4b)** — the page is taller than its scroll area (552 of 408 px) and didn't follow the highlight; now it does (`test_the_long_settings_pages_scroll_to_the_highlighted_row`). Press-to-bind: Enter, then a key; Esc cancels (`SettingsScreen.gd:630`). Name field: typing starts on arrival; Up/Down first moves the caret, then leaves | **fixed (558a0a5, 03a5e4b)** — scroll follows; and A on a key binding left a pad player stuck waiting for a key — B now ends the wait (`SettingsScreen.gd:637`, `test_a_controller_backs_out_of_waiting_for_a_key`). Name field: **open** — needs a keyboard to type (see Open gaps) | fine — shared path, scrollbar drag for the lower rows; the stick is off while a binding waits, by design (`test_rebinding_sees_the_stick_press_and_the_right_stick`). Name field: **open** (as highlight) |
| **Settings — Controller** (status, two stick sliders, note, profiles, 8 bindings incl. Cursor Click, reset) | **fixed (03a5e4b)** — as Keyboard page (a Back click mid-wait now hands the page back to the focus guard); sliders drag (`test_dragging_a_slider_follows_the_cursor`) | **fixed (558a0a5, 03a5e4b)** — 674 of 408 px, now follows the highlight; Enter on a binding then a pad button; Esc cancels | **fixed (558a0a5, 03a5e4b)** — follows the highlight; sliders keep left/right (`test_holding_left_or_right_on_a_slider_leaves_focus_on_it`); every pad button binds, B included, by design (R3 and B must be bindable). Name field **open**. Layout: play-test (note line + Cursor Click row fit) | fine — shared path; R3 is bindable (`test_the_right_stick_cannot_be_bound_to_an_action` keeps the stick itself unbindable) |
| **Settings — Mouse** (Cursor Shape, Cursor Colour, Mouse Sensitivity) | fine — ◀ ▶ are click-only Buttons (`test_the_arrow_buttons_click_and_are_not_focus_stops`); slider drags | fine — three stops + Back (`test_the_mouse_page_is_reachable_by_focus_navigation`); left/right step a row (`test_left_and_right_change_a_focused_row`) | play-test — one left-stick push = one step and held repeat are pinned (`test_a_stick_steps_once_per_push_not_once_per_motion_event`, `test_a_held_stick_repeats_at_the_nav_repeat_cadence_not_per_motion_event`) but want a real pad; icon crispness at 1× | fine — shared path |
| **Settings — Audio** (three volume sliders) | fine — sliders drag | fine — left/right change, focus stays (`test_holding_left_or_right_on_a_slider_leaves_focus_on_it`) | fine — same | fine — hold Cursor Click to drag (`test_holding_the_stick_press_drags_a_slider`) |
| **Settings — Display** (Window Mode, Resolution dropdowns) | play-test — list opens and picks with the cursor drawn over it (pinned: `test_a_dropdown_item_is_chosen_by_clicking_it_and_the_cursor_shows_over_the_list`); changing Window Mode keeps the cursor working | fine — Enter / arrows / Esc on the list | fine — A / d-pad / B | play-test — as mouse (`test_a_dropdown_works_from_the_stick`) |
| **Settings — Performance** (Max FPS row, V-Sync, FPS counter) | fine — ◀ ▶ click; toggles click (`test_max_fps_is_a_left_right_row`) | fine — left/right step, Enter toggles | play-test — one push one step with a real pad (Task 9) | fine — shared path |
| **Items** (4 tabs, ?, Use, target picker) | fine — tabs, ?, Use, target rows are Buttons | fine — tabs on Q/E (`ItemsScreen.gd:150`), list follows focus (`:230`), Esc closes the picker first (`:144`), then the page (pause menu) | fine — L1/R1 tabs; every row reachable (`test_question_marks_are_controller_reachable_in_every_tab`, `test_a_row_without_a_use_button_is_still_reachable`) | fine — shared path |
| **Equipment** (hero tabs, 5 slots, Unequip, Equip list) | fine — all Buttons | **fixed (1d4540d)** — a full set of spare accessories runs past the page (754 of 537 px) and the highlight walked out of sight; the page now follows it (`test_the_gear_list_scrolls_to_the_highlighted_piece`). Q/E heroes (`EquipmentScreen.gd:84`) | **fixed (1d4540d)** — same; L1/R1 heroes | fine — shared path; scrollbar drag for a long list |
| **Stats** (hero tabs, move cards — pick two to swap) | fine — every card has a click target (`test_every_equipped_card_has_a_click_target`, `test_pressing_two_cards_swaps_them`) | fine — Q/E heroes (`StatsScreen.gd:155`); cards focusable; fits without scrolling (481 of 537 px measured) | fine — `test_cards_are_focusable_on_a_controller`, `test_controller_can_reorder_with_the_focused_card`, `test_move_cards_loop_on_a_controller` | fine — shared path |
| **Quests** (Active / Side Quests tabs, Set as Active) | fine — tabs + Buttons | fine — Q/E tabs, Esc back (`QuestScreen.gd:43`), list follows focus (`:116`) | fine — L1/R1, B back | fine — shared path |
| **Moves** (loadout — campfire and trainer) | fine — slots, pool rows, ?, ✕, hero buttons are Buttons | fine — Esc closes (`LoadoutScreen.gd:55`); pool follows focus (`test_the_list_scrolls_to_a_row_reached_by_keyboard_or_controller`); panel fits with a details panel open (599 of 648 px) | fine — same, B closes | fine — shared path |
| **Shops** (Buy / Sell tabs, Buy, Sell, Leave) | fine — all Buttons | fine — Esc leaves (`ShopScreen.gd:43`), Q/E tabs, list follows focus (`:118`) | **fixed (66068ac)** — Start (pause, not cancel) opened the pause menu hidden beneath the shop and took the highlight; now the pause key waits (`OverworldScene.gd:232`, `test_the_pause_key_leaves_an_open_shop_alone`). B leaves | fine — shared path |
| **Rest area (campfire) / inn** | fine — campfire menu Buttons; the inn is a dialogue with choice Buttons | fine — Esc leaves the camp from any step (`RestScreen.gd:38`) — see Notes | **fixed (66068ac)** — Start opened the hidden pause menu over the campfire too; fixed with the shops | fine — shared path |
| **Dialogue box** (advance, choices) | **fixed (5ef41d8)** — the box's panel stopped clicks, so a click on the box never reached the advance (only a click elsewhere did); it now lets them through (`DialogueBox.gd:65`, `test_a_click_on_the_dialogue_box_advances_it`). Choices are Buttons and keep their clicks. play-test: one click = one line with a real mouse | **fixed (66068ac)** — Esc mid-conversation opened the pause menu under the dialogue box, which covered its lower buttons; the pause key now waits (`test_the_pause_key_waits_for_a_conversation_to_end`). Enter advances; choices take focus (`:192`); no Back by design (the choices include the decline) | **fixed (66068ac)** — same for Start; A advances | **fixed (5ef41d8)** — Cursor Click on the box advances, as the mouse now does (shared path) |
| **Battle — action menu** (Attack, Special, Items, Run, Resonance) | fine — Buttons from `BattleScene.tscn` | fine — scope follows visibility (`BattleScene.gd:616`); shown only while the hero may act (`test_the_action_menu_hides_once_the_hero_has_chosen`); nothing to go back to | fine — same | fine — shared path |
| **Battle — Attack / Special menus** | fine — move Buttons + ? + Back | fine — scope (`AttackMenu.gd:48`); Esc / Backspace back (`:28`, `test_backing_out_of_a_menu_on_your_turn_brings_the_menu_back`) | fine — B back | fine — shared path |
| **Battle — target selection** (enemy cards, hero panels) | play-test — a full-size Button over each card / panel, hover lights it (`BattleScene.gd:1126`, `:1237`); confirm hover with a real mouse | fine — enemy / party scopes (`:1116`, `:1119`), first target focused, Esc / Backspace back (`:1100`), "← Back" button (`test_target_selection_keeps_the_action_menu`) | fine — same; each panel aims at its own hero (`test_each_hero_panel_targets_its_own_hero`) | fine — shared path (`mouse_entered` sees pushed moves) |
| **Battle — Items menu** | fine — Use rows, ?, Back | fine — scope (`ItemsMenu.gd:38`), follows focus (`:105`), Esc back (`:18`) | fine — B back | fine — shared path; scrollbar drag for a long list |
| **Battle — Resonance menu** | fine — attack rows + ? (a locked row's ? stays live) | fine — scope (`ResonanceMenu.gd:63`), locked rows `FOCUS_NONE` (`:223`), Esc back (`:47`) | fine — B back | fine — shared path |
| **Battle — Victory** | fine — Continue / Level Up! Button | fine — scope (`VictoryScreen.gd:266`, re-registered `:305`); nothing to go back to | fine — same | fine — shared path |
| **Battle — Level-up** (stat picks, "Yes, Upgrade", stop the spin) | play-test — stat + confirm Buttons; any press stops the spin (`LevelUpScreen.gd:51`) — confirm one click stops it exactly once | fine — scope (`:93`); Enter stops the spin; Esc / Backspace cancels a pick (`:57`) | fine — A / B | fine — Cursor Click stops the spin (shared path) |
| **Battle — Defeat** (Load Last Save / Quit to Main Menu) | fine — Buttons | fine — scope (`DefeatScreen.gd:92`); greyed Load is skipped; nothing to go back to | fine — same | fine — shared path |
| **Overworld and interiors** (moving, zones, transitions, talking, campfire) | fine by design — walking, talking (`NPC.gd:144`, confirm) and the pause key are keyboard/controller; the mouse isn't used on the map | fine — `move_*` actions (`Player.gd:11`); zones and doors fire on walking in (`MapZone`, `body_entered`) | fine — left stick / d-pad, A talks | fine by design — as mouse |
| **Overworld pause / save path** (pause key → Save Game → toast) | fine — once open, the pause menu is all Buttons (row above) | fine — Esc opens, Save Game saves and toasts; the pause key now waits during a conversation or over a shop / camp / trainer (**66068ac**) | fine — Start opens; same rule (**66068ac**) | fine — shared path once open |

## Open gaps (left for a decision)

1. **Renaming a keybind profile needs a keyboard.** On the Keyboard and Controller
   pages the "Rename" field can be reached with the d-pad and clicked with the
   stick cursor, but a controller has no way to type. The profiles still work on a
   pad (they keep their "Profile 1–3" names, and switching uses the dropdown).
   Making it typeable on a pad would need an on-screen keyboard — a new piece of UI
   with its own design, so it was not built here.

## Notes (fine, but worth knowing)

- **Campfire:** Esc / B leaves the camp from any step, while the on-screen "← Back"
  in "Rest until…" steps back to the camp menu. Both are a way out; they just go
  different distances.
- **Waiting for a controller button** on the Controller page, every pad button
  binds — B included, so B can be bound. A pad-only player who changes their mind
  presses the row's old button again, or uses ↺. Esc or a click on "← Back" also
  cancels.
- **Tooltips** (a status chip's full name, the "+N" chip's hidden list, the Items
  "?" hint) need a pointer — the mouse or the stick cursor. They add detail only;
  nothing you need is tooltip-only.
- After Enter in a profile-name field the highlight goes back to the top of the
  page (the field lets go of focus when it saves the name).

## Manual play-test checklist

Plain steps for a real play session. Each says what to do and what should happen.

**Fixes from this pass**
- [ ] Settings → Controls → **Keyboard**, then **Controller**: press Down (arrow key,
  then d-pad) all the way to the bottom. The page scrolls so the highlighted row is
  always visible, down to "Reset This Profile to Defaults" and Back.
- [ ] Settings → Controls → **Keyboard** with a controller: press A on any binding
  (it says "Press…"), then press **B**. It goes back to showing the key, nothing
  changes, and the d-pad moves the highlight again.
- [ ] Pause → **Equipment** with lots of spare accessories (pick Accessory 1): press
  Down through the list. It scrolls to keep the highlighted Equip button visible.
- [ ] In a shop, at the campfire, and on a trainer's Moves page, press **Start**.
  Nothing happens (no pause menu opens behind the screen); the highlight stays put.
  B / Esc still leaves.
- [ ] Talk to an NPC and click **on the dialogue box itself** (mouse), then point the stick cursor at it and press R3. Each click shows the next line. With choices showing, clicking a choice picks it.
- [ ] Settings → Controls → Keyboard: click a binding (it says "Press…"), then click **← Back** with the mouse. Now press an arrow key (and, separately, the d-pad): the highlight appears on the Controls page — not on the main menu behind it.
- [ ] Talk to an NPC and press **Esc** (keyboard) and **Start** (pad) mid-conversation.
  No pause menu opens. Finish the conversation, press Esc again: the pause menu opens.

**Real mouse, real game**
- [ ] Main menu and pause menu: hover each entry (it lights, the cursor glows, the
  hover sound plays once) and click it (it opens).
- [ ] Settings → Display: open **Window Mode** and **Resolution**. The cursor is drawn
  over the open list, hovering lights rows, a click picks one.
- [ ] Change Window Mode (Fullscreen → Windowed → Borderless → Fullscreen). After each,
  the cursor still moves, hovers and clicks.
- [ ] In battle, pick a target: hovering an enemy card or a hero panel lights it; a
  click picks it.
- [ ] Level up after a battle: one click stops the spin once (it doesn't also press
  anything else). In a conversation, one click advances exactly one line.
- [ ] Hover a status chip in battle and the Items screen's "?" with the mouse, then
  with the stick cursor: the tooltip shows for both.

**Right stick (controller)**
- [ ] The right stick moves the cursor at a comfortable speed at 1.00× (Right Stick
  Sensitivity); full tilt crosses the screen in about a second and a half.
- [ ] R3 clicks wherever the cursor is. Holding R3 and moving the stick drags a volume
  slider, and drags the scrollbar on the Settings Keyboard page.
- [ ] Use the d-pad (the cursor hides), then press R3: the first press only brings the
  cursor back where it was; the second clicks.
- [ ] Settings → Controls → Controller: the line "Right stick moves the cursor — press
  it to click." and the **Cursor Click** row fit the column and read well.
- [ ] Settings → Controls → Mouse and Performance → Max FPS: one left-stick push moves
  exactly one choice; holding repeats at a steady pace. The shape icon looks crisp on
  a 1× (non-Retina) window.
- [ ] Windowed: if the stick drifts, it may pick the mouse back up after it slipped out
  of the window — note whether that happens on your pad.

**Windowed mode and the mouse leaving the window**
- [ ] Windowed: push the mouse out past each edge. It leaves at the same spot where the
  cursor was. Click back in: the cursor appears where you clicked, and that click
  presses nothing.
- [ ] Right after picking the mouse up (and right after launch), hover works on the
  very first move, and the pointer carries on smoothly after it slips out.
- [ ] Cmd-Tab away and back: windowed waits for a click; fullscreen and borderless take
  the mouse straight back. Minimise and restore. Open Mission Control while the game
  holds the mouse and come back.
- [ ] On a Retina screen, the system pointer shown while the mouse is let go is the same
  size as the drawn cursor.
- [ ] Leave native fullscreen for Windowed from Settings: note whether the mouse
  arrives let go (one click picks it up — expected). Borderless → Windowed always
  lets go (known; one click).
- [ ] Some windowed launches (about 1 in 6 on macOS) start with the mouse let go
  because macOS takes focus during startup — one click picks it up. Note if it is
  more often than that.

**From the Godot editor**
- [ ] Run the game from the editor and press **F8** inside the game window: it stops.
- [ ] If you use the embedded Game tab: note how focus and capture behave, and whether
  both the drawn cursor and the editor's pointer show.
