import { useId } from "react";
import styles from "./Toggle.module.css";
import { cx } from "./cx";

export type ToggleProps = {
  checked: boolean;
  onChange: (checked: boolean) => void;
  /** Shown beside the switch (clicking it flips the switch too), and its name for screen readers. */
  label: string;
  /** Keeps the label for screen readers only, where the row around the switch already says what it is. */
  hideLabel?: boolean;
  disabled?: boolean;
  className?: string;
};

/** An on/off switch (party-v4's move switch): role="switch", flipped by click, Space or Enter. */
export function Toggle({ checked, onChange, label, hideLabel = false, disabled = false, className }: ToggleProps) {
  const id = useId();
  return (
    <span className={cx(styles.toggle, disabled && styles.disabled, className)}>
      <button
        id={id}
        type="button"
        role="switch"
        aria-checked={checked}
        aria-label={hideLabel ? label : undefined}
        disabled={disabled}
        className={styles.track}
        onClick={() => onChange(!checked)}
      >
        <span className={styles.knob} aria-hidden="true" />
      </button>
      {!hideLabel && (
        <label htmlFor={id} className={styles.label}>
          {label}
        </label>
      )}
    </span>
  );
}
