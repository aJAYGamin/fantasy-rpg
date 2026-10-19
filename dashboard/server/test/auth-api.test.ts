import type { FastifyInstance } from "fastify";
import { beforeEach, expect, test, vi } from "vitest";
import { countAccounts } from "../src/auth/accounts.js";
import { isLocked, readLock, writeLock } from "../src/auth/locks.js";
import { verifyPassword } from "../src/auth/passwords.js";
import {
  OWNER_ANSWERS,
  OWNER_PASSWORD,
  cookieOf,
  dbOf,
  fakeClock,
  forgotBody,
  get,
  ownerApp,
  post,
  setupBody,
  signedIn,
  signin,
  signinCookie,
  testApp,
  tmpFile,
} from "./helpers.js";

// Wraps the real verifyPassword so a test can watch its calls, or run code while a check is in flight.
vi.mock("../src/auth/passwords.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../src/auth/passwords.js")>();
  return { ...actual, verifyPassword: vi.fn(actual.verifyPassword) };
});
const realVerify = (await vi.importActual<typeof import("../src/auth/passwords.js")>("../src/auth/passwords.js"))
  .verifyPassword;

beforeEach(() => {
  vi.mocked(verifyPassword).mockReset();
});

const DAY = 86_400_000;
const WRONG = "nope-nope-nope";

type Row = Record<string, unknown>;
const rows = (app: FastifyInstance, sql: string): Row[] => dbOf(app).prepare(sql).all() as Row[];
const notifications = (app: FastifyInstance) => rows(app, "SELECT kind, title, body FROM notifications ORDER BY id");
const lockRows = (app: FastifyInstance) => rows(app, "SELECT username, kind, failures FROM auth_locks");
const sessionCount = (app: FastifyInstance) => rows(app, "SELECT 1 FROM sessions").length;
// A database rule that makes saving one particular notification fail, to see what else is left behind.
const refuseNotification = (title: string) =>
  `CREATE TRIGGER refuse BEFORE INSERT ON notifications WHEN NEW.title = '${title}'
   BEGIN SELECT RAISE(ABORT, 'refused'); END`;

// ---- first-run setup ------------------------------------------------------------------------------

test("first run: setup creates the owner and signs them in", async () => {
  const app = await testApp();
  expect((await get(app, "/api/auth/state")).json()).toEqual({ setupRequired: true, user: null });
  const res = await post(app, "/api/auth/setup", setupBody());
  expect(res.statusCode).toBe(201);
  const owner = { id: 1, username: "owner", displayName: "Owner", role: "owner", hasAvatar: false };
  expect(res.json()).toEqual(owner);
  const session = res.cookies.find((c) => c.name === "amethyst_session");
  expect(session?.httpOnly).toBe(true);
  expect(session?.maxAge).toBeUndefined();
  const cookie = cookieOf(res);
  expect((await get(app, "/api/auth/state", cookie)).json()).toEqual({ setupRequired: false, user: owner });
  expect((await get(app, "/api/game/status", cookie)).statusCode).toBe(200);
});

test("setup stores only hashes, never the password or the answers", async () => {
  const app = await testApp();
  await post(app, "/api/auth/setup", setupBody());
  const [row] = rows(app, "SELECT password_hash, answer_hashes FROM accounts");
  expect(row.password_hash).toMatch(/^\$argon2id\$/);
  expect(row.password_hash).not.toContain(OWNER_PASSWORD);
  const answerHashes = JSON.parse(row.answer_hashes as string) as string[];
  expect(answerHashes).toHaveLength(3);
  for (const hash of answerHashes) expect(hash).toMatch(/^\$argon2id\$/);
  expect(String(row.answer_hashes).toLowerCase()).not.toContain("lanternfall");
});

test("setup trims the typed username and display name", async () => {
  const app = await testApp();
  const res = await post(app, "/api/auth/setup", setupBody({ username: "  owner  ", displayName: "  The Owner " }));
  expect(res.statusCode).toBe(201);
  expect(res.json()).toMatchObject({ username: "owner", displayName: "The Owner" });
});

test("setup can never run twice", async () => {
  const app = await testApp();
  await post(app, "/api/auth/setup", setupBody());
  const again = await post(app, "/api/auth/setup", { ...setupBody(), username: "intruder" });
  expect(again.statusCode).toBe(409);
  expect(again.json()).toEqual({ error: "already_set_up", message: "An account already exists." });
  expect(again.cookies).toEqual([]);
  expect(countAccounts(dbOf(app))).toBe(1);
});

test("two setups racing each other produce exactly one account", async () => {
  const app = await testApp();
  const [a, b] = await Promise.all([
    post(app, "/api/auth/setup", setupBody({ username: "first" })),
    post(app, "/api/auth/setup", setupBody({ username: "second" })),
  ]);
  expect([a.statusCode, b.statusCode].sort()).toEqual([201, 409]);
  expect(countAccounts(dbOf(app))).toBe(1);
  expect(sessionCount(app)).toBe(1);
});

