import { hash, verify } from "@node-rs/argon2";
import { MIN_PASSWORD_LENGTH } from "../../../shared/src/constants.js";

// Counts characters as a person sees them (code points), so an emoji is one, not two.
export function checkPasswordPolicy(pw: string): "ok" | "too_short" {
  return [...pw].length < MIN_PASSWORD_LENGTH ? "too_short" : "ok";
}

// The library's defaults are argon2id with a fresh random salt and the OWASP-recommended cost.
export function hashPassword(pw: string): Promise<string> {
  return hash(pw);
}

// Resolves false only for a wrong password. A stored hash the library cannot read makes it reject, on purpose: that
// is a broken account row (an error to surface), and must never look like a wrong password, because callers count
// wrong passwords toward a lock and would lock the owner out of their own account.
export async function verifyPassword(hashed: string, pw: string): Promise<boolean> {
  return verify(hashed, pw);
}
