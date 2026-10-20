import type { FastifyInstance } from "fastify";
import { beforeEach, expect, test, vi } from "vitest";
import { DEFAULT_SETTINGS } from "../../shared/src/api.js";
import { hashPassword, verifyPassword } from "../src/auth/passwords.js";
import { addNotification } from "../src/notifications/notifications.js";
import {
  OWNER_ANSWERS,
  OWNER_PASSWORD,
  dbOf,
  del,
  forgotBody,
  get,
  insertAccount,
  ownerApp,
  patch,
  post,
  signedIn,
  signin,
  signinCookie,
  testApp,
  tmpFile,
} from "./helpers.js";

// Wraps the real functions so a test can run code while a check or a hash is in flight.
vi.mock("../src/auth/passwords.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../src/auth/passwords.js")>();
  return {
    ...actual,
    verifyPassword: vi.fn(actual.verifyPassword),
    hashPassword: vi.fn(actual.hashPassword),
  };
});
const real = await vi.importActual<typeof import("../src/auth/passwords.js")>("../src/auth/passwords.js");

beforeEach(() => {
  vi.mocked(verifyPassword).mockReset();
  vi.mocked(hashPassword).mockReset();
});

const WRONG = "nope-nope-nope";
const NEW_PASSWORD = "another long password";

type Row = Record<string, unknown>;
const rows = (app: FastifyInstance, sql: string): Row[] => dbOf(app).prepare(sql).all() as Row[];
const lockRows = (app: FastifyInstance) => rows(app, "SELECT username, kind, failures FROM auth_locks");
const notifications = (app: FastifyInstance) => rows(app, "SELECT kind, title, body FROM notifications ORDER BY id");
const storedHashes = (app: FastifyInstance) => rows(app, "SELECT password_hash, answer_hashes FROM accounts");
const sessionCount = (app: FastifyInstance) => rows(app, "SELECT 1 FROM sessions").length;
const wrongCounts = (app: FastifyInstance) => rows(app, "SELECT wrong_passwords FROM sessions ORDER BY created_at, rowid").map((r) => r.wrong_passwords);
// A database rule that makes saving one particular notification fail, to see what else is left behind.
const refuseNotification = (title: string) =>
  `CREATE TRIGGER refuse BEFORE INSERT ON notifications WHEN NEW.title = '${title}'
   BEGIN SELECT RAISE(ABORT, 'refused'); END`;

// ---- the account ------------------------------------------------------------------------------------

test("the account is the signed-in user and nothing secret", async () => {
  const { app, cookie } = await signedIn();
  const res = await get(app, "/api/account", cookie);
  expect(res.statusCode).toBe(200);
  expect(res.json()).toEqual({ id: 1, username: "owner", displayName: "Owner", role: "owner", hasAvatar: false });
});

test("the display name can be changed, and is trimmed", async () => {
  const { app, cookie } = await signedIn();
  const res = await patch(app, "/api/account", { displayName: "  Sir Lanternfall  " }, cookie);
  expect(res.statusCode).toBe(200);
  expect(res.json()).toMatchObject({ username: "owner", displayName: "Sir Lanternfall" });
  expect((await get(app, "/api/account", cookie)).json().displayName).toBe("Sir Lanternfall");
});

test("a display name is 1 to 40 characters, counted as a person sees them", async () => {
  const { app, cookie } = await signedIn();
  for (const displayName of ["", "   ", "x".repeat(41), "🐉".repeat(41)]) {
    const res = await patch(app, "/api/account", { displayName }, cookie);
    expect(res.statusCode, displayName).toBe(400);
    expect(res.json().error, displayName).toBe("invalid_display_name");
  }
  expect((await patch(app, "/api/account", { displayName: "🐉".repeat(40) }, cookie)).statusCode).toBe(200);
  expect((await patch(app, "/api/account", { displayName: "x" }, cookie)).statusCode).toBe(200);
});

test("a display name that is not text is a bad request", async () => {
  const { app, cookie } = await signedIn();
  for (const body of [{}, { displayName: 7 }, { displayName: null }, [], "Owner"]) {
    const res = await patch(app, "/api/account", body, cookie);
    expect(res.statusCode, JSON.stringify(body)).toBe(400);
    expect(res.json().error, JSON.stringify(body)).toBe("bad_request");
  }
  expect((await get(app, "/api/account", cookie)).json().displayName).toBe("Owner");
});

test("a change made with a valid session but without the request header is refused", async () => {
  const { app, cookie } = await signedIn();
  const res = await app.inject({
    method: "PATCH",
    url: "/api/account",
    payload: { displayName: "Intruder" },
    headers: { cookie },
  });
  expect(res.statusCode).toBe(403);
  expect(res.json().error).toBe("bad_request_header");
  expect((await get(app, "/api/account", cookie)).json().displayName).toBe("Owner");
});

// ---- changing the password ----------------------------------------------------------------------------

test("changing the password needs the current one and signs out other sessions", async () => {
  const { app, cookie } = await signedIn();
  const other = await signinCookie(app);
  expect(
    (await post(app, "/api/account/password", { currentPassword: WRONG, newPassword: NEW_PASSWORD }, cookie)).statusCode,
  ).toBe(401);
  const res = await post(
    app,
    "/api/account/password",
    { currentPassword: OWNER_PASSWORD, newPassword: NEW_PASSWORD },
    cookie,
  );
  expect(res.statusCode).toBe(204);
  expect(res.body).toBe("");
  expect((await get(app, "/api/account", other)).statusCode).toBe(401);
  expect((await get(app, "/api/account", cookie)).statusCode).toBe(200);
});

test("after a change the new password signs in and the old one does not", async () => {
  const { app, cookie } = await signedIn();
  await post(app, "/api/account/password", { currentPassword: OWNER_PASSWORD, newPassword: NEW_PASSWORD }, cookie);
  expect((await signin(app, OWNER_PASSWORD)).statusCode).toBe(401);
  expect((await signin(app, NEW_PASSWORD)).statusCode).toBe(200);
  const stored = String(storedHashes(app)[0]?.password_hash);
  expect(stored).toMatch(/^\$argon2id\$/);
  expect(stored).not.toContain(NEW_PASSWORD);
});

