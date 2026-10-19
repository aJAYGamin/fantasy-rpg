import { KEEP_SIGNED_IN_DAY_CHOICES } from "../../../shared/src/constants.js";
import type { Db } from "../db/database.js";

const DEFAULT_KEEP_SIGNED_IN_DAYS = 30;

// How many days "Keep me signed in" lasts for this account. Anything unusable in the saved settings (no row, bad JSON,
// a number that is not one of the offered choices) falls back to the default: a damaged preference must never be what
// stops the owner signing in, and a bad number must never become a session length.
export function readKeepSignedInDays(db: Db, accountId: number): number {
  const row = db.prepare<[number], { json: string }>("SELECT json FROM settings WHERE account_id = ?").get(accountId);
  if (!row) return DEFAULT_KEEP_SIGNED_IN_DAYS;
  let saved: unknown;
  try {
    saved = (JSON.parse(row.json) as { keepSignedInDays?: unknown } | null)?.keepSignedInDays;
  } catch {
    return DEFAULT_KEEP_SIGNED_IN_DAYS;
  }
  return KEEP_SIGNED_IN_DAY_CHOICES.find((days) => days === saved) ?? DEFAULT_KEEP_SIGNED_IN_DAYS;
}
