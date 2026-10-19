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

// A stored hash that cannot be read counts as a wrong password, never as an error that skips the check.
export async function verifyPassword(hashed: string, pw: string): Promise<boolean> {
  try {
    return await verify(hashed, pw);
  } catch {
    return false;
  }
}
