import { type ReactNode, createContext, useContext, useId } from "react";
import styles from "./Field.module.css";
import { cx } from "./cx";

type FieldWiring = { id: string; describedBy: string | undefined; invalid: boolean };

const FieldContext = createContext<FieldWiring | null>(null);

/** The id, description and invalid state of the Field around an input, if there is one. */
export function useField(): FieldWiring | null {
  return useContext(FieldContext);
}

/** Joins aria-describedby ids, skipping missing ones. */
export function describedBy(...ids: Array<string | undefined>): string | undefined {
  const joined = ids.filter(Boolean).join(" ");
  return joined === "" ? undefined : joined;
}

export type FieldProps = {
  label: ReactNode;
  /** A short note under the input, e.g. "at least 10 characters". */
  hint?: ReactNode;
  /** What's wrong with the value; marks the input invalid. */
  error?: ReactNode;
  /**
   * How an error is announced to a screen reader. "polite" (the default) waits for a pause: right for checks that
   * run as someone types. "assertive" interrupts, as role="alert": for an error that appears because of something
   * the person just did, like a failed submit or the server's refusal.
   */
  announce?: "polite" | "assertive";
  className?: string;
  /** One Input or PasswordInput; it picks up the label, hint and error by itself. */
  children: ReactNode;
};

/** A labeled form row (signin-v1's .f): label above, input, then hint and error, all tied to the input. */
export function Field({ label, hint, error, announce = "polite", className, children }: FieldProps) {
  const id = useId();
  const hintId = hint ? `${id}-hint` : undefined;
  const errorId = error ? `${id}-error` : undefined;
  const wiring: FieldWiring = { id, describedBy: describedBy(hintId, errorId), invalid: Boolean(error) };
  return (
    <div className={cx(styles.field, className)}>
      <label htmlFor={id} className={styles.label}>
        {label}
      </label>
      <FieldContext.Provider value={wiring}>{children}</FieldContext.Provider>
      {hint && (
        <p id={hintId} className={styles.hint}>
          {hint}
        </p>
      )}
      {error && (
        <p
          id={errorId}
          role={announce === "assertive" ? "alert" : undefined}
          aria-live={announce === "polite" ? "polite" : undefined}
          className={styles.error}
        >
          {error}
        </p>
      )}
    </div>
  );
}
