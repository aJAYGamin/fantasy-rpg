import type { ComponentPropsWithRef, ReactNode } from "react";
import styles from "./IconButton.module.css";
import { cx } from "./cx";

export type IconButtonProps = Omit<ComponentPropsWithRef<"button">, "aria-label" | "children"> & {
  /** What the button does, for screen readers (the icon alone says nothing to them). */
  label: string;
  /** The icon, e.g. a lucide-react component. */
  children: ReactNode;
  /** The outlined square of the top bar's collapse button; off for the bare icons beside it. */
  bordered?: boolean;
};

export function IconButton({ label, children, bordered = true, type = "button", className, ...rest }: IconButtonProps) {
  return (
    <button
      {...rest}
      type={type}
      aria-label={label}
      className={cx(styles.iconButton, bordered && styles.bordered, className)}
    >
      {children}
    </button>
  );
}
