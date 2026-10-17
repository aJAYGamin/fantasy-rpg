# Themed Cursor & Mouse Sensitivity — Design

**Status:** agreed in chat, awaiting written review
**Track:** C (hardening) — the "virtual cursor + mouse sensitivity" item (was P4's deferred "Chunk D")
**Date:** 2026-10-17
**Art reference (source of truth for every shape and colour):**
`2026-10-17-themed-cursor-art.html` in this folder — open it in a browser.

## Intent

Replace the computer's ordinary arrow with a cursor that belongs to *The Amethyst
Requiem*, let players pick its shape and colour, and give them an in-game mouse
sensitivity setting. A sensitivity setting is the reason this is more than a
skin: the computer decides how fast its own pointer moves, so for the game to
change that speed it has to take over the mouse and draw and move the cursor
itself.

The user also set a standing rule for this work: **the entire UI must be usable
with a controller, with a keyboard, and with a mouse**, because input comes from
any of the three. The new cursor must not take anything away from any of them.

## Decisions made with the user

| Topic | Decision |
|---|---|
| Scope | The themed look **and** an in-game mouse sensitivity setting **and** a player choice of cursor style. |
| Shapes | Ten, approved one by one from mockups (below). Clean, bold, single silhouettes. |
| Colours | Twenty, each available on every shape, with one-word thematic names (below). Every colour must read on any background — dark menus and the bright overworld alike. |
| Readability | Every cursor has a **thin dark outer edge under its light rim**. On **AK** and **AR**, every colour except Void, Obsidian and Lunar uses a deeper shade map so it doesn't melt into the plains (the user flagged these individually). |
| Hover | Over anything clickable the cursor **brightens and glows in its own colour** (as shown on every mockup; exact values under *The cursor everywhere else*). |
| Where players choose | **Settings → Controls → Mouse**, a third page beside Keyboard and Controller. |
| Page layout | **Compact**: one row each — Cursor Shape `◀ name ▶`, Cursor Colour `◀ name ▶`, Mouse Sensitivity slider. **No preview section** on this page. |
| Fullscreen | The game holds the mouse while it is in front; the player sees only the game's cursor. |
| Windowed | Pushing the cursor past the window's edge lets it **slip out to the desktop**; **clicking back in** picks it up again. |
| All inputs | Every screen must be fully usable by controller, by keyboard, and by mouse. |

### The ten shapes

Ids are the letters used during the mockups; keep them as the shapes' ids so the
art reference, this document and the code agree.

| Id | Name | Look |
|---|---|---|
| A | Amethyst Arrow | the classic arrow, smooth gradient fill, light rim — **default** |
| B | Crystal Shard | four-facet kite crystal |
| K | Gem-cut Arrow | the arrow cut into five facets |
| L | Dart | notched arrowhead in two tones |
| S | Prism | bevelled triangle with a raised centre |
| AB | Sticker Arrow | flat bright arrow with a thick border |
| AK | Brilliant Diamond | even diamond, bevelled, coloured centre facet |
| AR | Trilliant | curved-sided triangle with a nine-facet brilliant cut |
| AS | Starlit Arrow | the arrow filled with a starry night sky |
| AV | Low-Poly Arrow | the arrow broken into many small facets |

### The twenty colours

In wheel order (the order the Colour row steps through):
Amethyst (**default**), Arcane, Rose, Garnet, Ember, Blaze, Gilded, Storm, Terra,
Venom, Gale, Grove, Spirit, Frost, Tidal, Abyss, Void, Obsidian, Steel, Lunar.
Their exact shades are the palettes in the art reference.

### How the art reference is organised

- Each shape is an SVG `<symbol>` (`#A`, `#B`, …) drawn in symbol units. Its
  paints come from the chosen colour's **palette**, written as CSS custom
  properties on the colour's class (`.c-amethyst`, …):
  `--s0` … `--s7` (eight shades, light → dark), `--rim` (the light rim),
  `--flat` (AB's flat fill), `--border` (AB's thick border), `--grad`
  (A's gradient), `--night` (AS's night-sky gradient). `--edge` is the shared
  dark outer edge.
- AK and AR read their own slot maps (`--ak*`, `--ar*`). The defaults are the
  deeper maps; Void, Obsidian and Lunar override them back to the original cut.
- The **hotspot** — the exact point that clicks — is each shape's tip:
  (1.5, 1.5) in symbol units, (2.5, 2.5) for AB. Every shape points up-left.
- The sheet's tiles show each cursor at roughly its real size; the game should
  draw them at about that size (≈24 × 28 px at the game's 1152 × 648 base
  resolution, scaling with the window like the rest of the UI).

## Behaviour

### The Mouse page (Settings → Controls → Mouse)

- **Cursor Shape** — `◀ ▶` steps through the ten shapes in the table's order,
  wrapping round. The row shows the shape's name and a small icon of that shape
  in the currently chosen colour.
- **Cursor Colour** — `◀ ▶` steps through the twenty colours in wheel order,
  wrapping round. The row shows the colour's name and a dot of that colour.
- **Mouse Sensitivity** — a slider styled like the existing stick-sensitivity
  sliders.
- Works with all three inputs: mouse (click the arrows, drag the slider),
  keyboard and controller (up/down between rows, left/right to change a row,
  like the other settings pages).
- *My call:* changes apply to the live cursor immediately — the real cursor is
  the preview, which is why the page needs no preview section.
- *My call:* the three choices are saved with the other settings
  (`user://config.cfg`), not per save slot, and survive a restart.
- *My call:* sensitivity runs **0.25× to 3.00×** in 0.05 steps, default
  **1.00×**, shown as `1.00×` like the stick sliders. 1.00× should feel the same
  speed as the desktop pointer.

### The cursor everywhere else

- Shown in **every** scene — menus, battle, overworld, interiors — on top of
  everything (above banners, fades and the save indicator), and it keeps working
  while the game is paused and across scene changes.
- Everything the mouse does today keeps working exactly as before: hovering
  (including the hover sound), clicking, double-clicking, wheel scrolling,
  dragging sliders and scrollbars, and clicking into and selecting text in the
  profile-name fields on the Keyboard and Controller pages.
- The hover glow appears over anything clickable. It is exactly the mockups'
  glow: the cursor drawn **20% brighter** with **two soft glows** behind it — a
  4 px blur in the colour's light tone (`--s2`) and an 8 px blur in its mid tone
  (`--s4`), at the cursor's real size. Void, Obsidian and Lunar glow in their
  rim colours instead (values in the art reference). Hover any cursor in the
  art reference to see it. The Stats screen's one "pointing hand" hover cursor
  is replaced by this glow (no per-control cursor shapes any more).
- The cursor stays visible above **open dropdown lists** too (Window Mode,
  Resolution and Max FPS in Settings). *My call:* the dropdowns stay as they
  are; it's the cursor that must draw above them.
- *My call:* the game draws its cursor once per frame, so with Max FPS capped
  very low (30) it moves a little less smoothly than the desktop pointer. That
  is accepted, not worked around.
- *My call:* the cursor shows only while the mouse is the input in use. Using
  the keyboard or a controller hides it (the game already switches menus to
  focus navigation then); moving the mouse brings it back where it was.
- *My call:* the controller's right stick does **not** move the cursor. It stays
  reserved, as the Controller page already says.
- *My call:* no click animation — the hover glow is the feedback.

### Holding and releasing the mouse

- **Fullscreen (the default) and borderless:** while the game window is in
  front, the game holds the mouse and draws its own cursor; the system pointer
  is hidden.
- **Windowed:** the same while the cursor is inside the window. When the player
  pushes it past an edge and keeps going, the mouse is let go and carries on out
  of the window from that same point, at desktop speed. While let go:
  *my call* — the system pointer wears the player's themed cursor over the game
  window (so it still looks right; it moves at desktop speed until picked up).
  **Clicking** inside the window picks the mouse up again, with the game's
  cursor appearing exactly where the click happened. *My call:* that first click
  only picks the mouse up and does not press whatever it landed on.
- Switching away from the game (Cmd/Alt-Tab, or the window losing focus for any
  reason) always lets the mouse go. *My call:* coming back to a **fullscreen or
  borderless** game picks the mouse up again straight away; coming back to a
  **windowed** game waits for a click inside the window, as above.
- At no point may the player be stuck with a mouse they can't get out of the
  window.
- *My call:* built on Godot's own cross-platform mouse handling, with nothing
  written for one operating system only. It is verified on macOS (the user's
  machine); Windows and Linux are expected to work but are untested.

## Every screen, every input

Part of this piece is a pass over every screen with each of the three inputs,
fixing any gap found, so the user's rule holds everywhere and the new cursor is
proven not to have broken anything. Screens to cover:

- Main menu, save-slot menu (load / copy / delete / new-game picker and its
  confirm prompts), pause menu and its confirm prompts.
- Settings: root, Game, Controls → Keyboard, Controller and the new Mouse page,
  Audio, Display, Performance (including press-to-bind and profile names).
- Items, Equipment, Stats, Quests, Moves (loadout), shops, rest area / inn,
  dialogue box (including choices).
- Battle: action menu, Attack / Special menus, target selection (enemies and
  hero panels), items menu, resonance menu, victory, level-up, defeat screens.
- Overworld and interiors (moving, zones, transitions, the pause/save path).

For each screen and each input: every control can be reached and used, and
Back / cancel works. Keep a short written record of the pass (screen × input,
fine or fixed) for the user.

## Success criteria

1. The player sees their chosen themed cursor everywhere the mouse is in use,
   correct in shape, colour, rim, dark edge and hover glow, matching the art
   reference, and readable over dark menus and the bright overworld.
2. The Mouse page offers all ten shapes, all twenty colours and the sensitivity
   slider, works by mouse, keyboard and controller, applies changes at once, and
   remembers them across restarts.
3. Sensitivity visibly changes cursor speed across its whole range; 1.00× feels
   like the desktop pointer.
4. Nothing the mouse could do before stops working (hover, hover sound, click,
   double-click, wheel, slider and scrollbar drags, text fields).
5. Keyboard and controller play is unaffected; the cursor hides while they're in
   use and comes back with the mouse.
6. Windowed play: the mouse slips out at the edges and is picked up again by a
   click; switching apps always releases it.
7. The every-screen pass is done and recorded, with any gaps fixed.
8. The automated suite stays green, with new tests for the settings, their
   saving, and the mouse-input forwarding wherever it can be tested headless.

## Non-goals and anti-goals

- **Not** a custom system cursor on its own — that can't honour a sensitivity
  setting. (A themed system cursor is used only for the "let go" moment above.)
- **No** preview section on the Mouse page; **no** cursor-size option; **no**
  cursor movement by the right stick; **no** per-save cursor choices; **no**
  click animation.
- No new shapes or colours beyond the approved 10 × 20; no restyling of them.
- Anti-goals — any of these is a failure even if everything else works:
  any screen losing mouse, keyboard or controller usability; a cursor that lags,
  stutters or jumps; a mouse trapped inside a window; clicks landing somewhere
  other than the cursor's tip.

## Left to the builder

- How the cursor is rendered in Godot (for example, rasterising each shape's SVG
  with the colour's palette substituted in, or drawing the polygons directly),
  as long as it matches the art reference.
- How mouse input reaches the UI once the game holds the mouse (for example,
  capturing it and forwarding events at the cursor's position), how "is the
  cursor over something clickable" is detected for the glow, and how the
  windowed edge slip-out is detected.
- Whether a quick throwaway spike comes first to prove the input forwarding in
  Godot 4.6 on macOS before the plan commits to it — recommended, since every
  mouse interaction in the game depends on it.
- Test strategy beyond the settings: what can be pinned headless, and a manual
  checklist for what can't.

## Risks

- **Input forwarding is the foundation.** If clicks, hovers, drags or wheel
  scrolls don't reach controls exactly as the real mouse did, every screen
  regresses at once. Prove it early.
- **macOS specifics** — how a held mouse behaves with Cmd-Tab, Mission Control
  and the Dock; the speed of raw mouse movement compared with the desktop
  pointer (which sets what 1.00× means).
- **Existing input-mode switching** (`GameManager._input` → mouse / keyboard /
  controller modes and the focus guard) must keep seeing real mouse use, and
  must not be confused by the game's own forwarded events.
