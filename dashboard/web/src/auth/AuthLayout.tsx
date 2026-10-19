import type { ReactNode } from "react";
import { PRODUCT_NAME } from "../../../shared/src/constants";
import styles from "./AuthLayout.module.css";

export type AuthLayoutProps = {
  /** The Cinzel line on the plum panel. */
  tagline: ReactNode;
  /** The small line under it. */
  tagsub: ReactNode;
  /** The form (or pause screen) on the right. */
  children: ReactNode;
};

/**
 * signin-v1's screen: the plum brand panel on the left with the gem, the product name, a tagline and the footer
 * line; the form on the right, on the card colour. Below 800 px the panel stacks on top.
 */
export function AuthLayout({ tagline, tagsub, children }: AuthLayoutProps) {
  return (
    <div className={styles.screen}>
      <div className={styles.brand}>
        <div className={styles.logo}>
          <span className={styles.gem} aria-hidden="true" />
          {PRODUCT_NAME}
        </div>
        <div>
          <p className={styles.tag}>{tagline}</p>
          <p className={styles.tagsub}>{tagsub}</p>
        </div>
        <p className={styles.foot}>The Amethyst Requiem · dev dashboard</p>
      </div>
      <main className={styles.formSide}>
        <div className={styles.formInner}>{children}</div>
      </main>
    </div>
  );
}
