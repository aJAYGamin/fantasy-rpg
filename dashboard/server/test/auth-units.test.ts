import { createHash } from "node:crypto";
import { afterEach, describe, expect, test } from "vitest";
import { LOCK_MINUTES, MAX_WRONG_PASSWORDS, MIN_PASSWORD_LENGTH } from "../../shared/src/constants.js";
import { AccountExistsError, countAccounts, createOwner, findById, findByUsername } from "../src/auth/accounts.js";
import { hashAnswers, normalizeAnswer, verifyAnswers } from "../src/auth/answers.js";
import {
  clearLock,
  isLocked,
  type LockState,
  readLock,
  registerFailure,
  triesLeft,
  writeLock,
} from "../src/auth/locks.js";
import { checkPasswordPolicy, hashPassword, verifyPassword } from "../src/auth/passwords.js";
import { createSession, findSession, revokeAllSessions, revokeSession } from "../src/auth/sessions.js";
import { type Db, openDatabase } from "../src/db/database.js";
import { insertAccount, seedOwner } from "./helpers.js";

const LOCK_MS = LOCK_MINUTES * 60_000;
const t0 = new Date("2026-10-18T12:00:00Z");
const none: LockState = { failures: 0, lockedUntil: null };

const opened: Db[] = [];

afterEach(() => {
  for (const db of opened.splice(0)) db.close();
});

function openDb(): Db {
  const db = openDatabase(":memory:");
  opened.push(db);
  return db;
}

function sessionCount(db: Db): number {
  return (db.prepare("SELECT COUNT(*) AS n FROM sessions").get() as { n: number }).n;
}

describe("answers", () => {
  test("answers ignore capitals and extra spaces", async () => {
    expect(normalizeAnswer("  New   York ")).toBe("new york");
    const h = await hashAnswers(["Lantern Festival", "New York", "Chess"]);
    expect(await verifyAnswers(h, ["lantern festival", "  New   York ", "CHESS"])).toEqual([true, true, true]);
    expect(await verifyAnswers(h, ["lantern festival", "Boston", "chess"])).toEqual([true, false, true]);
  });

  test("normalizing collapses tabs, line breaks, no-break spaces and runs of spaces", () => {
    expect(normalizeAnswer("\tSan \n Francisco\u00a0 ")).toBe("san francisco");
    expect(normalizeAnswer("New  York")).toBe("new york");
  });

  test("accents match however they were typed", async () => {
    const composed = "Caf\u00e9"; // e-acute as one character
    const decomposed = "Cafe\u0301"; // e followed by a combining accent
    expect(decomposed).not.toBe(composed);
    expect(normalizeAnswer(decomposed)).toBe(normalizeAnswer(composed));
    expect(normalizeAnswer("CAFE\u0301")).toBe(normalizeAnswer(composed));
    const h = await hashAnswers([composed, "New York", "Chess"]);
    expect(await verifyAnswers(h, [decomposed, "new york", "chess"])).toEqual([true, true, true]);
  });

  test("every answer is checked, wherever the wrong one is", async () => {
    const h = await hashAnswers(["Lantern Festival", "New York", "Chess"]);
    expect(await verifyAnswers(h, ["nope", "new york", "chess"])).toEqual([false, true, true]);
    expect(await verifyAnswers(h, ["nope", "nope", "nope"])).toEqual([false, false, false]);
  });

  test("hashed answers are argon2id and do not contain the answer", async () => {
    const h = await hashAnswers(["Lantern Festival", "New York", "Chess"]);
    expect(h).toHaveLength(3);
    for (const hash of h) expect(hash.startsWith("$argon2id$")).toBe(true);
    expect(h.join("").toLowerCase()).not.toContain("lantern");
  });

  test("a blank answer never matches, even if it was hashed", async () => {
    const h = await hashAnswers(["", "New York", "Chess"]);
    expect(await verifyAnswers(h, ["", "new york", "chess"])).toEqual([false, true, true]);
    expect(await verifyAnswers(h, ["   ", "new york", "chess"])).toEqual([false, true, true]);
  });

  test("a stored hash that is missing or unreadable is an error, not a wrong answer", async () => {
    const h = await hashAnswers(["Lantern Festival", "New York", "Chess"]);
    const answers: [string, string, string] = ["lantern festival", "new york", "chess"];
    await expect(verifyAnswers([h[0]!], answers)).rejects.toThrow();
    await expect(verifyAnswers([h[0]!, "garbage", h[2]!], answers)).rejects.toThrow();
  });
});

