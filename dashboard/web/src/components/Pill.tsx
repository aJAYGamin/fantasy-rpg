import type { ReactNode } from "react";
import styles from "./Pill.module.css";
import { cx } from "./cx";

export type PillTone = "ok" | "am" | "warn" | "bad" | "neutral";

/** A small rounded status label (the mockups' .pill), e.g. "● Connected" or "○ Waiting for the game". */
export function Pill({ tone = "neutral", className, children }: { tone?: PillTone; className?: string; children: ReactNode }) {
  return <span className={cx(styles.pill, styles[tone], className)}>{children}</span>;
}
