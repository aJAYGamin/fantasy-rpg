import { Check } from "lucide-react";
import type { ComponentPropsWithRef, ReactNode } from "react";
import { Link, type LinkProps } from "react-router";
import styles from "./Menu.module.css";
import { cx } from "./cx";

// The items of a Popover with role="menu". The Popover moves the focus between them (arrow keys, Home, End), so
// each one is reached by the arrows rather than by Tab (tabIndex -1).

export type MenuItemProps = Omit<ComponentPropsWithRef<"button">, "role" | "disabled"> & {
  icon?: ReactNode;
  /** Makes it one choice of several (a menuitemradio); true draws the tick. */
  checked?: boolean;
  /** Shown dimmed and does nothing, but can still be reached and read (a note such as "coming later"). */
  disabled?: boolean;
  /** Without an icon of its own, still lines its text up with the items that have one. */
  inset?: boolean;
};

export function MenuItem({ icon, checked, disabled, inset, children, className, onClick, ...rest }: MenuItemProps) {
  return (
    <button
      {...rest}
      type="button"
      role={checked === undefined ? "menuitem" : "menuitemradio"}
      aria-checked={checked}
      aria-disabled={disabled || undefined}
      tabIndex={-1}
      className={cx(styles.item, disabled && styles.disabled, className)}
      onClick={disabled ? undefined : onClick}
    >
      {(icon !== undefined || inset) && <span className={styles.icon}>{icon}</span>}
      <span className={styles.label}>{children}</span>
      {checked && <Check className={styles.check} />}
    </button>
  );
}

export type MenuLinkProps = Omit<LinkProps, "role"> & { icon?: ReactNode };

/** A menu item that goes to another page. */
export function MenuLink({ icon, children, className, ...rest }: MenuLinkProps) {
  return (
    <Link {...rest} role="menuitem" tabIndex={-1} className={cx(styles.item, className)}>
      {icon !== undefined && <span className={styles.icon}>{icon}</span>}
      <span className={styles.label}>{children}</span>
    </Link>
  );
}

export function MenuSeparator() {
  return <div role="separator" className={styles.separator} />;
}
