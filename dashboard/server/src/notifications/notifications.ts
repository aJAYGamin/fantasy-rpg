import type { Notification, NotificationKind, NotificationList } from "../../../shared/src/api.js";
import type { Db } from "../db/database.js";

export type { NotificationKind };

// New notifications start unread.
export function addNotification(
  db: Db,
  accountId: number,
  kind: NotificationKind,
  title: string,
  body: string,
  now: Date,
): void {
  db.prepare("INSERT INTO notifications (account_id, kind, title, body, created_at) VALUES (?, ?, ?, ?, ?)").run(
    accountId,
    kind,
    title,
    body,
    now.toISOString(),
  );
}

const LIST_LIMIT = 100;

type NotificationRow = {
  id: number;
  kind: NotificationKind;
  title: string;
  body: string;
  created_at: string;
  read_at: string | null;
};

// Newest first, at most LIST_LIMIT. Notifications of a kind that is switched off are still listed (they stay stored),
// but `unread` only counts the kinds in `counted`, and counts all of them, not just the ones listed.
export function listNotifications(db: Db, accountId: number, counted: readonly NotificationKind[]): NotificationList {
  const items = db
    .prepare<[number, number], NotificationRow>(
      `SELECT id, kind, title, body, created_at, read_at FROM notifications
       WHERE account_id = ? ORDER BY id DESC LIMIT ?`,
    )
    .all(accountId, LIST_LIMIT)
    .map(
      (row): Notification => ({
        id: row.id,
        kind: row.kind,
        title: row.title,
        body: row.body,
        createdAt: row.created_at,
        read: row.read_at !== null,
      }),
    );
  if (counted.length === 0) return { items, unread: 0 };
  const marks = counted.map(() => "?").join(", ");
  const { unread } = db
    .prepare<(number | string)[], { unread: number }>(
      `SELECT COUNT(*) AS unread FROM notifications WHERE account_id = ? AND read_at IS NULL AND kind IN (${marks})`,
    )
    .get(accountId, ...counted) as { unread: number };
  return { items, unread };
}

// False when this account has no such notification. One that is already read stays as it was.
export function markRead(db: Db, accountId: number, id: number, now: Date): boolean {
  const result = db
    .prepare("UPDATE notifications SET read_at = COALESCE(read_at, ?) WHERE id = ? AND account_id = ?")
    .run(now.toISOString(), id, accountId);
  return result.changes > 0;
}

export function markAllRead(db: Db, accountId: number, now: Date): void {
  db.prepare("UPDATE notifications SET read_at = ? WHERE account_id = ? AND read_at IS NULL").run(
    now.toISOString(),
    accountId,
  );
}
