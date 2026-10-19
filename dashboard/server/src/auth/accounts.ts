import type { Db } from "../db/database.js";

export type Account = {
  id: number;
  username: string;
  displayName: string;
  role: "owner";
  hasAvatar: boolean;
  passwordHash: string;
  answerHashes: string[];
};

type AccountRow = {
  id: number;
  username: string;
  role: string;
  display_name: string;
  password_hash: string;
  answer_hashes: string;
  has_avatar: number;
};

// has_avatar is computed in SQL so the picture itself is never loaded just to know whether there is one.
const SELECT_ACCOUNT = `SELECT id, username, role, display_name, password_hash, answer_hashes,
  avatar IS NOT NULL AS has_avatar FROM accounts`;

// Thrown by createOwner when setup has already happened.
export class AccountExistsError extends Error {
  constructor() {
    super("An account already exists");
    this.name = "AccountExistsError";
  }
}

// "owner" is the only role for now. Anything else in the row is a fault to surface, not to treat as the owner.
function parseRole(role: string): "owner" {
  if (role !== "owner") throw new Error(`Unknown account role "${role}"`);
  return role;
}

function toAccount(row: AccountRow): Account {
  return {
    id: row.id,
    username: row.username,
    displayName: row.display_name,
    role: parseRole(row.role),
    hasAvatar: row.has_avatar === 1,
    passwordHash: row.password_hash,
    answerHashes: JSON.parse(row.answer_hashes) as string[],
  };
}

export function countAccounts(db: Db): number {
  return (db.prepare<[], { n: number }>("SELECT COUNT(*) AS n FROM accounts").get() as { n: number }).n;
}

export function findById(db: Db, id: number): Account | null {
  const row = db.prepare<[number], AccountRow>(`${SELECT_ACCOUNT} WHERE id = ?`).get(id);
  return row ? toAccount(row) : null;
}

// The username column is case-insensitive, so "Owner" and "owner" are the same account.
export function findByUsername(db: Db, username: string): Account | null {
  const row = db.prepare<[string], AccountRow>(`${SELECT_ACCOUNT} WHERE username = ?`).get(username);
  return row ? toAccount(row) : null;
}

// Setup is a one-time step. The check and the insert share one transaction, so two sign-up requests that overlap
// while their passwords are being hashed still cannot both succeed.
export function createOwner(
  db: Db,
  input: { username: string; displayName: string; passwordHash: string; answerHashes: string[] },
  now: Date,
): Account {
  const create = db.transaction((): number => {
    if (countAccounts(db) > 0) throw new AccountExistsError();
    const result = db
      .prepare(
        `INSERT INTO accounts (username, display_name, password_hash, answer_hashes, role, created_at)
         VALUES (?, ?, ?, ?, 'owner', ?)`,
      )
      .run(
        input.username,
        input.displayName,
        input.passwordHash,
        JSON.stringify(input.answerHashes),
        now.toISOString(),
      );
    return Number(result.lastInsertRowid);
  });
  return findById(db, create.immediate()) as Account;
}