describe("passwords", () => {
  test("password policy and hashing", async () => {
    expect(checkPasswordPolicy("short")).toBe("too_short");
    expect(checkPasswordPolicy("long enough!")).toBe("ok");
    const h = await hashPassword("correct horse battery");
    expect(h).not.toContain("correct horse");
    expect(await verifyPassword(h, "correct horse battery")).toBe(true);
    expect(await verifyPassword(h, "wrong horse battery")).toBe(false);
  });

  test("the minimum length is exact and counts characters, not bytes", () => {
    expect(checkPasswordPolicy("a".repeat(MIN_PASSWORD_LENGTH - 1))).toBe("too_short");
    expect(checkPasswordPolicy("a".repeat(MIN_PASSWORD_LENGTH))).toBe("ok");
    expect(checkPasswordPolicy("é".repeat(MIN_PASSWORD_LENGTH - 1))).toBe("too_short");
    // Five emoji are 10 UTF-16 units but only 5 characters.
    expect(checkPasswordPolicy("🙂".repeat(5))).toBe("too_short");
    expect(checkPasswordPolicy("🙂".repeat(MIN_PASSWORD_LENGTH))).toBe("ok");
  });

  test("hashes are salted argon2id strings", async () => {
    const a = await hashPassword("correct horse battery");
    const b = await hashPassword("correct horse battery");
    expect(a.startsWith("$argon2id$")).toBe(true);
    expect(a).not.toBe(b);
  });

  // A broken stored hash must not look like a wrong password: callers count wrong passwords toward a lock.
  test("a hash that cannot be read is an error, not a wrong password", async () => {
    await expect(verifyPassword("not-a-hash", "correct horse battery")).rejects.toThrow();
    await expect(verifyPassword("", "correct horse battery")).rejects.toThrow();
  });
});