test.each([
  ["a password of 9 characters", { password: "123456789" }, "too_short"],
  ["a 2 character username", { username: "ab" }, "invalid_username"],
  ["a 33 character username", { username: "a".repeat(33) }, "invalid_username"],
  ["a username with a space", { username: "the owner" }, "invalid_username"],
  ["a username with a slash", { username: "own/er" }, "invalid_username"],
  ["a username with an accent", { username: "ówner" }, "invalid_username"],
  ["a blank display name", { displayName: "   " }, "invalid_display_name"],
  ["a 41 character display name", { displayName: "d".repeat(41) }, "invalid_display_name"],
  ["a blank answer", { answers: ["Lanternfall", "   ", "Dragonbridge"] }, "missing_answer"],
  ["an answer of only a no-break space", { answers: ["Lanternfall", "Port Quillon", " "] }, "missing_answer"],
])("setup refuses %s", async (_name, change, code) => {
  const app = await testApp();
  const res = await post(app, "/api/auth/setup", setupBody(change));
  expect(res.statusCode).toBe(400);
  expect(res.json().error).toBe(code);
  expect(countAccounts(dbOf(app))).toBe(0);
});

test("the password minimum counts characters, not bytes", async () => {
  const app = await testApp();
  const res = await post(app, "/api/auth/setup", setupBody({ password: "\u{1F642}".repeat(10) }));
  expect(res.statusCode).toBe(201);
});

test("the username may use letters, digits, underscore, dot and dash", async () => {
  const app = await testApp();
  const res = await post(app, "/api/auth/setup", setupBody({ username: "Mr_Owner-2.0" }));
  expect(res.statusCode).toBe(201);
});

test("the three security questions are served", async () => {
  const app = await testApp();
  const res = await get(app, "/api/auth/questions");
  expect(res.json()).toEqual({
    questions: ["What is my favorite holiday?", "Which city was I born in?", "What is my favorite board game?"],
  });
});

// ---- request shape ----------------------------------------------------------------------------------

test("mutating requests without the header are refused", async () => {
  const app = await testApp();
  const res = await app.inject({ method: "POST", url: "/api/auth/setup", payload: setupBody() });
  expect(res.statusCode).toBe(403);
  expect(res.json()).toEqual({ error: "bad_request_header", message: "Missing request header." });
  expect(countAccounts(dbOf(app))).toBe(0);
});

test("the header must say 1, and every mutating method needs it", async () => {
  const app = await ownerApp();
  const wrong = await app.inject({
    method: "POST",
    url: "/api/auth/signin",
    payload: { username: "owner", password: OWNER_PASSWORD },
    headers: { "x-amethyst-request": "0" },
  });
  expect(wrong.statusCode).toBe(403);
  for (const method of ["POST", "PUT", "PATCH", "DELETE"] as const) {
    const res = await app.inject({ method, url: "/api/anything" });
    expect(res.statusCode, method).toBe(403);
    expect(res.json().error, method).toBe("bad_request_header");
  }
  expect(sessionCount(app)).toBe(0);
});

test("reading needs no header", async () => {
  const app = await testApp();
  expect((await app.inject({ method: "GET", url: "/api/auth/state" })).statusCode).toBe(200);
  expect((await app.inject({ method: "GET", url: "/api/health" })).statusCode).toBe(200);
});

test.each([
  ["setup with a numeric password", "/api/auth/setup", setupBody({ password: 1234567890 })],
  ["setup with two answers", "/api/auth/setup", setupBody({ answers: ["a", "b"] })],
  ["setup with a non-string answer", "/api/auth/setup", setupBody({ answers: ["a", "b", 3] })],
  ["setup with no body fields", "/api/auth/setup", {}],
  ["signin with a numeric username", "/api/auth/signin", { username: 5, password: "x" }],
  ["signin with no password", "/api/auth/signin", { username: "owner" }],
  ["signin with keepSignedIn as a string", "/api/auth/signin", { username: "owner", password: "x", keepSignedIn: "yes" }],
  ["forgot with answers that are not a list", "/api/auth/forgot", forgotBody({ answers: "Lanternfall" })],
  ["forgot with two answers", "/api/auth/forgot", forgotBody({ answers: ["a", "b"] })],
  ["forgot with a missing new password", "/api/auth/forgot", { username: "owner", answers: OWNER_ANSWERS }],
])("%s is a bad request, not an attempt", async (_name, url, body) => {
  const app = await ownerApp();
  const res = await post(app, url, body);
  expect(res.statusCode).toBe(400);
  expect(res.json().error).toBe("bad_request");
  expect(lockRows(app)).toEqual([]);
});

test("a body that is not valid JSON is a plain bad request that does not echo the parser's complaint", async () => {
  const app = await testApp();
  const res = await app.inject({
    method: "POST",
    url: "/api/auth/signin",
    payload: '{"username": "owner", "passw',
    headers: { "x-amethyst-request": "1", "content-type": "application/json" },
  });
  expect(res.statusCode).toBe(400);
  expect(res.json()).toEqual({ error: "bad_request", message: "That request couldn't be read." });
});

