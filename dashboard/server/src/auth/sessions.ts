import { createHash, randomBytes } from "node:crypto";
import { SESSION_HOURS_DEFAULT } from "../../../shared/src/constants.js";
import type { Db } from "../db/database.js";

const HOUR_MS = 3_600_000;
const DAY_MS = 24 * HOUR_MS;

// The token is 256 random bits, so a fast hash is enough: there is nothing to brute-force.
// Only this hash is stored, so a copy of the database cannot be used to sign in.
function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

export function createSession(
  db: Db,
  accountId: number,
  persistent: boolean,
  keepDays: number,
  now: Date,
): { token: string; expiresAt: Date } {
  const token = randomBytes(32).toString("base64url");
  const lifetimeMs = persistent ? keepDays * DAY_MS : SESSION_HOURS_DEFAULT * HOUR_MS;
  const expiresAt = new Date(now.getTime() + lifetimeMs);
  db.prepare(
    "INSERT INTO sessions (token_hash, account_id, persistent, expires_at, created_at) VALUES (?, ?, ?, ?, ?)",
  ).run(hashToken(token), accountId, persistent ? 1 : 0, expiresAt.toISOString(), now.toISOString());
  return { token, expiresAt };
}

// A session is good until its expiry instant; an expired one is deleted as it is found.
export function findSession(db: Db, token: string, now: Date): { accountId: number; persistent: boolean } | null {
  const tokenHash = hashToken(token);
  const row = db
    .prepare<[string], { account_id: number; persistent: number; expires_at: string }>(
      "SELECT account_id, persistent, expires_at FROM sessions WHERE token_hash = ?",
    )
    .get(tokenHash);
  if (!row) return null;
  if (now.getTime() >= new Date(row.expires_at).getTime()) {
    db.prepare("DELETE FROM sessions WHERE token_hash = ?").run(tokenHash);
    return null;
  }
  return { accountId: row.account_id, persistent: row.persistent === 1 };
}

export function revokeSession(db: Db, token: string): void {
  db.prepare("DELETE FROM sessions WHERE token_hash = ?").run(hashToken(token));
}

// Signs the account out everywhere, optionally sparing the session making the request.
export function revokeAllSessions(db: Db, accountId: number, exceptToken?: string): void {
  if (exceptToken === undefined) {
    db.prepare("DELETE FROM sessions WHERE account_id = ?").run(accountId);
  } else {
    db.prepare("DELETE FROM sessions WHERE account_id = ? AND token_hash != ?").run(accountId, hashToken(exceptToken));
  }
}

// Counts one wrong current password against this session. The `max`-th one ends the session ("ended"); "gone" means
// the session was already over. Runs without an await, so overlapping guesses cannot all be counted as the first.
export function registerWrongPassword(db: Db, token: string, max: number): "counted" | "ended" | "gone" {
  const tokenHash = hashToken(token);
  const row = db
    .prepare<[string], { wrong_passwords: number }>("SELECT wrong_passwords FROM sessions WHERE token_hash = ?")
    .get(tokenHash);
  if (!row) return "gone";
  const count = row.wrong_passwords + 1;
  if (count >= max) {
    db.prepare("DELETE FROM sessions WHERE token_hash = ?").run(tokenHash);
    return "ended";
  }
  db.prepare("UPDATE sessions SET wrong_passwords = ? WHERE token_hash = ?").run(count, tokenHash);
  return "counted";
}

// The right current password was typed: the count starts again. False when the session was already over.
export function clearWrongPasswords(db: Db, token: string): boolean {
  return db.prepare("UPDATE sessions SET wrong_passwords = 0 WHERE token_hash = ?").run(hashToken(token)).changes > 0;
}
