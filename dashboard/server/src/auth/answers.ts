import { hashPassword, verifyPassword } from "./passwords.js";

export type Answers = [string, string, string];

// Trim, lower-case, and squash runs of whitespace, so "  New   York " matches "new york".
export function normalizeAnswer(a: string): string {
  return a.trim().toLowerCase().replace(/\s+/g, " ");
}

export function hashAnswers(a: Answers): Promise<string[]> {
  return Promise.all(a.map((answer) => hashPassword(normalizeAnswer(answer))));
}

// All three are always checked, so the result (and the time taken) never reveals which one was wrong first.
// A blank answer or a missing hash never matches.
export function verifyAnswers(hashes: string[], a: Answers): Promise<boolean[]> {
  return Promise.all(
    a.map(async (answer, i) => {
      const normalized = normalizeAnswer(answer);
      const stored = hashes[i];
      if (normalized === "" || stored === undefined) return false;
      return verifyPassword(stored, normalized);
    }),
  );
}
