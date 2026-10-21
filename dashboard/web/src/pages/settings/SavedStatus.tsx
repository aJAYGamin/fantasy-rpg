import { Check } from "lucide-react";
import styles from "./SavedStatus.module.css";

/**
 * "Saved", beside a section's title. The element is always there, empty, because a screen reader only speaks
 * a status that changes inside one that already exists.
 */
export function SavedStatus({ saved }: { saved: boolean }) {
  return (
    <span role="status" className={styles.status}>
      {saved && (
        <>
          <Check aria-hidden="true" />
          Saved
        </>
      )}
    </span>
  );
}
