import type { CSSProperties, ReactNode } from "react";
import styles from "./Ring.module.css";
import { cx } from "./cx";

/** The token the filled part of the ring is drawn in. */
export type RingColor = "am" | "am2" | "gold" | "ok" | "warn" | "bad" | "aria" | "kael" | "lyra";

export type RingProps = {
  /** How full the ring is, 0–100 (kept within that range). */
  percent: number;
  /** What sits in the middle: "72%", "9", a Countdown. */
  label: ReactNode;
  color?: RingColor;
  /** md: the stat strip's 46 px gauge; lg: the lock screen's 120 px countdown ring. */
  size?: "md" | "lg";
  /** What the ring measures, for screen readers ("Party HP"). Required: a gauge with no name says nothing. */
  "aria-label": string;
  /**
   * The value in words, when the center says more than a percentage ("4 minutes 6 seconds"). Screen readers
   * don't read inside a progress bar, so a countdown in the middle is only heard through this.
   */
  valueText?: string;
  className?: string;
};

/** A ring gauge (overview-v3's .ring, signin-v1's lock ring). */
export function Ring({
  percent,
  label,
  color = "am",
  size = "md",
  "aria-label": ariaLabel,
  valueText,
  className,
}: RingProps) {
  const filled = Math.min(100, Math.max(0, Number.isFinite(percent) ? percent : 0));
  const style = { "--ring-p": filled, "--ring-c": `var(--${color})` } as CSSProperties;
  return (
    <div
      role="progressbar"
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={Math.round(filled)}
      aria-label={ariaLabel}
      aria-valuetext={valueText}
      className={cx(styles.ring, styles[size], className)}
      style={style}
    >
      <span className={styles.inner}>{label}</span>
    </div>
  );
}
