import { MAX_WRONG_PASSWORDS } from "../../../shared/src/constants.js";
import type { Db } from "../db/database.js";

export type LockKind = "signin" | "reset";
export type LockState = { failures: number; lockedUntil: Date | null };

export function isLocked(s: LockState, now: Date): boolean {
  return s.lockedUntil !== null && now.getTime() < s.lockedUntil.getTime();
}

// Returns the new state. Sign-in locks after MAX_WRONG_PASSWORDS wrong passwords in a row; reset locks on the first
// wrong answer. Callers pass config.lockMs. Attempts made while already locked change nothing, so hammering a locked
// account can neither push the unlock time back nor pre-load the next round of tries.
export function registerFailure(kind: LockKind, s: LockState, now: Date, lockMs: number): LockState {
  if (isLocked(s, now)) return s;
  const lockedUntil = new Date(now.getTime() + lockMs);
  if (kind === "reset") return { failures: 0, lockedUntil };
  const failures = s.failures + 1;
  if (failures >= MAX_WRONG_PASSWORDS) return { failures: 0, lockedUntil };
  return { failures, lockedUntil: null };
}

// Wrong passwords left before sign-in locks (meaningful for "signin" only).
export function triesLeft(s: LockState): number {
  return MAX_WRONG_PASSWORDS - s.failures;
}

// Keyed by the typed username (case-insensitive), so a name that has no account locks exactly like one that does.
export function readLock(db: Db, username: string, kind: LockKind): LockState {
  const row = db
    .prepare<[string, string], { failures: number; locked_until: string | null }>(
      "SELECT failures, locked_until FROM auth_locks WHERE username = ? AND kind = ?",
    )
    .get(username, kind);
  if (!row) return { failures: 0, lockedUntil: null };
  return { failures: row.failures, lockedUntil: row.locked_until === null ? null : new Date(row.locked_until) };
}

export function writeLock(db: Db, username: string, kind: LockKind, s: LockState): void {
  db.prepare(
    `INSERT INTO auth_locks (username, kind, failures, locked_until) VALUES (?, ?, ?, ?)
     ON CONFLICT (username, kind) DO UPDATE SET failures = excluded.failures, locked_until = excluded.locked_until`,
  ).run(username, kind, s.failures, s.lockedUntil === null ? null : s.lockedUntil.toISOString());
}

export function clearLock(db: Db, username: string, kind: LockKind): void {
  db.prepare("DELETE FROM auth_locks WHERE username = ? AND kind = ?").run(username, kind);
}
