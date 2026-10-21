# Amethyst Dashboard — Stage 1 (the dashboard itself) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Amethyst Dashboard web app up to the point where the game connects: accounts and sign-in, the full themed layout (light and dark), search, notifications, settings, the Admin placeholder, and every Debug page in its "waiting for the game" state.

**Architecture:** One npm package in a new top-level `dashboard/` folder holding three parts: `shared/` (constants and API types used by both sides), `server/` (a Fastify app on Node with a local SQLite database: accounts, sessions, sign-in/reset locks, settings, notifications, avatar), and `web/` (a React app built with Vite, talking to the server only through `/api`). In development `npm run dev` runs both; Vite proxies `/api` to the server. In stage 1 the server has no game link: `/api/game/status` always answers "waiting", which is what every Debug page shows. Stage 2 (its own plan) adds the game connection and the working Debug tools.

**Tech Stack:** Node 24 · TypeScript (strict) · Fastify 5 (+ `@fastify/cookie`, `@fastify/multipart`, `@fastify/static`) · `better-sqlite3` · `@node-rs/argon2` · React 19 · `react-router` 7 (library mode) · `@tanstack/react-query` 5 · `lucide-react` icons · `@fontsource/inter` + `@fontsource/cinzel` · Vite · Vitest (+ jsdom, `@testing-library/react`, `@testing-library/user-event`, `msw`) · Playwright (end-to-end) · `tsx`, `concurrently`. Use each package's current stable major.

**Spec:** `.claude/docs/superpowers/specs/2026-10-18-amethyst-dashboard-design.md` — read §3, §4, §5.1–5.3, §5.5 (Overview/Admin only), §5.6–5.10, §9. **Look:** the approved mockups in `.claude/docs/superpowers/specs/2026-10-18-amethyst-dashboard-mockups/` (open in a browser): `signin-v1.html`, `overview-v3.html`, `overview-dark-v1.html`, `party-v4.html`, `party-dark-v1.html` are the visual source of truth for this stage.

## Global Constraints

- Work on branch `amethyst-dashboard` in the main checkout. Never commit to `main`, never use git worktrees. Never stage `.DS_Store`, `.superpowers/`, `dashboard/node_modules/`, `dashboard/data/`, `dashboard/dist/`, `dashboard/test-results/` or `dashboard/playwright-report/`.
- Commit messages: `git commit -F <file>` — plain subject line, blank line, short body, blank line, the `Co-Authored-By:` trailer the committing agent's own environment gives it.
- All commands run from `dashboard/`. A task is done when `npm run typecheck` and `npm test` both pass with no warnings in the output (and `npm run e2e` where the task says so).
- Product name, exactly: **Amethyst Dashboard**. Breadcrumb root: `Dashboard` (e.g. `Dashboard / Debug / Party`).
- The three security questions, exactly, in this order: `What is my favorite holiday?` · `Which city was I born in?` · `What is my favorite board game?`
- Real answers are never written anywhere but the running app's own form. Tests use invented answers only.
- Lock duration **5 minutes**; **5** wrong passwords in a row lock sign-in; **any** wrong security answer locks password reset; minimum password length **10**.
- Passwords and security answers are stored only as argon2id hashes. Answers are normalized before hashing and checking: trim, lower-case, collapse runs of whitespace to one space.
- Session tokens: 32 random bytes, sent in an `httpOnly`, `SameSite=Lax` cookie named `amethyst_session` (`Secure` only when `AMETHYST_SECURE_COOKIES=1`), stored server-side only as a SHA-256 hash. "Keep me signed in" → persistent cookie for the account's `keepSignedInDays` setting (default 30); otherwise a browser-session cookie with a 12-hour server-side limit.
- Every state-changing request (`POST`/`PATCH`/`PUT`/`DELETE`) must carry header `X-Amethyst-Request: 1`, or the server answers 403. The web client adds it automatically.
- Colours are CSS custom properties in `web/src/theme/tokens.css`, values copied from the mockups (Task 6 lists them). No hard-coded colours in components; both themes must look finished.
- No default-looking browser or library controls: every input, button, select, checkbox, toggle, scrollbar, popover and dialog is styled to the mockups.
- Mouse and keyboard: every control reachable with Tab, visible focus ring (amethyst), Enter/Space activate, Escape closes popovers/dialogs/the search palette.
- Original design only — nothing copied from the SmartAdmin template.
- In stage 1 there is no game link: `GET /api/game/status` returns `{"connected":false,"state":"waiting"}`.
- A test written below as a name plus a comment body is specified by that comment: write it as assertions on exactly the observable the comment states.
- Shared test helpers (`testApp`, `ownerApp`, `signedIn`, `signin`, `post`, `get`, `patch`, `fakeClock`, `tmpFile`, `seedOwner`, `setupBody`, `forgotBody`, `OWNER_PASSWORD`, …) live in `server/test/helpers.ts`; web helpers (`renderAt`, `renderShellAt`, `click`, `type`, `keyboard`, `lastRequest`, `mock*`) in `web/test/helpers.tsx` + `web/test/msw.ts`. Each task adds the helpers its tests need.

## Review Focus

