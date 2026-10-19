import { Button, Card } from "../components";
import styles from "./CenteredNotice.module.css";

/** Shown instead of any page when the dashboard's own server doesn't answer. */
export function ServerUnreachable({ onRetry }: { onRetry: () => void }) {
  return (
    <main className={styles.page}>
      <Card className={styles.card}>
        <h1 className={styles.title}>Can't reach the dashboard's server</h1>
        <p className={styles.text}>Check that it's running, then try again.</p>
        <Button variant="primary" onClick={onRetry}>
          Try again
        </Button>
      </Card>
    </main>
  );
}
