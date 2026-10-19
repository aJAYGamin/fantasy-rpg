import { Outlet } from "react-router";
import styles from "./AppShell.module.css";

// Placeholder: the sidebar, top bar and page header arrive in a later task.
export function AppShell() {
  return (
    <main className={styles.main}>
      <Outlet />
    </main>
  );
}
