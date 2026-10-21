# Amethyst Dashboard — design

*Date: 2026-10-18. Status: written up from the brainstorm and a builder check; awaiting the
user's review.*

A web dashboard for **The Amethyst Requiem** (Godot 4.6.1, `new-game-project/`) that
connects to the running game and lets its developer skip the grind while play-testing:
jump straight to a boss, try any move, give the party gold and items, fix up a hero's
stats, and undo all of it afterwards. It also has an **Admin** section, empty for now,
and a proper account sign-in.

**Visual reference (source of truth for the look):** the approved mockups in
`2026-10-18-amethyst-dashboard-mockups/` next to this file — open the `.html` files in a
browser. They are mockups (static, hand-written), not code to reuse; the build matches
their layout, content and styling.

| File | Shows |
|---|---|
| `signin-v1.html` | The four sign-in screens: create the owner account, sign in, forgot password, locked |
| `overview-v3.html` / `overview-dark-v1.html` | Overview, light and dark |
| `party-v4.html` / `party-dark-v1.html` | Party, light and dark |
| `inventory-v1.html` | Inventory (with gold) |
| `gear-v2.html` | Gear (uses the game's rarity gem icons) |
| `location-v2.html` | Location, incl. the "invalid location" state |

---

## 1. Intent

**Why now.** Play-testing wastes most of its time on getting to the thing being tested.
In the user's words, from their last test session:
- testing the Goblin Warlord's moves and phases meant walking to the castle every time;
- testing every hero's moves meant asking the developer to flip a code switch
  (`PartyFactory.TEST_UNLOCK_ALL_SKILLS`) so the moves were available;
- testing shops meant fighting enemies for gold whenever it ran out.

The dashboard removes that waiting. Success: the user can open it, change what they need
in the running game in a few clicks, test, and put everything back.

**Who.** Only the user, for now. Other people may get accounts "in the far, far future";
when that happens the user creates their accounts — there is never a public sign-up.

**What it is.** A professional, polished admin-style web app — modelled on the layout and
level of polish of the commercial "SmartAdmin" template the user showed (dark sidebar,
top bar with search / settings / dark mode / theme / full screen / notifications / avatar,
breadcrumbed page titles, clean cards, ring gauges), but **an original design in the
game's amethyst style** — none of SmartAdmin's code, name, logo or artwork is copied.

The user said this is the place they want "a pristine product" and will give the most
feedback on, so quality of finish matters as much as function.

## 2. Goals, non-goals, anti-goals

**Goals**
- Read the running game's state and change it live, safely: party, gold, items, gear,
  location, difficulty.
- Every change can be undone in one action ("Reset to before debugging"), even after the
  game has been quit and restarted.
- Look and feel like a finished, professional product, in light and dark.
- Real accounts with safe password storage, from day one.
- Runs on the user's Mac now; built so it can be hosted later without a rewrite.

**Non-goals (not in this version)**
- Any Admin feature: the Admin section shows "In development" until the user decides what
  goes there.
- Account management for other people (the user will set others up "in the far future").
- Colour themes other than Amethyst (the theme picker exists; Amethyst is the only choice).
- Editing the starting list of saved spots beyond rename / delete / save-this-spot (the user
  wants to revisit the list later).
- Story flags, quests, time of day, roaming enemies or battles as editable things (not
  asked for; candidates for later).
- Mobile/phone layout (desktop browser on a Mac is the target; see §9).

**Anti-goals (would make it a failure even if it "works")**
- A shipped (release) copy of the game that anyone can connect to — players must not be
  able to cheat through it.
- Changes landing in the middle of a battle or conversation and breaking it.
- Applying a change the user didn't see listed first (pages other than quick actions always
  show what will change before Apply).
- Moving the player into a wall, water or any other spot they could never stand on.
- Default-looking, unstyled controls; any page that looks unfinished in either theme.
- Security questions or answers written into the code, a config file in the repo, or chat.

## 3. Decided by the user (as they decided it)