1. **A lock must survive a page refresh and a server restart** (someone guessing shouldn't get a fresh 5 tries by restarting) → test in Task 4.
2. **Answers typed with different capitals or spacing still match** (`"  New   York "` vs `"new york"`) → test in Task 3.
3. **Once an owner account exists, nobody can create another through the first-run endpoint** → test in Task 4.
4. **Signed out, any page (deep link included) lands on Sign in, and after signing in you return to the page you asked for; with no account yet, everything lands on Create your account** → test in Task 6.
5. **"Follow my Mac" switches theme live when macOS switches, and the page never flashes the wrong theme on load** → test in Task 6.

---

## File map

```
dashboard/
  package.json  tsconfig.json  tsconfig.server.json  tsconfig.web.json
  vite.config.ts  vitest.config.ts  playwright.config.ts  index.html  README.md  .gitignore
  shared/src/constants.ts        names, questions, limits, defaults
  shared/src/api.ts              request/response types for every /api route
  server/src/index.ts            starts the server (reads config, opens db, listens)
  server/src/app.ts              buildApp(options) → Fastify instance (used by tests)
  server/src/config.ts           loadConfig(env) → Config
  server/src/db/database.ts      openDatabase(path) → Db (runs migrations)
  server/src/db/migrations.ts    ordered SQL migrations
  server/src/auth/passwords.ts   hashing + policy
  server/src/auth/answers.ts     answer normalization + hashing
  server/src/auth/locks.ts       lock rules (pure, clock injected)
  server/src/auth/sessions.ts    session create/verify/revoke
  server/src/auth/accounts.ts    account store
  server/src/auth/routes.ts      /api/auth/*
  server/src/auth/guard.ts       requireUser hook + request-header check
  server/src/account/routes.ts   /api/account/*
  server/src/settings/settings.ts  settings store + validation
  server/src/settings/routes.ts  /api/settings
  server/src/notifications/notifications.ts  store
  server/src/notifications/routes.ts         /api/notifications/*
  server/src/game/routes.ts      /api/game/status (stage-1 stub)
  server/test/*.test.ts
  web/src/main.tsx  web/src/App.tsx  web/src/router.tsx
  web/src/api/client.ts  web/src/api/hooks.ts
  web/src/theme/tokens.css  web/src/theme/global.css  web/src/theme/ThemeProvider.tsx
  web/src/components/        Button, IconButton, Card, Field, Input, PasswordInput, Pill,
                             Ring, Toggle, Checkbox, Segmented, Popover, Dialog, Countdown
  web/src/auth/              AuthLayout, SetupPage, SignInPage, ForgotPage, LockedPanel
  web/src/shell/             AppShell, Sidebar, TopBar, PageHeader, NotificationsPanel,
                             SearchPalette, ColourThemeMenu, AvatarMenu, nav.ts
  web/src/pages/             OverviewPage, PartyPage, InventoryPage, GearPage, LocationPage,
                             AdminPage, SettingsPage, WaitingForGame
  web/test/*.test.tsx  web/test/msw.ts
  e2e/*.spec.ts
```

---

### Task 1: Project scaffold

**Files:**
- Create: everything at `dashboard/` top level listed above, `shared/src/constants.ts`, `server/src/{index,app,config}.ts`, `server/test/health.test.ts`, `web/src/{main,App}.tsx`, `web/test/smoke.test.tsx`
- Modify: repo-root `.gitignore` (add `dashboard/node_modules/`, `dashboard/data/`, `dashboard/dist/`, `dashboard/test-results/`, `dashboard/playwright-report/`)

**Interfaces:**
- Produces:
  - `shared/src/constants.ts`: `PRODUCT_NAME = "Amethyst Dashboard"`; `SECURITY_QUESTIONS: readonly [string, string, string]` (the three exact strings); `LOCK_MINUTES = 5`; `MAX_WRONG_PASSWORDS = 5`; `MIN_PASSWORD_LENGTH = 10`; `SESSION_HOURS_DEFAULT = 12`; `KEEP_SIGNED_IN_DAY_CHOICES = [7, 30, 90] as const`; `DEFAULT_GAME_PORT = 47821`; `SESSION_COOKIE = "amethyst_session"`; `REQUEST_HEADER = "X-Amethyst-Request"`.
  - `server/src/config.ts`: `interface Config { port: number; host: string; dbPath: string; secureCookies: boolean; webDist: string | null; lockMs: number }`; `loadConfig(env: NodeJS.ProcessEnv): Config` — defaults `port 4517`, `host "127.0.0.1"`, `dbPath "data/amethyst.db"`, `secureCookies false`, `webDist "dist/web"` in production else `null`, `lockMs = LOCK_MINUTES * 60_000`; env names `AMETHYST_PORT`, `AMETHYST_HOST`, `AMETHYST_DB`, `AMETHYST_SECURE_COOKIES`, and `AMETHYST_LOCK_SECONDS` which is honoured **only when `NODE_ENV === "test"`** (end-to-end tests use a short lock; a real run can never shorten it).
  - `server/src/app.ts`: `buildApp(opts: { config: Config; now?: () => Date }): Promise<FastifyInstance>` — registers routes; `GET /api/health` → `{ "ok": true, "name": "Amethyst Dashboard" }`. Later tasks add `db` to its options (Task 2).
  - npm scripts: `dev` (concurrently: `tsx watch server/src/index.ts` + `vite`), `build` (`vite build` → `dist/web`, `tsc -p tsconfig.server.json` → `dist/server`), `start` (`node dist/server/index.js`, serves `dist/web` too), `test` (`vitest run`), `typecheck` (both tsconfigs, `--noEmit`), `e2e` (`playwright test`).
  - `vitest.config.ts`: two projects — `server` (environment `node`, `server/test/**`) and `web` (environment `jsdom`, `web/test/**`, setup file `web/test/setup.ts` registering `@testing-library/jest-dom` matchers).
  - `vite.config.ts`: root `web/`, `server.proxy` `/api` → `http://127.0.0.1:4517`, build out `dist/web`.

- [ ] **Step 1: Write the failing tests**

```ts
// server/test/health.test.ts
test("health answers with the product name", async () => {
  const app = await buildApp({ config: loadConfig({}) });
  const res = await app.inject({ method: "GET", url: "/api/health" });
  expect(res.statusCode).toBe(200);
  expect(res.json()).toEqual({ ok: true, name: "Amethyst Dashboard" });
});
test("config reads its env names and keeps safe defaults", () => {
  expect(loadConfig({}).host).toBe("127.0.0.1");
  expect(loadConfig({ AMETHYST_PORT: "5000" }).port).toBe(5000);
});
// web/test/smoke.test.tsx
test("the app renders the product name", () => {
  render(<App />);
  expect(screen.getByText("Amethyst Dashboard")).toBeInTheDocument();
});
```

- [ ] **Step 2: Run `npm install` then `npm test` — expect failures (modules missing).**
- [ ] **Step 3: Create the scaffold and the three source files.** `web/src/App.tsx` renders the product name for now (Task 6 replaces it with the router). `dashboard/README.md`: what it is, `npm install`, `npm run dev` → open `http://localhost:5173`, `npm test`, `npm run e2e`, where the database lives, that it must only run on this Mac for now.
- [ ] **Step 4: `npm run typecheck && npm test` — PASS.**
- [ ] **Step 5: Commit** — "Scaffold the Amethyst Dashboard (server, web, shared)".

---

### Task 2: Database

**Files:**
- Create: `server/src/db/database.ts`, `server/src/db/migrations.ts`, `server/test/database.test.ts`
- Modify: `server/src/app.ts` (options gain `db: Db`), `server/src/index.ts` (open the db from `config.dbPath`, creating its folder)

**Interfaces:**
- Produces: `type Db = import("better-sqlite3").Database`; `openDatabase(path: string): Db` (`":memory:"` allowed; WAL mode; `foreign_keys = ON`; runs pending migrations inside a transaction; records versions in `schema_migrations(version INTEGER PRIMARY KEY, applied_at TEXT)`).
- Tables (migration 1):
  - `accounts(id INTEGER PK, username TEXT UNIQUE NOT NULL COLLATE NOCASE, display_name TEXT NOT NULL, password_hash TEXT NOT NULL, answer_hashes TEXT NOT NULL /* JSON array of 3 */, role TEXT NOT NULL /* 'owner' */, avatar BLOB, avatar_type TEXT, created_at TEXT NOT NULL)`
  - `sessions(token_hash TEXT PK, account_id INTEGER NOT NULL REFERENCES accounts ON DELETE CASCADE, persistent INTEGER NOT NULL, expires_at TEXT NOT NULL, created_at TEXT NOT NULL)`
  - `auth_locks(username TEXT NOT NULL COLLATE NOCASE, kind TEXT NOT NULL /* 'signin' | 'reset' */, failures INTEGER NOT NULL, locked_until TEXT, PRIMARY KEY(username, kind))` — keyed by the typed username, so unknown usernames are treated the same as real ones.
  - `settings(account_id INTEGER PK REFERENCES accounts ON DELETE CASCADE, json TEXT NOT NULL)`
  - `notifications(id INTEGER PK, account_id INTEGER NOT NULL REFERENCES accounts ON DELETE CASCADE, kind TEXT NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL, created_at TEXT NOT NULL, read_at TEXT)`

- [ ] **Step 1: Write the failing tests**

```ts
test("a new database gets every table", () => {
  const db = openDatabase(":memory:");
  const names = db.prepare("select name from sqlite_master where type='table'").all().map((r: any) => r.name);
  for (const t of ["accounts","sessions","auth_locks","settings","notifications","schema_migrations"]) expect(names).toContain(t);
});
test("opening twice applies migrations once", () => {
  const file = tmpFile(); openDatabase(file).close();
  const db = openDatabase(file);
  expect(db.prepare("select count(*) as n from schema_migrations").get()).toEqual({ n: 1 });
});
test("usernames are unique regardless of case", () => {
  const db = openDatabase(":memory:");
  insertAccount(db, "owner"); expect(() => insertAccount(db, "OWNER")).toThrow();
});
```
(`tmpFile()` and `insertAccount()` are small helpers in `server/test/helpers.ts`.)

- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: `npm run typecheck && npm test` — PASS.**
- [ ] **Step 5: Commit** — "Add the dashboard's database".

---

### Task 3: Auth building blocks

**Files:**
- Create: `server/src/auth/{passwords,answers,locks,sessions,accounts}.ts`, `server/test/auth-units.test.ts`

**Interfaces:**
- `passwords.ts`: `checkPasswordPolicy(pw: string): "ok" | "too_short"` (fewer than `MIN_PASSWORD_LENGTH` characters → `too_short`); `hashPassword(pw: string): Promise<string>`; `verifyPassword(hash: string, pw: string): Promise<boolean>` (argon2id via `@node-rs/argon2`).
- `answers.ts`: `normalizeAnswer(a: string): string`; `hashAnswers(a: [string,string,string]): Promise<string[]>`; `verifyAnswers(hashes: string[], a: [string,string,string]): Promise<boolean[]>` (normalizes first; checks all three, never short-circuits).
- `locks.ts` (pure, no db): `type LockState = { failures: number; lockedUntil: Date | null }`; `isLocked(s: LockState, now: Date): boolean`; `registerFailure(kind: "signin" | "reset", s: LockState, now: Date, lockMs: number): LockState` — `signin`: failures+1, at `MAX_WRONG_PASSWORDS` set `lockedUntil = now + lockMs` and failures 0; `reset`: lock at once (callers pass `config.lockMs`); `triesLeft(s: LockState): number` (signin only: `MAX_WRONG_PASSWORDS - failures`); plus db helpers `readLock(db, username, kind): LockState`, `writeLock(db, username, kind, s)`, `clearLock(db, username, kind)`.
- `sessions.ts`: `createSession(db, accountId, persistent: boolean, keepDays: number, now: Date): { token: string; expiresAt: Date }` (persistent → now + keepDays; else now + `SESSION_HOURS_DEFAULT`); `findSession(db, token, now): { accountId: number; persistent: boolean } | null` (expired → null and deleted); `revokeSession(db, token)`; `revokeAllSessions(db, accountId, exceptToken?: string)`.
- `accounts.ts`: `countAccounts(db): number`; `createOwner(db, input: { username; displayName; passwordHash; answerHashes }, now): Account`; `findByUsername(db, username): Account | null`; `findById(db, id): Account | null`; `type Account = { id; username; displayName; role: "owner"; hasAvatar: boolean; passwordHash; answerHashes: string[] }`.

- [ ] **Step 1: Write the failing tests**

```ts
test("answers ignore capitals and extra spaces", async () => {  // Review Focus 2
  expect(normalizeAnswer("  New   York ")).toBe("new york");
  const h = await hashAnswers(["Lantern Festival", "New York", "Chess"]);
  expect(await verifyAnswers(h, ["lantern festival", "  New   York ", "CHESS"])).toEqual([true, true, true]);
  expect(await verifyAnswers(h, ["lantern festival", "Boston", "chess"])).toEqual([true, false, true]);
});
test("password policy and hashing", async () => {
  expect(checkPasswordPolicy("short")).toBe("too_short");
  expect(checkPasswordPolicy("long enough!")).toBe("ok");
  const h = await hashPassword("correct horse battery");
  expect(h).not.toContain("correct horse");
  expect(await verifyPassword(h, "correct horse battery")).toBe(true);
  expect(await verifyPassword(h, "wrong horse battery")).toBe(false);
});
test("five wrong passwords lock sign-in for five minutes", () => {
  const t0 = new Date("2026-10-18T12:00:00Z");
  let s = { failures: 0, lockedUntil: null as Date | null };
  for (let i = 0; i < 4; i++) s = registerFailure("signin", s, t0, 5 * 60_000);
  expect(isLocked(s, t0)).toBe(false); expect(triesLeft(s)).toBe(1);
  s = registerFailure("signin", s, t0, 5 * 60_000);
  expect(isLocked(s, t0)).toBe(true);
  expect(isLocked(s, new Date(t0.getTime() + 5 * 60_000 - 1))).toBe(true);
  expect(isLocked(s, new Date(t0.getTime() + 5 * 60_000))).toBe(false);
});
test("one wrong answer locks reset", () => {
  const t0 = new Date("2026-10-18T12:00:00Z");
  expect(isLocked(registerFailure("reset", { failures: 0, lockedUntil: null }, t0, 5 * 60_000), t0)).toBe(true);
});
test("sessions expire and can be revoked", () => {
  const db = openDatabase(":memory:"); const id = seedOwner(db);
  const t0 = new Date("2026-10-18T12:00:00Z");
  const s = createSession(db, id, false, 30, t0);
  expect(findSession(db, s.token, t0)?.accountId).toBe(id);
  expect(findSession(db, s.token, new Date(t0.getTime() + 12 * 3600_000 + 1))).toBeNull();
  const p = createSession(db, id, true, 30, t0);
  expect(findSession(db, p.token, new Date(t0.getTime() + 29 * 86400_000))?.persistent).toBe(true);
  revokeSession(db, p.token); expect(findSession(db, p.token, t0)).toBeNull();
  expect(db.prepare("select token_hash from sessions").all().some((r: any) => r.token_hash === p.token)).toBe(false); // only hashes stored
});
```

- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: PASS (typecheck + tests).**
- [ ] **Step 5: Commit** — "Add password, answer, lock and session building blocks".

---

### Task 4: Auth API

**Files:**
- Create: `server/src/auth/routes.ts`, `server/src/auth/guard.ts`, `server/src/notifications/notifications.ts`, `server/test/auth-api.test.ts`
- Modify: `server/src/app.ts`, `shared/src/api.ts`

**Interfaces:**
- `shared/src/api.ts` (types for everything below): `User = { id: number; username: string; displayName: string; role: "owner"; hasAvatar: boolean }`; `AuthState = { setupRequired: boolean; user: User | null }`; error body `ApiError = { error: string; message: string; triesLeft?: number; lockedUntil?: string }`.
- Routes (all JSON; mutating ones require `X-Amethyst-Request: 1` → else 403 `{error:"bad_request_header"}`):
  - `GET /api/auth/state` → `AuthState`.
  - `GET /api/auth/questions` → `{ questions: SECURITY_QUESTIONS }`.
  - `POST /api/auth/setup` `{ username, displayName, password, answers: [a1,a2,a3] }` → 201 `User` + session cookie (persistent false). 409 `{error:"already_set_up"}` if any account exists. 400 `{error:"too_short"}` / `{error:"invalid_username"}` (3–32 chars, letters, digits, `_ . -`) / `{error:"missing_answer"}` (any answer blank after normalizing).
  - `POST /api/auth/signin` `{ username, password, keepSignedIn }` → 200 `User` + cookie. Locked → 423 `{error:"locked", lockedUntil}`. Wrong password for a real account → 401 `{error:"wrong_password", triesLeft}` (or 423 when this attempt locks it). Unknown username → 401 `{error:"wrong_password", triesLeft}` counted the same way (locks keyed by typed username). Success clears the signin lock.
  - `POST /api/auth/signout` → 204, revokes the session, clears the cookie.
  - `POST /api/auth/forgot` `{ username, answers: [a1,a2,a3], newPassword }` → 204 (password changed, reset lock cleared, all sessions revoked). Locked → 423 `{error:"locked", lockedUntil}`. Any wrong answer, or unknown username → 401 `{error:"wrong_answer", lockedUntil}` and the reset lock is set. `too_short` → 400 before answers are checked (no lock).
  - `guard.ts`: `requireUser` preHandler — reads the cookie, `findSession`, sets `request.user: User`; else 401 `{error:"signed_out"}`. Every route outside `/api/auth/*` and `/api/health` uses it.
- Session length: the cookie for "Keep me signed in" lasts `readKeepSignedInDays(db, accountId): number` days — Task 4 creates `server/src/settings/settings.ts` with just this function (the account's saved `keepSignedInDays`, or 30 when it has no settings row); Task 5 grows that file and keeps this function reading through it.
- `notifications.ts`: `addNotification(db, accountId, kind: NotificationKind, title: string, body: string, now: Date): void`; `type NotificationKind = "security" | "game" | "changes"`. Auth routes add, for a real account: `security` "Failed sign-in" on each wrong password; `security` "Sign-in locked" on a sign-in lock; `security` "Password reset locked" on a reset lock; `security` "Password changed" on a successful reset.

- [ ] **Step 1: Write the failing tests** (use `buildApp` with an in-memory db and an injected clock `now`; a helper `post(app, url, body)` adds the request header)

```ts
test("first run: setup creates the owner and signs them in", async () => {
  const app = await testApp();
  expect((await get(app, "/api/auth/state")).json()).toEqual({ setupRequired: true, user: null });
  const res = await post(app, "/api/auth/setup", setupBody());
  expect(res.statusCode).toBe(201);
  expect(res.cookies.find(c => c.name === "amethyst_session")?.httpOnly).toBe(true);
});
test("setup can never run twice", async () => {   // Review Focus 3
  const app = await testApp(); await post(app, "/api/auth/setup", setupBody());
  const again = await post(app, "/api/auth/setup", { ...setupBody(), username: "intruder" });
  expect(again.statusCode).toBe(409); expect(again.json().error).toBe("already_set_up");
});
test("mutating requests without the header are refused", async () => {
  const app = await testApp();
  const res = await app.inject({ method: "POST", url: "/api/auth/setup", payload: setupBody() });
  expect(res.statusCode).toBe(403);
});
test("wrong passwords count down and then lock", async () => {
  const app = await ownerApp();
  for (let i = 4; i >= 1; i--) expect((await signin(app, "nope-nope-nope")).json()).toMatchObject({ error: "wrong_password", triesLeft: i });
  const fifth = await signin(app, "nope-nope-nope");
  expect(fifth.statusCode).toBe(423);
  expect((await signin(app, OWNER_PASSWORD)).statusCode).toBe(423);          // even the right one, while locked
});
test("a lock survives a server restart", async () => {   // Review Focus 1
  const file = tmpFile(); let app = await ownerApp({ dbPath: file });
  for (let i = 0; i < 5; i++) await signin(app, "nope-nope-nope");
  await app.close(); app = await testApp({ dbPath: file });                   // same database, new process
  expect((await signin(app, OWNER_PASSWORD)).statusCode).toBe(423);
});
test("the lock lifts after five minutes", async () => {
  const clock = fakeClock("2026-10-18T12:00:00Z"); const app = await ownerApp({ clock });
  for (let i = 0; i < 5; i++) await signin(app, "nope-nope-nope");
  clock.advance(5 * 60_000);
  expect((await signin(app, OWNER_PASSWORD)).statusCode).toBe(200);
});
test("forgot password: one wrong answer locks reset, right answers change the password", async () => {
  const app = await ownerApp();
  const bad = await post(app, "/api/auth/forgot", { username: "owner", answers: ["x","y","z"], newPassword: "a brand new password" });
  expect(bad.statusCode).toBe(401); expect(bad.json().lockedUntil).toBeDefined();
  expect((await post(app, "/api/auth/forgot", forgotBody())).statusCode).toBe(423);
});
test("an unknown username gets the same answer shape as a real one", async () => {
  const app = await ownerApp();
  expect((await signin(app, "whatever-pass", "nobody")).json()).toMatchObject({ error: "wrong_password", triesLeft: 4 });
  expect((await post(app, "/api/auth/forgot", { ...forgotBody(), username: "nobody" })).json().error).toBe("wrong_answer");
});
test("keep me signed in sets a lasting cookie, otherwise a session cookie", async () => {
  const app = await ownerApp();
  expect((await signin(app, OWNER_PASSWORD, "owner", true)).cookies[0].maxAge).toBe(30 * 86400);
  expect((await signin(app, OWNER_PASSWORD, "owner", false)).cookies[0].maxAge).toBeUndefined();
});
test("protected routes need a session", async () => {
  const app = await ownerApp();
  expect((await get(app, "/api/game/status")).statusCode).toBe(401);
});
```

- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement routes, guard, notifications store. Also add `server/src/game/routes.ts`: `GET /api/game/status` (guarded) → `{ connected: false, state: "waiting" }`.**
- [ ] **Step 4: PASS.**
- [ ] **Step 5: Commit** — "Add sign-in, first-run setup and password reset to the server".

---

### Task 5: Account, settings and notifications API

**Files:**
- Create: `server/src/account/routes.ts`, `server/src/settings/{settings,routes}.ts`, `server/src/notifications/routes.ts`, `server/test/account-api.test.ts`
- Modify: `server/src/app.ts`, `shared/src/api.ts`

**Interfaces:**
- `shared/src/api.ts` adds:
  - `Settings = { appearance: "light" | "dark" | "system"; colourTheme: "amethyst"; sidebar: "expanded" | "icons"; keepSignedInDays: 7 | 30 | 90; gamePort: number; autoReconnect: boolean; notify: { security: boolean; game: boolean; changes: boolean } }`
  - `DEFAULT_SETTINGS: Settings` = light, amethyst, expanded, 30, `DEFAULT_GAME_PORT`, true, all three `true`.
  - `Notification = { id: number; kind: NotificationKind; title: string; body: string; createdAt: string; read: boolean }`
- Routes (all guarded):
  - `GET /api/account` → `User`; `PATCH /api/account` `{ displayName }` (1–40 chars) → `User`.
  - `POST /api/account/password` `{ currentPassword, newPassword }` → 204; wrong current → 401 `{error:"wrong_password"}`; policy → 400. Revokes the account's other sessions.
  - `POST /api/account/answers` `{ currentPassword, answers:[3] }` → 204; wrong current → 401.
  - `PUT /api/account/avatar` multipart field `file` (png, jpeg or webp, at most 2 MB) → 204; `GET /api/account/avatar` → the image or 404; `DELETE /api/account/avatar` → 204.
  - `GET /api/settings` → `Settings` (defaults merged); `PATCH /api/settings` partial → `Settings`; unknown keys or bad values → 400 `{error:"invalid_setting", message:<key>}`; `gamePort` 1024–65535.
  - `GET /api/notifications` → `{ items: Notification[]; unread: number }` newest first, at most 100; `POST /api/notifications/:id/read` → 204; `POST /api/notifications/read-all` → 204. Notifications of a kind switched off in `settings.notify` are still stored but not counted in `unread`.

- [ ] **Step 1: Write the failing tests**

```ts
test("settings start at the defaults and save partial changes", async () => {
  const { app, cookie } = await signedIn();
  expect((await get(app, "/api/settings", cookie)).json()).toEqual(DEFAULT_SETTINGS);
  const res = await patch(app, "/api/settings", { appearance: "dark" }, cookie);
  expect(res.json().appearance).toBe("dark"); expect(res.json().keepSignedInDays).toBe(30);
});
test("bad settings are refused", async () => {
  const { app, cookie } = await signedIn();
  expect((await patch(app, "/api/settings", { colourTheme: "teal" }, cookie)).statusCode).toBe(400);
  expect((await patch(app, "/api/settings", { gamePort: 80 }, cookie)).statusCode).toBe(400);
});
test("changing the password needs the current one and signs out other sessions", async () => {
  const { app, cookie } = await signedIn(); const other = await signinCookie(app);
  expect((await post(app, "/api/account/password", { currentPassword: "nope-nope-nope", newPassword: "another long password" }, cookie)).statusCode).toBe(401);
  expect((await post(app, "/api/account/password", { currentPassword: OWNER_PASSWORD, newPassword: "another long password" }, cookie)).statusCode).toBe(204);
  expect((await get(app, "/api/account", other)).statusCode).toBe(401);
  expect((await get(app, "/api/account", cookie)).statusCode).toBe(200);
});
test("security events become notifications and can be marked read", async () => {
  const { app, cookie } = await signedIn(); await signin(app, "nope-nope-nope");
  const list = (await get(app, "/api/notifications", cookie)).json();
  expect(list.unread).toBe(1); expect(list.items[0]).toMatchObject({ kind: "security", title: "Failed sign-in", read: false });
  await post(app, "/api/notifications/read-all", {}, cookie);
  expect((await get(app, "/api/notifications", cookie)).json().unread).toBe(0);
});
test("avatar upload accepts small images only", async () => {
  const { app, cookie } = await signedIn();
  expect((await putAvatar(app, cookie, tinyPng(), "image/png")).statusCode).toBe(204);
  expect((await get(app, "/api/account", cookie)).json().hasAvatar).toBe(true);
  expect((await putAvatar(app, cookie, Buffer.alloc(2 * 1024 * 1024 + 1), "image/png")).statusCode).toBe(413);
  expect((await putAvatar(app, cookie, Buffer.from("hi"), "text/plain")).statusCode).toBe(415);
});
```

- [ ] **Step 2: Run — FAIL.**  - [ ] **Step 3: Implement.**  - [ ] **Step 4: PASS.**
- [ ] **Step 5: Commit** — "Add account, settings and notifications to the server".

---

### Task 6: Web foundations — theme, components, API client, routing

**Files:**
- Create: `web/src/theme/{tokens.css,global.css,ThemeProvider.tsx}`, `web/src/components/*`, `web/src/api/{client,hooks}.ts`, `web/src/router.tsx`, `web/test/{setup.ts,msw.ts,theme.test.tsx,router.test.tsx,components.test.tsx}`
- Modify: `web/src/App.tsx`, `web/src/main.tsx`, `index.html`

**Interfaces:**
- `tokens.css` — light on `:root, [data-theme="light"]`, dark on `[data-theme="dark"]`, exactly these values (from the mockups):

| Token | Light | Dark |
|---|---|---|
| `--side` / `--side2` | `#1E1230` / `#281A3F` | `#0D0817` / `#1E1433` |
| `--side-text` / `--side-head` | `#B9A9D6` / `#7E6AA3` | `#B3A3D3` / `#6E5B94` |
| `--bg` / `--card` / `--line` | `#F5F3F9` / `#FFFFFF` / `#E7E2F0` | `#120D1F` / `#1A1329` / `#2C2242` |
| `--text` / `--dim` | `#2A2238` / `#7A7090` | `#ECE4FA` / `#9C8FB8` |
| `--am` / `--am2` / `--am-soft` | `#7E4FE0` / `#9C6BF5` / `#EFE7FF` | `#9C6BF5` / `#B48CFF` / `#2A1D47` |
| `--gold` / `--warn` | `#C9962B` / `#D9822B` | `#E2B54B` / `#E6A04F` |
| `--ok` / `--ok-soft` | `#2E9E5B` / `#E3F5EA` | `#4CC27E` / `#17301F` |
| `--bad` / `--bad-soft` | `#C6455E` / `#FBE9ED` | `#EE6F86` / `#3A1A24` |
| `--aria` / `--kael` / `--lyra` | `#3D8FE0` / `#D84545` / `#4CAF50` | `#5AA7F5` / `#F06A6A` / `#6CCF6E` |

  Plus spacing/radius scale (card radius 10px, control radius 8px), font `Inter` (body) and `Cinzel` (brand moments), focus ring `0 0 0 3px` amethyst at 35%.
- `ThemeProvider.tsx`: `ThemeProvider({ appearance }: { appearance: Settings["appearance"] })` sets `document.documentElement.dataset.theme` to `"light" | "dark"`, following `matchMedia("(prefers-color-scheme: dark)")` live when `appearance === "system"`; `useTheme(): { resolved: "light" | "dark" }`. `index.html` has an inline script that applies the last resolved theme from `localStorage["amethyst-theme"]` before React loads (no flash).
- Components (each a small file, styled with CSS modules): `Button` (`variant: "primary" | "secondary" | "danger" | "ghost"`, `size: "sm" | "md"`, `loading`), `IconButton` (needs `label` for screen readers), `Card` (`title`, `actions`), `Field` (`label`, `hint`, `error`), `Input`, `PasswordInput` (Show/Hide), `Pill` (`tone: "ok" | "am" | "warn" | "bad" | "neutral"`), `Ring` (`percent`, `label`, `colour`), `Toggle`, `Checkbox`, `Segmented`, `Popover` (anchored, closes on Escape/outside click, returns focus), `Dialog` (focus-trapped), `Countdown` (`until: Date`, `onDone`, shows `m:ss`).
- `api/client.ts`: `api<T>(method, path, body?): Promise<T>` — always `credentials: "same-origin"`, adds `X-Amethyst-Request: 1` to non-GET, throws `ApiFailure { status: number; body: ApiError }` on non-2xx.
- `api/hooks.ts` (react-query): `useAuthState()`, `useSettings()` / `useUpdateSettings()`, `useNotifications()` (refetch every 30 s), `useGameStatus()` (refetch every 3 s), `useSignOut()`.
- `router.tsx`: routes `/setup`, `/signin`, `/forgot`, and inside `AppShell`: `/` (Overview), `/party`, `/inventory`, `/gear`, `/location`, `/admin`, `/settings` (+ `/settings/:section`). Guards: `setupRequired` → everything goes to `/setup`; signed out → `/signin?next=<path>`; signed in → `/setup`, `/signin`, `/forgot` go to `/`. After sign-in, go to `next` if it is an in-app path, else `/`.

- [ ] **Step 1: Write the failing tests** (msw mocks `/api/*`)

```tsx
test("no account yet: every route lands on Create your account", async () => {   // Review Focus 4
  mockAuthState({ setupRequired: true, user: null });
  renderAt("/inventory"); expect(await screen.findByRole("heading", { name: "Create your account" })).toBeInTheDocument();
});
test("signed out: a deep link goes to sign in, then back to the page asked for", async () => {   // Review Focus 4
  mockAuthState({ setupRequired: false, user: null });
  const { router } = renderAt("/gear");
  expect(router.state.location.pathname).toBe("/signin");
  expect(router.state.location.search).toBe("?next=%2Fgear");
  await signInThroughForm();                                   // msw answers 200 + switches auth state
  expect(router.state.location.pathname).toBe("/gear");
});
test("follow my Mac switches live", () => {   // Review Focus 5
  const mq = mockMatchMedia(false);
  render(<ThemeProvider appearance="system" />);
  expect(document.documentElement.dataset.theme).toBe("light");
  act(() => mq.setMatches(true));
  expect(document.documentElement.dataset.theme).toBe("dark");
});
test("the saved theme is applied before React renders", () => {   // Review Focus 5
  localStorage.setItem("amethyst-theme", "dark"); runIndexHtmlThemeScript();
  expect(document.documentElement.dataset.theme).toBe("dark");
});
test("the API client marks state-changing requests", async () => {
  const seen = captureRequests(); await api("POST", "/api/auth/signout");
  expect(seen[0].headers.get("X-Amethyst-Request")).toBe("1");
});
test("popover and dialog close on Escape and return focus", async () => { /* open via button, press Escape, focus back on the button */ });
```

- [ ] **Step 2: Run — FAIL.**  - [ ] **Step 3: Implement.**  - [ ] **Step 4: PASS.**
- [ ] **Step 5: Commit** — "Add the dashboard's theme, components, API client and routing".

---

### Task 7: Sign-in screens

**Files:**
- Create: `web/src/auth/{AuthLayout,SetupPage,SignInPage,ForgotPage,LockedPanel}.tsx` (+ CSS modules), `web/test/auth-pages.test.tsx`

**Interfaces:** Consumes Task 6 components and `api`. Matches `signin-v1.html`: a deep-plum brand panel on the left (gem mark, "Amethyst Dashboard", Cinzel tagline, small footer "The Amethyst Requiem · dev dashboard") and the form on the right; at narrow widths the brand panel stacks on top.
- **SetupPage** (`/setup`): heading "Create your account"; lead "You'll be the owner of this dashboard."; fields Display name, Username, Password (strength meter: 4 bars; "at least 10 characters" hint), Confirm password; "SECURITY QUESTIONS · used to reset your password" with the three questions (numbered) and an answer field each; button "Create account". Brand tagline "Welcome. Let's set up your account." with "This only appears once. After this, nobody can sign up. You'll create any other accounts yourself, from inside." Client-side checks mirror the server's (too short, passwords differ, blank answers) with messages under the fields.
- **SignInPage** (`/signin`): heading "Sign in"; lead "Use the account you created."; Username, Password, "Keep me signed in" (checked by default), link "Forgot password?", button "Sign in". On `wrong_password`: alert "That password isn't right. **N tries left** before a 5-minute pause." (singular "1 try left"). On 423: the `LockedPanel`.
- **ForgotPage** (`/forgot`): heading "Answer your security questions"; lead "Capitals and extra spaces don't matter."; Username; the three questions with hidden answers (Show toggles); New password + Confirm; "Reset password"; "← Back to sign in". On success: back to `/signin` with a green note "Password changed. Sign in with your new password." On 401/423: `LockedPanel`.
- **LockedPanel**: heading "Password reset is locked" (forgot) / "Sign-in is paused" (sign-in); a countdown ring to `lockedUntil` (`Countdown` inside a `Ring`); "The page unlocks on its own. No need to refresh."; a disabled "Try again" that enables when the timer ends; "← Back to sign in". Brand tagline "Taking a short pause." / "This stops anyone from guessing over and over."

- [ ] **Step 1: Write the failing tests** (msw)

```tsx
test("setup shows the three questions in order and creates the account", async () => {
  renderAt("/setup");
  const qs = screen.getAllByTestId("security-question").map(e => e.textContent);
  expect(qs).toEqual(["What is my favorite holiday?", "Which city was I born in?", "What is my favorite board game?"]);
  await fillSetup({ password: "short" }); await click("Create account");
  expect(screen.getByText(/at least 10 characters/)).toBeInTheDocument();
  await fillSetup({ password: "a long password!", confirm: "a long password!" }); await click("Create account");
  expect(lastRequest("/api/auth/setup").body.answers).toHaveLength(3);
});
test("a wrong password shows the tries left", async () => {
  mockSignin(401, { error: "wrong_password", triesLeft: 3 });
  await signInWith("owner", "nope-nope-nope");
  expect(screen.getByText(/3 tries left/)).toBeInTheDocument();
});
test("a locked sign-in counts down and unlocks itself", async () => {
  vi.useFakeTimers(); mockSignin(423, { error: "locked", lockedUntil: inMinutes(5) });
  await signInWith("owner", "x");
  expect(screen.getByText("5:00")).toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Try again" })).toBeDisabled();
  act(() => vi.advanceTimersByTime(5 * 60_000));
  expect(screen.getByRole("button", { name: "Try again" })).toBeEnabled();
});
test("a wrong answer locks reset with a countdown", async () => {
  mockForgot(401, { error: "wrong_answer", lockedUntil: inMinutes(5) });
  await submitForgot(); expect(screen.getByRole("heading", { name: "Password reset is locked" })).toBeInTheDocument();
});
```

- [ ] **Step 2: Run — FAIL.**  - [ ] **Step 3: Implement.**  - [ ] **Step 4: PASS.**
- [ ] **Step 5: Visual check.** `npm run dev`, then in a browser at 1440 px wide compare each screen with `signin-v1.html` in light and dark (dark: same layout, form side on `--card`). Record in the commit body what you compared.
- [ ] **Step 6: Commit** — "Add the sign-in screens".

---

### Task 8: App shell — sidebar, top bar, page header

**Files:**
- Create: `web/src/shell/{AppShell,Sidebar,TopBar,PageHeader,ColourThemeMenu,AvatarMenu,nav}.tsx` (+ CSS modules), `web/test/shell.test.tsx`

**Interfaces:** Matches `overview-v3.html` / `overview-dark-v1.html` (sidebar 250 px; top bar 64 px).
- `nav.ts`: `NAV: { group: "OVERVIEW" | "DEBUG" | "ADMIN"; items: { label: string; path: string; icon: LucideIcon; badge?: string }[] }[]` = OVERVIEW: Overview `/` (LayoutDashboard); DEBUG: Party `/party` (Users), Inventory `/inventory` (ShoppingBag), Gear `/gear` (Sword), Location `/location` (MapPin); ADMIN: Admin `/admin` (Shield, badge "In development").
- **Sidebar:** gem mark + "Amethyst Dashboard"; a "Filter" box that hides non-matching items (case-insensitive) and empty groups; active item highlighted with a 3 px amethyst left bar; `settings.sidebar === "icons"` collapses to a 72 px icon rail with tooltips.
- **TopBar:** collapse button (toggles `sidebar` setting); search box styled as an input "Search for anything — a hero, an item, a map…" that opens the Search palette (Task 9) — so does ⌘K / Ctrl+K anywhere; then icon buttons, each with a tooltip and `aria-label`: Settings (→ `/settings`), Light/Dark (moon in light, sun in dark; flips `appearance` between light and dark), Colour theme (`ColourThemeMenu`: "Amethyst" ✓ and a muted "More themes coming later"), Full screen (Fullscreen API; icon swaps to exit), Notifications (bell with unread badge; opens Task 9's panel), Avatar (initials or picture; `AvatarMenu`: name + username, "Profile" → `/settings/account`, "Settings", divider, "Sign out").
- **PageHeader:** `PageHeader({ title, crumbs, right? })` — uppercase title, breadcrumb `Dashboard / …`, optional right-side content (mini-stats or a status pill).

- [ ] **Step 1: Write the failing tests**

```tsx
test("the sidebar shows the three groups and filters", async () => {
  renderShellAt("/");
  expect(screen.getByText("OVERVIEW")).toBeVisible(); expect(screen.getByText("DEBUG")).toBeVisible(); expect(screen.getByText("ADMIN")).toBeVisible();
  expect(screen.getByText("In development")).toBeVisible();
  await type(screen.getByPlaceholderText("Filter"), "gea");
  expect(screen.getByRole("link", { name: "Gear" })).toBeVisible();
  expect(screen.queryByRole("link", { name: "Party" })).toBeNull();
  expect(screen.queryByText("ADMIN")).toBeNull();
});
test("the theme button flips light and dark and saves it", async () => {
  renderShellAt("/", { settings: { appearance: "light" } });
  await click(screen.getByRole("button", { name: "Switch to dark mode" }));
  expect(lastRequest("/api/settings").body).toEqual({ appearance: "dark" });
});
test("collapse keeps every page reachable by icon", async () => {
  renderShellAt("/", { settings: { sidebar: "icons" } });
  for (const name of ["Overview","Party","Inventory","Gear","Location","Admin"]) expect(screen.getByRole("link", { name })).toBeInTheDocument();
});
test("the avatar menu signs out", async () => { /* open menu, click Sign out → POST /api/auth/signout, lands on /signin */ });
test("every top-bar button has a name", () => {
  renderShellAt("/");
  for (const b of within(screen.getByRole("banner")).getAllByRole("button")) expect(b).toHaveAccessibleName();
});
```

- [ ] **Step 2: Run — FAIL.**  - [ ] **Step 3: Implement.**  - [ ] **Step 4: PASS.**
- [ ] **Step 5: Visual check** against `overview-v3.html` and `overview-dark-v1.html` at 1440 px (sidebar, top bar, header only): icon row aligned (a review caught a misaligned bell in the mockup), badge positions, spacing.
- [ ] **Step 6: Commit** — "Add the dashboard's sidebar, top bar and page header".

---

### Task 9: Notifications panel and search palette

**Files:**
- Create: `web/src/shell/{NotificationsPanel,SearchPalette}.tsx` (+ CSS), `web/src/shell/searchIndex.ts`, `web/test/notifications-search.test.tsx`

**Interfaces:**
- **NotificationsPanel** (popover from the bell): header "Notifications" + "Mark all as read"; list newest first — icon by kind (`security` ShieldAlert, `game` Gamepad2, `changes` Sparkles), title, body, relative time ("2 min ago"), unread dot; clicking an item marks it read; empty state "You're all caught up."
- `searchIndex.ts`: `type SearchEntry = { id: string; label: string; group: "Pages" | "Heroes" | "Settings"; path: string; keywords?: string[] }`; `buildIndex(): SearchEntry[]` — Pages (every NAV item + Settings), Heroes (Aria → `/party?hero=aria`, Kael, Lyra), Settings sections (Appearance, Account, Sign-in, Game connection, Notifications → `/settings/<section>`). Items, gear, maps and saved spots join the index in stage 2 (from the game). `search(index, query): SearchEntry[]` — case-insensitive substring on label and keywords; label-prefix matches first, then the rest; alphabetical within each; max 20.
- **SearchPalette** (dialog): input "Search for anything — a hero, an item, a map…", results grouped; ↑/↓ move the highlight, Enter opens, Escape closes; opened by the top-bar box and ⌘K/Ctrl+K; when the query matches nothing: "Nothing found. Items, gear and maps appear here once the game is connected."

- [ ] **Step 1: Write the failing tests**

```tsx
test("the bell shows the unread count and mark all clears it", async () => {
  mockNotifications([{ id: 1, kind: "security", title: "Failed sign-in", body: "…", createdAt: nowIso(), read: false }], 1);
  renderShellAt("/");
  expect(within(bell()).getByText("1")).toBeVisible();
  await click(bell()); await click(screen.getByRole("button", { name: "Mark all as read" }));
  expect(lastRequest("/api/notifications/read-all")).toBeDefined();
});
test("⌘K opens search and the keyboard picks a result", async () => {
  const { router } = renderShellAt("/");
  await keyboard("{Meta>}k{/Meta}");
  await type(screen.getByRole("combobox"), "gea");
  await keyboard("{ArrowDown}{Enter}");
  expect(router.state.location.pathname).toBe("/gear");
});
test("search ranks prefix matches first", () => {
  expect(search(buildIndex(), "a").map(e => e.label).slice(0, 3)).toEqual(["Account", "Admin", "Appearance"]);
});
```

- [ ] **Step 2: Run — FAIL.**  - [ ] **Step 3: Implement.**  - [ ] **Step 4: PASS.**
- [ ] **Step 5: Commit** — "Add notifications and search to the dashboard".

---

### Task 10: Settings and Admin pages

**Files:**
- Create: `web/src/pages/{SettingsPage,AdminPage}.tsx` (+ CSS), `web/test/settings-admin.test.tsx`

**Interfaces:**
- **SettingsPage** (`/settings`, `/settings/:section`): `PageHeader` "SETTINGS"; a section list on the left (Appearance, Account, Sign-in, Game connection, Notifications) and the chosen section on the right; changes save immediately with a small "Saved" confirmation, except passwords/answers which have their own Save buttons.
  - Appearance: `Segmented` Light / Dark / Follow my Mac; Colour theme: Amethyst (selected) + "More themes coming later"; Sidebar: Expanded / Icons only.
  - Account: avatar (upload, remove; initials fallback), Display name, Username (read-only); "Change password" (current, new, confirm); "Change security answers" (current password + the three questions).
  - Sign-in: "Keep me signed in lasts" `Segmented` 7 days / 30 days / 90 days.
  - Game connection: Port (number, 1024–65535, default 47821), "Reconnect automatically when the game restarts" `Toggle`; a note "The game connection arrives in the next stage."
  - Notifications: a `Toggle` each for Account security, Game connection, Changes.
- **AdminPage** (`/admin`): `PageHeader` "ADMIN", breadcrumb `Dashboard / Admin`; one centred card with a shield icon, "In development", and "Admin tools will appear here once you decide what they should be." Works whether or not the game is connected.

- [ ] **Step 1: Write the failing tests**

```tsx
test("appearance options save and apply", async () => {
  renderShellAt("/settings/appearance");
  await click(screen.getByRole("radio", { name: "Follow my Mac" }));
  expect(lastRequest("/api/settings").body).toEqual({ appearance: "system" });
});
test("changing answers needs the current password and shows the three questions", async () => {
  renderShellAt("/settings/account");
  expect(screen.getAllByTestId("security-question")).toHaveLength(3);
  mockPost("/api/account/answers", 401, { error: "wrong_password" });
  await fillAnswers("wrong current"); expect(screen.getByText("That password isn't right.")).toBeInTheDocument();
});
test("the port must be a valid number", async () => {
  renderShellAt("/settings/game-connection");
  await replace(screen.getByLabelText("Port"), "80");
  expect(screen.getByText("Use a port from 1024 to 65535.")).toBeInTheDocument();
});
test("admin says in development, with or without the game", () => {
  renderShellAt("/admin", { game: { connected: false, state: "waiting" } });
  expect(screen.getByText("In development")).toBeVisible();
});
```

- [ ] **Step 2: Run — FAIL.**  - [ ] **Step 3: Implement.**  - [ ] **Step 4: PASS.**
- [ ] **Step 5: Commit** — "Add the Settings and Admin pages".

---

### Task 11: Overview and Debug pages — waiting for the game

**Files:**
- Create: `web/src/pages/{OverviewPage,PartyPage,InventoryPage,GearPage,LocationPage,WaitingForGame}.tsx` (+ CSS), `web/test/debug-pages.test.tsx`

**Interfaces:** Consumes `useGameStatus()`.
- **WaitingForGame**: a card with a softly pulsing gem, Cinzel heading "✦ The game isn't running ✦", "Start it from Godot and this page will connect on its own.", and a small status line "Waiting for the game · checking every few seconds". It re-renders the moment `useGameStatus()` reports `connected` (stage 2).
- **OverviewPage** (`/`): `PageHeader` "OVERVIEW" (mini-stats on the right show "—" while waiting); the Game Status card with `Pill` "○ Waiting for the game" (warn tone) and the WaitingForGame message; the Quick Actions card with every action from the spec shown **disabled**, each with the tooltip "Available once the game is running"; the stat strip, party summary and debug activity cards shown as empty placeholders that match the mockup's frames ("No data yet").
- **PartyPage / InventoryPage / GearPage / LocationPage**: `PageHeader` with title, breadcrumb `Dashboard / Debug / <Page>` and the status pill on the right ("○ Waiting for the game"); the reminder strip from spec §5.1; then `WaitingForGame`. (Their full tools are built in stage 2.)

- [ ] **Step 1: Write the failing tests**

```tsx
test.each(["/party", "/inventory", "/gear", "/location"])("%s waits for the game", async (path) => {
  renderShellAt(path, { game: { connected: false, state: "waiting" } });
  expect(await screen.findByText("✦ The game isn't running ✦")).toBeVisible();
  expect(screen.getByText("○ Waiting for the game")).toBeVisible();
});
test("overview quick actions are disabled while waiting", async () => {
  renderShellAt("/", { game: { connected: false, state: "waiting" } });
  for (const name of ["Heal party + full resonance", "Unlock all moves", "Max out gold", "Save the game now", "Reset to before debugging"])
    expect(await screen.findByRole("button", { name })).toBeDisabled();
});
```

- [ ] **Step 2: Run — FAIL.**  - [ ] **Step 3: Implement.**  - [ ] **Step 4: PASS.**
- [ ] **Step 5: Visual check** of Overview against `overview-v3.html` / `overview-dark-v1.html` (frames, spacing, typography — content is the waiting state).
- [ ] **Step 6: Commit** — "Add the Overview and Debug pages in their waiting state".

---

### Task 12: End-to-end flows, polish pass and docs

**Files:**
- Create: `e2e/{auth,shell}.spec.ts`, `playwright.config.ts` (if not already), `dashboard/docs/stage1-playtest.md`
- Modify: `dashboard/README.md`, `new-game-project/CLAUDE.md` (Roadmap: a short "Amethyst Dashboard" entry pointing at `dashboard/README.md` and the spec; stage 1 done, stage 2 next)

**Interfaces:** Playwright starts the real server against a temporary database (`AMETHYST_DB` in a temp dir) plus the built web app, Chromium only, viewport 1440×900.

- [ ] **Step 1: Write the end-to-end tests**
  - `auth.spec.ts`: first visit → Create your account → fill (invented answers) → lands on Overview; sign out; five wrong passwords → "Sign-in is paused" with a countdown; (fake the clock or use a test-only env `AMETHYST_LOCK_SECONDS` that the server honours only when `NODE_ENV === "test"`) after it ends → sign in → Overview; forgot password with one wrong answer → "Password reset is locked"; after it ends → right answers → new password works.
  - `shell.spec.ts`: ⌘K → type "loc" → Enter → Location page shows "The game isn't running"; theme button → `html[data-theme="dark"]`; reload → still dark with no light flash (check `data-theme` on first paint via `page.addInitScript` observer); sidebar collapse persists across reload; Tab from the top of the page reaches every top-bar button in order with a visible focus ring.
- [ ] **Step 2: `npx playwright install chromium` once, then `npm run build && npm run e2e` — make them pass.** The Playwright web server runs with `NODE_ENV=test AMETHYST_LOCK_SECONDS=3`.
- [ ] **Step 3: Polish pass.** At 1440 px and 1280 px, light and dark, walk every screen against its mockup and fix anything off (alignment, spacing, contrast, hover/focus/disabled states, scrollbars). Screenshots from Playwright for each screen in both themes go to `dashboard/test-results/` (not committed); list what you fixed in the report.
- [ ] **Step 4: Write `dashboard/docs/stage1-playtest.md`** — the user's checklist in plain steps: start the dashboard; create your account (with your real answers — only here); sign out and back in with and without "Keep me signed in"; trip the 5-wrong-passwords pause and watch it unlock; forgot password with a deliberate wrong answer, then the right ones; theme switch, Follow my Mac, colour theme menu, full screen, sidebar collapse and filter; ⌘K search; notifications after a failed sign-in; Settings sections; Admin page; each Debug page's waiting message.
- [ ] **Step 5: Full verification** — `npm run typecheck && npm test && npm run build && npm run e2e`, all green, no warnings.
- [ ] **Step 6: Commit** — "Test the dashboard end to end and add its play-test checklist".
