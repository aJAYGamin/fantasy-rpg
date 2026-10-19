import type { NotificationKind } from "../../../shared/src/api.js";
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
