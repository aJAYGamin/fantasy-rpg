import { type ReactNode, useState } from "react";
import styles from "./Tooltip.module.css";
import { cx } from "./cx";

export type TooltipProps = {
  /** The words shown; the control already says them to screen readers (its accessible name), so this is drawn only. */
  text: string;
  /** Under the control (the top bar), or to its right (the folded sidebar). */
  side?: "bottom" | "right";
  /** For a control at the window's right edge: the bubble's right edge lines up with the control's. */
  align?: "center" | "end";
  /** Extra class for the wrapper, e.g. to make it a full-width block. */
  className?: string;
  children: ReactNode;
};

/**
 * A small label that appears while the pointer rests on a control or the keyboard focus is on it, and hides while
 * the control's own menu is open. Escape hides it; the pointer can move onto it without it vanishing.
 */
export function Tooltip({ text, side = "bottom", align = "center", className, children }: TooltipProps) {
  const [dismissed, setDismissed] = useState(false);
  return (
    <span
      className={cx(styles.anchor, styles[side], align === "end" && styles.end, className)}
      data-dismissed={dismissed || undefined}
      onKeyDown={(event) => {
        if (event.key === "Escape") setDismissed(true);
      }}
      onPointerLeave={() => setDismissed(false)}
      onBlur={() => setDismissed(false)}
    >
      {children}
      <span className={styles.bubble} aria-hidden="true">
        <span className={styles.text}>{text}</span>
      </span>
    </span>
  );
}
