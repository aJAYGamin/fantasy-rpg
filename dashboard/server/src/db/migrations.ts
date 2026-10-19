import type { Db } from "./database.js";

interface Migration {
  version: number;
  sql: string;
}

// Append new migrations; never edit one that has shipped, since its version is already recorded.
const MIGRATIONS: readonly Migration[] = [
  {
    version: 1,
    sql: `
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY,
        username TEXT UNIQUE NOT NULL COLLATE NOCASE,
        display_name TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        answer_hashes TEXT NOT NULL,  -- JSON array of the three answer hashes
        role TEXT NOT NULL,           -- 'owner' for now
        avatar BLOB,
        avatar_type TEXT,
        created_at TEXT NOT NULL
      );

      CREATE TABLE sessions (
        token_hash TEXT PRIMARY KEY,  -- SHA-256 of the cookie token; the token itself is never stored
        account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        persistent INTEGER NOT NULL,
        expires_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      );

      -- Keyed by the typed username, so an unknown name locks exactly like a real one.
      CREATE TABLE auth_locks (
        username TEXT NOT NULL COLLATE NOCASE,
        kind TEXT NOT NULL,           -- 'signin' or 'reset'
        failures INTEGER NOT NULL,
        locked_until TEXT,
        PRIMARY KEY (username, kind)
      );

      CREATE TABLE settings (
        account_id INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
        json TEXT NOT NULL
      );

      CREATE TABLE notifications (
        id INTEGER PRIMARY KEY,
        account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        created_at TEXT NOT NULL,
        read_at TEXT
      );
    `,
  },
];

// Applies each migration that has not been recorded yet, each in its own transaction.
export function runMigrations(db: Db): void {
  db.exec(
    "CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT)",
  );
  const applied = new Set(
    db.prepare<[], { version: number }>("SELECT version FROM schema_migrations").all().map((row) => row.version),
  );
  const record = db.prepare("INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)");

  for (const migration of MIGRATIONS) {
    if (applied.has(migration.version)) continue;
    db.transaction(() => {
      db.exec(migration.sql);
      record.run(migration.version, new Date().toISOString());
    })();
  }
}
