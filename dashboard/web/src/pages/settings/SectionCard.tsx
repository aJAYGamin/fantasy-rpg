import type { ReactNode } from "react";
import { Alert } from "../../auth/Alert";
import { Card } from "../../components";
import styles from "./SectionCard.module.css";
import { SavedStatus } from "./SavedStatus";

export type SectionCardProps = {
  title: string;
  /** Whether "Saved" is showing beside the title. */
  saved?: boolean;
  /** Why the last change wasn't saved, if it wasn't. */
  problem?: string;
  children: ReactNode;
};

/** A card of Settings: the section's title, "Saved" beside it, a refusal above the rows, then the rows. */
export function SectionCard({ title, saved = false, problem, children }: SectionCardProps) {
  return (
    <Card title={title} actions={<SavedStatus saved={saved} />}>
      {problem !== undefined && (
        <Alert tone="bad" className={styles.problem}>
          {problem}
        </Alert>
      )}
      <div>{children}</div>
    </Card>
  );
}
