import { hash, verify } from "@node-rs/argon2";
import { MIN_PASSWORD_LENGTH } from "../../../shared/src/constants.js";

// The one place a password is normalized (R42), so setup, sign-in, reset and a change all agree: Unicode NFKC, so an
// accent typed as one character or as letter-plus-combining-mark, and full-width or other look-alike forms, are the
// same password. Nothing else: no trimming and no case-folding, since every character typed is part of a password.
// Security answers come through hashPassword and verifyPassword too, already normalized more thoroughly by
// normalizeAnswer; this step runs again both when an answer is hashed and when it is checked, so the two agree.
export function normalizePassword(pw: string): string {
  return pw.normalize("NFKC");
}

// Counts characters as a person sees them (code points of the normalized form), so an emoji is one, not two, and an
// accent typed as a separate mark doesn't count twice.
export function checkPasswordPolicy(pw: string): "ok" | "too_short" {
  return [...normalizePassword(pw)].length < MIN_PASSWORD_LENGTH ? "too_short" : "ok";
}

// The library's defaults are argon2id with a fresh random salt and the OWASP-recommended cost.
export function hashPassword(pw: string): Promise<string> {
  return hash(normalizePassword(pw));
}

// Resolves false only for a wrong password. A stored hash the library cannot read makes it reject, on purpose: that
// is a broken account row (an error to surface), and must never look like a wrong password, because callers count
// wrong passwords toward a lock and would lock the owner out of their own account.
export async function verifyPassword(hashed: string, pw: string): Promise<boolean> {
  return verify(hashed, normalizePassword(pw));
}
