import type { ComponentPropsWithRef, ReactNode } from "react";
import { Link, type LinkProps } from "react-router";
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

export type IconLinkProps = Omit<LinkProps, "aria-label" | "children"> & {
  /** Where it goes, for screen readers. */
  label: string;
  children: ReactNode;
  bordered?: boolean;
};

/** An IconButton that goes to another page (a real link: it can be opened in a new tab). */
export function IconLink({ label, children, bordered = true, className, ...rest }: IconLinkProps) {
  return (
    <Link {...rest} aria-label={label} className={cx(styles.iconButton, bordered && styles.bordered, className)}>
      {children}
    </Link>
  );
}
