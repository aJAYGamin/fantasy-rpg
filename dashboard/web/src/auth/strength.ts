import { MIN_PASSWORD_LENGTH } from "../../../shared/src/constants";

export type Strength = 0 | 1 | 2 | 3 | 4;

/** What each step is called; step 0 (nothing typed yet) has no name. */
export const STRENGTH_WORDS = ["", "Weak", "Okay", "Good", "Strong"] as const;

const KINDS = [/\p{Ll}/u, /\p{Lu}/u, /\p{Nd}/u, /[^\p{L}\p{Nd}]/u];

/**
 * A rough guide for the meter, not a promise: 0 for nothing typed, then 1 to 4. Length matters most, counted in
 * characters as a person sees them (the same count the server enforces). Repeating a character adds little, so
 * each distinct character counts twice at most; mixing three kinds of character earns one more step. Passwords
 * under the minimum length are always 1.
 */
export function passwordStrength(password: string): Strength {
  const characters = [...password];
  if (characters.length === 0) return 0;
  const counted = Math.min(characters.length, new Set(characters).size * 2);
  if (counted < MIN_PASSWORD_LENGTH) return 1;
  const base = counted >= 20 ? 4 : counted >= 14 ? 3 : 2;
  const mixed = KINDS.filter((kind) => kind.test(password)).length >= 3;
  return Math.min(4, base + (mixed ? 1 : 0)) as Strength;
}