// R42: both the current and the new password are normalized, so the way a character was typed doesn't matter.
test("changing the password normalizes the current one and the new one", async () => {
  const { app, cookie } = await signedIn();
  // OWNER_PASSWORD with full-width letters and ideographic spaces.
  const fullWidthCurrent = "ｃｏｒｒｅｃｔ　horse　battery";
  const decomposedNew = "Café au lait 42";
  const res = await post(app, "/api/account/password", { currentPassword: fullWidthCurrent, newPassword: decomposedNew }, cookie);
  expect(res.statusCode).toBe(204);
  expect((await signin(app, "Café au lait 42")).statusCode).toBe(200);

  const tooShort = await post(app, "/api/account/password", { currentPassword: "Café au lait 42", newPassword: "é".repeat(9) }, cookie);
  expect(tooShort.statusCode).toBe(400);
  expect(tooShort.json().error).toBe("too_short");
});

test("changing the answers normalizes the current password too", async () => {
  const { app, cookie } = await signedIn();
  const fullWidthCurrent = "ｃｏｒｒｅｃｔ　horse　battery";
  const res = await post(app, "/api/account/answers", { currentPassword: fullWidthCurrent, answers: ["Tidewake", "Oldharbor", "Runestones"] }, cookie);
  expect(res.statusCode).toBe(204);
});

test("a wrong current password is a 401 with the usual code, and never counts toward the sign-in lock", async () => {
  const { app, cookie } = await signedIn();
  for (let i = 0; i < 4; i++) {
    const res = await post(app, "/api/account/password", { currentPassword: WRONG, newPassword: NEW_PASSWORD }, cookie);
    expect(res.statusCode).toBe(401);
    expect(res.json()).toEqual({ error: "wrong_password", message: "That password isn't right." });
  }
  expect(lockRows(app)).toEqual([]);
  expect((await signin(app, OWNER_PASSWORD)).statusCode).toBe(200);
  expect((await get(app, "/api/account", cookie)).statusCode).toBe(200);
});

// ---- guessing the current password with a stolen session ---------------------------------------------

const guessViaPassword = (app: FastifyInstance, cookie: string) =>
  post(app, "/api/account/password", { currentPassword: WRONG, newPassword: NEW_PASSWORD }, cookie);
const guessViaAnswers = (app: FastifyInstance, cookie: string) =>
  post(app, "/api/account/answers", { currentPassword: WRONG, answers: NEW_ANSWERS }, cookie);
const SIGNED_OUT = { error: "signed_out", message: "Please sign in." };

test("four wrong current passwords in a row, across both routes, leave the session signed in", async () => {
  const { app, cookie } = await signedIn();
  for (const guess of [guessViaPassword, guessViaAnswers, guessViaPassword, guessViaAnswers]) {
    const res = await guess(app, cookie);
    expect(res.statusCode).toBe(401);
    expect(res.json().error).toBe("wrong_password");
  }
  expect(wrongCounts(app)).toEqual([4]);
  expect((await get(app, "/api/account", cookie)).statusCode).toBe(200);
});

test("the fifth wrong current password ends the session, says so, and leaves the sign-in lock alone", async () => {
  const { app, cookie } = await signedIn();
  const before = storedHashes(app);
  for (const guess of [guessViaPassword, guessViaAnswers, guessViaPassword, guessViaAnswers]) await guess(app, cookie);
  const fifth = await guessViaPassword(app, cookie);
  expect(fifth.statusCode).toBe(401);
  expect(fifth.json()).toEqual(SIGNED_OUT);

  expect((await get(app, "/api/account", cookie)).statusCode).toBe(401);
  expect(sessionCount(app)).toBe(0);
  expect(notifications(app)).toMatchObject([{ kind: "security", title: "Signed out after wrong passwords" }]);
  expect(JSON.stringify(notifications(app))).not.toContain(WRONG);
  expect(storedHashes(app)).toEqual(before);
  // The owner is not locked out: signing in with the right password still works.
  expect(lockRows(app)).toEqual([]);
  expect((await signin(app, OWNER_PASSWORD)).statusCode).toBe(200);
});

test("the session is over for every route after the fifth wrong guess, even with the right password", async () => {
  const { app, cookie } = await signedIn();
  for (let i = 0; i < 5; i++) await guessViaPassword(app, cookie);
  const right = await post(app, "/api/account/password", { currentPassword: OWNER_PASSWORD, newPassword: NEW_PASSWORD }, cookie);
  expect(right.statusCode).toBe(401);
  expect(right.json()).toEqual(SIGNED_OUT);
  expect((await signin(app, OWNER_PASSWORD)).statusCode).toBe(200);
  expect((await signin(app, NEW_PASSWORD)).statusCode).toBe(401);
});

test("a correct current password starts the count again", async () => {
  const { app, cookie } = await signedIn();
  for (let i = 0; i < 4; i++) await guessViaPassword(app, cookie);
  // Right password, too-short new one: nothing changes except that the count starts over.
  const right = await post(app, "/api/account/password", { currentPassword: OWNER_PASSWORD, newPassword: "short" }, cookie);
  expect(right.statusCode).toBe(400);
  expect(wrongCounts(app)).toEqual([0]);
  for (let i = 0; i < 4; i++) expect((await guessViaAnswers(app, cookie)).json().error).toBe("wrong_password");
  expect((await get(app, "/api/account", cookie)).statusCode).toBe(200);
  expect((await guessViaAnswers(app, cookie)).json()).toEqual(SIGNED_OUT);
  expect(notifications(app)).toHaveLength(1);
});

test("a correct answers change also starts the count again", async () => {
  const { app, cookie } = await signedIn();
  for (let i = 0; i < 4; i++) await guessViaPassword(app, cookie);
  const right = await post(app, "/api/account/answers", { currentPassword: OWNER_PASSWORD, answers: NEW_ANSWERS }, cookie);
  expect(right.statusCode).toBe(204);
  expect(wrongCounts(app)).toEqual([0]);
});

test("each session has its own count", async () => {
  const { app, cookie: first } = await signedIn();
  const second = await signinCookie(app);
  for (let i = 0; i < 4; i++) await guessViaPassword(app, first);
  for (let i = 0; i < 4; i++) await guessViaAnswers(app, second);
  expect(wrongCounts(app)).toEqual([4, 4]);

  expect((await guessViaPassword(app, first)).json()).toEqual(SIGNED_OUT);
  expect((await get(app, "/api/account", first)).statusCode).toBe(401);
  // The other session is untouched: still signed in, still at four.
  expect((await get(app, "/api/account", second)).statusCode).toBe(200);
  expect(wrongCounts(app)).toEqual([4]);
  expect((await guessViaAnswers(app, second)).json()).toEqual(SIGNED_OUT);
  expect(notifications(app).map((n) => n.title)).toEqual([
    "Signed out after wrong passwords",
    "Signed out after wrong passwords",
  ]);
});

