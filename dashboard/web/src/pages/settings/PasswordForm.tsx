import { type ChangeEvent, type FormEvent, useRef, useState } from "react";
import { useChangePassword } from "../../api/hooks";
import { Alert } from "../../auth/Alert";
import { StrengthMeter } from "../../auth/StrengthMeter";
import { useFocusFirstInvalid } from "../../auth/focus";
import { refusalOf } from "../../auth/refusal";
import { passwordHint, passwordStrength } from "../../auth/strength";
import {
  type Problem,
  checkConfirmation,
  checkNewPassword,
  checkPasswordGiven,
  hasProblem,
} from "../../auth/validation";
import { Button, Card, Field, PasswordInput } from "../../components";
import styles from "./Forms.module.css";

type Values = { current: string; next: string; confirm: string };
type FieldName = keyof Values;

const EMPTY: Values = { current: "", next: "", confirm: "" };

// The server's refusals that belong under one particular field (R35).
const FIELD_FOR_REFUSAL: Record<string, FieldName> = { wrong_password: "current", too_short: "next" };

function checkAll(values: Values): Record<FieldName, Problem> {
  return {
    current: checkPasswordGiven(values.current),
    next: checkNewPassword(values.next),
    confirm: checkConfirmation(values.next, values.confirm),
  };
}

/** Change password: the current one, the new one twice. It has its own button; nothing is saved until it is pressed. */
export function PasswordForm() {
  const change = useChangePassword();
  const formRef = useRef<HTMLFormElement>(null);
  const [values, setValues] = useState<Values>(EMPTY);
  const [showProblems, setShowProblems] = useState(false);
  const [attempts, setAttempts] = useState(0);
  // "The passwords don't match" is only fair once there is something in Confirm to compare, or it has been left.
  const [confirmTouched, setConfirmTouched] = useState(false);
  // A problem that comes from pressing the button interrupts a screen reader; once typing starts it only waits.
  const [editedSinceSubmit, setEditedSinceSubmit] = useState(false);
  const [done, setDone] = useState(false);

  const refusal = refusalOf(change.error);
  const refusedField = refusal ? FIELD_FOR_REFUSAL[refusal.body.error] : undefined;
  const found = showProblems ? checkAll(values) : undefined;
  const announce = editedSinceSubmit ? "polite" : "assertive";
  const strength = passwordStrength(values.next);
  // What to show under a field: this form's own check first, otherwise what the server said about it.
  const problemFor = (field: FieldName): Problem => {
    if (field === "confirm" && !confirmTouched && values.confirm === "") return undefined;
    return found?.[field] ?? (refusedField === field ? refusal?.body.message : undefined);
  };

  useFocusFirstInvalid(formRef, attempts, refusal);

  function edit(field: FieldName) {
    return (event: ChangeEvent<HTMLInputElement>) => {
      const typed = event.target.value;
      setValues((now) => ({ ...now, [field]: typed }));
      setEditedSinceSubmit(true);
      setDone(false);
      // The server's complaint was about the old value.
      if (refusedField === field) change.reset();
    };
  }

  function submit(event: FormEvent) {
    event.preventDefault();
    setEditedSinceSubmit(false);
    setDone(false);
    const checks = checkAll(values);
    const problem = hasProblem(Object.values(checks));
    setShowProblems(problem);
    if (problem) {
      // If the passwords differ the person has to be told, even when Confirm is still empty.
      if (checks.confirm !== undefined) setConfirmTouched(true);
      setAttempts((count) => count + 1);
      return;
    }
    change.mutate(
      { currentPassword: values.current, newPassword: values.next },
      {
        onSuccess: () => {
          setValues(EMPTY);
          setShowProblems(false);
          setConfirmTouched(false);
          setDone(true);
          // The request holds what was typed; let it go now rather than when this page is left.
          change.reset();
        },
      },
    );
  }

  // The refusals that have no field of their own. A session that has ended needs no word here: it is on its way to sign-in.
  const alert = refusal && !refusedField && refusal.body.error !== "signed_out" ? refusal.body.message : undefined;

  return (
    <Card title="Change password">
      <form ref={formRef} className={styles.form} onSubmit={submit} noValidate>
        <Field label="Current password" error={problemFor("current")} announce={announce} className={styles.field}>
          <PasswordInput
            showLabel="Show current password"
            autoComplete="current-password"
            value={values.current}
            onChange={edit("current")}
          />
        </Field>
        <Field
          label="New password"
          hint={passwordHint(strength)}
          error={problemFor("next")}
          announce={announce}
          className={styles.field}
        >
          <PasswordInput
            showLabel="Show new password"
            autoComplete="new-password"
            value={values.next}
            onChange={edit("next")}
          />
          <StrengthMeter level={strength} />
        </Field>
        <Field label="Confirm new password" error={problemFor("confirm")} announce={announce} className={styles.field}>
          <PasswordInput
            showLabel="Show confirm new password"
            autoComplete="new-password"
            value={values.confirm}
            onChange={edit("confirm")}
            onBlur={() => setConfirmTouched(true)}
          />
        </Field>
        {alert !== undefined && (
          <Alert tone="bad" className={styles.alert}>
            {alert}
          </Alert>
        )}
        {done && (
          <Alert tone="ok" className={styles.alert}>
            Password changed. Every other sign-in was ended.
          </Alert>
        )}
        <Button type="submit" variant="primary" loading={change.isPending} className={styles.submit}>
          Change password
        </Button>
      </form>
    </Card>
  );
}
