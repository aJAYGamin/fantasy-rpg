import styles from "./NotificationsPanel.module.css";

export type NotificationsPanelProps = {
  /** Closes the panel (and puts the focus back on the bell). */
  onClose: () => void;
};

// Stand-in until the notifications list arrives (Task 9 replaces this file); the bell already opens it.
export function NotificationsPanel(_props: NotificationsPanelProps) {
  return (
    <div className={styles.panel}>
      <h2 className={styles.title}>Notifications</h2>
      <p className={styles.note}>Your notifications will show here.</p>
    </div>
  );
}