test("ten wrong guesses at once end the session after exactly five", async () => {
  const { app, cookie } = await signedIn();
  const results = await Promise.all(
    Array.from({ length: 10 }, (_, i) => (i % 2 === 0 ? guessViaPassword(app, cookie) : guessViaAnswers(app, cookie))),
  );
  const bodies = results.map((r) => r.json().error);
  expect(results.every((r) => r.statusCode === 401)).toBe(true);
  expect(bodies.filter((e) => e === "wrong_password")).toHaveLength(4);
  expect(bodies.filter((e) => e === "signed_out")).toHaveLength(6);
  expect(sessionCount(app)).toBe(0);
  expect(notifications(app).map((n) => n.title)).toEqual(["Signed out after wrong passwords"]);
});

test("a session that ends while the current password is being checked changes nothing, even if it was right", async () => {
  const { app, cookie } = await signedIn();
  const before = storedHashes(app);
  vi.mocked(verifyPassword).mockImplementationOnce(async (hashed, password) => {
    const ok = await real.verifyPassword(hashed, password);
    dbOf(app).exec("DELETE FROM sessions");
    return ok;
  });
  const res = await post(app, "/api/account/password", { currentPassword: OWNER_PASSWORD, newPassword: NEW_PASSWORD }, cookie);
  expect(res.statusCode).toBe(401);
  expect(res.json()).toEqual(SIGNED_OUT);
  expect(storedHashes(app)).toEqual(before);
  expect(notifications(app)).toEqual([]);
});

test("a session that ends while the new password is being hashed changes nothing", async () => {
  const { app, cookie } = await signedIn();
  const before = storedHashes(app);
  vi.mocked(hashPassword).mockImplementationOnce(async (password) => {
    dbOf(app).exec("DELETE FROM sessions");
    return real.hashPassword(password);
  });
  const res = await post(app, "/api/account/password", { currentPassword: OWNER_PASSWORD, newPassword: NEW_PASSWORD }, cookie);
  expect(res.statusCode).toBe(401);
  expect(res.json()).toEqual(SIGNED_OUT);
  expect(storedHashes(app)).toEqual(before);
  expect(notifications(app)).toEqual([]);
});

test("a session that ends while the new answers are being hashed changes nothing", async () => {
  const { app, cookie } = await signedIn();
  const before = storedHashes(app);
  vi.mocked(hashPassword).mockImplementationOnce(async (answer) => {
    dbOf(app).exec("DELETE FROM sessions");
    return real.hashPassword(answer);
  });
  const res = await post(app, "/api/account/answers", { currentPassword: OWNER_PASSWORD, answers: NEW_ANSWERS }, cookie);
  expect(res.statusCode).toBe(401);
  expect(res.json()).toEqual(SIGNED_OUT);
  expect(storedHashes(app)).toEqual(before);
  expect(notifications(app)).toEqual([]);
});

test("a new password that is too short is refused and changes nothing", async () => {
  const { app, cookie } = await signedIn();
  const other = await signinCookie(app);
  const before = storedHashes(app);
  const res = await post(app, "/api/account/password", { currentPassword: OWNER_PASSWORD, newPassword: "short" }, cookie);
  expect(res.statusCode).toBe(400);
  expect(res.json().error).toBe("too_short");
  expect(storedHashes(app)).toEqual(before);
  expect((await get(app, "/api/account", other)).statusCode).toBe(200);
  // Ten characters is long enough, counted as a person sees them.
  const ok = await post(app, "/api/account/password", { currentPassword: OWNER_PASSWORD, newPassword: "🐉".repeat(10) }, cookie);
  expect(ok.statusCode).toBe(204);
});

test.each([
  ["no fields", {}],
  ["a numeric current password", { currentPassword: 1234567890, newPassword: NEW_PASSWORD }],
  ["a missing new password", { currentPassword: OWNER_PASSWORD }],
  ["a list for a body", [OWNER_PASSWORD, NEW_PASSWORD]],
])("changing the password with %s is a bad request", async (_name, body) => {
  const { app, cookie } = await signedIn();
  const before = storedHashes(app);
  const res = await post(app, "/api/account/password", body, cookie);
  expect(res.statusCode).toBe(400);
  expect(res.json().error).toBe("bad_request");
  expect(storedHashes(app)).toEqual(before);
});

test("a password change leaves a security notification that does not hold either password", async () => {
  const { app, cookie } = await signedIn();
  await post(app, "/api/account/password", { currentPassword: OWNER_PASSWORD, newPassword: NEW_PASSWORD }, cookie);
  expect(notifications(app)).toMatchObject([{ kind: "security", title: "Password changed" }]);
  const text = JSON.stringify(notifications(app));
  expect(text).not.toContain(OWNER_PASSWORD);
  expect(text).not.toContain(NEW_PASSWORD);
});

test("a failed password change leaves no notification", async () => {
  const { app, cookie } = await signedIn();
  await post(app, "/api/account/password", { currentPassword: WRONG, newPassword: NEW_PASSWORD }, cookie);
  await post(app, "/api/account/password", { currentPassword: OWNER_PASSWORD, newPassword: "short" }, cookie);
  expect(notifications(app)).toEqual([]);
});

test("two password changes at once: one wins, the other is told its current password is no longer right", async () => {
  const { app, cookie } = await signedIn();
  const results = await Promise.all(
    ["first long password", "second long password"].map((newPassword) =>
      post(app, "/api/account/password", { currentPassword: OWNER_PASSWORD, newPassword }, cookie),
    ),
  );
  expect(results.map((r) => r.statusCode).sort()).toEqual([204, 401]);
  expect(notifications(app)).toHaveLength(1);
});

test("a stored password hash that cannot be read is a server error, not a wrong password", async () => {
  const { app, cookie } = await signedIn();
  dbOf(app).prepare("UPDATE accounts SET password_hash = ?").run("not-a-hash");
  const res = await post(app, "/api/account/password", { currentPassword: OWNER_PASSWORD, newPassword: NEW_PASSWORD }, cookie);
  expect(res.statusCode).toBe(500);
  expect(res.json().error).toBe("server_error");
  expect(rows(app, "SELECT password_hash FROM accounts")).toEqual([{ password_hash: "not-a-hash" }]);
  expect(notifications(app)).toEqual([]);
});

// ---- changing the security answers ------------------------------------------------------------------

const NEW_ANSWERS = ["  Winterfest ", "Harrow   Bay", "Stonecastle"];