**Overall**
- React web dashboard. One app with separate **Debug** and **Admin** sections.
- Admin: shows "In development"; available whether or not the game is running.
- Debug: when the game isn't running, says so and that it is waiting for the game, then
  connects by itself once the game starts.
- Name: **Amethyst Dashboard**.
- Look: the SmartAdmin screenshot as the baseline; **amethyst purples**; mostly white/light
  surfaces in light mode (the default) with amethyst accents, and a **dark mode**. Other
  colour themes may come later, not now.
- Use the screenshot's UI elements with their functions: sidebar with groups and a filter,
  sidebar collapse, search, settings, dark mode, colour theme, full screen,
  notifications, avatar menu.

**Applying changes**
- Edits are made on the page, then an **Apply changes** button sends them; once clicked,
  they happen in the game right away.
- **Quick actions** on the Overview are one click (no Apply step).
- Debug changes only happen when the player is **not in a battle or a cutscene**
  (conversations count; see §5.3 for menus).
- **Reset** rewinds **the whole game** to the moment just before the first Apply — not just
  the dashboard's own edits — and it **still works after quitting and restarting** the game.
- Reset also **restores that slot's save file** to the starting point, so the real save is
  clean again even if auto-save wrote debug changes into it. Auto-save keeps working
  normally while debugging. *(My suggestion, chosen by the user after the builder check.)*
- **Raising a hero's level from the dashboard gives an average level-up bonus for each level
  gained** (instead of the in-game bonus spin). *(Option C, chosen by the user.)*
- A separate **Discard edits** throws away edits not yet applied *(my call, accepted)*.

**Accounts**
- An account login system; the user creates their own account and signs in.
- First start: create the owner account; afterwards **no public sign-up** — only the owner
  can create accounts for others (later). "Keep me signed in" option.
- **Forgot password:** reset only by answering **all three** security questions correctly;
  **any wrong answer → 5-minute lock** before trying again. The three questions are fixed:
  1. What is my favorite holiday?
  2. Which city was I born in?
  3. What is my favorite board game?

  The answers are typed into the dashboard when the account is created — never stored in
  code, the repo, or chat.

**Pages and content** (each approved against its mockup)
- **Overview:** game status, quick actions, a stat strip, a party summary, a debug activity
  feed — "keep everything", plus a **difficulty** control.
- **Party:** per hero; Vitals (level, EXP shown as "x / needed", HP and MP each with Max and
  Current where Current shows "/ max" that follows the Max field live, resonance) above
  Stats (just the number, plus the **normal** in-game value beside each), on the left;
  **all** of the hero's moves on the right with unlock switches and **equipping**.
  Max HP and Max MP also show their normal value.
- **Inventory:** gold, item list by the game's tabs, change quantities, add any item, delete
  — "keep everything".
- **Gear:** per-hero equipped slots, the shared spare pile, add any piece, delete; rarity
  text **colour-coded to the user's gem icons**.
- **Location:** move the player by map + coordinates or by clicking the map; any spot the
  player can't stand on is shown as **"Invalid location"** and can't be applied; pins must
  be easy to see.
- **Sign-in screens:** create account, sign in, forgot password, locked — "keep everything".
- **Notifications, Settings, Search:** contents agreed in words (§5.6–5.8).
- **Dark mode:** as mocked — "keep everything".

## 4. How it gets made — my calls (the user said "pick sensible defaults and tell me")

- **Where:** a new top-level `dashboard/` folder in this repo, next to `new-game-project/`.
- **Front end:** React + TypeScript + Vite. Started with one command (`npm run dev`) and
  opened in the browser at a local address; a short `dashboard/README.md` explains.
  Node.js 24 is already installed on the user's Mac.
- **A small server of its own** (TypeScript on Node, in `dashboard/`), because accounts
  need safe storage. It holds: accounts, sessions, lockout timers, notifications, settings,
  saved spots and the debug activity log, in a local database file that is **not committed**.
  Passwords and security answers are stored only as slow, salted hashes (e.g. argon2id or
  bcrypt) — never readable.
- **Hostable later:** nothing assumes "this computer only" except configuration (ports,
  addresses, where the database lives), which lives in one place.
