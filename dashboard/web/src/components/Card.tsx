import { type ReactNode, useId } from "react";
import styles from "./Card.module.css";
import { cx } from "./cx";

export type CardProps = {
  /** The header title (the mockups set it in italic). The card is announced as a region by this name. */
  title?: ReactNode;
  /** Shown at the right of the header: a pill, a link, a small button. */
  actions?: ReactNode;
  /** No body padding, for content that runs edge to edge (the stat strip). */
  flush?: boolean;
  className?: string;
  /** For the body, e.g. to let it fill a card that has been stretched to match its neighbor. */
  bodyClassName?: string;
  children?: ReactNode;
};

export function Card({ title, actions, flush = false, className, bodyClassName, children }: CardProps) {
  const titleId = useId();
  const hasHeader = title !== undefined || actions !== undefined;
  return (
    <section className={cx(styles.card, className)} aria-labelledby={title !== undefined ? titleId : undefined}>
      {hasHeader && (
        <header className={styles.header}>
          {title !== undefined && (
            <h2 id={titleId} className={styles.title}>
              {title}
            </h2>
          )}
          {actions !== undefined && <div className={styles.actions}>{actions}</div>}
        </header>
      )}
      <div className={cx(!flush && styles.body, bodyClassName)}>{children}</div>
    </section>
  );
}
