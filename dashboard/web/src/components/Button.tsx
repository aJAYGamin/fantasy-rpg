import type { ComponentPropsWithRef, MouseEvent } from "react";
import styles from "./Button.module.css";
import { cx } from "./cx";

export type ButtonProps = ComponentPropsWithRef<"button"> & {
  variant?: "primary" | "secondary" | "danger" | "ghost";
  size?: "sm" | "md";
  /** Shows a spinner and ignores further presses until the work finishes. */
  loading?: boolean;
  /**
   * Grayed and inert, yet still reachable by pointer and keyboard so a tooltip can say why (a `disabled` button gets
   * neither hover nor focus). Point `aria-describedby` at the reason, which a tooltip alone doesn't tell screen readers.
   */
  unavailable?: boolean;
};

export function Button({
  variant = "secondary",
  size = "md",
  loading = false,
  unavailable = false,
  disabled,
  type = "button",
  onClick,
  className,
  children,
  ...rest
}: ButtonProps) {
  // Busy is not disabled: a disabled button would drop the keyboard focus of whoever just pressed it. It stays
  // focusable, says it is unavailable, and swallows presses (and so form submits) until the work is done.
  function press(event: MouseEvent<HTMLButtonElement>) {
    if (loading || unavailable) {
      event.preventDefault();
      return;
    }
    onClick?.(event);
  }

  return (
    <button
      {...rest}
      type={type}
      disabled={disabled}
      aria-disabled={loading || unavailable || undefined}
      aria-busy={loading || undefined}
      data-loading={loading || undefined}
      data-unavailable={unavailable || undefined}
      onClick={press}
      className={cx(styles.button, styles[variant], styles[size], className)}
    >
      {loading && <span className={styles.spinner} aria-hidden="true" />}
      {children}
    </button>
  );
}