- **Game connection:** the dashboard's server talks to the game; the browser only ever talks
  to the dashboard's server, after signing in. So the sign-in protects the game connection
  too. (When hosting comes, a small bridge on the Mac will relay to the hosted server; the
  game-facing part is kept separate so that change stays contained.)
- **The game's side** listens **only on this computer** (127.0.0.1) and **only in debug
  builds** (running from the Godot editor or a debug export — `OS.is_debug_build()`); a
  release export has no listener at all. It also requires a shared secret from the
  dashboard's server so another local program can't drive it.
- **Fonts and icons:** a clean sans-serif (the mockups use Inter) for the interface, Cinzel
  for brand moments (sign-in tagline); a consistent outline icon set. The game's own rarity
  gem PNGs (`new-game-project/assets/icons/*GemIcon.png`) are reused for rarity.
- **Tests:** the dashboard (front end and server) gets its own automated tests; the game's
  side gets tests in the existing headless Godot suite (`tests/TestRunner.tscn`, which runs
  headless only). Every stage ends with a written play-test checklist for the user.

## 5. Behaviour

### 5.1 Layout (every signed-in page)
- **Sidebar** (deep plum in both themes): brand ("Amethyst Dashboard" with a gem mark), a
  filter box that narrows the menu, and groups: **Overview** → Overview; **Debug** → Party,
  Inventory, Gear, Location; **Admin** → Admin ("In development" badge). The active page is
  highlighted. The sidebar collapses to icons-only (button at the left of the top bar).
- **Top bar:** collapse button · search box ("Search for anything — a hero, an item, a map…")
  · settings · light/dark switch (moon in light mode, sun in dark mode) · colour theme ·
  full screen · notifications bell with unread count · avatar menu (profile, settings,
  sign out).
