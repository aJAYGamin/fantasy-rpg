import { afterEach, expect, test } from "vitest";
import { type Db, openDatabase } from "../src/db/database.js";
import { insertAccount, tmpFile } from "./helpers.js";

const opened: Db[] = [];

afterEach(() => {
  for (const db of opened.splice(0)) db.close();
});

function openDb(path: string): Db {
  const db = openDatabase(path);
  opened.push(db);
  return db;
}

function count(db: Db, table: string): number {
  return (db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get() as { n: number }).n;
}

test("a new database gets every table", () => {
  const db = openDb(":memory:");
  const names = db
    .prepare<[], { name: string }>("SELECT name FROM sqlite_master WHERE type = 'table'")
    .all()
    .map((row) => row.name);
  for (const table of ["accounts", "sessions", "auth_locks", "settings", "notifications", "schema_migrations"]) {
    expect(names).toContain(table);
  }
});

test("opening twice applies migrations once", () => {
  const file = tmpFile();
  openDb(file).close();
  const db = openDb(file);
  expect(db.prepare("SELECT COUNT(*) AS n FROM schema_migrations").get()).toEqual({ n: 2 });
});

test("a database from before the wrong-password count gains it, keeping its sessions", () => {
  const file = tmpFile();
  const old = openDb(file);
  const id = insertAccount(old, "owner");
  const now = new Date().toISOString();
  old
    .prepare("INSERT INTO sessions (token_hash, account_id, persistent, expires_at, created_at) VALUES (?, ?, 0, ?, ?)")
    .run("token-hash", id, now, now);
  // Make it look like migration 1 is the last one that ever ran.
  old.exec("ALTER TABLE sessions DROP COLUMN wrong_passwords; DELETE FROM schema_migrations WHERE version = 2;");
  old.close();

  const upgraded = openDb(file);
  expect(upgraded.prepare("SELECT token_hash, wrong_passwords FROM sessions").all()).toEqual([
    { token_hash: "token-hash", wrong_passwords: 0 },
  ]);
  expect(upgraded.prepare("SELECT COUNT(*) AS n FROM schema_migrations").get()).toEqual({ n: 2 });
});

test("usernames are unique regardless of case", () => {
  const db = openDb(":memory:");
  insertAccount(db, "owner");
  expect(() => insertAccount(db, "OWNER")).toThrow();
});

test("a file database uses WAL and enforces foreign keys", () => {
  const db = openDb(tmpFile());
  expect(db.pragma("journal_mode", { simple: true })).toBe("wal");
  expect(db.pragma("foreign_keys", { simple: true })).toBe(1);
});

test("deleting an account removes its sessions and settings", () => {
  const db = openDb(":memory:");
  const id = insertAccount(db, "owner");
  const now = new Date().toISOString();
  db.prepare(
    "INSERT INTO sessions (token_hash, account_id, persistent, expires_at, created_at) VALUES (?, ?, 0, ?, ?)",
  ).run("token-hash", id, now, now);
  db.prepare("INSERT INTO settings (account_id, json) VALUES (?, '{}')").run(id);

  db.prepare("DELETE FROM accounts WHERE id = ?").run(id);

  expect(count(db, "sessions")).toBe(0);
  expect(count(db, "settings")).toBe(0);
});