test("every error body has a code and a short sentence", async () => {
  const app = await ownerApp();
  const cookie = await signinCookie(app);
  const responses = {
    wrong_password: await signin(app, WRONG),
    wrong_answer: await post(app, "/api/auth/forgot", forgotBody({ answers: ["x", "y", "z"] })),
    locked: await post(app, "/api/auth/forgot", forgotBody()),
    already_set_up: await post(app, "/api/auth/setup", setupBody()),
    signed_out: await get(app, "/api/game/status"),
    bad_request_header: await app.inject({ method: "POST", url: "/api/auth/signout" }),
    not_found: await get(app, "/api/nope", cookie),
  };
  const messages = {
    wrong_password: "That password isn't right.",
    wrong_answer: "One or more answers didn't match.",
    locked: "Too many tries. Try again when the timer runs out.",
    already_set_up: "An account already exists.",
    signed_out: "Please sign in.",
    bad_request_header: "Missing request header.",
    not_found: "Not found",
  };
  for (const [code, res] of Object.entries(responses)) {
    expect(res.json(), code).toMatchObject({ error: code, message: messages[code as keyof typeof messages] });
  }
});

// ---- sign-in and locks -----------------------------------------------------------------------------

test("signing in returns the user and nothing secret", async () => {
  const app = await ownerApp();
  const res = await signin(app, OWNER_PASSWORD);
  expect(res.statusCode).toBe(200);
  expect(res.json()).toEqual({ id: 1, username: "owner", displayName: "Owner", role: "owner", hasAvatar: false });
  expect(cookieOf(res)).toMatch(/^amethyst_session=/);
});

test("the username is matched without regard to case or surrounding spaces", async () => {
  const app = await ownerApp();
  expect((await signin(app, OWNER_PASSWORD, "  OWNER ")).statusCode).toBe(200);
});

test("wrong passwords count down and then lock", async () => {
  const app = await ownerApp();
  for (let i = 4; i >= 1; i--) {
    const res = await signin(app, WRONG);
    expect(res.statusCode).toBe(401);
    expect(res.json()).toMatchObject({ error: "wrong_password", triesLeft: i });
  }
  const fifth = await signin(app, WRONG);
  expect(fifth.statusCode).toBe(423);
  expect(fifth.json().error).toBe("locked");
  const right = await signin(app, OWNER_PASSWORD); // even the right one, while locked
  expect(right.statusCode).toBe(423);
  expect(right.cookies).toEqual([]);
});

test("a lock lasts the configured time and tells the client when it ends", async () => {
  const clock = fakeClock("2026-10-18T12:00:00Z");
  const app = await ownerApp({ clock, config: { lockMs: 90_000 } });
  for (let i = 0; i < 4; i++) await signin(app, WRONG);
  const locking = await signin(app, WRONG);
  expect(locking.json().lockedUntil).toBe("2026-10-18T12:01:30.000Z");
  clock.advance(30_000);
  expect((await signin(app, OWNER_PASSWORD)).json().lockedUntil).toBe("2026-10-18T12:01:30.000Z");
});

test("a lock survives a server restart", async () => {
  const file = tmpFile();
  let app = await ownerApp({ dbPath: file });
  for (let i = 0; i < 5; i++) await signin(app, WRONG);
  await app.close();
  app = await testApp({ dbPath: file }); // same database, new process
  expect((await signin(app, OWNER_PASSWORD)).statusCode).toBe(423);
});

test("the lock lifts after five minutes", async () => {
  const clock = fakeClock("2026-10-18T12:00:00Z");
  const app = await ownerApp({ clock });
  for (let i = 0; i < 5; i++) await signin(app, WRONG);
  clock.advance(5 * 60_000 - 1);
  expect((await signin(app, OWNER_PASSWORD)).statusCode).toBe(423);
  clock.advance(1);
  expect((await signin(app, OWNER_PASSWORD)).statusCode).toBe(200);
});

test("after a lock lifts the count starts again from five tries", async () => {
  const clock = fakeClock("2026-10-18T12:00:00Z");
  const app = await ownerApp({ clock });
  for (let i = 0; i < 5; i++) await signin(app, WRONG);
  clock.advance(5 * 60_000);
  expect((await signin(app, WRONG)).json()).toMatchObject({ error: "wrong_password", triesLeft: 4 });
});

test("a good sign-in clears the failures so far", async () => {
  const app = await ownerApp();
  for (let i = 0; i < 3; i++) await signin(app, WRONG);
  expect((await signin(app, OWNER_PASSWORD)).statusCode).toBe(200);
  expect(lockRows(app)).toEqual([]);
  expect((await signin(app, WRONG)).json().triesLeft).toBe(4);
});

test("an unknown username gets the same answer shape as a real one", async () => {
  const app = await ownerApp();
  expect((await signin(app, "whatever-pass", "nobody")).json()).toMatchObject({ error: "wrong_password", triesLeft: 4 });
  const forgot = await post(app, "/api/auth/forgot", { ...forgotBody(), username: "nobody" });
  expect(forgot.statusCode).toBe(401);
  expect(forgot.json().error).toBe("wrong_answer");
  expect(forgot.json().lockedUntil).toBeDefined();
});

