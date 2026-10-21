import type { ReactNode } from "react";
import { Field } from "../components";
import styles from "./QuestionField.module.css";

export type QuestionFieldProps = {
  /** 1, 2 or 3. */
  number: number;
  question: string;
  error?: ReactNode;
  announce?: "polite" | "assertive";
  /** The answer's Input or PasswordInput. */
  children: ReactNode;
};

/** One security question as signin-v1 draws it: its number in a circle, the question as the label, the answer below. */
export function QuestionField({ number, question, error, announce, children }: QuestionFieldProps) {
  return (
    <Field
      className={styles.question}
      announce={announce}
      label={
        <>
          <span className={styles.number} aria-hidden="true">
            {number}
          </span>
          <span data-testid="security-question">{question}</span>
        </>
      }
      error={error}
    >
      {children}
    </Field>
  );
}