test("changing the answers needs the current password", async () => {
  const { app, cookie } = await signedIn();
  const before = storedHashes(app);
  const wrong = await post(app, "/api/account/answers", { currentPassword: WRONG, answers: NEW_ANSWERS }, cookie);
  expect(wrong.statusCode).toBe(401);
  expect(wrong.json().error).toBe("wrong_password");
  expect(storedHashes(app)).toEqual(before);
  expect(lockRows(app)).toEqual([]);
});

test("new answers work for a password reset, ignoring case and extra spaces", async () => {
  const { app, cookie } = await signedIn();
  const res = await post(app, "/api/account/answers", { currentPassword: OWNER_PASSWORD, answers: NEW_ANSWERS }, cookie);
  expect(res.statusCode).toBe(204);
  expect(res.body).toBe("");
  expect(JSON.stringify(storedHashes(app))).not.toMatch(/winterfest|harrow|stonecastle/i);
  const reset = await post(app, "/api/auth/forgot", forgotBody({ answers: ["winterfest", "HARROW bay", "stonecastle"] }));
  expect(reset.statusCode).toBe(204);
});

test("the old answers stop working", async () => {
  const { app, cookie } = await signedIn();
  await post(app, "/api/account/answers", { currentPassword: OWNER_PASSWORD, answers: NEW_ANSWERS }, cookie);
  const reset = await post(app, "/api/auth/forgot", forgotBody({ answers: [...OWNER_ANSWERS] }));
  expect(reset.statusCode).toBe(401);
  expect(reset.json().error).toBe("wrong_answer");
});

test("all three answers are needed, and none can be blank", async () => {
  const { app, cookie } = await signedIn();
  const before = storedHashes(app);
  for (const answers of [["a", "b", ""], ["a", "   ", "c"], ["", "", ""], ["a", "b", " \t"]]) {
    const res = await post(app, "/api/account/answers", { currentPassword: OWNER_PASSWORD, answers }, cookie);
    expect(res.statusCode, JSON.stringify(answers)).toBe(400);
    expect(res.json().error, JSON.stringify(answers)).toBe("missing_answer");
  }
  expect(storedHashes(app)).toEqual(before);
});

test.each([
  ["two answers", { currentPassword: OWNER_PASSWORD, answers: ["a", "b"] }],
  ["four answers", { currentPassword: OWNER_PASSWORD, answers: ["a", "b", "c", "d"] }],
  ["a non-text answer", { currentPassword: OWNER_PASSWORD, answers: ["a", "b", 3] }],
  ["answers that are not a list", { currentPassword: OWNER_PASSWORD, answers: "abc" }],
  ["no current password", { answers: ["a", "b", "c"] }],
])("changing the answers with %s is a bad request", async (_name, body) => {
  const { app, cookie } = await signedIn();
  const before = storedHashes(app);
  const res = await post(app, "/api/account/answers", body, cookie);
  expect(res.statusCode).toBe(400);
  expect(res.json().error).toBe("bad_request");
  expect(storedHashes(app)).toEqual(before);
});

test("an answers change leaves a security notification that holds no answers and no password", async () => {
  const { app, cookie } = await signedIn();
  await post(app, "/api/account/answers", { currentPassword: OWNER_PASSWORD, answers: NEW_ANSWERS }, cookie);
  expect(notifications(app)).toMatchObject([{ kind: "security", title: "Security answers changed" }]);
  expect(JSON.stringify(notifications(app))).not.toMatch(/winterfest|harrow|stonecastle|lanternfall/i);
  expect(JSON.stringify(notifications(app))).not.toContain(OWNER_PASSWORD);
});

test("a refused answers change leaves no notification", async () => {
  const { app, cookie } = await signedIn();
  await post(app, "/api/account/answers", { currentPassword: WRONG, answers: NEW_ANSWERS }, cookie);
  await post(app, "/api/account/answers", { currentPassword: OWNER_PASSWORD, answers: ["a", "", "c"] }, cookie);
  expect(notifications(app)).toEqual([]);
});

test("an answers change whose notification cannot be saved changes nothing", async () => {
  const { app, cookie } = await signedIn();
  const before = storedHashes(app);
  dbOf(app).exec(refuseNotification("Security answers changed"));
  const res = await post(app, "/api/account/answers", { currentPassword: OWNER_PASSWORD, answers: NEW_ANSWERS }, cookie);
  expect(res.statusCode).toBe(500);
  expect(storedHashes(app)).toEqual(before);
});

test("a password change that lands while the answers are being checked turns the answers change away", async () => {
  const { app, cookie } = await signedIn();
  vi.mocked(verifyPassword).mockImplementationOnce(async (hashed, password) => {
    const ok = await real.verifyPassword(hashed, password);
    dbOf(app).prepare("UPDATE accounts SET password_hash = ?").run("$argon2id$v=19$changed-in-the-meantime");
    return ok;
  });
  const answersBefore = rows(app, "SELECT answer_hashes FROM accounts");
  const res = await post(app, "/api/account/answers", { currentPassword: OWNER_PASSWORD, answers: NEW_ANSWERS }, cookie);
  expect(res.statusCode).toBe(401);
  expect(res.json().error).toBe("wrong_password");
  expect(rows(app, "SELECT answer_hashes FROM accounts")).toEqual(answersBefore);
  expect(notifications(app)).toEqual([]);
});

test("a password reset that lands while the answers are being hashed turns the answers change away", async () => {
  const { app, cookie } = await signedIn();
  const answersBefore = rows(app, "SELECT answer_hashes FROM accounts");
  vi.mocked(hashPassword).mockImplementationOnce(async (answer) => {
    // The reset finishes (new password, every session ended) while the new answers are still being hashed.
    const reset = await post(app, "/api/auth/forgot", forgotBody());
    expect(reset.statusCode).toBe(204);
    return real.hashPassword(answer);
  });
  const res = await post(app, "/api/account/answers", { currentPassword: OWNER_PASSWORD, answers: NEW_ANSWERS }, cookie);
  expect(res.statusCode).toBe(401);
  expect(rows(app, "SELECT answer_hashes FROM accounts")).toEqual(answersBefore);
  expect(notifications(app).map((n) => n.title)).toEqual(["Password changed"]);
});

test("changing the answers keeps the password and the other sessions", async () => {
  const { app, cookie } = await signedIn();
  const other = await signinCookie(app);
  await post(app, "/api/account/answers", { currentPassword: OWNER_PASSWORD, answers: NEW_ANSWERS }, cookie);
  expect((await get(app, "/api/account", other)).statusCode).toBe(200);
  expect((await signin(app, OWNER_PASSWORD)).statusCode).toBe(200);
});

// ---- the picture ------------------------------------------------------------------------------------

// A real 1x1 PNG, a JPEG and WebP with just enough of a header to be what they say, and some text.
const tinyPng = () =>
  Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==",
    "base64",
  );
