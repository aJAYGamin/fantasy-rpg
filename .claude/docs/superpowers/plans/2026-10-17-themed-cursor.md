# Themed Cursor & Mouse Sensitivity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the system pointer with a game-drawn themed cursor (10 shapes × 20 colours) that the mouse moves at an in-game sensitivity and the controller's right stick can also move and click with, chosen on a new Settings → Controls → Mouse page — without taking any mouse, keyboard or controller ability away from any screen.

**Architecture:** A `VirtualCursor` node (created by `GameManager`, child of the root) replaces the main window's input callback (`DisplayServer.window_set_input_event_callback`). Every mouse event is re-pushed into the root window at the virtual cursor's position (`Window.push_input(ev, true)`); every other event passes straight through; right-stick motion and the Cursor Click button are turned into synthetic mouse motion/clicks. The cursor is drawn on a top `CanvasLayer`, and mirrored into any open embedded popup (dropdown lists draw above every CanvasLayer). Art is rasterised at runtime from per-shape SVG templates with the chosen palette substituted in (`Image.load_svg_from_string`). **This architecture was proven by a throwaway spike in Godot 4.6 on macOS** (hover, click, slider drag, OptionButton list selection, wheel scroll, LineEdit focus all work through the hook; the popup mirror shows the cursor over an open list; SVG gradients and clip paths render correctly).

**Tech Stack:** Godot 4.6.1, GDScript, the project's headless `TestSuite` runner.

**Spec:** `.claude/docs/superpowers/specs/2026-10-17-themed-cursor-design.md` — **art source of truth:** `.claude/docs/superpowers/specs/2026-10-17-themed-cursor-art.html` (all shape geometry and all palette values, verbatim). Executors read the spec and open the art file.

## Global Constraints

