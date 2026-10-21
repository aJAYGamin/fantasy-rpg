import { Check } from "lucide-react";
import type { ComponentPropsWithRef, ReactNode } from "react";
import styles from "./Checkbox.module.css";
import { cx } from "./cx";

export type CheckboxProps = Omit<ComponentPropsWithRef<"input">, "type"> & { label: ReactNode };

/** A real checkbox drawn as signin-v1's .box: a 16 px rounded square, amethyst with a white tick when on. */
export function Checkbox({ label, className, ...rest }: CheckboxProps) {
  return (
    <label className={cx(styles.checkbox, className)}>
      <span className={styles.box}>
        <input {...rest} type="checkbox" className={styles.input} />
        <Check className={styles.tick} aria-hidden="true" strokeWidth={3} />
      </span>
      <span>{label}</span>
    </label>
  );
}