const tinyJpeg = () => Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]), Buffer.from("JFIF\0"), Buffer.alloc(32)]);
const tinyWebp = () => Buffer.concat([Buffer.from("RIFF"), Buffer.from([0x24, 0, 0, 0]), Buffer.from("WEBPVP8 "), Buffer.alloc(32)]);

type Part = { name: string; data: Buffer | string; filename?: string; type?: string };

// A multipart/form-data body, built by hand so a test controls every byte.
function multipart(parts: Part[]) {
  const boundary = "----amethyst-test-boundary";
  const chunks: Buffer[] = [];
  for (const part of parts) {
    let head = `--${boundary}\r\nContent-Disposition: form-data; name="${part.name}"`;
    if (part.filename !== undefined) head += `; filename="${part.filename}"`;
    head += "\r\n";
    if (part.type !== undefined) head += `Content-Type: ${part.type}\r\n`;
    chunks.push(Buffer.from(`${head}\r\n`), Buffer.from(part.data), Buffer.from("\r\n"));
  }
  chunks.push(Buffer.from(`--${boundary}--\r\n`));
  return { payload: Buffer.concat(chunks), contentType: `multipart/form-data; boundary=${boundary}` };
}

function putParts(app: FastifyInstance, cookie: string, parts: Part[]) {
  const { payload, contentType } = multipart(parts);
  return app.inject({
    method: "PUT",
    url: "/api/account/avatar",
    payload,
    headers: { cookie, "x-amethyst-request": "1", "content-type": contentType },
  });
}

const putAvatar = (app: FastifyInstance, cookie: string, bytes: Buffer, type: string) =>
  putParts(app, cookie, [{ name: "file", data: bytes, filename: "me", type }]);

const avatarRow = (app: FastifyInstance) => rows(app, "SELECT avatar, avatar_type FROM accounts")[0] as Row;

test("avatar upload accepts small images only", async () => {
  const { app, cookie } = await signedIn();
  expect((await putAvatar(app, cookie, tinyPng(), "image/png")).statusCode).toBe(204);
  expect((await get(app, "/api/account", cookie)).json().hasAvatar).toBe(true);
  expect((await putAvatar(app, cookie, Buffer.alloc(2 * 1024 * 1024 + 1), "image/png")).statusCode).toBe(413);
  expect((await putAvatar(app, cookie, Buffer.from("hi"), "text/plain")).statusCode).toBe(415);
});

test("the picture comes back as it went in, with its own content type and never cached", async () => {
  const { app, cookie } = await signedIn();
  for (const [bytes, type] of [
    [tinyPng(), "image/png"],
    [tinyJpeg(), "image/jpeg"],
    [tinyWebp(), "image/webp"],
  ] as const) {
    expect((await putAvatar(app, cookie, bytes, type)).statusCode, type).toBe(204);
    const res = await get(app, "/api/account/avatar", cookie);
    expect(res.statusCode, type).toBe(200);
    expect(res.headers["content-type"], type).toBe(type);
    expect(res.headers["cache-control"], type).toBe("no-store");
    expect(res.headers["x-content-type-options"], type).toBe("nosniff");
    expect(res.rawPayload.equals(bytes), type).toBe(true);
  }
});

test("there is no picture until one is uploaded, and removing it brings that back", async () => {
  const { app, cookie } = await signedIn();
  const none = await get(app, "/api/account/avatar", cookie);
  expect(none.statusCode).toBe(404);
  expect(none.json()).toEqual({ error: "not_found", message: "Not found" });

  await putAvatar(app, cookie, tinyPng(), "image/png");
  const removed = await del(app, "/api/account/avatar", cookie);
  expect(removed.statusCode).toBe(204);
  expect(removed.body).toBe("");
  expect((await get(app, "/api/account/avatar", cookie)).statusCode).toBe(404);
  expect((await get(app, "/api/account", cookie)).json().hasAvatar).toBe(false);
  expect(avatarRow(app)).toEqual({ avatar: null, avatar_type: null });
  // Removing what is not there is fine too.
  expect((await del(app, "/api/account/avatar", cookie)).statusCode).toBe(204);
});

test("a new picture replaces the old one", async () => {
  const { app, cookie } = await signedIn();
  await putAvatar(app, cookie, tinyPng(), "image/png");
  await putAvatar(app, cookie, tinyJpeg(), "image/jpeg");
  expect((await get(app, "/api/account/avatar", cookie)).headers["content-type"]).toBe("image/jpeg");
});

test("exactly 2 MB is allowed, one byte more is not", async () => {
  const { app, cookie } = await signedIn();
  const limit = 2 * 1024 * 1024;
  const exact = Buffer.concat([tinyPng(), Buffer.alloc(limit - tinyPng().length)]);
  expect(exact.length).toBe(limit);
  expect((await putAvatar(app, cookie, exact, "image/png")).statusCode).toBe(204);
  const over = Buffer.concat([tinyPng(), Buffer.alloc(limit + 1 - tinyPng().length)]);
  const res = await putAvatar(app, cookie, over, "image/png");
  expect(res.statusCode).toBe(413);
  expect(res.json()).toEqual({ error: "too_large", message: "That request is too large." });
});