test("an unknown username counts down and locks exactly like a real one", async () => {
  const app = await ownerApp();
  const codes: number[] = [];
  const triesLeft: unknown[] = [];
  for (let i = 0; i < 6; i++) {
    const res = await signin(app, "whatever-pass", "nobody");
    codes.push(res.statusCode);
    triesLeft.push(res.json().triesLeft);
  }
  expect(codes).toEqual([401, 401, 401, 401, 423, 423]);
  expect(triesLeft.slice(0, 4)).toEqual([4, 3, 2, 1]);
  // The real account is a different lock key and is untouched.
  expect((await signin(app, OWNER_PASSWORD)).statusCode).toBe(200);
});

test("locks are per username, ignoring case", async () => {
  const app = await ownerApp();
  await signin(app, WRONG, "OWNER");
  expect((await signin(app, WRONG, "owner")).json().triesLeft).toBe(3);
  expect(lockRows(app)).toHaveLength(1);
});

test("an unknown username runs a real argon2 check, always against the same throwaway hash", async () => {
  const app = await ownerApp();
  const [ownerHash] = rows(app, "SELECT password_hash FROM accounts").map((r) => r.password_hash);
  await signin(app, "whatever-pass", "nobody");
  await signin(app, "whatever-pass", "other-nobody");
  const calls = vi.mocked(verifyPassword).mock.calls;
  expect(calls).toHaveLength(2);
  expect(calls[0][0]).toMatch(/^\$argon2id\$v=19\$/);
  expect(calls[0][1]).toBe("whatever-pass");
  expect(calls[0][0]).not.toBe(ownerHash);
  expect(calls[1][0]).toBe(calls[0][0]);
});

test("a username that breaks the rules is checked the same way as an unknown one", async () => {
  const app = await ownerApp();
  await signin(app, "whatever-pass", "has spaces in it");
  expect(vi.mocked(verifyPassword).mock.calls[0][0]).toMatch(/^\$argon2id\$/);
});

test("the lock key is the typed username, trimmed and cut to 32 characters", async () => {
  const app = await ownerApp();
  const res = await signin(app, "whatever-pass", "x".repeat(5000));
  expect(res.statusCode).toBe(401);
  expect(res.json()).toMatchObject({ error: "wrong_password", triesLeft: 4 });
  expect(lockRows(app).map((r) => r.username)).toEqual(["x".repeat(32)]);
  await signin(app, "whatever-pass", `   ${"y".repeat(40)}   `);
  expect(lockRows(app).map((r) => r.username)).toEqual(["x".repeat(32), "y".repeat(32)]);
});

test("cutting the lock key never splits a character", async () => {
  const app = await ownerApp();
  await signin(app, "whatever-pass", "\u{1F600}".repeat(40));
  const [key] = lockRows(app).map((r) => r.username as string);
  expect([...key]).toHaveLength(32);
  expect(key).not.toContain("�");
});

test("a typed name that only starts like a real 32 character username does not sign in as it", async () => {
  const app = await ownerApp();
  const name = "a".repeat(32);
  dbOf(app).prepare("UPDATE accounts SET username = ?").run(name);
  const tooLong = await signin(app, OWNER_PASSWORD, `${name}b`);
  expect(tooLong.statusCode).toBe(401);
  expect(tooLong.cookies).toEqual([]);
  expect((await signin(app, OWNER_PASSWORD, name)).statusCode).toBe(200);
});

test("ten wrong sign-ins at once lock the account after exactly five", async () => {
  const app = await ownerApp();
  const results = await Promise.all(Array.from({ length: 10 }, () => signin(app, WRONG)));
  const codes = results.map((r) => r.statusCode);
  // Four countdown answers, then the fifth wrong one locks (423) and every later one is turned away (423).
  expect(codes.filter((c) => c === 401)).toHaveLength(4);
  expect(codes.filter((c) => c === 423)).toHaveLength(6);
  const titles = notifications(app).map((n) => n.title);
  expect(titles.filter((t) => t === "Failed sign-in")).toHaveLength(5);
  expect(titles.filter((t) => t === "Sign-in locked")).toHaveLength(1);
  expect(titles).toHaveLength(6);
  expect(isLocked(readLock(dbOf(app), "owner", "signin"), new Date())).toBe(true);
  expect(lockRows(app)).toEqual([{ username: "owner", kind: "signin", failures: 0 }]);
  expect((await signin(app, OWNER_PASSWORD)).statusCode).toBe(423);
});

test("ten wrong sign-ins at once for an unknown name lock it after exactly five too", async () => {
  const app = await ownerApp();
  const results = await Promise.all(Array.from({ length: 10 }, () => signin(app, WRONG, "nobody")));
  const codes = results.map((r) => r.statusCode);
  expect(codes.filter((c) => c === 401)).toHaveLength(4);
  expect(codes.filter((c) => c === 423)).toHaveLength(6);
  expect(isLocked(readLock(dbOf(app), "nobody", "signin"), new Date())).toBe(true);
  expect(notifications(app)).toEqual([]);
});

