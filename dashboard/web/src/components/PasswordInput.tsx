import { useState } from "react";
import { useField } from "./Field";
import { Input, type InputProps } from "./Input";
import styles from "./PasswordInput.module.css";
import { cx } from "./cx";

export type PasswordInputProps = Omit<InputProps, "type"> & {
  /**
   * The switch's name for screen readers, naming the field: "Show password", "Show confirm password",
   * "Show answer 2". It starts with "Show", the word on the switch, so voice control finds it by what it says.
   */
  showLabel: string;
};

/**
 * A password (or secret answer) input with signin-v1's "Show" switch inside its right edge. The switch is a
 * toggle button: its name stays the same and aria-pressed says whether the text is showing.
 */
export function PasswordInput({ showLabel, className, ...rest }: PasswordInputProps) {
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
        aria-label={showLabel}
        aria-pressed={shown}
        aria-controls={rest.id ?? field?.id}
        onClick={() => setShown((now) => !now)}
      >
        Show
      </button>
    </div>
  );
}