- Work on branch `themed-cursor` inside the main checkout. Never commit to `main`; never use worktrees. Never stage `.DS_Store`.
- Commits: `git commit -F <file>` — subject line, blank line, body, blank line, `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Tests: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/TestRunner.tscn --quit-after 5` from `new-game-project/`. Must end `0 failed` **and** zero `SCRIPT ERROR` lines (a runtime error aborts a test method silently). New `class_name` files need `… --headless --editor --path . --quit-after 3` once. New suites go in `tests/TestRunner.gd` `SUITE_PATHS`. Tests are synchronous; any test touching `GameManager` state restores it.
- Play-test flags (`PartyFactory.TEST_UNLOCK_ALL_SKILLS`, `GameManager.REST_REFRESH_BATTLES`, `BattleScene.TEST_SHOW_ENEMY_HP`) stay at shipping values in every commit.
- Shapes, in this order, ids and names exactly: `A` Amethyst Arrow, `B` Crystal Shard, `K` Gem-cut Arrow, `L` Dart, `S` Prism, `AB` Sticker Arrow, `AK` Brilliant Diamond, `AR` Trilliant, `AS` Starlit Arrow, `AV` Low-Poly Arrow. Default `A`.
- Colours, in this order (wheel order), ids lowercase / names capitalised: Amethyst, Arcane, Rose, Garnet, Ember, Blaze, Gilded, Storm, Terra, Venom, Gale, Grove, Spirit, Frost, Tidal, Abyss, Void, Obsidian, Steel, Lunar. Default `amethyst`.
- Hotspot = the shape's tip: (1.5, 1.5) in symbol units, (2.5, 2.5) for AB. Drawn size: 1 symbol unit = 1 base pixel at the 1152 × 648 base resolution.
- AK and AR use the deeper slot maps for every colour except `void`, `obsidian`, `lunar` (exact maps in the art file's CSS).
- Hover glow: fill 20% brighter (`× 1.2`), plus a 4 px blur in `--s2` and an 8 px blur in `--s4` (base pixels); Void `#B48CFF`/`#8C59F2`, Obsidian `#D9D9E6`/`#8C8C99`, Lunar `#FFFFFF`/`#B9C0D4`.
- Mouse sensitivity: 0.25× – 3.00×, step 0.05, default 1.00×, label format `"%.2f×"`. Right Stick Sensitivity keeps today's slider and range.
- Right stick at full tilt crosses the 1152-wide screen in about 1.5 s at 1.00× (768 base px/s), with a dead zone and finer control near the centre.
- New controller action `cursor_click`, label **Cursor Click**, default the right stick press (`JOY_BUTTON_RIGHT_STICK`), remappable, controller-only (not on the Keyboard page).
- Max FPS becomes a `◀ value ▶` row stepping Uncapped, 30, 60, 120, 144, wrapping. Window Mode and Resolution keep their dropdowns.
- The cursor draws above everything (the FPS overlay is layer 128 — the cursor uses 200), works while paused, across scene changes, and above open dropdown lists.
- Every screen stays fully usable by controller (d-pad/left-stick highlight **and** right-stick cursor), keyboard, and mouse.
- A test written below as a name plus a comment body is specified by that comment: write it as assertions on exactly the observable the comment states.

## Review Focus

1. **One physical click must reach scripts that read clicks in `_input` exactly once** (`LevelUpScreen`, `DialogueBox`): real + synthetic double delivery would skip a level-up spin or a dialogue line. → test in Task 5.
2. **Rebinding on the Controller page must still see the right-stick press and right-stick motion** while `VirtualCursor` normally consumes them. → test in Task 7.
3. **Controller profiles and configs saved before `cursor_click` existed must still click with the stick press.** → test in Task 3.
4. **Clicking an item in an open dropdown list selects it, and the cursor is drawn over the list.** → test in Task 5.
5. **Keyboard and controller events keep flowing unchanged through the hook** (Enter / controller A press a focused button; `ui_cancel` backs out). → test in Task 5.

---

## File map

| File | Responsibility |
|---|---|
| Create `scripts/cursor/CursorArt.gd` | Catalogue of shapes and colours, palettes, SVG templates → textures, hotspots, glow colours, swatch colours. Pure data + static functions. |
| Create `scripts/cursor/CursorMotion.gd` | Pure maths: mouse delta → position, stick → velocity, edge overshoot. |
| Create `scripts/cursor/CursorHold.gd` | Pure hold/release state machine (captured vs let go). |
| Create `scripts/cursor/VirtualCursor.gd` | The node: input hook and routing, drawing, popup mirrors, glow, stick + Cursor Click, hold/release side effects. |
| Create `scripts/cursor/cursor_glow.gdshader` | Brighten + two-radius glow, toggled by a uniform. |
| Create `scripts/ui/CyclerRow.gd` | Reusable `Label  ◀ [icon] value ▶` row, mouse/keyboard/controller operable. |
| Modify `scripts/settings/SettingsModel.gd` | `cursor_shape`, `cursor_colour`, `mouse_sensitivity` + validation + config. |
| Modify `scripts/settings/InputMapConfig.gd` | `cursor_click` action (pad-only), profile fallback for missing actions. |
| Modify `scripts/ui/SettingsScreen.gd` | Mouse page, Max FPS row, Controller page note + Cursor Click row, Keyboard page skips pad-only, binding-capture flag. |
| Modify `scripts/GameManager.gd` | Create `VirtualCursor`; `apply_cursor_and_save()`; `raw_input_passthrough`; notify cursor on display changes. |
| Tests | `tests/suites/test_cursor_art.gd`, `test_cursor_motion.gd`, `test_cursor_hold.gd`, `test_virtual_cursor.gd`, `test_cycler_row.gd` (new); `test_settings.gd`, `test_input_map.gd`, `test_input_profiles.gd` (extended). |
| Docs | `new-game-project/CLAUDE.md` "Themed cursor" section; `.claude/docs/superpowers/notes/2026-10-17-every-screen-every-input.md` (the pass record). |

---

### Task 1: The cursor art catalogue

**Files:**
- Create: `new-game-project/scripts/cursor/CursorArt.gd`
- Test: `new-game-project/tests/suites/test_cursor_art.gd` (register in `SUITE_PATHS`)

**Interfaces:**
- Produces (all `static`, `class_name CursorArt extends RefCounted`):
  - `const SHAPES: Array[String]`, `const COLOURS: Array[String]` (orders above), `const DEFAULT_SHAPE := "A"`, `const DEFAULT_COLOUR := "amethyst"`
  - `const RENDER_SCALE := 4.0` (textures are rasterised at 4× and drawn at ¼ for crispness)
  - `const GLOW_MARGIN := 10.0` (symbol units of transparent padding around every texture, room for the glow)
  - `static func shape_name(id: String) -> String`, `static func colour_name(id: String) -> String`
  - `static func swatch(colour: String) -> Color` — the header-dot colour from the art file's colour list (Amethyst `#8C59F2` … Void `#24183F`, Obsidian `#1A1A1F`, Lunar `#E6E9F2`)
  - `static func swatch_ring(colour: String) -> bool` — true for `void` and `obsidian`, whose dots get a 1 px `#D9D9E6` ring (as in the art file) so they show on the dark panel
  - `static func svg(shape: String, colour: String) -> String` — a complete SVG document, viewBox = the art file's viewBox grown by `GLOW_MARGIN` on every side, every `var(--…)` replaced by the palette's literal colour; the edge is `stroke="#080510" stroke-opacity="0.85"`
  - `static func texture(shape: String, colour: String, scale := RENDER_SCALE) -> ImageTexture` — cached per `shape|colour|scale`
  - `static func hotspot(shape: String) -> Vector2` — tip offset from the texture's top-left, in symbol units: `tip - viewBox_min + Vector2(GLOW_MARGIN, GLOW_MARGIN)` (A: `(1.5,1.5) - (-1,-1) + (10,10) = (12.5, 12.5)`)
  - `static func glow_colours(colour: String) -> Array[Color]` — `[glow1, glow2]`
  - `static func is_known(shape: String, colour: String) -> bool`

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_the_catalogue_lists_ten_shapes_and_twenty_colours_in_order() -> void:
	assert_eq(CursorArt.SHAPES, ["A","B","K","L","S","AB","AK","AR","AS","AV"], "shape order")
	assert_eq(CursorArt.COLOURS.size(), 20, "twenty colours")
	assert_eq(CursorArt.COLOURS[0], "amethyst", "Amethyst first")
	assert_eq(CursorArt.COLOURS[19], "lunar", "Lunar last")
	assert_eq(CursorArt.shape_name("AK"), "Brilliant Diamond", "names")
	assert_eq(CursorArt.colour_name("obsidian"), "Obsidian", "colour names")

func test_every_shape_renders_in_every_colour() -> void:
	for shape in CursorArt.SHAPES:
		for colour in CursorArt.COLOURS:
			var img := Image.new()
			var err := img.load_svg_from_string(CursorArt.svg(shape, colour), 1.0)
			assert_eq(err, OK, "%s in %s parses" % [shape, colour])
			assert_true(img.get_used_rect().size.x > 10, "%s in %s draws something" % [shape, colour])
			assert_false(CursorArt.svg(shape, colour).contains("var("), "no CSS variables left")

func test_the_hotspot_is_the_tip() -> void:
	assert_eq(CursorArt.hotspot("A"), Vector2(12.5, 12.5), "A's tip, inside the glow margin")
	assert_eq(CursorArt.hotspot("AB"), Vector2(13.5, 13.5), "AB's tip")
	# The tip pixel is opaque and the pixel up-left of it is clear.
	var img := CursorArt.texture("A", "amethyst", 1.0).get_image()
	assert_true(img.get_pixelv(Vector2i(CursorArt.hotspot("A")) + Vector2i(1, 1)).a > 0.5, "drawn at the tip")
	assert_true(img.get_pixelv(Vector2i(CursorArt.hotspot("A")) - Vector2i(4, 4)).a < 0.1, "clear beyond it")

func test_ak_and_ar_use_the_deeper_cut_except_void_obsidian_lunar() -> void:
	assert_true(CursorArt.svg("AK", "amethyst").contains("#B48CFF"), "Amethyst AK centre is s2")
	assert_true(CursorArt.svg("AK", "void").contains("#6B55A0"), "Void AK keeps its s0 centre")
	assert_true(CursorArt.svg("AR", "venom").contains('stroke-width="3.8"'), "deeper AR has the heavier edge")
	assert_true(CursorArt.svg("AR", "lunar").contains('stroke-width="3"'), "Lunar AR keeps the original edge")

func test_glow_colours() -> void:
	assert_eq(CursorArt.glow_colours("amethyst"), [Color("#B48CFF"), Color("#7E4FE0")], "s2 then s4")
	assert_eq(CursorArt.glow_colours("obsidian"), [Color("#D9D9E6"), Color("#8C8C99")], "rim glow")

func test_textures_are_cached_and_unknown_ids_are_refused() -> void:
	assert_true(CursorArt.texture("B", "tidal") == CursorArt.texture("B", "tidal"), "one texture per style")
	assert_false(CursorArt.is_known("Z", "tidal"), "unknown shape")
	assert_false(CursorArt.is_known("A", "teal"), "unknown colour")
```

- [ ] **Step 2: Run the tests — expect a parse failure ("CursorArt" not declared).**

- [ ] **Step 3: Implement `CursorArt`.** Transcribe each `<symbol>` from the art file into a per-shape SVG body template whose paints are `{token}` placeholders (`{s0}`…`{s7}`, `{rim}`, `{flat}`, `{border}`, gradient stop tokens, `{edge}`), filled with `String.format()`. Transcribe the 20 palettes verbatim from the art file's `.c-<colour>` rules; derive the AK (`ak*`) and AR (`ar*`, plus the edge width 3.8 vs 3) maps and glow colours exactly as the art file's CSS does, with `void`/`obsidian`/`lunar` as the exceptions. Gradients become `<linearGradient>` defs with literal stop colours; AS keeps its `clipPath`. Each document gets `width`/`height` equal to the grown viewBox size so `load_svg_from_string(svg, scale)` returns `size × scale` pixels.

- [ ] **Step 4: Rescan classes, run the suite — expect PASS, zero SCRIPT ERROR.**

- [ ] **Step 5: Commit** — "Add the themed cursor art catalogue (10 shapes × 20 colours)".

---

### Task 2: Cursor settings in the settings model

**Files:**
- Modify: `new-game-project/scripts/settings/SettingsModel.gd` (fields after `stick_sensitivity_right`; `clamp_all`, `from_config`, `to_config`)
- Test: `new-game-project/tests/suites/test_settings.gd`

**Interfaces:**
- Consumes: `CursorArt.SHAPES`, `COLOURS`, `DEFAULT_SHAPE`, `DEFAULT_COLOUR`, `is_known` (Task 1)
- Produces: `var cursor_shape: String`, `var cursor_colour: String`, `var mouse_sensitivity: float`; `const MOUSE_SENS_MIN := 0.25`, `MOUSE_SENS_MAX := 3.0`, `MOUSE_SENS_STEP := 0.05`; config keys `"cursor_shape"`, `"cursor_colour"`, `"mouse_sensitivity"` in the existing `[settings]` section

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_cursor_defaults() -> void:
	var s := SettingsModel.new()
	assert_eq(s.cursor_shape, "A", "Amethyst Arrow by default")
	assert_eq(s.cursor_colour, "amethyst", "in Amethyst")
	assert_near(s.mouse_sensitivity, 1.0, 0.0001, "1.00× by default")

func test_cursor_settings_round_trip_through_config() -> void:
	var a := SettingsModel.new()
	a.cursor_shape = "AK"; a.cursor_colour = "garnet"; a.mouse_sensitivity = 2.35
	var cfg := ConfigFile.new(); a.to_config(cfg)
	var b := SettingsModel.new(); b.from_config(cfg)
	assert_eq(b.cursor_shape, "AK", "shape survives a restart")
	assert_eq(b.cursor_colour, "garnet", "colour survives")
	assert_near(b.mouse_sensitivity, 2.35, 0.0001, "sensitivity survives")

func test_bad_cursor_values_fall_back() -> void:
	var s := SettingsModel.new()
	s.cursor_shape = "Z"; s.cursor_colour = "teal"; s.mouse_sensitivity = 9.0
	s.clamp_all()
	assert_eq(s.cursor_shape, "A", "unknown shape → default")
	assert_eq(s.cursor_colour, "amethyst", "unknown colour → default")
	assert_near(s.mouse_sensitivity, 3.0, 0.0001, "clamped to the top")
	s.mouse_sensitivity = 0.0; s.clamp_all()
	assert_near(s.mouse_sensitivity, 0.25, 0.0001, "clamped to the bottom")
```

- [ ] **Step 2: Run — expect FAIL (no such properties).**
- [ ] **Step 3: Add the three fields, constants, validation in `clamp_all()` and the config keys.**
- [ ] **Step 4: Run — expect PASS.**
- [ ] **Step 5: Commit** — "Remember the cursor shape, colour and mouse sensitivity".

---

### Task 3: The Cursor Click control

**Files:**
- Modify: `new-game-project/scripts/settings/InputMapConfig.gd` (`ACTIONS`, `defaults()`, `apply_device()`, new `is_pad_only()`)
- Modify: `new-game-project/scripts/ui/SettingsScreen.gd` (Keyboard page loop at ~line 323 skips pad-only actions; Controller page note at ~line 339)
- Test: `new-game-project/tests/suites/test_input_map.gd`, `test_input_profiles.gd`, `test_settings.gd`

**Interfaces:**
- Produces: action `"cursor_click"` (`ACTIONS` entry `{"action": "cursor_click", "label": "Cursor Click", "pad_only": true}`, appended last); `defaults()["cursor_click"] == [{"type": "joyb", "button": JOY_BUTTON_RIGHT_STICK}]`; `static func is_pad_only(action: String) -> bool`
- `apply_device(bindings, keyboard)`: an action **absent** from `bindings` gets that device's defaults (an action present with `[]` stays unbound — the player cleared it).
- Controller page note text, exactly: `Right stick moves the cursor — press it to click.`

- [ ] **Step 1: Write the failing tests**

```gdscript
# test_input_map.gd
func test_cursor_click_defaults_to_the_right_stick_press() -> void:
	InputMapConfig.reset_all()
	var evs := InputMap.action_get_events("cursor_click")
	assert_eq(evs.size(), 1, "one binding")
	assert_true(evs[0] is InputEventJoypadButton and evs[0].button_index == JOY_BUTTON_RIGHT_STICK, "R3")
	assert_true(InputMapConfig.is_pad_only("cursor_click"), "controller-only")
	assert_false(InputMapConfig.is_pad_only("confirm"), "others are not")

# test_input_profiles.gd — Review Focus 3
func test_a_profile_saved_before_cursor_click_still_clicks_with_the_stick() -> void:
	var old_profile := InputMapConfig.device_defaults(false)
	old_profile.erase("cursor_click")             # what an older save holds
	InputMapConfig.apply_device(old_profile, false)
	var evs := InputMap.action_get_events("cursor_click")
	assert_eq(evs.size(), 1, "falls back to the default binding")
	InputMapConfig.reset_all()

# test_settings.gd
func test_the_keyboard_page_has_no_cursor_click_row_and_the_controller_page_does() -> void:
	# build both views (same pattern as the existing SettingsScreen tests) and
	# assert a row labelled "Cursor Click" exists only on the Controller view,
	# and the note label reads exactly "Right stick moves the cursor — press it to click."
```

- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement the action, default, `is_pad_only`, the `apply_device` fallback, the Keyboard-page skip and the new note text.** The Controller page's binding list already iterates `ACTIONS`, so the Cursor Click row (press-to-bind, reset, per-profile) appears without further code.
- [ ] **Step 4: Run — expect PASS; also `test_input_profiles` and `test_focus_guard` unchanged-green.**
- [ ] **Step 5: Commit** — "Add a remappable Cursor Click control for the controller".

---

### Task 4: Cursor movement maths and the hold state machine

**Files:**
- Create: `new-game-project/scripts/cursor/CursorMotion.gd`, `new-game-project/scripts/cursor/CursorHold.gd`
- Test: `new-game-project/tests/suites/test_cursor_motion.gd`, `test_cursor_hold.gd`

**Interfaces:**
- `CursorMotion` (static): `const STICK_DEADZONE := 0.2`, `const STICK_FULL_SPEED := 768.0`, `const SLIP_OUT_DISTANCE := 24.0`;
  `static func mouse_step(pos: Vector2, rel_window: Vector2, window_scale: Vector2, sensitivity: float, bounds: Vector2) -> Vector2` (`pos + rel_window / window_scale * sensitivity`, clamped to `[0, bounds - 1]`);
  `static func stick_velocity(axis: Vector2, sensitivity: float) -> Vector2` (0 inside the dead zone; outside, magnitude `((m - dz) / (1 - dz))²` along the axis direction, × `STICK_FULL_SPEED × sensitivity`);
  `static func overshoot(pos: Vector2, rel: Vector2, bounds: Vector2) -> float` (how far `rel` pushes past an edge `pos` is already on; 0 otherwise).
- `CursorHold` (`class_name CursorHold extends RefCounted`): `enum State { HELD, RELEASED }`, `var state := State.HELD`;
  `func on_motion(overshoot: float, windowed: bool) -> bool` (windowed only: accumulates overshoot, returns `true` once it reaches `SLIP_OUT_DISTANCE` and switches to RELEASED; any non-overshooting motion resets the total);
  `func on_focus(focused: bool, windowed: bool) -> void` (out → RELEASED; in → HELD unless windowed);
  `func on_click_while_released() -> void` (→ HELD; the caller swallows that press and its release);
  `func on_stick() -> void` (→ HELD: moving the right stick in a focused window picks the mouse up, so a released system pointer and the drawn cursor are never both on screen);
  `func mouse_mode() -> int` (HELD → `Input.MOUSE_MODE_CAPTURED`, RELEASED → `Input.MOUSE_MODE_VISIBLE`).

- [ ] **Step 1: Write the failing tests**

```gdscript
# test_cursor_motion.gd
func test_the_mouse_moves_the_cursor_at_its_sensitivity() -> void:
	var b := Vector2(1152, 648)
	assert_eq(CursorMotion.mouse_step(Vector2(100, 100), Vector2(20, 0), Vector2(2, 2), 1.0, b), Vector2(110, 100), "window pixels → base pixels")
	assert_eq(CursorMotion.mouse_step(Vector2(100, 100), Vector2(20, 0), Vector2(2, 2), 3.0, b), Vector2(130, 100), "3.00× is three times as far")
	assert_eq(CursorMotion.mouse_step(Vector2(5, 5), Vector2(-100, -100), Vector2.ONE, 1.0, b), Vector2.ZERO, "clamped at the corner")

func test_the_stick_has_a_dead_zone_a_curve_and_a_full_speed() -> void:
	assert_eq(CursorMotion.stick_velocity(Vector2(0.15, 0), 1.0), Vector2.ZERO, "inside the dead zone")
	assert_near(CursorMotion.stick_velocity(Vector2(1, 0), 1.0).x, 768.0, 0.01, "full tilt: 1152 px in 1.5 s")
	assert_true(CursorMotion.stick_velocity(Vector2(0.6, 0), 1.0).x < 768.0 * 0.5, "finer control near the centre")
	assert_near(CursorMotion.stick_velocity(Vector2(1, 0), 2.0).x, 1536.0, 0.01, "Right Stick Sensitivity scales it")

func test_overshoot_only_counts_pushing_past_an_edge() -> void:
	var b := Vector2(1152, 648)
	assert_near(CursorMotion.overshoot(Vector2(1151, 300), Vector2(10, 0), b), 10.0, 0.01, "pushing out the right edge")
	assert_near(CursorMotion.overshoot(Vector2(1151, 300), Vector2(-10, 0), b), 0.0, 0.01, "moving back in")
	assert_near(CursorMotion.overshoot(Vector2(500, 300), Vector2(10, 0), b), 0.0, 0.01, "not at an edge")

# test_cursor_hold.gd
func test_windowed_slip_out_needs_a_deliberate_push() -> void:
	var h := CursorHold.new()
	assert_false(h.on_motion(10.0, true), "a nudge doesn't release")
	assert_true(h.on_motion(15.0, true), "24 px of push does")
	assert_eq(h.state, CursorHold.State.RELEASED, "let go")

func test_fullscreen_never_slips_out() -> void:
	var h := CursorHold.new()
	assert_false(h.on_motion(500.0, false), "fullscreen holds")

func test_focus_and_pick_up() -> void:
	var h := CursorHold.new()
	h.on_focus(false, false); assert_eq(h.state, CursorHold.State.RELEASED, "switching away lets go")
	h.on_focus(true, false); assert_eq(h.state, CursorHold.State.HELD, "fullscreen picks up on return")
	h.on_focus(false, true); h.on_focus(true, true)
	assert_eq(h.state, CursorHold.State.RELEASED, "windowed waits for a click")
	h.on_click_while_released(); assert_eq(h.state, CursorHold.State.HELD, "the click picks it up")
	h.on_focus(false, true); h.on_focus(true, true); h.on_stick()
	assert_eq(h.state, CursorHold.State.HELD, "the right stick picks it up too")
	assert_eq(h.mouse_mode(), Input.MOUSE_MODE_CAPTURED, "held = captured")
```

- [ ] **Step 2: Run — expect parse failures.**
- [ ] **Step 3: Implement both files.**
- [ ] **Step 4: Rescan, run — expect PASS.**
- [ ] **Step 5: Commit** — "Add cursor movement maths and the hold/release state".

---

### Task 5: The virtual cursor — routing mouse input and drawing the cursor

**Files:**
- Create: `new-game-project/scripts/cursor/VirtualCursor.gd`
- Modify: `new-game-project/scripts/GameManager.gd` (`var virtual_cursor: VirtualCursor`, created in `_ready()` and added to the root deferred; `func apply_cursor_and_save()` = save settings + `virtual_cursor.refresh_style()`)
- Test: `new-game-project/tests/suites/test_virtual_cursor.gd`; `test_save_coverage.gd` — add `"virtual_cursor"` to `GAME_NOT_SAVED` (a scene node, rebuilt at launch)
- Docs: `new-game-project/CLAUDE.md` — new "Themed cursor" section (architecture paragraph from this plan, the hook, the popup mirror, the files)

**Interfaces:**
- Consumes: `CursorArt.texture/hotspot/RENDER_SCALE`, `CursorMotion.mouse_step`, `GameManager.settings.cursor_shape/cursor_colour/mouse_sensitivity`
- Produces (`class_name VirtualCursor extends Node`, `process_mode = PROCESS_MODE_ALWAYS`):
  - `const LAYER := 200`
  - `var pointer_pos: Vector2` (root-viewport coordinates)
  - `var shown: bool` — the cursor is visible
  - `func install() -> void` — replaces the main window's input callback with `route_os_event`; **does nothing when `DisplayServer.get_name() == "headless"`** (the test runner)
  - `func route_os_event(ev: InputEvent) -> void` — the hook body: mouse motion → `pointer_pos = CursorMotion.mouse_step(...)` and push a new `InputEventMouseMotion` at `pointer_pos` (relative in base pixels, `button_mask` = the buttons this cursor has pressed and not yet released — tracked by `VirtualCursor` from the button events it routes, so it works headless and merges with Cursor Click); mouse button → push a duplicate at `pointer_pos`; everything else → `get_tree().root.push_input(ev)` unchanged. Mouse events set `shown = true`; `InputEventKey` and joypad events except the right stick / `cursor_click` (Task 7) set `shown = false`.
  - `func refresh_style() -> void` — rebuild the sprite texture and offset from settings
  - drawing: a `CanvasLayer` (layer `LAYER`) with a `Sprite2D` (`centered = false`, `scale = 1/RENDER_SCALE`, `offset = -hotspot × RENDER_SCALE`), positioned at `pointer_pos` each frame
  - `func update_mirrors() -> void` (called from `_process`; public so tests call it directly): each visible window in `get_tree().root.get_embedded_subwindows()` gets (once) an internal `CanvasLayer` + `Sprite2D` copy at `(pointer_pos - Vector2(w.position)) / w.content_scale_factor`; freed windows are dropped from the map

- [ ] **Step 1: Write the failing tests** (they drive `route_os_event` directly, as the OS would, against controls added under the root; each test frees its nodes and restores `pointer_pos`/`shown`)

```gdscript
func _vc() -> VirtualCursor:
	return GameManager.virtual_cursor

func _motion_to(target: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = (target - _vc().pointer_pos) * get_tree().root.get_final_transform().get_scale()
	ev.position = Vector2(576, 324)   # a held mouse reports a meaningless position
	_vc().route_os_event(ev)

func _button(index: int, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = index; ev.pressed = pressed; ev.position = Vector2(576, 324)
	_vc().route_os_event(ev)

func test_a_click_lands_where_the_cursor_is_not_where_the_mouse_reports() -> void:
	# a Button at (100,100) size (120,40): move to its centre, press, release → pressed once

func test_hover_reaches_controls() -> void:
	# moving over a Button fires its mouse_entered (the hover sound hangs off this)

func test_the_wheel_scrolls_what_the_cursor_is_over() -> void:
	# a ScrollContainer with 20 rows: three wheel-down presses under the cursor → scroll_vertical > 0

func test_dragging_a_slider_follows_the_cursor() -> void:
	# press on an HSlider's left end, move right in steps with the button held, release → value > 0

func test_a_dropdown_item_is_chosen_by_clicking_it_and_the_cursor_shows_over_the_list() -> void:  # Review Focus 4
	# click an OptionButton → its popup is visible, and after update_mirrors() a mirror sprite exists inside it at the cursor;
	# click the third item → selected == 2 and the popup closed

func test_a_physical_click_reaches_input_readers_exactly_once() -> void:  # Review Focus 1
	# a Node under the root whose _input counts InputEventMouseButton presses: one press+release → count == 1

func test_keyboard_and_controller_pass_through_unchanged() -> void:  # Review Focus 5
	# focus a Button, route an InputEventAction / InputEventKey for ui_accept → it is pressed;
	# route ui_cancel → an _input reader sees it

func test_the_cursor_shows_for_the_mouse_and_hides_for_keys() -> void:
	# mouse motion → shown; a key press → hidden; mouse motion → shown again at the same pointer_pos

func test_the_cursor_wears_the_chosen_style_and_points_with_its_tip() -> void:
	# set settings to ("AV","rose"), refresh_style() → sprite.texture == CursorArt.texture("AV","rose");
	# sprite.offset == -CursorArt.hotspot("AV") * CursorArt.RENDER_SCALE

func test_the_hook_is_not_installed_headless() -> void:
	# install() under the headless test runner leaves the DisplayServer callback alone (no error, a flag stays false)
```


- [ ] **Step 2: Run — expect parse failure.**
- [ ] **Step 3: Implement `VirtualCursor` and the GameManager wiring.** `install()` is called from `GameManager._ready()` after the node enters the tree, and again after every display-mode change (`apply_display_and_save`), since a recreated window would drop the callback.
- [ ] **Step 4: Run the full suite — PASS, zero SCRIPT ERROR. Run the real game once (not headless) and confirm the cursor appears and menus respond to the mouse.**
- [ ] **Step 5: Commit** — "Draw the themed cursor and route the mouse through it".

---

### Task 6: The hover glow

**Files:**
- Create: `new-game-project/scripts/cursor/cursor_glow.gdshader`
- Modify: `new-game-project/scripts/cursor/VirtualCursor.gd`
- Test: `new-game-project/tests/suites/test_virtual_cursor.gd`

**Interfaces:**
- Shader uniforms: `uniform bool glowing`, `uniform vec4 glow1 : source_color`, `uniform vec4 glow2 : source_color`, `uniform float brightness = 1.2`, `uniform float r1_px = 16.0`, `uniform float r2_px = 32.0` (4 px and 8 px × `RENDER_SCALE`). Off: the texture unchanged. On: the texture × `brightness`, composited over a soft glow built by sampling the texture's alpha in rings at `r1_px`/`r2_px`, tinted `glow1`/`glow2`.
- `static func is_clickable(c: Control, local_pos: Vector2) -> bool` on `VirtualCursor`: an enabled `BaseButton`, any `Range` that is a `Slider` or `ScrollBar`, a `LineEdit`, or any control whose `get_cursor_shape(local_pos) == Control.CURSOR_POINTING_HAND`. Over an open embedded popup also counts as clickable.
- `var glowing: bool` and `func update_glow() -> void` (called from `_process`; public so tests call it directly) — set from `get_viewport().gui_get_hovered_control()` (and the mirrors' popups), pushed to the shader and to every mirror sprite.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_what_counts_as_clickable() -> void:
	var b := Button.new(); assert_true(VirtualCursor.is_clickable(b, Vector2.ZERO), "a button")
	b.disabled = true; assert_false(VirtualCursor.is_clickable(b, Vector2.ZERO), "not a greyed button")
	assert_true(VirtualCursor.is_clickable(HSlider.new(), Vector2.ZERO), "a slider")
	assert_false(VirtualCursor.is_clickable(Label.new(), Vector2.ZERO), "not a label")
	var hand := Control.new(); hand.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	assert_true(VirtualCursor.is_clickable(hand, Vector2.ZERO), "Stats-screen style hit areas")
	# free all

func test_the_cursor_glows_over_a_button_and_not_over_empty_space() -> void:
	# move onto a Button → update_glow() → glowing == true and the shader uniform "glowing" is true;
	# move off → false. Glow colours equal CursorArt.glow_colours(current colour).
```

- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement the shader, `is_clickable` and the per-frame update.** `CursorArt.GLOW_MARGIN` already pads the texture so the glow is not clipped.
- [ ] **Step 4: Run — PASS. Render check: a throwaway probe (deleted after) screenshots the cursor over a button in three colours; compare with the art file's hover state.**
- [ ] **Step 5: Commit** — "Glow the cursor over anything clickable".

---

### Task 7: The right-stick cursor and Cursor Click

**Files:**
- Modify: `new-game-project/scripts/cursor/VirtualCursor.gd`, `new-game-project/scripts/GameManager.gd` (`var raw_input_passthrough := false`), `new-game-project/scripts/ui/SettingsScreen.gd` (set `GameManager.raw_input_passthrough = true` in `_start_listening()`, `false` in `_stop_listening()`); `tests/suites/test_save_coverage.gd` (add `"raw_input_passthrough"` to `GAME_NOT_SAVED` — a moment-to-moment UI flag)
- Test: `new-game-project/tests/suites/test_virtual_cursor.gd`

**Interfaces:**
- Consumes: `CursorMotion.stick_velocity`, `GameManager.settings.stick_sensitivity_right`, action `"cursor_click"` (Task 3)
- Produces: `func step_stick(axis: Vector2, delta: float) -> void` — called from `_process` with the strongest connected pad's right-stick axis (`JOY_AXIS_RIGHT_X/Y`); non-zero velocity moves `pointer_pos`, sets `shown = true`, and pushes a synthetic `InputEventMouseMotion` (with the current synthetic button mask).
- In `route_os_event`: right-stick `InputEventJoypadMotion` and any event matching `cursor_click` are **consumed** (not forwarded). A `cursor_click` press when `shown == false` only sets `shown = true` (no click); otherwise press/release become a left `InputEventMouseButton` press/release at `pointer_pos`, and while it is held the synthetic button mask includes the left button (so holding drags). **When `GameManager.raw_input_passthrough` is true, every joypad event is forwarded untouched and the stick does not move the cursor.**
- d-pad, left stick and face-button events still pass through unchanged and set `shown = false`.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_the_right_stick_moves_the_cursor() -> void:
	# pointer at (500,300); step_stick(Vector2(1,0), 0.5) → pointer.x ≈ 500 + 384 (×stick sensitivity 1.0); shown

func test_the_stick_press_clicks_where_the_cursor_points() -> void:
	# cursor shown over a Button; route an InputEventJoypadButton R3 press then release → the Button is pressed once

func test_a_stick_press_while_hidden_only_brings_the_cursor_back() -> void:
	# shown = false over a Button; R3 press+release → shown, Button NOT pressed

func test_holding_the_stick_press_drags_a_slider() -> void:
	# R3 press on an HSlider's left end, step_stick right over a few frames, R3 release → value > 0

func test_rebinding_sees_the_stick_press_and_the_right_stick() -> void:  # Review Focus 2
	# raw_input_passthrough = true: an _input reader receives the R3 InputEventJoypadButton and a right-stick
	# InputEventJoypadMotion unchanged, and pointer_pos does not move; restore the flag

func test_the_dpad_hides_the_cursor_and_still_navigates() -> void:
	# shown = true; route a d-pad InputEventJoypadButton → shown == false and an _input reader received it
```

- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement.** Stick motion is clamped to the window and never feeds `hold.on_motion` (only the mouse slips out); stick motion while RELEASED calls `hold.on_stick()` first (Task 8 applies the mouse mode).
- [ ] **Step 4: Run — PASS (including the existing rebinding tests in `test_settings.gd`).**
- [ ] **Step 5: Commit** — "Let the right stick move the cursor and its press click".

---

### Task 8: Holding and letting go of the mouse

**Files:**
- Modify: `new-game-project/scripts/cursor/VirtualCursor.gd`, `new-game-project/scripts/GameManager.gd` (call `virtual_cursor.on_display_changed()` from `apply_display_and_save`)
- Test: `new-game-project/tests/suites/test_virtual_cursor.gd`

**Interfaces:**
- Consumes: `CursorHold` (Task 4), `CursorMotion.overshoot`, `SettingsModel.window_mode`
- Produces on `VirtualCursor`: `var hold := CursorHold.new()`; `func on_display_changed() -> void`; `func _notification(what)` handling `NOTIFICATION_APPLICATION_FOCUS_OUT/IN` → `hold.on_focus(...)`; `func _apply_hold() -> void` sets `Input.mouse_mode = hold.mouse_mode()` (skipped headless).
- Windowed slip-out: in `route_os_event`, a mouse motion while HELD and windowed feeds `hold.on_motion(CursorMotion.overshoot(...), true)`; on release, warp the system pointer to the window point matching `pointer_pos` (`Input.warp_mouse`) before switching to VISIBLE, hide the drawn cursor, and set the themed system cursor: `Input.set_custom_mouse_cursor(CursorArt.texture(shape, colour, os_scale), Input.CURSOR_ARROW, CursorArt.hotspot(shape) * os_scale)` (and the same for `CURSOR_POINTING_HAND`), `os_scale` = the window's content scale × screen scale, capped so the image stays ≤ 256 px.
- While RELEASED, mouse events are not forwarded; a left press inside the window calls `hold.on_click_while_released()`, sets `pointer_pos` to the press position in viewport coordinates, and swallows that press **and its release**.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_pushing_out_of_a_windowed_game_lets_the_mouse_go() -> void:
	# windowed; pointer at the right edge; route motions pushing +30 px right → hold.state == RELEASED, shown == false

func test_the_click_that_picks_the_mouse_up_presses_nothing() -> void:
	# RELEASED over a Button; route a left press+release with a real window position → HELD,
	# pointer_pos at that spot, the Button NOT pressed

func test_switching_away_and_back() -> void:
	# focus-out notification → RELEASED; focus-in with fullscreen → HELD; with windowed → still RELEASED

func test_a_fullscreen_game_never_lets_go_at_the_edge() -> void:
	# fullscreen; push far past the edge → still HELD, pointer clamped
```

- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run — PASS. Manual check in a real windowed run: slip out at an edge, click back in, Cmd-Tab away and back; fullscreen Cmd-Tab and back.**
- [ ] **Step 5: Commit** — "Hold the mouse in the game and let it slip out of a window".

---

### Task 9: The Mouse page and the Max FPS row

**Files:**
- Create: `new-game-project/scripts/ui/CyclerRow.gd`
- Modify: `new-game-project/scripts/ui/SettingsScreen.gd` (Controls menu gains `["mouse", "Mouse"]` after Controller; `_view_title`, `_parent_of("mouse") == "controls"`; new `_build_mouse(v)`; `_build_performance` uses a `CyclerRow` for Max FPS; `_sens_row` gains optional `min_v`/`max_v` defaulting to `SettingsModel.SENS_MIN/SENS_MAX`)
- Test: `new-game-project/tests/suites/test_cycler_row.gd`, `test_settings.gd`

**Interfaces:**
- `class_name CyclerRow extends HBoxContainer`: `signal changed(index: int)`; `func setup(label_text: String, labels: PackedStringArray, index: int) -> void`; `func set_icon(tex: Texture2D) -> void`; `func set_swatch(c: Color) -> void`; `func step(dir: int) -> void` (wraps, emits `changed`); `var index: int`. Layout: name label · `◀` button · [icon or dot] value label · `▶` button, in the settings screen's fonts and `BattleUITheme` buttons. The row is focusable: `ui_left`/`ui_right` while it has focus call `step(-1/+1)`; clicking the arrows calls `step` too. It registers with the focus guard like the other settings controls.
- Mouse page rows, in order: **Cursor Shape** (labels = shape names; icon = `CursorArt.texture(shape, current colour, 1.0)`), **Cursor Colour** (labels = colour names; swatch = `CursorArt.swatch(colour)`), **Mouse Sensitivity** (`_sens_row` with 0.25–3.00, step 0.05). Shape and colour changes set the setting and call `GameManager.apply_cursor_and_save()`; the sensitivity row saves as the stick rows already do (the cursor reads it live); changing the colour also re-tints the Shape row's icon. No preview section.
- Max FPS: `CyclerRow` with `_fps_labels()`, index `_fps_index(cap)`, on change set `fps_cap` and call `GameManager.apply_performance_and_save()`.

- [ ] **Step 1: Write the failing tests**

```gdscript
# test_cycler_row.gd
func test_the_arrows_step_and_wrap() -> void:
	var r := CyclerRow.new(); r.setup("Colour", PackedStringArray(["A", "B", "C"]), 0)
	var seen := []; r.changed.connect(func(i): seen.append(i))
	r.step(-1); r.step(+1); r.step(+1)
	assert_eq(seen, [2, 0, 1], "wraps both ways")
	r.free()

func test_left_and_right_change_a_focused_row() -> void:
	# add to the tree, grab_focus, push ui_right → index 1; ui_left → index 0

# test_settings.gd
func test_the_mouse_page_offers_shape_colour_and_sensitivity() -> void:
	# open the "mouse" view; three rows labelled "Cursor Shape", "Cursor Colour", "Mouse Sensitivity";
	# stepping the shape row forward sets settings.cursor_shape == "B" and the live cursor texture follows;
	# no node named or labelled "Preview"; restore settings

func test_max_fps_is_a_left_right_row() -> void:
	# open "performance"; no OptionButton remains for Max FPS; its CyclerRow labels are
	# ["Uncapped","30","60","120","144"]; stepping from 144 wraps to Uncapped and sets fps_cap == 0

func test_window_mode_and_resolution_keep_their_dropdowns() -> void:
	# open "display"; both are still OptionButtons
```

- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement `CyclerRow` and the SettingsScreen changes.**
- [ ] **Step 4: Run — PASS. Render the Mouse and Performance pages once (throwaway probe screenshot) and check they match the game's settings style.**
- [ ] **Step 5: Commit** — "Add the Mouse settings page and make Max FPS a left/right row".

---

### Task 10: Every screen, every input — the pass and the record

**Files:**
- Create: `.claude/docs/superpowers/notes/2026-10-17-every-screen-every-input.md`
- Modify: whichever screen scripts the pass finds a gap in (each fix with its own failing test first, in that screen's existing suite)
- Modify: `new-game-project/CLAUDE.md` (finish the "Themed cursor" section: settings, controller, hold/release, the record's location; update the Settings/Controls docs; test count)

**Interfaces:**
- Consumes: everything above.
- Produces: the record — a table, one row per screen from the spec's list (main menu; save-slot menu with load/copy/delete/new-game picker and confirms; pause menu and confirms; Settings root, Game, Keyboard, Controller, Mouse, Audio, Display, Performance incl. press-to-bind and profile names; Items, Equipment, Stats, Quests, Moves, shops, rest area/inn, dialogue incl. choices; battle action menu, Attack/Special menus, target selection on enemies and hero panels, items menu, resonance menu, victory, level-up, defeat; overworld and interiors incl. zones, transitions, pause/save), columns **Mouse**, **Keyboard**, **Controller (highlight)**, **Controller (stick cursor)**, each cell `fine (code/test)`, `fixed (commit)` or `play-test` with a one-line note. Every `play-test` cell becomes a line in a manual checklist at the end of the record for the user's play-test.

- [ ] **Step 1: For each screen, read its script and check, per input: every control reachable and operable, Back/cancel works (`ui_cancel`), nothing is mouse-only or focus-only by accident. Write the row.**
- [ ] **Step 2: For each gap: write the failing test in that screen's suite, fix, run, commit (one commit per screen fixed: "Make <screen> usable by <input>").**
- [ ] **Step 3: Full suite — PASS, zero SCRIPT ERROR; play-test flags at shipping values.**
- [ ] **Step 4: Finish CLAUDE.md and the record's manual checklist.**
- [ ] **Step 5: Commit** — "Record the every-screen, every-input pass and document the cursor".