test("a lock that lands while the password is being checked refuses even the right password", async () => {
  const app = await ownerApp();
  vi.mocked(verifyPassword).mockImplementationOnce(async (hashed, password) => {
    writeLock(dbOf(app), "owner", "signin", { failures: 0, lockedUntil: new Date(Date.now() + 60_000) });
    return realVerify(hashed, password);
  });
  const res = await signin(app, OWNER_PASSWORD);
  expect(res.statusCode).toBe(423);
  expect(res.cookies).toEqual([]);
  expect(sessionCount(app)).toBe(0);
});

test("a password changed while it was being checked does not sign anyone in", async () => {
  const app = await ownerApp();
  vi.mocked(verifyPassword).mockImplementationOnce(async (hashed, password) => {
    const ok = await realVerify(hashed, password);
    dbOf(app).prepare("UPDATE accounts SET password_hash = ?").run("$argon2id$v=19$changed-in-the-meantime");
    return ok;
  });
  const res = await signin(app, OWNER_PASSWORD);
  expect(res.statusCode).toBe(401);
  expect(res.cookies).toEqual([]);
  expect(sessionCount(app)).toBe(0);
});

test("a stored password hash that cannot be read is a server error, not a wrong password", async () => {
  const app = await ownerApp();
  dbOf(app).prepare("UPDATE accounts SET password_hash = ?").run("not-a-hash");
  for (let i = 0; i < 6; i++) {
    const res = await signin(app, OWNER_PASSWORD);
    expect(res.statusCode).toBe(500);
    expect(res.json()).toEqual({ error: "server_error", message: "Something went wrong on the server." });
  }
  expect(lockRows(app)).toEqual([]);
  expect(notifications(app)).toEqual([]);
  expect(sessionCount(app)).toBe(0);
});

// ---- failures are saved all together ----------------------------------------------------------------

test("a wrong password whose notification cannot be saved does not count either", async () => {
  const app = await ownerApp();
  dbOf(app).exec(refuseNotification("Failed sign-in"));
  const res = await signin(app, WRONG);
  expect(res.statusCode).toBe(500);
  expect(lockRows(app)).toEqual([]);
  expect(notifications(app)).toEqual([]);
});

test("a locking wrong password whose second notification cannot be saved leaves the count at four", async () => {
  const app = await ownerApp();
  for (let i = 0; i < 4; i++) await signin(app, WRONG);
  dbOf(app).exec(refuseNotification("Sign-in locked"));
  const res = await signin(app, WRONG);
  expect(res.statusCode).toBe(500);
  expect(lockRows(app)).toEqual([{ username: "owner", kind: "signin", failures: 4 }]);
  expect(notifications(app).map((n) => n.title)).toEqual(Array(4).fill("Failed sign-in"));
});

test("a wrong answer whose notification cannot be saved does not lock the reset", async () => {
  const app = await ownerApp();
  dbOf(app).exec(refuseNotification("Password reset locked"));
  const res = await post(app, "/api/auth/forgot", forgotBody({ answers: ["x", "y", "z"] }));
  expect(res.statusCode).toBe(500);
  expect(lockRows(app)).toEqual([]);
  expect(notifications(app)).toEqual([]);
});

// ---- notifications ----------------------------------------------------------------------------------

test("a wrong password and then a lock leave security notifications for the account", async () => {
  const app = await ownerApp();
  await signin(app, WRONG);
  expect(notifications(app)).toMatchObject([{ kind: "security", title: "Failed sign-in" }]);
  for (let i = 0; i < 4; i++) await signin(app, WRONG);
  const titles = notifications(app).map((n) => n.title);
  expect(titles).toEqual([...Array(5).fill("Failed sign-in"), "Sign-in locked"]);
  for (const n of notifications(app)) {
    expect(n.kind).toBe("security");
    expect(String(n.body)).not.toContain(WRONG);
  }
});

test("failed attempts on unknown names leave no notification", async () => {
  const app = await ownerApp();
  for (let i = 0; i < 5; i++) await signin(app, WRONG, "nobody");
  expect(notifications(app)).toEqual([]);
});

// ---- sessions and cookies -------------------------------------------------------------------------

test("keep me signed in sets a lasting cookie, otherwise a session cookie", async () => {
  const app = await ownerApp();
  expect((await signin(app, OWNER_PASSWORD, "owner", true)).cookies[0].maxAge).toBe(30 * 86400);
  expect((await signin(app, OWNER_PASSWORD, "owner", false)).cookies[0].maxAge).toBeUndefined();
});

test("the cookie lasts as many days as the account's saved setting", async () => {
  const app = await ownerApp();
  const save = (json: string) =>
    dbOf(app).prepare("INSERT OR REPLACE INTO settings (account_id, json) VALUES (1, ?)").run(json);
  save('{"keepSignedInDays":90}');
  expect((await signin(app, OWNER_PASSWORD, "owner", true)).cookies[0].maxAge).toBe(90 * 86400);
  for (const unusable of ['{"keepSignedInDays":3}', '{"keepSignedInDays":"90"}', "{}", "null", "not json"]) {
    save(unusable);
    expect((await signin(app, OWNER_PASSWORD, "owner", true)).cookies[0].maxAge, unusable).toBe(30 * 86400);
  }
});

