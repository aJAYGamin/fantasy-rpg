import { type ReactNode, useId } from "react";
import { Toggle } from "../../components";
import styles from "./SettingRow.module.css";

export type SettingRowProps = {
  title: string;
  /** A line of explanation under the title. */
  hint?: ReactNode;
  /** The control at the right: a Segmented, usually. */
  children: ReactNode;
};

/** One setting as a row: what it is at the left (a title and a dim line), its control at the right. */
export function SettingRow({ title, hint, children }: SettingRowProps) {
  return (
    <div className={styles.row}>
      <div className={styles.text}>
        <p className={styles.title}>{title}</p>
        {hint !== undefined && <p className={styles.hint}>{hint}</p>}
      </div>
      <div className={styles.control}>{children}</div>
    </div>
  );
}

export type ToggleRowProps = {
  label: string;
  hint?: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
};

/** A switch with its name beside it (party-v4's .mv row), and a dim line under the name that is its description. */
export function ToggleRow({ label, hint, checked, onChange }: ToggleRowProps) {
  const hintId = useId();
  return (
    <div className={styles.toggleRow}>
      <Toggle
        label={label}
        checked={checked}
        onChange={onChange}
        describedBy={hint === undefined ? undefined : hintId}
      />
      {hint !== undefined && (
        <p id={hintId} className={styles.toggleHint}>
          {hint}
        </p>
      )}
    </div>
  );
}