test("the file's own bytes and its declared type must both say png, jpeg or webp, and agree", async () => {
  const { app, cookie } = await signedIn();
  const cases: [string, Buffer, string][] = [
    ["text bytes declared as png", Buffer.from("<script>alert(1)</script>"), "image/png"],
    ["png bytes declared as text", tinyPng(), "text/plain"],
    ["png bytes declared as jpeg", tinyPng(), "image/jpeg"],
    ["jpeg bytes declared as png", tinyJpeg(), "image/png"],
    ["webp bytes declared as png", tinyWebp(), "image/png"],
    ["png bytes declared as gif", tinyPng(), "image/gif"],
    ["gif bytes declared as gif", Buffer.from("GIF89a\u0001\u0000\u0001\u0000", "latin1"), "image/gif"],
    ["svg declared as svg", Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"/>'), "image/svg+xml"],
    ["an empty file", Buffer.alloc(0), "image/png"],
    ["a RIFF file that is not webp", Buffer.concat([Buffer.from("RIFF"), Buffer.alloc(4), Buffer.from("WAVEfmt ")]), "image/webp"],
  ];
  for (const [name, bytes, type] of cases) {
    const res = await putAvatar(app, cookie, bytes, type);
    expect(res.statusCode, name).toBe(415);
    expect(res.json(), name).toEqual({ error: "unsupported_media_type", message: "That kind of request isn't supported." });
  }
  expect(avatarRow(app)).toEqual({ avatar: null, avatar_type: null });
});

test("the declared type is compared without regard to case", async () => {
  const { app, cookie } = await signedIn();
  expect((await putAvatar(app, cookie, tinyPng(), "IMAGE/PNG")).statusCode).toBe(204);
  expect((await get(app, "/api/account/avatar", cookie)).headers["content-type"]).toBe("image/png");
});

test("a refused upload leaves the old picture alone", async () => {
  const { app, cookie } = await signedIn();
  await putAvatar(app, cookie, tinyPng(), "image/png");
  await putAvatar(app, cookie, Buffer.from("hi"), "text/plain");
  await putAvatar(app, cookie, Buffer.alloc(2 * 1024 * 1024 + 1), "image/png");
  const res = await get(app, "/api/account/avatar", cookie);
  expect(res.headers["content-type"]).toBe("image/png");
  expect(res.rawPayload.equals(tinyPng())).toBe(true);
});

test("an upload needs a file called file", async () => {
  const { app, cookie } = await signedIn();
  const wrongName = await putParts(app, cookie, [{ name: "avatar", data: tinyPng(), filename: "me", type: "image/png" }]);
  expect(wrongName.statusCode).toBe(400);
  expect(wrongName.json().error).toBe("bad_request");
  const onlyText = await putParts(app, cookie, [{ name: "file", data: "just words" }]);
  expect(onlyText.statusCode).toBe(400);
  const nothing = await putParts(app, cookie, []);
  expect(nothing.statusCode).toBe(400);
  expect(avatarRow(app)).toEqual({ avatar: null, avatar_type: null });
});

test("a field before the file and a second file after it do not get in the way", async () => {
  const { app, cookie } = await signedIn();
  const res = await putParts(app, cookie, [
    { name: "note", data: "hello" },
    { name: "file", data: tinyPng(), filename: "me", type: "image/png" },
    { name: "file", data: tinyJpeg(), filename: "second", type: "image/jpeg" },
  ]);
  expect(res.statusCode).toBe(204);
  expect((await get(app, "/api/account/avatar", cookie)).headers["content-type"]).toBe("image/png");
});

test("an upload that is not multipart is an unsupported media type", async () => {
  const { app, cookie } = await signedIn();
  const res = await app.inject({
    method: "PUT",
    url: "/api/account/avatar",
    payload: { file: "abc" },
    headers: { cookie, "x-amethyst-request": "1" },
  });
  expect(res.statusCode).toBe(415);
  expect(res.json().error).toBe("unsupported_media_type");
});

test("the picture is not served, taken or removed without a session", async () => {
  const { app, cookie } = await signedIn();
  await putAvatar(app, cookie, tinyPng(), "image/png");
  expect((await get(app, "/api/account/avatar")).statusCode).toBe(401);
  expect((await del(app, "/api/account/avatar")).statusCode).toBe(401);
  const { payload, contentType } = multipart([{ name: "file", data: tinyPng(), filename: "me", type: "image/png" }]);
  const put = await app.inject({
    method: "PUT",
    url: "/api/account/avatar",
    payload,
    headers: { "x-amethyst-request": "1", "content-type": contentType },
  });
  expect(put.statusCode).toBe(401);
  expect((await get(app, "/api/account/avatar", cookie)).statusCode).toBe(200);
});

// ---- settings ---------------------------------------------------------------------------------------

test("settings start at the defaults and save partial changes", async () => {
  const { app, cookie } = await signedIn();
  expect((await get(app, "/api/settings", cookie)).json()).toEqual(DEFAULT_SETTINGS);
  const res = await patch(app, "/api/settings", { appearance: "dark" }, cookie);
  expect(res.json().appearance).toBe("dark");
  expect(res.json().keepSignedInDays).toBe(30);
});

test("the defaults are what the brief lists", () => {
  expect(DEFAULT_SETTINGS).toEqual({
    appearance: "light",
    colourTheme: "amethyst",
    sidebar: "expanded",
    keepSignedInDays: 30,
    gamePort: 47821,
    autoReconnect: true,
    notify: { security: true, game: true, changes: true },
  });
});

test("every setting can be changed, one change at a time, and the rest stay", async () => {
  const { app, cookie } = await signedIn();
  await patch(app, "/api/settings", { appearance: "system" }, cookie);
  await patch(app, "/api/settings", { sidebar: "icons" }, cookie);
  await patch(app, "/api/settings", { keepSignedInDays: 90 }, cookie);
  await patch(app, "/api/settings", { gamePort: 50000 }, cookie);
  await patch(app, "/api/settings", { autoReconnect: false }, cookie);
  await patch(app, "/api/settings", { colourTheme: "amethyst" }, cookie);
  const res = await patch(app, "/api/settings", { notify: { game: false } }, cookie);
  const expected = {
    appearance: "system",
    colourTheme: "amethyst",
    sidebar: "icons",
    keepSignedInDays: 90,
    gamePort: 50000,
    autoReconnect: false,
    notify: { security: true, game: false, changes: true },
  };
  expect(res.json()).toEqual(expected);
  expect((await get(app, "/api/settings", cookie)).json()).toEqual(expected);
});

test("a change to one kind of notification leaves the others as they were", async () => {
  const { app, cookie } = await signedIn();
  await patch(app, "/api/settings", { notify: { security: false } }, cookie);
  const res = await patch(app, "/api/settings", { notify: { changes: false } }, cookie);
  expect(res.json().notify).toEqual({ security: false, game: true, changes: false });
});

test("an empty change returns the settings as they are", async () => {
  const { app, cookie } = await signedIn();
  await patch(app, "/api/settings", { appearance: "dark" }, cookie);
  const res = await patch(app, "/api/settings", {}, cookie);
  expect(res.statusCode).toBe(200);
  expect(res.json()).toEqual({ ...DEFAULT_SETTINGS, appearance: "dark" });
});

const storedSettings = (app: FastifyInstance) => rows(app, "SELECT json FROM settings").map((r) => JSON.parse(String(r.json)));

test("only the settings that were set are stored, not the defaults", async () => {
  const { app, cookie } = await signedIn();
  expect(storedSettings(app)).toEqual([]);
  await patch(app, "/api/settings", { appearance: "dark" }, cookie);
  expect(storedSettings(app)).toEqual([{ appearance: "dark" }]);
  await patch(app, "/api/settings", { notify: { game: false } }, cookie);
  expect(storedSettings(app)).toEqual([{ appearance: "dark", notify: { game: false } }]);
  await patch(app, "/api/settings", { notify: { security: true }, appearance: "light" }, cookie);
  expect(storedSettings(app)).toEqual([{ appearance: "light", notify: { game: false, security: true } }]);
  // What is read back is still the whole thing, over the defaults.
  expect((await get(app, "/api/settings", cookie)).json()).toEqual({
    ...DEFAULT_SETTINGS,
    notify: { security: true, game: false, changes: true },
  });
});

test("a patch with nothing in it stores nothing new", async () => {
  const { app, cookie } = await signedIn();
  await patch(app, "/api/settings", { notify: {} }, cookie);
  await patch(app, "/api/settings", {}, cookie);
  expect(storedSettings(app).every((saved) => Object.keys(saved).length === 0)).toBe(true);
});

test("saving drops whatever damaged values were stored and keeps the good ones", async () => {
  const { app, cookie } = await signedIn();
  dbOf(app).prepare("INSERT INTO settings (account_id, json) VALUES (1, ?)").run('{"appearance":"neon","sidebar":"icons","x":1}');
  await patch(app, "/api/settings", { gamePort: 50000 }, cookie);
  expect(storedSettings(app)).toEqual([{ sidebar: "icons", gamePort: 50000 }]);
});

test("settings survive a server restart", async () => {
  const file = tmpFile();
  let app = await ownerApp({ dbPath: file });
  const cookie = await signinCookie(app);
  await patch(app, "/api/settings", { appearance: "dark", gamePort: 40000 }, cookie);
  await app.close();
  app = await testApp({ dbPath: file });
  const again = await signinCookie(app);
  expect((await get(app, "/api/settings", again)).json()).toMatchObject({ appearance: "dark", gamePort: 40000 });
});

test("bad settings are refused", async () => {
  const { app, cookie } = await signedIn();
  expect((await patch(app, "/api/settings", { colourTheme: "teal" }, cookie)).statusCode).toBe(400);
  expect((await patch(app, "/api/settings", { gamePort: 80 }, cookie)).statusCode).toBe(400);
});

test.each([
  ["appearance", { appearance: "sepia" }],
  ["appearance", { appearance: 1 }],
  ["colourTheme", { colourTheme: "teal" }],
  ["sidebar", { sidebar: "hidden" }],
  ["keepSignedInDays", { keepSignedInDays: 10 }],
  ["keepSignedInDays", { keepSignedInDays: "30" }],
  ["gamePort", { gamePort: 1023 }],
  ["gamePort", { gamePort: 65536 }],
  ["gamePort", { gamePort: 8080.5 }],
  ["gamePort", { gamePort: "8080" }],
  ["gamePort", { gamePort: null }],
  ["autoReconnect", { autoReconnect: "yes" }],
  ["autoReconnect", { autoReconnect: 1 }],
  ["notify", { notify: true }],
  ["notify", { notify: [] }],
  ["notify", { notify: null }],
  ["notify.game", { notify: { game: "off" } }],
  ["notify.sound", { notify: { sound: true } }],
  ["notify.constructor", { notify: { constructor: true } }],
  ["theme", { theme: "dark" }],
])("setting %s is refused with a sentence, and its name in a field of its own: %j", async (key, body) => {
  const { app, cookie } = await signedIn();
  const res = await patch(app, "/api/settings", body, cookie);
  expect(res.statusCode).toBe(400);
  expect(res.json()).toEqual({ error: "invalid_setting", message: "That setting isn't valid.", setting: key });
  expect((await get(app, "/api/settings", cookie)).json()).toEqual(DEFAULT_SETTINGS);
});

test("one bad setting among good ones saves none of them", async () => {
  const { app, cookie } = await signedIn();
  const res = await patch(app, "/api/settings", { appearance: "dark", sidebar: "icons", gamePort: 80 }, cookie);
  expect(res.statusCode).toBe(400);
  expect(res.json().setting).toBe("gamePort");
  expect((await get(app, "/api/settings", cookie)).json()).toEqual(DEFAULT_SETTINGS);
});

test("the port may be anywhere from 1024 to 65535", async () => {
  const { app, cookie } = await signedIn();
  expect((await patch(app, "/api/settings", { gamePort: 1024 }, cookie)).json().gamePort).toBe(1024);
  expect((await patch(app, "/api/settings", { gamePort: 65535 }, cookie)).json().gamePort).toBe(65535);
});

test("a __proto__ key is never accepted", async () => {
  const { app, cookie } = await signedIn();
  const res = await app.inject({
    method: "PATCH",
    url: "/api/settings",
    payload: '{"__proto__": {"appearance": "dark"}}',
    headers: { cookie, "x-amethyst-request": "1", "content-type": "application/json" },
  });
  expect(res.statusCode).toBe(400);
  expect((await get(app, "/api/settings", cookie)).json()).toEqual(DEFAULT_SETTINGS);
});

test("settings that are not an object are a bad request", async () => {
  const { app, cookie } = await signedIn();
  for (const body of [[], ["appearance"], "dark", 7]) {
    const res = await patch(app, "/api/settings", body, cookie);
    expect(res.statusCode, JSON.stringify(body)).toBe(400);
    expect(res.json().error, JSON.stringify(body)).toBe("bad_request");
  }
});

test("the saved sign-in length is what a lasting sign-in uses", async () => {
  const { app, cookie } = await signedIn();
  await patch(app, "/api/settings", { keepSignedInDays: 7 }, cookie);
  const res = await signin(app, OWNER_PASSWORD, "owner", true);
  expect(res.cookies.find((c) => c.name === "amethyst_session")?.maxAge).toBe(7 * 86_400);
});

test("damaged saved settings read as defaults, one setting at a time", async () => {
  const { app, cookie } = await signedIn();
  const save = (json: string) => dbOf(app).prepare("INSERT OR REPLACE INTO settings (account_id, json) VALUES (1, ?)").run(json);

  save('{"appearance":"neon","sidebar":"icons","gamePort":80,"notify":{"game":false,"security":"x"}}');
  expect((await get(app, "/api/settings", cookie)).json()).toEqual({
    ...DEFAULT_SETTINGS,
    sidebar: "icons",
    notify: { security: true, game: false, changes: true },
  });

  for (const broken of ["not json", "null", "[]", '"dark"', "7"]) {
    save(broken);
    expect((await get(app, "/api/settings", cookie)).json(), broken).toEqual(DEFAULT_SETTINGS);
  }
});

// ---- notifications ----------------------------------------------------------------------------------

type Listed = { items: { id: number; kind: string; title: string; body: string; createdAt: string; read: boolean }[]; unread: number };
const listOf = async (app: FastifyInstance, cookie: string) => (await get(app, "/api/notifications", cookie)).json() as Listed;
const AT = new Date("2026-10-18T12:00:00Z");
const add = (app: FastifyInstance, kind: "security" | "game" | "changes", title: string, accountId = 1) =>
  addNotification(dbOf(app), accountId, kind, title, `${title} body`, AT);

test("security events become notifications and can be marked read", async () => {
  const { app, cookie } = await signedIn();
  await signin(app, WRONG);
  const list = (await get(app, "/api/notifications", cookie)).json();
  expect(list.unread).toBe(1);
  expect(list.items[0]).toMatchObject({ kind: "security", title: "Failed sign-in", read: false });
  await post(app, "/api/notifications/read-all", {}, cookie);
  expect((await get(app, "/api/notifications", cookie)).json().unread).toBe(0);
});

test("a notification has exactly the fields the web app reads", async () => {
  const { app, cookie } = await signedIn();
  add(app, "game", "Game connected");
  const { items } = await listOf(app, cookie);
  expect(items).toEqual([
    { id: 1, kind: "game", title: "Game connected", body: "Game connected body", createdAt: "2026-10-18T12:00:00.000Z", read: false },
  ]);
});

test("notifications list newest first, at most 100, and unread counts them all", async () => {
  const { app, cookie } = await signedIn();
  for (let i = 1; i <= 120; i++) add(app, "game", `n${i}`);
  const list = await listOf(app, cookie);
  expect(list.items).toHaveLength(100);
  expect(list.items[0]?.title).toBe("n120");
  expect(list.items[99]?.title).toBe("n21");
  expect(list.unread).toBe(120);
});

test("an empty list is an empty list", async () => {
  const { app, cookie } = await signedIn();
  expect(await listOf(app, cookie)).toEqual({ items: [], unread: 0 });
});

test("one notification can be marked read, and marking it again changes nothing", async () => {
  const { app, cookie } = await signedIn();
  add(app, "game", "one");
  add(app, "changes", "two");
  const first = await post(app, "/api/notifications/1/read", {}, cookie);
  expect(first.statusCode).toBe(204);
  expect(first.body).toBe("");
  expect((await post(app, "/api/notifications/1/read", {}, cookie)).statusCode).toBe(204);
  const list = await listOf(app, cookie);
  expect(list.unread).toBe(1);
  expect(list.items.map((n) => [n.title, n.read])).toEqual([["two", false], ["one", true]]);
});

test("marking a notification that does not exist is a 404", async () => {
  const { app, cookie } = await signedIn();
  for (const id of ["99", "0", "-1", "abc", "1.5", "99999999999999999999"]) {
    const res = await post(app, `/api/notifications/${id}/read`, {}, cookie);
    expect(res.statusCode, id).toBe(404);
    expect(res.json(), id).toEqual({ error: "not_found", message: "Not found" });
  }
});

test("one account cannot read or mark another account's notifications", async () => {
  const { app, cookie } = await signedIn();
  const otherId = insertAccount(dbOf(app), "someone-else");
  add(app, "security", "theirs", otherId);
  add(app, "security", "mine");
  expect((await listOf(app, cookie)).items.map((n) => n.title)).toEqual(["mine"]);
  expect((await post(app, "/api/notifications/1/read", {}, cookie)).statusCode).toBe(404);
  await post(app, "/api/notifications/read-all", {}, cookie);
  expect(rows(app, "SELECT account_id, read_at IS NOT NULL AS read FROM notifications ORDER BY id")).toEqual([
    { account_id: otherId, read: 0 },
    { account_id: 1, read: 1 },
  ]);
});

test("mark all as read marks every notification, including kinds that are switched off", async () => {
  const { app, cookie } = await signedIn();
  await patch(app, "/api/settings", { notify: { game: false } }, cookie);
  add(app, "security", "a");
  add(app, "game", "b");
  add(app, "changes", "c");
  const res = await post(app, "/api/notifications/read-all", {}, cookie);
  expect(res.statusCode).toBe(204);
  expect(res.body).toBe("");
  const list = await listOf(app, cookie);
  expect(list.items.every((n) => n.read)).toBe(true);
  await patch(app, "/api/settings", { notify: { game: true } }, cookie);
  expect((await listOf(app, cookie)).unread).toBe(0);
});

test("notifications of a kind that is switched off are kept and listed, but not counted as unread", async () => {
  const { app, cookie } = await signedIn();
  add(app, "security", "sec");
  add(app, "game", "gam");
  add(app, "changes", "chg");
  expect((await listOf(app, cookie)).unread).toBe(3);

  await patch(app, "/api/settings", { notify: { game: false } }, cookie);
  let list = await listOf(app, cookie);
  expect(list.unread).toBe(2);
  expect(list.items).toHaveLength(3);
  expect(list.items.find((n) => n.title === "gam")).toMatchObject({ kind: "game", read: false });

  await patch(app, "/api/settings", { notify: { security: false, changes: false } }, cookie);
  list = await listOf(app, cookie);
  expect(list.unread).toBe(0);
  expect(list.items).toHaveLength(3);

  // Switching a kind back on counts what was waiting.
  await patch(app, "/api/settings", { notify: { game: true } }, cookie);
  expect((await listOf(app, cookie)).unread).toBe(1);
});

test("the unread count covers every unread notification, not just the hundred listed", async () => {
  const { app, cookie } = await signedIn();
  for (let i = 0; i < 105; i++) add(app, "changes", `c${i}`);
  await patch(app, "/api/settings", { notify: { changes: false } }, cookie);
  add(app, "security", "newest");
  const list = await listOf(app, cookie);
  expect(list.unread).toBe(1);
  expect(list.items).toHaveLength(100);
});

// ---- signed-out callers -------------------------------------------------------------------------------

test("none of the new routes answers a signed-out caller", async () => {
  const app = await ownerApp();
  const calls: [string, string][] = [
    ["GET", "/api/account"],
    ["PATCH", "/api/account"],
    ["POST", "/api/account/password"],
    ["POST", "/api/account/answers"],
    ["GET", "/api/account/avatar"],
    ["DELETE", "/api/account/avatar"],
    ["GET", "/api/settings"],
    ["PATCH", "/api/settings"],
    ["GET", "/api/notifications"],
    ["POST", "/api/notifications/read-all"],
    ["POST", "/api/notifications/1/read"],
  ];
  for (const [method, url] of calls) {
    const res = await app.inject({ method: method as "GET", url, headers: { "x-amethyst-request": "1" } });
    expect(res.statusCode, `${method} ${url}`).toBe(401);
  }
});