test("the session cookie is HttpOnly, SameSite=Lax, site-wide, and Secure only when configured", async () => {
  const plain = await ownerApp();
  const header = String((await signin(plain, OWNER_PASSWORD, "owner", true)).headers["set-cookie"]);
  expect(header).toMatch(/^amethyst_session=/);
  expect(header).toMatch(/; Path=\//);
  expect(header).toMatch(/; HttpOnly/);
  expect(header).toMatch(/; SameSite=Lax/);
  expect(header).toMatch(/; Max-Age=2592000/);
  expect(header).not.toMatch(/Secure/i);

  const session = String((await signin(plain, OWNER_PASSWORD)).headers["set-cookie"]);
  expect(session).not.toMatch(/Max-Age|Expires/i);

  const secure = await ownerApp({ config: { secureCookies: true } });
  expect(String((await signin(secure, OWNER_PASSWORD)).headers["set-cookie"])).toMatch(/; Secure/);
  expect(String((await post(secure, "/api/auth/signout")).headers["set-cookie"])).toMatch(/; Secure/);
});

test("a lasting session ends after the saved number of days", async () => {
  const clock = fakeClock("2026-10-18T12:00:00Z");
  const app = await ownerApp({ clock });
  const cookie = cookieOf(await signin(app, OWNER_PASSWORD, "owner", true));
  clock.advance(30 * DAY - 1);
  expect((await get(app, "/api/game/status", cookie)).statusCode).toBe(200);
  clock.advance(1);
  expect((await get(app, "/api/game/status", cookie)).statusCode).toBe(401);
});

test("a browser-session sign-in ends after twelve hours on the server", async () => {
  const clock = fakeClock("2026-10-18T12:00:00Z");
  const app = await ownerApp({ clock });
  const cookie = cookieOf(await signin(app, OWNER_PASSWORD));
  clock.advance(12 * 3_600_000 - 1);
  expect((await get(app, "/api/game/status", cookie)).statusCode).toBe(200);
  clock.advance(1);
  expect((await get(app, "/api/game/status", cookie)).statusCode).toBe(401);
});

test("protected routes need a session", async () => {
  const app = await ownerApp();
  const none = await get(app, "/api/game/status");
  expect(none.statusCode).toBe(401);
  expect(none.json()).toEqual({ error: "signed_out", message: "Please sign in." });
  expect((await get(app, "/api/game/status", "amethyst_session=not-a-real-token")).statusCode).toBe(401);
  expect((await get(app, "/api/game/status", await signinCookie(app))).statusCode).toBe(200);
});

test("the game status is a stub that says waiting", async () => {
  const { app, cookie } = await signedIn();
  expect((await get(app, "/api/game/status", cookie)).json()).toEqual({ connected: false, state: "waiting" });
});

test("signing out ends the session and clears the cookie", async () => {
  const { app, cookie } = await signedIn();
  const other = await signinCookie(app);
  const res = await post(app, "/api/auth/signout", {}, cookie);
  expect(res.statusCode).toBe(204);
  expect(res.body).toBe("");
  // The cleared cookie has to match the one that was set (same path) and be told to expire at once.
  expect(res.cookies.find((c) => c.name === "amethyst_session")).toMatchObject({
    value: "",
    path: "/",
    maxAge: 0,
    httpOnly: true,
  });
  expect(String(res.headers["set-cookie"])).toMatch(/Path=\/;/);
  expect(String(res.headers["set-cookie"])).toMatch(/Max-Age=0/);
  expect((await get(app, "/api/game/status", cookie)).statusCode).toBe(401);
  expect((await get(app, "/api/game/status", other)).statusCode).toBe(200);
  expect((await get(app, "/api/auth/state", cookie)).json().user).toBeNull();
});

test("signing out with no session is harmless", async () => {
  const app = await ownerApp();
  expect((await post(app, "/api/auth/signout")).statusCode).toBe(204);
});

// ---- forgot password --------------------------------------------------------------------------------

test("forgot password: one wrong answer locks reset, right answers change the password", async () => {
  const app = await ownerApp();
  const bad = await post(app, "/api/auth/forgot", { username: "owner", answers: ["x", "y", "z"], newPassword: "a brand new password" });
  expect(bad.statusCode).toBe(401);
  expect(bad.json().lockedUntil).toBeDefined();
  expect((await post(app, "/api/auth/forgot", forgotBody())).statusCode).toBe(423);
});

test.each([0, 1, 2])("a wrong answer in slot %i alone locks reset", async (slot) => {
  const app = await ownerApp();
  const answers = [...OWNER_ANSWERS];
  answers[slot] = "not it";
  const res = await post(app, "/api/auth/forgot", forgotBody({ answers }));
  expect(res.statusCode).toBe(401);
  expect(res.json()).toMatchObject({ error: "wrong_answer" });
  expect((await signin(app, OWNER_PASSWORD)).statusCode).toBe(200); // the password is untouched
  expect((await post(app, "/api/auth/forgot", forgotBody())).statusCode).toBe(423);
});

test("right answers change the password, end every session and clear the reset lock", async () => {
  const clock = fakeClock("2026-10-18T12:00:00Z");
  const app = await ownerApp({ clock });
  const open = await signinCookie(app);
  await post(app, "/api/auth/forgot", forgotBody({ answers: ["x", "y", "z"] }));
  clock.advance(5 * 60_000);

  const res = await post(app, "/api/auth/forgot", forgotBody({ answers: ["  LANTERNFALL ", "port   quillon", "DragonBridge"] }));
  expect(res.statusCode).toBe(204);
  expect(res.body).toBe("");
  expect(lockRows(app).filter((r) => r.kind === "reset")).toEqual([]);
  expect(notifications(app).map((n) => n.title)).toEqual(["Password reset locked", "Password changed"]);
  expect((await get(app, "/api/game/status", open)).statusCode).toBe(401);
  expect((await signin(app, OWNER_PASSWORD)).statusCode).toBe(401);
  expect((await signin(app, "a brand new password")).statusCode).toBe(200);
});

test("a wrong answer leaves a notification for a real account", async () => {
  const app = await ownerApp();
  await post(app, "/api/auth/forgot", forgotBody({ answers: ["x", "y", "z"] }));
  expect(notifications(app)).toMatchObject([{ kind: "security", title: "Password reset locked" }]);
});

test("a too-short new password is refused before any answer is checked and sets no lock", async () => {
  const app = await ownerApp();
  const res = await post(app, "/api/auth/forgot", forgotBody({ newPassword: "short", answers: ["x", "y", "z"] }));
  expect(res.statusCode).toBe(400);
  expect(res.json().error).toBe("too_short");
  expect(lockRows(app)).toEqual([]);
  expect(vi.mocked(verifyPassword)).not.toHaveBeenCalled();
});

test("blank answers never reset a password", async () => {
  const app = await ownerApp();
  const res = await post(app, "/api/auth/forgot", forgotBody({ answers: ["", " ", "\t"] }));
  expect(res.statusCode).toBe(401);
  expect(res.json().error).toBe("wrong_answer");
});

test("a reset lock lifts after five minutes", async () => {
  const clock = fakeClock("2026-10-18T12:00:00Z");
  const app = await ownerApp({ clock });
  await post(app, "/api/auth/forgot", forgotBody({ answers: ["x", "y", "z"] }));
  clock.advance(5 * 60_000 - 1);
  expect((await post(app, "/api/auth/forgot", forgotBody())).statusCode).toBe(423);
  clock.advance(1);
  expect((await post(app, "/api/auth/forgot", forgotBody())).statusCode).toBe(204);
});

test("a reset lock survives a server restart", async () => {
  const file = tmpFile();
  let app = await ownerApp({ dbPath: file });
  await post(app, "/api/auth/forgot", forgotBody({ answers: ["x", "y", "z"] }));
  await app.close();
  app = await testApp({ dbPath: file });
  expect((await post(app, "/api/auth/forgot", forgotBody())).statusCode).toBe(423);
});

test("a sign-in pause does not stop a reset, and a successful reset lifts it", async () => {
  const app = await ownerApp();
  for (let i = 0; i < 5; i++) await signin(app, WRONG);
  expect((await signin(app, OWNER_PASSWORD)).statusCode).toBe(423);
  expect(lockRows(app).map((r) => r.kind)).toEqual(["signin"]);
  expect((await post(app, "/api/auth/forgot", forgotBody())).statusCode).toBe(204);
  // The person just proved who they are with all three answers: no waiting out the sign-in pause.
  expect(lockRows(app)).toEqual([]);
  expect((await signin(app, "a brand new password")).statusCode).toBe(200);
});

test("a reset lock does not touch the sign-in count", async () => {
  const app = await ownerApp();
  await signin(app, WRONG);
  await post(app, "/api/auth/forgot", forgotBody({ answers: ["x", "y", "z"] }));
  expect(lockRows(app).map((r) => [r.kind, r.failures])).toEqual([
    ["signin", 1],
    ["reset", 0],
  ]);
});

test("the sign-in pause that a reset lifts is the typed name's, whatever its case", async () => {
  const app = await ownerApp();
  for (let i = 0; i < 5; i++) await signin(app, WRONG, "OWNER");
  expect((await signin(app, OWNER_PASSWORD, "owner")).statusCode).toBe(423);
  expect((await post(app, "/api/auth/forgot", forgotBody({ username: " Owner " }))).statusCode).toBe(204);
  expect((await signin(app, "a brand new password", "OWNER")).statusCode).toBe(200);
});

test("a reset whose notification cannot be saved changes nothing, not even the sign-in pause", async () => {
  const app = await ownerApp();
  for (let i = 0; i < 5; i++) await signin(app, WRONG);
  const before = dbOf(app).prepare("SELECT password_hash FROM accounts").get();
  dbOf(app).exec(refuseNotification("Password changed"));
  const res = await post(app, "/api/auth/forgot", forgotBody());
  expect(res.statusCode).toBe(500);
  expect(dbOf(app).prepare("SELECT password_hash FROM accounts").get()).toEqual(before);
  expect(lockRows(app)).toEqual([{ username: "owner", kind: "signin", failures: 0 }]);
});

test("an unknown username locks reset after one try, like a real one", async () => {
  const app = await ownerApp();
  const first = await post(app, "/api/auth/forgot", forgotBody({ username: "nobody" }));
  expect(first.statusCode).toBe(401);
  expect(first.json()).toMatchObject({ error: "wrong_answer" });
  expect(first.json().lockedUntil).toBeDefined();
  expect((await post(app, "/api/auth/forgot", forgotBody({ username: "nobody" }))).statusCode).toBe(423);
  expect(notifications(app)).toEqual([]);
});

test("an unknown username runs real argon2 checks for each answer", async () => {
  const app = await ownerApp();
  await post(app, "/api/auth/forgot", forgotBody({ username: "nobody" }));
  const calls = vi.mocked(verifyPassword).mock.calls;
  expect(calls).toHaveLength(3);
  for (const call of calls) expect(call[0]).toMatch(/^\$argon2id\$v=19\$/);
});

test("the reset lock key is bounded too", async () => {
  const app = await ownerApp();
  await post(app, "/api/auth/forgot", forgotBody({ username: "z".repeat(5000) }));
  expect(lockRows(app)).toEqual([{ username: "z".repeat(32), kind: "reset", failures: 0 }]);
});

test("a stored answer hash that cannot be read is a server error and sets no lock", async () => {
  const app = await ownerApp();
  dbOf(app).prepare("UPDATE accounts SET answer_hashes = ?").run(JSON.stringify(["bad", "bad", "bad"]));
  const res = await post(app, "/api/auth/forgot", forgotBody());
  expect(res.statusCode).toBe(500);
  expect(res.json().error).toBe("server_error");
  expect(lockRows(app)).toEqual([]);
  expect(notifications(app)).toEqual([]);
  expect((await signin(app, OWNER_PASSWORD)).statusCode).toBe(200); // password unchanged
});

test("a lock that lands while the answers are being checked refuses even right answers", async () => {
  const app = await ownerApp();
  vi.mocked(verifyPassword).mockImplementationOnce(async (hashed, answer) => {
    writeLock(dbOf(app), "owner", "reset", { failures: 0, lockedUntil: new Date(Date.now() + 60_000) });
    return realVerify(hashed, answer);
  });
  const res = await post(app, "/api/auth/forgot", forgotBody());
  expect(res.statusCode).toBe(423);
  expect((await signin(app, OWNER_PASSWORD)).statusCode).toBe(200); // password unchanged
  expect(readLock(dbOf(app), "owner", "reset").lockedUntil).not.toBeNull();
});

// ---- logs and unknown routes ------------------------------------------------------------------------

test("passwords, answers and tokens never reach the log", async () => {
  const lines: string[] = [];
  const stream = {
    write(chunk: string) {
      lines.push(chunk);
    },
  };
  const app = await ownerApp({ logger: { level: "trace", stream } });
  const typedWrong = "wrong-marker-4471";
  await signin(app, typedWrong);
  const signedInRes = await signin(app, OWNER_PASSWORD, "owner", true);
  const token = cookieOf(signedInRes).split("=")[1];
  await get(app, "/api/game/status", cookieOf(signedInRes));
  await post(app, "/api/auth/forgot", forgotBody({ answers: ["wrong-answer-5521", "y", "z"], newPassword: "new-marker-8830-pass" }));
  dbOf(app).prepare("UPDATE accounts SET password_hash = ?").run("not-a-hash"); // a logged 500
  await signin(app, "after-fault-marker-1198");

  const log = lines.join("");
  expect(log).toContain("/api/auth/signin"); // the logger really was listening, including the error
  expect(log).toContain('"statusCode":500');
  for (const secret of [OWNER_PASSWORD, typedWrong, token, "wrong-answer-5521", "new-marker-8830-pass", "after-fault-marker-1198", "Lanternfall", "Dragonbridge"]) {
    expect(log, secret).not.toContain(secret);
  }
});

test("an unknown route is a JSON 404 in the shape every error has", async () => {
  const app = await ownerApp();
  const cookie = await signinCookie(app);
  for (const res of [await get(app, "/api/nope"), await post(app, "/api/nope", {}, cookie), await get(app, "/somewhere/else")]) {
    expect(res.statusCode).toBe(404);
    expect(res.json()).toEqual({ error: "not_found", message: "Not found" });
  }
});

test("an empty password is just a wrong password", async () => {
  const app = await ownerApp();
  const real = await signin(app, "");
  const unknown = await signin(app, "", "nobody");
  expect(real.statusCode).toBe(401);
  expect(real.json()).toMatchObject({ error: "wrong_password", triesLeft: 4 });
  expect(unknown.json()).toMatchObject({ error: "wrong_password", triesLeft: 4 });
});