describe("locks", () => {
  test("five wrong passwords lock sign-in for five minutes", () => {
    let s = { failures: 0, lockedUntil: null as Date | null };
    for (let i = 0; i < 4; i++) s = registerFailure("signin", s, t0, 5 * 60_000);
    expect(isLocked(s, t0)).toBe(false);
    expect(triesLeft(s)).toBe(1);
    s = registerFailure("signin", s, t0, 5 * 60_000);
    expect(isLocked(s, t0)).toBe(true);
    expect(isLocked(s, new Date(t0.getTime() + 5 * 60_000 - 1))).toBe(true);
    expect(isLocked(s, new Date(t0.getTime() + 5 * 60_000))).toBe(false);
  });

  test("one wrong answer locks reset", () => {
    expect(isLocked(registerFailure("reset", { failures: 0, lockedUntil: null }, t0, 5 * 60_000), t0)).toBe(true);
  });

  test("each wrong password counts down the tries left", () => {
    let s = none;
    expect(triesLeft(s)).toBe(MAX_WRONG_PASSWORDS);
    s = registerFailure("signin", s, t0, LOCK_MS);
    expect(s).toEqual({ failures: 1, lockedUntil: null });
    expect(triesLeft(s)).toBe(MAX_WRONG_PASSWORDS - 1);
  });

  test("locking resets the count and uses the length the caller passes", () => {
    let s = none;
    for (let i = 0; i < MAX_WRONG_PASSWORDS; i++) s = registerFailure("signin", s, t0, 7_000);
    expect(s).toEqual({ failures: 0, lockedUntil: new Date(t0.getTime() + 7_000) });
    expect(registerFailure("reset", none, t0, 9_000).lockedUntil).toEqual(new Date(t0.getTime() + 9_000));
  });

  test("a failure after the lock ran out starts a fresh count", () => {
    let s = none;
    for (let i = 0; i < MAX_WRONG_PASSWORDS; i++) s = registerFailure("signin", s, t0, LOCK_MS);
    const later = new Date(t0.getTime() + LOCK_MS);
    expect(registerFailure("signin", s, later, LOCK_MS)).toEqual({ failures: 1, lockedUntil: null });
  });

  test("attempts made during a lock neither count nor extend it", () => {
    let s = none;
    for (let i = 0; i < MAX_WRONG_PASSWORDS; i++) s = registerFailure("signin", s, t0, LOCK_MS);
    const during = new Date(t0.getTime() + 60_000);
    expect(registerFailure("signin", s, during, LOCK_MS)).toEqual(s);
    expect(registerFailure("reset", s, during, LOCK_MS)).toEqual(s);
  });

  test("an unknown username has no lock until it fails", () => {
    const db = openDb();
    expect(readLock(db, "nobody", "signin")).toEqual(none);
  });

  test("locks are stored per username and kind, ignoring case, and can be cleared", () => {
    const db = openDb();
    const locked: LockState = { failures: 0, lockedUntil: new Date(t0.getTime() + LOCK_MS) };
    writeLock(db, "Owner", "signin", { failures: 3, lockedUntil: null });
    expect(readLock(db, "OWNER", "signin")).toEqual({ failures: 3, lockedUntil: null });
    expect(readLock(db, "owner", "reset")).toEqual(none);

    writeLock(db, "owner", "signin", locked);
    expect(readLock(db, "Owner", "signin")).toEqual(locked);
    expect(db.prepare("SELECT COUNT(*) AS n FROM auth_locks").get()).toEqual({ n: 1 });

    writeLock(db, "owner", "reset", locked);
    clearLock(db, "OWNER", "signin");
    expect(readLock(db, "owner", "signin")).toEqual(none);
    expect(readLock(db, "owner", "reset")).toEqual(locked);
  });

  test("a stored lock still holds when read back", () => {
    const db = openDb();
    const s = registerFailure("reset", none, t0, LOCK_MS);
    writeLock(db, "owner", "reset", s);
    expect(isLocked(readLock(db, "owner", "reset"), new Date(t0.getTime() + 1_000))).toBe(true);
  });
});

