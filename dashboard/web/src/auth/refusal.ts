import { ApiFailure } from "../api/client";

/** The server's refusal inside a mutation's error, or null when there was no error or it wasn't a refusal. */
export const refusalOf = (error: unknown): ApiFailure | null => (error instanceof ApiFailure ? error : null);

/**
 * When a pause ends, if this refusal is one of `codes` and carries a real time; otherwise null. The server gives
 * the time on its own clock; the Date returned is on this computer's, so a countdown to it is right even when
 * the two clocks disagree.
 */
export function pauseEnd(refusal: ApiFailure | null, codes: readonly string[]): Date | null {
  if (refusal === null || !codes.includes(refusal.body.error) || !refusal.body.lockedUntil) return null;
  const end = Date.parse(refusal.body.lockedUntil);
  return Number.isNaN(end) ? null : new Date(end - refusal.clockOffset);
}
