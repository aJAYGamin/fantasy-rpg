import { Gamepad2, type LucideIcon, ShieldAlert, Sparkles } from "lucide-react";
import type { Notification, NotificationKind } from "../../../shared/src/api";
import { useMarkAllNotificationsRead, useMarkNotificationRead, useNotifications } from "../api/hooks";
import { cx } from "../components/cx";
import styles from "./NotificationsPanel.module.css";
import { relativeTime, useNow } from "./relativeTime";

const KIND_ICONS: Record<NotificationKind, LucideIcon> = {
  security: ShieldAlert,
  game: Gamepad2,
  changes: Sparkles,
};

function fullDate(iso: string): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
}

/**
 * The bell's panel: the newest notifications with a button to mark them all read. Opening one marks it read (nothing
 * to go to yet in stage 1). Unread ones have a dot; the times count on while the panel is open.
 */
export function NotificationsPanel() {
  const { data, isError } = useNotifications();
  const markRead = useMarkNotificationRead();
  const markAll = useMarkAllNotificationsRead();
  const now = useNow();

  const items = data?.items ?? [];
  const anyUnread = (data?.unread ?? 0) > 0 || items.some((item) => !item.read);
  const refused = markRead.isError || markAll.isError;

  // A fresh try starts clean: the other button's last refusal is no longer news.
  function attempt(send: () => void) {
    markRead.reset();
    markAll.reset();
    send();
  }

  return (
    <div className={styles.panel}>
      <div className={styles.header}>
        <h2 className={styles.title}>Notifications</h2>
        {/* aria-disabled, not disabled: a focused button that goes dead would take the focus (and the panel) with it. */}
        <button
          type="button"
          className={styles.markAll}
          aria-disabled={!anyUnread || undefined}
          onClick={() => anyUnread && attempt(() => markAll.mutate())}
        >
          Mark all as read
        </button>
      </div>

      {refused && (
        <p role="alert" className={styles.error}>
          Couldn't update your notifications. Try again.
        </p>
      )}

      {data === undefined ? (
        <p className={styles.empty}>{isError ? "Couldn't load your notifications." : "Loading…"}</p>
      ) : items.length === 0 ? (
        <p className={styles.empty}>You're all caught up.</p>
      ) : (
        <ul className={styles.list}>
          {items.map((item) => (
            <li key={item.id}>
              <Row item={item} now={now} onOpen={() => !item.read && attempt(() => markRead.mutate(item.id))} />
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function Row({ item, now, onOpen }: { item: Notification; now: number; onOpen: () => void }) {
  const Icon = KIND_ICONS[item.kind];
  return (
    <button type="button" className={cx(styles.row, !item.read && styles.unread)} onClick={onOpen}>
      <span className={cx(styles.icon, styles[item.kind])}>
        <Icon />
      </span>
      <span className={styles.text}>
        <span className={styles.rowTitle}>
          {!item.read && <span className="visually-hidden">Unread</span>} {item.title}
        </span>{" "}
        <span className={styles.body}>{item.body}</span>{" "}
        <time className={styles.time} dateTime={item.createdAt} title={fullDate(item.createdAt)}>
          {relativeTime(item.createdAt, now)}
        </time>
      </span>
      {!item.read && <span className={styles.dot} aria-hidden="true" />}
    </button>
  );
}
