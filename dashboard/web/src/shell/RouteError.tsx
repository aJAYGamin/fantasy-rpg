import { Button, Card } from "../components";
import styles from "./CenteredNotice.module.css";

/** Shown in place of any page that crashed while rendering. */
export function RouteError() {
  return (
    <main className={styles.page}>
      <Card className={styles.card}>
        <h1 className={styles.title}>Something went wrong</h1>
        <p className={styles.text}>This page hit a problem it couldn't recover from. Reloading usually fixes it.</p>
        <Button variant="primary" onClick={() => window.location.reload()}>
          Reload
        </Button>
      </Card>
    </main>
  );
}
