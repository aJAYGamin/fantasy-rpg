import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach } from "vitest";
import { createOwner } from "../src/auth/accounts.js";
import type { Db } from "../src/db/database.js";

// Every tmpFile() gets its own folder under the OS temp folder; all are removed after each test.
const folders: string[] = [];

afterEach(() => {
  for (const folder of folders.splice(0)) rmSync(folder, { recursive: true, force: true });
});

export function tmpFile(name = "amethyst.db"): string {
  const folder = mkdtempSync(join(tmpdir(), "amethyst-test-"));
  folders.push(folder);
  return join(folder, name);
}

// A minimal accounts row. The hashes are placeholders: database tests never check a password.
export function insertAccount(db: Db, username: string): number {
  const result = db
    .prepare(
      "INSERT INTO accounts (username, display_name, password_hash, answer_hashes, role, created_at) VALUES (?, ?, ?, ?, 'owner', ?)",
    )
    .run(username, username, "placeholder-hash", JSON.stringify(["a", "b", "c"]), new Date().toISOString());
  return Number(result.lastInsertRowid);
}

// The one owner account with placeholder hashes, for tests that need an account but never sign in as it.
export function seedOwner(db: Db): number {
  return createOwner(
    db,
    { username: "owner", displayName: "Owner", passwordHash: "placeholder-hash", answerHashes: ["a", "b", "c"] },
    new Date(),
  ).id;
}