- **Page header:** uppercase title, breadcrumb ("Dashboard / Debug / Party"), and on Debug
  pages a status pill ("● Exploring · changes can be applied" / the reason it can't).
- **Debug pages** carry a short reminder strip: applied changes stay if you save the game;
  Reset to before debugging (on Overview) rewinds everything.
- **Apply bar** (Party, Inventory, Gear, Location): pinned to the bottom; shows how many
  changes are waiting and lists them in plain words, with **Discard edits** and **Apply
  changes**.
- **Edited fields** glow amethyst and show what they "were" (or the normal value where the
  page shows one); added rows are green and tagged "new"; removed rows are struck through
  with Undo.

### 5.2 When the game isn't connected
- Debug pages (and the Overview's game cards) show a clear "The game isn't running —
  waiting for it" state and connect on their own when the game starts. Unapplied edits are
  kept in the page while waiting.
- Admin, Settings, notifications, search and the account menu all work without the game.

### 5.3 When changes can be applied
- Allowed only while the player is **walking around freely** — in the overworld or a
  building interior, with no battle, no conversation, no scene change in progress and no
  game menu open (pause menu, shop, campfire, trainer — anything that pauses the game).
  *(Menus: my call, accepted by the user in playback — so no game screen shows old numbers.)*
- While not allowed, **Apply** and quick actions are greyed with the reason ("In a battle",
  "In a conversation", "A menu is open"). Edits stay waiting. A quick action clicked while
  blocked waits and runs as soon as it's allowed (with a notification when it does).
- The game is the judge: it re-checks when the change arrives and refuses (with the
  reason) if the state changed in between.

### 5.4 Reset to before debugging
- The **first Apply (or quick action) of a debugging session** takes a **starting point**:
  everything a save holds (party, gold, items, gear, location and map, quests, roaming
  enemies, time of day …) plus the difficulty setting.
- **Reset** rewinds the running game to that starting point exactly, as if that moment had
  been loaded, **writes the starting point over that slot's save file** (so the save on disk
  is clean again — auto-save may have written debug changes into it), then clears the
  starting point; the next Apply takes a fresh one. With no active slot (an unsaved new
  game) it rewinds the game only.
- The starting point is **stored with its save slot on disk**, so Reset still works after
  quitting and restarting the game. Each slot has its own. Starting a new game in a slot, or
  deleting it, drops that slot's starting point.
- *(My call, from the builder check.)* A save written while a starting point exists is marked
  as holding debug changes. Loading a slot whose save is **not** marked drops that slot's
  starting point — the file on disk is already clean, and keeping it would let Reset jump
  *forward* to the moment of the first Apply.
- If no starting point exists, Reset is greyed ("Nothing to reset").
- Reset asks for confirmation first: "This rewinds the game to before your first change and
  also restores Slot N's save." (It can undo real play since the first Apply.)

### 5.5 Pages

**Overview** (`overview-v3.html`)
- Header mini-stats: gold, party level, number of debug changes applied.
- **Game Status:** connected/waiting · map and coordinates · what the player is doing and
  whether changes can be applied · save slot and last save time · difficulty · time of day ·
  roaming enemies on this map · game build.
- **Quick Actions** (one click): Heal party + full resonance (full HP/MP for everyone,
  revives the fallen, fills every resonance bar) · Unlock all moves (every hero) · Max out
  gold · Save the game now (to the current slot, as the pause menu's Save does; greyed when
  there's no slot) · Teleport to a saved spot (menu + Go) · **Difficulty** Easy / Normal /
  Hard · Reset to before debugging.
- **Stat strip** (ring gauges): party HP, party MP, moves unlocked, items carried.
- **Party summary:** each hero's HP / MP / resonance bars, link to Party.
- **Debug Activity:** a timeline of this session's applied changes and connection events.

**Party** (`party-v4.html`)
- Hero tabs (Aria, Kael, Lyra in their hero colours) with Heal [hero] and Heal whole party.
- **Vitals:** Level; EXP as "[85] / 100 to reach level 8"; HP and MP boxes, each with a bar,
  "current / max" heading, a **Max** field (with the normal value beside it) and a
  **Current** field followed by "/ max" that follows the Max field as it's typed; Resonance
  slider (0–100).
- **Stats:** Attack, Defense, Magic, Arcane, Speed — the number only, with **normal N**
  beside each. "Normal" = what the hero would have **without the dashboard's direct stat
  edits**: their real stats, including every level-up bonus they earned in play, at their
  current level and gear. *(My call, from the builder check: a plain formula — starting
  stats + level growth + gear — would ignore earned level-up bonuses and mark every
  levelled hero as "edited" before anything was changed.)*
- **Moves:** every move in the hero's 18-move pool, grouped Attack (8) and Special (10), each
  with an unlock switch, its normal unlock level, and an Equip control; the 4 Attack + 4
  Special battle slots shown at the top; Unlock all; "Back to level N's moves" (restores
  what the hero would normally know). Equip greys out when that category's slots are full;
  clicking an equipped move unequips it; a locked move can't be equipped.
- Rules *(my calls)*: setting a stat or Max HP/MP makes the displayed number exact now and
  it still grows normally with levels; gear stays on top. A direct edit is kept as a
  difference on top of the hero's normal value, so a level-up bonus earned later still
  raises both, and "normal" stays honest. Lowering Max pulls Current down; Current can't
  exceed Max. The EXP field accepts up to one less than needed — changing Level is how to
  level a hero. Unlocks survive saving and loading.
- **Changing Level** *(the user chose an average bonus)*:
  - Each level **gained** gives the normal level growth **plus an average level-up bonus**:
    the in-game spin pays +2 to +10 (average 6) to one stat the player picks, so the
    dashboard gives **6 points per level, spread over the five stats as evenly as possible**
    (2+1+1+1+1, rotating which stat gets the extra so it evens out over several levels).
    *(Spread rule: my call.)* These count as the hero's normal values (they stand in for
    earned bonuses), not as direct edits.
  - Moves for the levels gained are **learned and put into free slots**, exactly as a real
    level-up does. *(My call, accepted.)*
  - Each level **removed** takes away the level growth and the same average bonus, never
    dropping a stat below the hero's starting value; moves above the new level lock again
    unless they were unlocked by hand.
  - EXP resets to 0 toward the next level.

**Inventory** (`inventory-v1.html`)
- **Gold:** an editable amount with +1,000 / +10,000 / Max / Zero.
- Summary: items carried, different items, key items; a note on Hard difficulty's cap
  (10 healing / battle items each).
- Item list with the game's tabs (All, Items, Healing, Battle, Key) and a filter: name, type,
  what it does, sell price, − / + quantity, delete.
- **+ Add item:** a searchable list of every item in the game; pick quantity; add.
- Gold has no page of its own (it lives here); the sidebar has no Gold entry.

**Gear** (`gear-v2.html`)
- Hero tabs. **Equipped on [hero]:** Weapon, Armor, Accessory 1–3 with each piece's gem,
  coloured rarity, bonuses, Change / Unequip; empty slots offer Choose…; a live "[hero] with
  this gear" stat preview.
- **Spare gear** (shared by the party): tabs by slot; each piece's gem, coloured rarity,
  slot, who can use it, bonuses; "Equip on [hero]" — greyed with the reason when not allowed
  (class or element restriction, as the game enforces); delete.
- **+ Add gear:** searchable list of all 18 pieces.
- Rarity text colours match the user's gem icons; on white backgrounds the light gems
  (Legendary, Celestial) use a deeper shade of the same colour for readability; in dark
  mode they use the bright gem colour.

**Location** (`location-v2.html`)
- **Move the player:** map dropdown (every overworld map and building interior), X and Y
  fields, "Use the map's arrival spot"; a zoomable picture of the chosen map — click to fill
  X/Y. Large, high-contrast pins with labels: green "You are here", purple "Move here"
  (pulsing), red "Invalid location"; a small key explains them.
- **Invalid location:** any spot the player can't stand on (walls, water, buildings,
  anything solid) turns the coordinates red, shows "Invalid location" with the reason, and
  is kept out of the change list. The game decides validity from its own collision for the
  chosen map.
