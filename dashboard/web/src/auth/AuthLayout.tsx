import type { ReactNode } from "react";
import { Card } from "../components";
import styles from "./AuthLayout.module.css";

// Placeholder until the sign-in screens are built: the form centred on the page.
export function AuthLayout({ children }: { children: ReactNode }) {
  return (
    <main className={styles.page}>
      <Card className={styles.card}>{children}</Card>
    </main>
  );
}
