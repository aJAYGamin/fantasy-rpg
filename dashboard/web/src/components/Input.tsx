import type { ComponentPropsWithRef } from "react";
import { describedBy, useField } from "./Field";
import styles from "./Input.module.css";
import { cx } from "./cx";

export type InputProps = ComponentPropsWithRef<"input"> & {
  /** Marks the value as wrong; inside a Field, its error does this already. */
  invalid?: boolean;
};

/** A text input (signin-v1's .in). Inside a Field it takes the Field's label, hint and error. */
export function Input({ id, invalid, className, "aria-describedby": ownDescription, ...rest }: InputProps) {
  const field = useField();
  const isInvalid = invalid ?? field?.invalid ?? false;
  return (
    <input
      {...rest}
      id={id ?? field?.id}
      aria-describedby={describedBy(ownDescription, field?.describedBy)}
      aria-invalid={isInvalid || undefined}
      className={cx(styles.input, className)}
    />
  );
}
