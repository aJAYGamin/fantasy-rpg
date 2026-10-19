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
  className?: string;
  /** One Input or PasswordInput; it picks up the label, hint and error by itself. */
  children: ReactNode;
};

/** A labelled form row (signin-v1's .f): label above, input, then hint and error, all tied to the input. */
export function Field({ label, hint, error, className, children }: FieldProps) {
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
        // role="alert": an error that appears after a submit is announced as it appears.
        <p id={errorId} role="alert" className={styles.error}>
          {error}
        </p>
      )}
    </div>
  );
}
