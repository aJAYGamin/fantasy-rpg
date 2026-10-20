# Amethyst Dashboard — stage 1 play-test checklist

Tick each box as you go. Anything that looks off, or doesn't do what a step says, is worth a note: what you did, what you expected, what happened (a screenshot helps).

**Your real security answers go in one place only: the dashboard's own "Create your account" form (and later its Forgot password and Settings forms).** Never type them anywhere else: not in chat, not in a note, not in any file. The dashboard keeps only one-way hashes of them.

The pauses below last **5 minutes** for real. (The automated tests shorten them; you don't need to.)

## 1. Start it

- [ ] In Terminal, from the `dashboard` folder: `npm install` (first time only), then `npm run dev`.
- [ ] Open <http://localhost:5173> in Chrome. You land on **Create your account**.

## 2. Create your account

- [ ] Fill in a display name, a username and a password (at least 10 characters). Watch the strength meter change as you type.
- [ ] Type a different password in Confirm: it says they don't match. Fix it.
- [ ] Answer the three security questions with your **real** answers.
- [ ] Press **Create account**. You land on the Overview, signed in.
- [ ] Chrome does **not** offer to save your security answers as a password. (If it offers to save the account password itself, that's fine.)
- [ ] Go to <http://localhost:5173/setup>: it sends you to the Overview. The create-account screen never comes back.

## 3. Sign out and back in

- [ ] Avatar (top right) → **Sign out**. You're on **Sign in**.
- [ ] Sign in with **Keep me signed in** ticked.
- [ ] Quit Chrome completely (⌘Q) and reopen the page: you're still signed in.
- [ ] Sign out, then sign in with **Keep me signed in** unticked.
- [ ] Quit Chrome completely and reopen the page: you're asked to sign in again. (If Chrome is set to "Continue where you left off", it may keep you signed in for up to 12 hours. That's Chrome, not the dashboard.)

## 4. Too many wrong passwords

- [ ] Sign out.
- [ ] Type your username and a wrong password, and press **Sign in**. It says "That password isn't right" and how many tries are left (4).
- [ ] Keep going until the fifth wrong one: **Sign-in is paused**, with a ring counting down from 5:00 and a greyed-out **Try again**.
- [ ] Refresh the page.
- [ ] Sign in with the right password: still paused (the pause is kept by the server).
- [ ] Wait it out without touching anything. At 0:00 it says "You can try again now." and **Try again** wakes up.
- [ ] Press **Try again** and sign in with the right password.
- [ ] The bell shows unread notifications for the failed sign-ins and the pause. Open it.
- [ ] Open one notification: it turns read.
- [ ] Press **Mark all as read**: the bell's number goes away.

## 5. Forgot password

- [ ] Sign out, then choose **Forgot password?**.
- [ ] Fill in your username, two right answers and **one deliberately wrong** answer, and a new password twice.
- [ ] Press **Reset password**: it says **Password reset is locked**, with the countdown.
- [ ] Wait out the 5 minutes.
- [ ] Press **Try again**: the form is back with your username kept and the answers cleared.
- [ ] Answer all three correctly, typing odd capitals and extra spaces (if an answer is `blue`, `  BLUE  ` works too).
- [ ] Fill in a new password twice.
- [ ] Press **Reset password**: the answers still match, and you land on Sign in with "Password changed".
- [ ] Chrome does **not** offer to save your answers as a password.
- [ ] Sign in with the old password: it's refused.
- [ ] Sign in with the new password: it works.

## 6. The top bar and sidebar

- [ ] The moon switches to dark mode, the sun back to light.
- [ ] Reload in dark mode: no flash of white.
- [ ] Settings (gear) → Appearance → **Follow my Mac**.
- [ ] Switch your Mac between Light and Dark in System Settings → Appearance: the dashboard follows at once.
- [ ] The palette icon opens the colour theme menu: Amethyst is ticked, "More themes coming later" does nothing.
- [ ] The corners icon goes full screen.
- [ ] Press it again (or Esc) to come back.
- [ ] The arrow at the left folds the sidebar to icons.
- [ ] Hover each icon: a label appears beside it.
- [ ] Reload: still folded.
- [ ] Unfold it.
- [ ] Type in the sidebar's **Filter**: the pages narrow down.
- [ ] Type something that matches nothing: "No pages match".
- [ ] Press Esc: the filter clears.

## 7. Search

- [ ] Press **⌘K**, type `loc` and press Enter: the Location page.
- [ ] Press ⌘K again and move the highlight with the arrow keys.
- [ ] Press Enter: the highlighted page opens.
- [ ] Press ⌘K, then Esc: it closes without going anywhere.
- [ ] Click the search box in the top bar: the same search opens.

## 8. Settings

- [ ] **Appearance**: pick Light, Dark and Follow my Mac in turn. Each saves at once ("Saved" appears briefly).
- [ ] **Appearance**: switch the sidebar between Expanded and Icons only. Each saves at once.
- [ ] **Account**: change your display name and press Enter (or click away). It saves, and the avatar's initials follow.
- [ ] **Account**: type another display name and press Esc. The saved one comes back.
- [ ] **Account**: upload a profile picture (PNG, JPEG or WebP, up to 2 MB). It shows here and in the top bar at once.
- [ ] **Account**: try a picture over 2 MB. It says why it can't.
- [ ] **Account**: remove the picture. The initials come back.
- [ ] **Account**: change your password (needs the current one). The bell shows "Password changed" at once.
- [ ] **Account**: change your security answers (needs the current password). Use your real answers if you change them; only here.
- [ ] **Sign-in**: pick how long "Keep me signed in" lasts.
- [ ] **Game connection**: type a port below 1024. It says why it can't.
- [ ] **Game connection**: put the port back. It saves.
- [ ] **Game connection**: flip "Reconnect automatically". It saves.
- [ ] **Notifications**: with "Password changed" still unread on the bell, flip **Account security** off. The bell's number drops at once (security notifications stop counting).
- [ ] **Notifications**: flip **Account security** back on. The number comes back.

## 9. The other pages

- [ ] **Admin** says "In development".
- [ ] **Overview**, **Party**, **Inventory**, **Gear** and **Location** each say the game isn't running and that they're waiting for it.
- [ ] On the Overview, hover a quick action: it says "Available once the game is running".
- [ ] Click that quick action: nothing happens.

## 10. Keyboard and mouse

- [ ] Reload the Overview and press **Tab** repeatedly: a purple ring moves through "Skip to content", the sidebar, then every top-bar button in order.
- [ ] On each top-bar button, press Enter or Space: it opens.
- [ ] With a menu or search open, press Esc: it closes.
- [ ] Do a few of the steps above with the mouse only, and a few with the keyboard only. Everything works both ways.

## 11. Safari or Firefox (a quick look)

The automated tests use Chrome only, so open <http://localhost:5173> in Safari or Firefox too (sign in there) and check:

- [ ] The folded sidebar: the icons line up, and each one's label shows on hover, above the page rather than hidden under it.
- [ ] The notifications, avatar and colour theme menus open, look right and close on Esc and on a click outside.
- [ ] ⌘K opens search there too.
- [ ] Tooltips appear on hover over the top-bar buttons.
- [ ] Click the top-bar search box, press **Esc**, then **Tab**: the ring lands on the Settings gear (the next button), not back at the top of the page.
- [ ] Open the bell, press **⌘K**, then **Esc**, then **Tab**: the ring lands on the avatar (the button after the bell).

## 12. Done

- [ ] Stop the dashboard with **Ctrl+C** in Terminal.
- [ ] Send your notes: anything that looked unfinished, in either theme, counts.
