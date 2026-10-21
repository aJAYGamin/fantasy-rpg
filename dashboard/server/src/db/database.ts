import Database from "better-sqlite3";
import { runMigrations } from "./migrations.js";

export type Db = import("better-sqlite3").Database;

// WAL keeps reads and writes from blocking each other; foreign keys must be on for the ON DELETE CASCADEs to work.
export function openDatabase(path: string): Db {
  const db = new Database(path);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");
  runMigrations(db);
  return db;
}
