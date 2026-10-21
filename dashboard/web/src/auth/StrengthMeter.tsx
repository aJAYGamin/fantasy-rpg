import { STRENGTH_WORDS, type Strength } from "./strength";
import styles from "./StrengthMeter.module.css";

/**
 * Four bars under a new password. The hint under it says the level in words; the bars add color and give
 * assistive tech a named meter.
 */
export function StrengthMeter({ level }: { level: Strength }) {
  return (
    <div
      role="meter"
      aria-label="Password strength"
      aria-valuemin={0}
      aria-valuemax={4}
      aria-valuenow={level}
      aria-valuetext={STRENGTH_WORDS[level] || "Empty"}
      data-level={level}
      className={styles.meter}
    >
      {[1, 2, 3, 4].map((step) => (
        <i key={step} className={step <= level ? styles.on : undefined} />
      ))}
    </div>
  );
}