- Moving loads the target the way a door does (minus the walk); arrival gets the usual
  3-second grace so a roaming enemy can't start a fight on landing.
- **Where you are** (map, coordinates, area, roaming enemies) with **Save this spot…**
- **Saved spots:** name, map, coordinates; one-click Go; rename; delete. Stored by the
  dashboard (work in every save slot); the same list feeds Overview's Teleport menu.
  Starting list *(mine; the user will revisit later)*: Warlord's chamber, Castle gate,
  Center Town square, Item shop counter, Mountain Pass campfire — at real valid coordinates.

**Admin** — an "In development" page.

### 5.6 Notifications (bell)
The game connected / disconnected · changes applied · changes failed (with the reason) ·
changes waiting because of a battle / conversation / menu, and later applied · reset
finished · account security (failed sign-ins, a password-reset lockout) since last viewed.
Each can be marked read; "Mark all as read"; the bell shows the unread count.

### 5.7 Settings (gear icon)
- Appearance: Light / Dark / Follow my Mac; colour theme (Amethyst; others "coming
  later"); sidebar expanded or icons-only.
- Account: display name and profile picture; change password; change security answers
  (requires the current password).
- Sign-in: how long "Keep me signed in" lasts.
- Game connection: the port; reconnect automatically when the game restarts.
- Notifications: each kind on/off.

### 5.8 Search (top bar, ⌘K)
Finds pages, heroes, every item and piece of gear, maps and saved spots, and individual
settings. Choosing a result goes there (an item opens Inventory with it ready to add).
Arrow keys + Enter work without the mouse.

### 5.9 Accounts and sign-in (`signin-v1.html`)
- **First start** (no accounts exist): "Create your account" — display name, username,
  password (strength meter; at least 10 characters), confirm, and answers to the three
  questions. The person who does this becomes the owner. This screen never appears again.
- **Sign in:** username, password, "Keep me signed in", "Forgot password?". After a wrong
  password: "That password isn't right — N tries left before a 5-minute pause." **Five
  wrong passwords in a row → 5-minute sign-in lock** *(my suggestion, accepted)*.
- **Forgot password:** username, then answers to all three questions (hidden as typed, with
  Show), then a new password + confirm. Answers ignore capital letters and extra spaces.
  **Any wrong answer → reset locked for 5 minutes.**
- **Locked:** a countdown ring; "Try again" disabled until it ends; the page unlocks itself.
- Locks are enforced by the server, per account, and survive a page refresh or restart.
- Signed-out visitors can reach only the sign-in screens.

### 5.10 Light and dark (`overview-dark-v1.html`, `party-dark-v1.html`)
Light: white / soft-grey surfaces, amethyst accents, deep-plum sidebar. Dark: plum-black
background, cards one step lighter, the sidebar darkest; amethyst and the hero / status
colours lifted to stay vivid; edited fields stay readable. Default light; Settings offers
Follow my Mac.

## 6. What the game exposes (the game's side)

The dashboard needs the running game to report and to accept:

| Area | Read | Change |
|---|---|---|
| Status | connected; map; coordinates; doing (exploring / battle / conversation / menu / loading); save slot + last save; difficulty; time of day; roamers on map; build | — |
| Party | per hero: level, EXP and EXP needed, HP/MP current and max (+ normal), resonance, five stats (+ normal), all 18 moves with unlock level, unlocked or not, equipped slots | all of those; heal; full resonance; revive |
| Gold & items | gold; items with type, description, price, quantity | gold; quantities; add any item; remove |
| Gear | each hero's 5 slots; the shared spare pile; every piece's slot, rarity, bonuses, restrictions | equip / unequip (game rules); add any piece; remove |
| Location | map and coordinates; the list of maps; whether a given spot is open ground | move to map + coordinates (or arrival spot) |
| Session | — | difficulty; save now; take / restore / drop the starting point |

Existing hooks to build on: the save system's `GameManager._build_save_dict()` /
`_apply_save_dict()` (the starting point is a save in memory), `GameManager.in_overworld_battle`,
`DialogueManager.is_active()`, the paused tree for menus, `SettingsModel.difficulty`,
`PartyFactory`'s pools and unlock tables (for "normal" values and "back to level N"),
`ItemFactory` / `EquipmentFactory` definitions, `Equipment.can_equip`, and the map
scenes' collision for the open-ground check.

## 7. Built in two stages (each: its own plan, review, play-test)

1. **The dashboard itself:** project setup, server and database, accounts (first-run,
   sign-in, forgot / lock), the full layout and both themes, search, notifications,
   settings, and every page drawn with real structure — Debug pages show "waiting for the
   game", Admin shows "In development".
2. **The game connection:** the game's debug-only listener, reading state and applying
   changes, quick actions, difficulty, reset and its on-disk starting points, invalid
   location, waiting-while-blocked — and the Debug pages working end to end.

## 8. Left to the builder

The message format between the dashboard's server and the game; the database engine and
schema; the exact port numbers and the shared-secret handshake; component library choices
(as long as the result matches the mockups and nothing looks default); how map pictures
are produced from the game's map art; session length defaults; how the open-ground check
is computed for a map that isn't loaded; folder layout inside `dashboard/`.

## 9. Constraints and risks

- **Input:** the dashboard is a browser app on a Mac — fully usable by mouse and by
  keyboard (tab order, focus rings, ⌘K, Enter/Escape in dialogs). Controller use is not a
  goal for the dashboard *(my call — the project's every-input rule covers the game's UI)*.
- **Never in a release build:** the game's listener must be compiled in only for debug
  builds; a test checks it is absent otherwise.
- **The starting point is big** (a full save): one per slot, overwritten, never accumulated.
- **Applying while state moves:** the game is the judge (§5.3) — the dashboard never
  assumes its view is current; after every apply it re-reads.
- **Godot side stays tidy:** debug code lives in its own scripts, not sprinkled through
  gameplay code; gameplay changes go through the same functions the game uses (equipping
  via `Inventory.equip_from_pool`, etc.) so the rules stay the game's.
- **Hosting later:** HTTPS, a real secret store and an email or authenticator option for
  password recovery should come with hosting; noted, not built.
- **Licensing:** original design only; no SmartAdmin assets.