describe("sessions", () => {
  test("sessions expire and can be revoked", () => {
    const db = openDb();
    const id = seedOwner(db);
    const s = createSession(db, id, false, 30, t0);
    expect(findSession(db, s.token, t0)?.accountId).toBe(id);
    expect(findSession(db, s.token, new Date(t0.getTime() + 12 * 3600_000 + 1))).toBeNull();
    const p = createSession(db, id, true, 30, t0);
    expect(findSession(db, p.token, new Date(t0.getTime() + 29 * 86400_000))?.persistent).toBe(true);
    revokeSession(db, p.token);
    expect(findSession(db, p.token, t0)).toBeNull();
    expect(db.prepare("select token_hash from sessions").all().some((r: any) => r.token_hash === p.token)).toBe(
      false,
    ); // only hashes stored
  });

  test("tokens are 32 random bytes and only their SHA-256 is stored", () => {
    const db = openDb();
    const id = seedOwner(db);
    const a = createSession(db, id, false, 30, t0);
    const b = createSession(db, id, false, 30, t0);
    expect(a.token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(a.token).not.toBe(b.token);
    const stored = db.prepare("SELECT token_hash FROM sessions").all() as {
      token_hash: string;
    }[];
    expect(stored.map((r) => r.token_hash).sort()).toEqual(
      [a.token, b.token].map((t) => createHash("sha256").update(t).digest("hex")).sort(),
    );
  });

  test("a browser session lasts 12 hours and a kept one lasts the chosen days", () => {
    const db = openDb();
    const id = seedOwner(db);
    expect(createSession(db, id, false, 30, t0).expiresAt).toEqual(new Date(t0.getTime() + 12 * 3600_000));
    expect(createSession(db, id, true, 7, t0).expiresAt).toEqual(new Date(t0.getTime() + 7 * 86400_000));
    expect(createSession(db, id, true, 90, t0).expiresAt).toEqual(new Date(t0.getTime() + 90 * 86400_000));
  });

  test("a session ends at the instant it expires, and its row is removed", () => {
    const db = openDb();
    const id = seedOwner(db);
    const s = createSession(db, id, false, 30, t0);
    const end = new Date(t0.getTime() + 12 * 3600_000);
    expect(findSession(db, s.token, new Date(end.getTime() - 1))).toEqual({ accountId: id, persistent: false });
    expect(sessionCount(db)).toBe(1);
    expect(findSession(db, s.token, end)).toBeNull();
    expect(sessionCount(db)).toBe(0);
  });

  test("an unknown token finds nothing", () => {
    const db = openDb();
    seedOwner(db);
    expect(findSession(db, "x".repeat(43), t0)).toBeNull();
    expect(findSession(db, "", t0)).toBeNull();
  });

  test("revoking all sessions can spare the one in use", () => {
    const db = openDb();
    const id = seedOwner(db);
    const other = insertAccount(db, "second");
    const keep = createSession(db, id, false, 30, t0);
    const drop1 = createSession(db, id, true, 30, t0);
    const drop2 = createSession(db, id, false, 30, t0);
    const unrelated = createSession(db, other, false, 30, t0);

    revokeAllSessions(db, id, keep.token);
    expect(findSession(db, keep.token, t0)).not.toBeNull();
    expect(findSession(db, drop1.token, t0)).toBeNull();
    expect(findSession(db, drop2.token, t0)).toBeNull();
    expect(findSession(db, unrelated.token, t0)).not.toBeNull();

    revokeAllSessions(db, id);
    expect(findSession(db, keep.token, t0)).toBeNull();
    expect(findSession(db, unrelated.token, t0)).not.toBeNull();
  });
});

describe("accounts", () => {
  const input = {
    username: "Owner",
    displayName: "The Owner",
    passwordHash: "password-hash",
    answerHashes: ["h1", "h2", "h3"],
  };

  test("no accounts at first, then one owner", () => {
    const db = openDb();
    expect(countAccounts(db)).toBe(0);
    const account = createOwner(db, input, t0);
    expect(countAccounts(db)).toBe(1);
    expect(account).toEqual({
      id: expect.any(Number),
      username: "Owner",
      displayName: "The Owner",
      role: "owner",
      hasAvatar: false,
      passwordHash: "password-hash",
      answerHashes: ["h1", "h2", "h3"],
    });
  });

  test("accounts are found by id and by username in any case", () => {
    const db = openDb();
    const account = createOwner(db, input, t0);
    expect(findById(db, account.id)).toEqual(account);
    expect(findByUsername(db, "owner")).toEqual(account);
    expect(findByUsername(db, "OWNER")).toEqual(account);
    expect(findById(db, account.id + 1)).toBeNull();
    expect(findByUsername(db, "someone-else")).toBeNull();
  });

  test("hasAvatar follows whether a picture is stored", () => {
    const db = openDb();
    const account = createOwner(db, input, t0);
    db.prepare("UPDATE accounts SET avatar = ?, avatar_type = 'image/png' WHERE id = ?").run(
      Buffer.from([1, 2, 3]),
      account.id,
    );
    expect(findById(db, account.id)?.hasAvatar).toBe(true);
  });

  test("the creation time is stored as an ISO string", () => {
    const db = openDb();
    const account = createOwner(db, input, t0);
    expect(db.prepare("SELECT created_at FROM accounts WHERE id = ?").get(account.id)).toEqual({
      created_at: "2026-10-18T12:00:00.000Z",
    });
  });

  test("a second owner can never be created", () => {
    const db = openDb();
    createOwner(db, input, t0);
    let thrown: unknown;
    try {
      createOwner(db, { ...input, username: "intruder" }, t0);
    } catch (error) {
      thrown = error;
    }
    expect(thrown).toBeInstanceOf(AccountExistsError);
    expect(countAccounts(db)).toBe(1);
    expect(findByUsername(db, "intruder")).toBeNull();
  });

  test("an account with an unknown role is refused, never treated as the owner", () => {
    const db = openDb();
    const id = insertAccount(db, "guest");
    db.prepare("UPDATE accounts SET role = 'admin' WHERE id = ?").run(id);
    expect(() => findById(db, id)).toThrow(/role/i);
    expect(() => findByUsername(db, "guest")).toThrow(/role/i);
  });
});
