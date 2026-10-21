import type { ReactNode } from "react";
import styles from "./Alert.module.css";
import { cx } from "../components/cx";

export type AlertProps = {
  /** bad: something went wrong (announced at once); ok: good news (announced politely). */
  tone: "bad" | "ok";
  id?: string;
  className?: string;
  children: ReactNode;
};

/** A boxed message above a form (signin-v1's .alert). */
export function Alert({ tone, id, className, children }: AlertProps) {
  return (
    <div id={id} role={tone === "bad" ? "alert" : "status"} className={cx(styles.alert, styles[tone], className)}>
      {children}
    </div>
  );
}
