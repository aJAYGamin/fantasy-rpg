import type { ReactNode } from "react";
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

/** A switch with its name beside it (party-v4's .mv row), and a dim line under the name. */
export function ToggleRow({ label, hint, checked, onChange }: ToggleRowProps) {
  return (
    <div className={styles.toggleRow}>
      <Toggle label={label} checked={checked} onChange={onChange} />
      {hint !== undefined && <p className={styles.toggleHint}>{hint}</p>}
    </div>
  );
}
