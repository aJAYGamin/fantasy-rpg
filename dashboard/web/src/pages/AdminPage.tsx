import { Shield } from "lucide-react";
import { Card } from "../components";
import { usePageTitle } from "../pageTitle";
import { PageHeader } from "../shell/PageHeader";
import styles from "./AdminPage.module.css";

/**
 * Admin is empty until the owner decides what it should hold. The page reads nothing from the game, so it looks the
 * same whether or not the game is connected.
 */
export function AdminPage() {
  usePageTitle("Admin");
  return (
    <>
      <PageHeader title="Admin" crumbs={["Admin"]} />
      <Card flush className={styles.card}>
        <div className={styles.content}>
          <div className={styles.icon}>
            <Shield aria-hidden="true" />
          </div>
          <h2 className={styles.title}>In development</h2>
          <p className={styles.text}>Admin tools will appear here once you decide what they should be.</p>
        </div>
      </Card>
    </>
  );
}
