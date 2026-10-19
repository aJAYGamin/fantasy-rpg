import { useState } from "react";
import { useField } from "./Field";
import { Input, type InputProps } from "./Input";
import styles from "./PasswordInput.module.css";
import { cx } from "./cx";

/** A password (or secret answer) input with signin-v1's Show / Hide switch inside its right edge. */
export function PasswordInput({ className, ...rest }: Omit<InputProps, "type">) {
  const [shown, setShown] = useState(false);
  const field = useField();
  return (
    <div className={styles.wrap}>
      <Input
        {...rest}
        type={shown ? "text" : "password"}
        spellCheck={false}
        autoCapitalize="off"
        autoCorrect="off"
        className={cx(styles.input, className)}
      />
      <button
        type="button"
        className={styles.toggle}
        aria-controls={rest.id ?? field?.id}
        onClick={() => setShown((now) => !now)}
      >
        {shown ? "Hide" : "Show"}
      </button>
    </div>
  );
}
