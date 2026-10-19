import { hashPassword, verifyPassword } from "./passwords.js";

export type Answers = [string, string, string];

// Unicode-normalizes first (NFKC), so an accent typed as one character or as letter-plus-combining-mark, and
// look-alike forms such as a no-break space, compare equal. Then trims, lower-cases, and squashes runs of whitespace,
// so "  New   York " matches "new york".
export function normalizeAnswer(a: string): string {
  return a.normalize("NFKC").trim().toLowerCase().replace(/\s+/g, " ");
}

export function hashAnswers(a: Answers): Promise<string[]> {
  return Promise.all(a.map((answer) => hashPassword(normalizeAnswer(answer))));
}

// All three are always checked, so the result (and the time taken) never reveals which one was wrong first.
// A blank answer never matches. A missing or unreadable stored hash rejects (see verifyPassword) instead of
// counting as a wrong answer.
export function verifyAnswers(hashes: string[], a: Answers): Promise<boolean[]> {
  return Promise.all(
    a.map(async (answer, i) => {
      const normalized = normalizeAnswer(answer);
      const stored = hashes[i];
      if (normalized === "") return false;
      if (stored === undefined) throw new Error("Stored answer hash is missing");
      return verifyPassword(stored, normalized);
    }),
  );
}
