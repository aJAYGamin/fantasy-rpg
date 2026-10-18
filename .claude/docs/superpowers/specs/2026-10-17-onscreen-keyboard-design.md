# On-screen keyboard — renaming controller profiles on a pad (design)

**Date:** 2026-10-17 · **Branch:** `onscreen-keyboard` (off `main` once `themed-cursor` is
merged) · **Look:** `2026-10-17-onscreen-keyboard-mockup.html` beside this file is the
approved layout (open it in a browser; it uses the game's Cinzel font and panel colours).

## Why

The user's rule is that every screen is fully usable by controller, keyboard **and**
mouse. The themed-cursor every-screen pass
(`.claude/docs/superpowers/notes/2026-10-17-every-screen-every-input.md`) found one gap it
left open on purpose because it needs new UI: on Settings → Controls → **Controller**, the
**Rename** field (`SettingsScreen._pad_profile_name`, a `LineEdit`) can be reached with the
d-pad highlight and clicked with the stick cursor, but a controller has no way to type. The
user would rename their controller profiles ("Couch", "Boss fights"), so this is a real
feature for them, not only a box to tick.

## Goals

- A pad-only player can rename any of the three **controller** profiles, start to finish,
  without touching a keyboard or mouse.
- It feels like a console's on-screen keyboard and looks like the rest of the game
  (amethyst panel, Cinzel, `BattleUITheme`).
- Keyboard and mouse use of both Rename fields is exactly as it is today.

## Non-goals

- **The Keyboard page's Rename field gets no on-screen keyboard.** The user's point: a
  player on a controller has no reason to rename the *keyboard* profiles, and a player
  renaming those has a keyboard. That field stays keyboard/mouse only.
- No moving the caret inside the name: letters are added and deleted at the end only.
- No other text fields: there are none in the game today. (The panel should still be
  built as its own reusable piece, see "Left to the builder".)
- No new name rules: the name is cleaned exactly as today (`InputProfiles.set_name`).

## Anti-goals (would be a failure even if it technically works)

- Pressing **B** to fix a typo throws away the whole name. (This is why B deletes a letter,
  and closing without saving is on X.)
- A button pressed in the panel also acts on the page or menu behind it: B backing the
  Settings page out a level, Start re-opening the pause menu, Esc closing the pause menu.
- Anything default-themed (grey Godot buttons, a plain popup) — the project's aesthetic rule.
- A mouse player who clicks the Controller page's field gets a keyboard panel instead of a
  caret.

## How it behaves (agreed with the user)

### Opening

- On the **Controller** page, pressing the pad's **Confirm** (A by default) on the
  highlighted Rename field opens the panel.
- Clicking the field with the **stick cursor** (Cursor Click, R3 by default) opens it too.
- Clicking the field with a **real mouse** does not: the caret goes in and the player types
  on their keyboard, as today. *(Claude's call — the user approved it in the playback.)*
  Today a Cursor Click and a mouse click are the same `InputEventMouseButton` by the time
  they reach the field, so the cursor has to mark the clicks it makes (see constraints).
- Arriving on the field with the keyboard's arrow keys and typing works as today; Enter on
  the field does not open the panel.
- The panel opens over the Settings page, which stays visible but dimmed behind it, and
  shows the profile's **current name** with the caret at its end.

### The panel (approved mockup: layout B, QWERTY)

```
            ✦ Rename Profile ✦
          [   Couch|            ]          ← the name being typed
                  5 / 18                    ← length / InputProfiles.MAX_NAME_LENGTH
  1  2  3  4  5  6  7  8  9  0
  Q  W  E  R  T  Y  U  I  O  P
  A  S  D  F  G  H  J  K  L  '
  ⇧  Z  X  C  V  B  N  M  -  ⌫
  [ ! ? ][    Space    ][✕ Cancel][✓ Done]
  A Type · B Delete · X Cancel · Y Space · LB Caps · Start Done   ← legend
```

- The d-pad (and left stick) moves the glowing highlight between keys; holding a direction
  repeats, and the edges wrap, as everywhere else (the focus guard does both).
- **⇧** toggles capitals; the letter keys show the case they will type.
- **! ?** swaps the letter keys for a page of punctuation; pressing it again swaps back.
- At 18 characters, letter/space keys add nothing more (the count reads "18 / 18").
- *(Claude's call)* The highlight starts on **Q** each time the panel opens.

### Controller buttons (agreed with the user)

| Button | Does |
|---|---|
| **A** (the player's **Confirm**) | presses the highlighted key |
| **B** (the player's **Cancel / Back**) | deletes the last letter (nothing when empty) |
| **X** | closes **without saving**; the name stays what it was |
| **Y** | adds a space |
| **LB** | toggles capitals (same as ⇧) |
| **Start** (the player's **Pause / Menu**) | finishes and saves |

*(Claude's call, approved in the playback)* A, B and Start follow the player's remapped
**Confirm**, **Cancel / Back** and **Pause / Menu** controller bindings from the Controller
page; X, Y and LB are fixed buttons, the way L1/R1 tab switching is fixed today
(`FocusUtil`). If a fixed button is also one of the player's remapped Confirm / Cancel /
Pause buttons, the remapped meaning wins. The legend shows the player's actual buttons for
the three that follow bindings, using the game's own button names
(`InputMapConfig.joy_button_name`).

### Finishing and saving

- **Done** (the key, Start, or Enter) sends the typed name through the existing rename path
  (`SettingsScreen._on_profile_renamed` → `InputProfiles.set_name` → `save_input_config`):
  ends trimmed, capped at 18, a blank name falls back to "Profile 1/2/3". The Active
  Profile dropdown and the field show the stored name at once.
- **Cancel** (the ✕ key, X, or Esc) closes and changes nothing.
- Either way the panel closes and the highlight goes back to the **Rename** field
  *(Claude's call)*, so a pad player is where they started.

### Every input inside the panel

- **Controller highlight:** as above.
- **Stick cursor / mouse:** every key, ✕ Cancel and ✓ Done is a clickable button (glows
  under the cursor). Pad buttons keep working while the cursor is up.
- **Keyboard** *(Claude's call, approved in the playback)*: typing a character adds it,
  Backspace deletes, **Enter** finishes, **Esc** cancels. The arrow keys move the highlight
  like the d-pad, but Enter means Done here, not "press the highlighted key" — someone with
  a keyboard types the letter instead.
- While the panel is open, **every** key and pad press it receives stops at the panel:
  nothing reaches the Settings page, the pause menu, the overworld's pause handler or the
  L1/R1 tab helpers behind it.

## The look

Match the mockup. Everything from `BattleUITheme`; nothing default-themed.

- Full-screen dim (as the Settings page's own dim), then a centred panel about 470 base px
  wide: `PANEL_BG` with a 2 px `PANEL_BORDER` border and the theme's rounded corners and
  shadow.
- Title "✦ Rename Profile ✦" in `font_bold()`, the Settings page's `ACCENT` colour.
- Name box: `BUTTON_HOVER_BG` with a 2 px `PANEL_BORDER` border (the Rename field's own
  focus style), text `TEXT_PRIMARY`, a caret at the end. Count line in the Settings
  page's `NOTE_COLOR`.
- Keys: themed buttons (`BattleUITheme.make_button` / `style_button`), equal-width grid of
  10 columns, the action keys (⇧ ⌫ ! ? ✕ Cancel ✓ Done) in `TEXT_SUBTITLE`. The
  highlighted key uses the game's normal focus highlight.
- Legend: one or two small lines in `NOTE_COLOR`, button names in `TEXT_SUBTITLE` (the
  game's names are long, e.g. "B / Circle", so two lines is fine).
- Cinzel draws lowercase as small capitals, so "couch" and "COUCH" differ only in size. That
  is the game's font, not a bug.

## Constraints from the codebase

- **Never read the OS mouse position** (CLAUDE.md, Themed cursor). Use the event's position
  or `GameManager.virtual_cursor.pointer_pos`.
- **Telling a Cursor Click from a mouse click.** `VirtualCursor._push_click` turns Cursor
  Click into a plain left `InputEventMouseButton`. The cursor must leave a mark the field
  can read (for example a flag it sets for the click it is pushing, or something on the
  event itself) without changing what any other control sees. Nothing outside
  `scripts/cursor/` may start reading the mouse another way.
- **Focus.** The panel registers its own focus scope when it opens (it then sits on top and
  the Settings page is locked out) and unregisters when it closes; it uses
  `GameManager.set_preferred_focus` to start on Q, and hands focus back to the Rename field
  on close. Controls built while in mouse mode must still become focusable when the pad is
  used (the focus guard handles this for a registered scope).
- **Input order.** `OverworldScene._input` opens/re-opens the pause menu on `pause`,
  `PauseMenu._input` backs out on `ui_cancel`, `SettingsScreen._input` backs out a view on
  `ui_cancel`. The panel must take its presses before all of them and mark them handled.
  Test this rather than assume it.
- **The field already commits on focus loss** (`_name_field`: `focus_exited` →
  `on_commit`). Opening the panel takes focus from the field; make sure that does not save
  a half-typed or unchanged name in a way that matters, and that Cancel leaves the
  config untouched.
- **A page rebuild while the panel is open** (`SettingsScreen._build`, e.g. a controller
  connecting) must not leave a stray panel or a stale focus scope: treat it as Cancel.
- **The rebind wait** (`_listening`, `raw_input_passthrough`) and the panel are never open
  at the same time.
- **The press that opens the panel must not also type.** The A press (or the Cursor Click)
  that opens it, and its release, must not press the key the highlight lands on. Likewise
  the Start / X / Esc that closes it must not reach anything behind it.
- **Space and Enter are the keyboard's Confirm** (`confirm` → `ui_accept` holds Enter,
  Space and A; Esc is both `cancel` and `pause`). In the panel a typed Space adds a space
  and Enter finishes; neither presses the highlighted key. The arrow keys and the d-pad
  still move the highlight, so only printable characters, Backspace, Enter and Esc are
  taken as typing.
- **Holding B or Backspace deletes repeatedly** *(Claude's call)* — Backspace through the
  key's own echo, B with the same rhythm as a held direction (`HoldRepeat`).
- **`PROCESS_MODE_ALWAYS`** like the Settings page: the panel works with the tree paused
  (the pause menu).
- **Tests run headless only**, with the command in CLAUDE.md, and the output must have no
  `SCRIPT ERROR`. A new `class_name` file needs the `--editor --quit-after 3` class-cache
  rescan once.

## Left to the builder

- Names and files (e.g. `scripts/ui/OnScreenKeyboard.gd`, `class_name OnScreenKeyboard`, a
  `Control` with `finished(text)` / `cancelled` signals and an `open(initial, max_length)`
  call), and where it sits in the tree.
- How the cursor marks its own clicks.
- The punctuation set (only characters Cinzel actually draws), key sizes and spacing within
  the mockup's look, the legend's exact wording.
- Whether the pad-button actions (B, X, Y, LB, Start) play the menu click that pressing a
  key button already plays (every Button gets it from GameManager).
- Test split: the panel on its own in a new `tests/suites/test_onscreen_keyboard.gd`
  (registered in `TestRunner.SUITE_PATHS`), the Settings wiring in
  `tests/suites/test_settings.gd`.

## Done means

- On the Controller page, with only a pad: A on Rename opens the panel; type "Couch",
  fix a typo with B, add a space with Y, capitals with LB, Start saves. The dropdown and the
  field say the new name, it survives a restart (`config.cfg`), and the highlight is back
  on Rename. X instead leaves the old name.
- The same with the stick cursor clicking the field and the keys.
- From the pause menu and from the main menu, no button pressed in the panel closes or
  changes anything behind it.
- Keyboard page: nothing new. Controller page with a mouse click: caret, type, Enter — as
  today.
- Headless tests green, no `SCRIPT ERROR`, the suites touched assert more than before.
- Docs: the every-screen record's Settings — Keyboard / Controller cells and "Open gaps"
  item 1 updated (Keyboard page: by design keyboard-only; Controller page: fixed), new
  play-test checklist steps; CLAUDE.md's Themed cursor "Open:" line, Deferred list, the
  Settings description and the test counts / suite list.

## Calls Claude made (for the user to check)

1. Mouse click on the Controller page's field → caret as today; only the pad (A or the
   stick cursor's click) opens the panel.
2. Letters are added and deleted at the end only; no caret moving.
3. A real keyboard works inside the panel (type, Backspace, Enter = Done, Esc = Cancel).
4. A ✕ Cancel key on the bottom row, so the mouse / stick cursor can close it.
5. A, B and Start follow the player's remapped Confirm / Cancel / Pause; X, Y, LB are fixed.
6. The highlight starts on Q; after closing, it returns to the Rename field.
7. Capitals stay on until toggled off (a lock, not one letter).
8. Holding B or Backspace keeps deleting.
