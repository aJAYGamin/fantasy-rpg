// The username rule, shared by the server (which enforces it) and the forms (which check it before sending).
import { USERNAME_MAX, USERNAME_MIN } from "./constants.js";

// Keyboards and phones often turn a typed ' or " into its curly form; either way it is the same name.
const CURLY_SINGLE = /[‘’]/g;
const CURLY_DOUBLE = /[“”]/g;
const SPACE_RUN = /\p{Zs}+/gu;

// Anything that draws nothing, or breaks the line, could make two names look identical: control and format
// characters (tabs, line breaks, zero-width spaces and joiners, soft hyphens), private-use and unassigned code
// points, and the other characters Unicode says to render as nothing (such as the Hangul fillers).
const INVISIBLE = /[\p{C}\p{Zl}\p{Zp}\p{Default_Ignorable_Code_Point}]/u;

/**
 * A typed username in the form it is stored and looked up in: NFKC (an accent typed as one character or two is the
 * same), curly quotes made straight, spaces at the ends dropped and a run of spaces inside made one. Capitals are kept;
 * sign-in ignores them through the database's case-insensitive column.
 */
export function cleanUsername(typed: string): string {
  return typed
    .normalize("NFKC")
    .replace(CURLY_SINGLE, "'")
    .replace(CURLY_DOUBLE, '"')
    .trim()
    .replace(SPACE_RUN, " ");
}

/** Whether an already cleaned name is a username: 3 to 32 characters (an emoji is one), none of them invisible. */
export function isUsername(cleaned: string): boolean {
  const length = [...cleaned].length;
  return length >= USERNAME_MIN && length <= USERNAME_MAX && !INVISIBLE.test(cleaned);
}
