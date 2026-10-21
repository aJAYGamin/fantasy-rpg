import type { ReactNode } from "react";
import styles from "./PageHeader.module.css";

export type PageHeaderProps = {
  /** The page's name, written normally ("Party"); it shows in capitals. */
  title: string;
  /** The trail after "Dashboard", ending with this page, e.g. ["Debug", "Party"]. */
  crumbs: string[];
  /** What sits at the right end: mini-stats, or a status pill. */
  right?: ReactNode;
};

/** The top of every signed-in page: its title, where it sits ("Dashboard / Debug / Party"), and an optional extra. */
export function PageHeader({ title, crumbs, right }: PageHeaderProps) {
  return (
    // A div, not <header>: the page's only banner is the top bar.
    <div className={styles.header}>
      <div className={styles.titles}>
        <h1 className={styles.title}>{title}</h1>
        <p className={styles.crumbs}>{["Dashboard", ...crumbs].join(" / ")}</p>
      </div>
      {right !== undefined && <div className={styles.right}>{right}</div>}
    </div>
  );
}
