import { ApiFailure } from "../api/client";

/** The server's refusal inside a mutation's error, or null when there was no error or it wasn't a refusal. */
export const refusalOf = (error: unknown): ApiFailure | null => (error instanceof ApiFailure ? error : null);

/** When a pause ends, if this refusal is one of `codes` and carries a real time; otherwise null. */
export function pauseEnd(refusal: ApiFailure | null, codes: readonly string[]): Date | null {
  if (refusal === null || !codes.includes(refusal.body.error) || !refusal.body.lockedUntil) return null;
  const end = new Date(refusal.body.lockedUntil);
  return Number.isNaN(end.getTime()) ? null : end;
}
