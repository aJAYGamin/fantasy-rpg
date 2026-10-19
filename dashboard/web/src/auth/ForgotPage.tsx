import { type ChangeEvent, type FormEvent, useEffect, useRef, useState } from "react";
import { Link, useNavigate } from "react-router";
import { LOCK_MINUTES, SECURITY_QUESTIONS } from "../../../shared/src/constants";
import { useResetPassword } from "../api/hooks";
import { Button, Field, Input, PasswordInput } from "../components";
import { cx } from "../components/cx";
import { Alert } from "./Alert";
import { AuthLayout } from "./AuthLayout";
import form from "./AuthForm.module.css";
import { LockedPanel } from "./LockedPanel";
import { QuestionField } from "./QuestionField";
import { useFocusFirstInvalid } from "./focus";
import { type SignInArrival, useSignInTo } from "./links";
import { pauseEnd, refusalOf } from "./refusal";
import {
  checkAnswer,
  checkConfirmation,
  checkNewPassword,
  checkUsernameGiven,
  hasProblem,
} from "./validation";

type Answers = [string, string, string];
type Values = { username: string; answers: Answers; newPassword: string; confirm: string };
type Pause = { until: Date; justLocked: boolean };

const EMPTY: Values = { username: "", answers: ["", "", ""], newPassword: "", confirm: "" };

function checkAll(values: Values) {
  return {
    username: checkUsernameGiven(values.username),
    // A blank answer is never sent: the server would take it for a wrong one and lock the reset.
    answers: values.answers.map(checkAnswer),
    newPassword: checkNewPassword(values.newPassword),
    confirm: checkConfirmation(values.newPassword, values.confirm),
  };
}

export function ForgotPage() {
  const resetPassword = useResetPassword();
  const navigate = useNavigate();
  const signInTo = useSignInTo();
  const formRef = useRef<HTMLFormElement>(null);
  const [values, setValues] = useState<Values>(EMPTY);
  const [showProblems, setShowProblems] = useState(false);
  const [attempts, setAttempts] = useState(0);
  // "The passwords don't match" is only fair once there is something in Confirm to compare, or it has been left.
  const [confirmTouched, setConfirmTouched] = useState(false);
  // Errors that come from pressing Reset password interrupt a screen reader; once typing starts they only wait
  // for a pause.
  const [editedSinceSubmit, setEditedSinceSubmit] = useState(false);
  const [pause, setPause] = useState<Pause | null>(null);
  // Set once the pause screen has been left, so the cursor starts on the first answer instead of the name.
  const [afterPause, setAfterPause] = useState(false);

  const refusal = refusalOf(resetPassword.error);
  const serverSaysTooShort = refusal?.body.error === "too_short";
  const found = showProblems ? checkAll(values) : undefined;
  const announce = editedSinceSubmit ? "polite" : "assertive";
  const paused = pause !== null;
  const confirmProblem =
    !confirmTouched && values.confirm === "" ? undefined : found?.confirm;

  useFocusFirstInvalid(formRef, attempts, refusal);

  // Once the pause screen is up, the attempt that caused it is let go: it holds the answers that were typed.
  useEffect(() => {
    if (paused) resetPassword.reset();
  }, [paused, resetPassword.reset]);

  function edit(field: "username" | "newPassword" | "confirm") {
    return (event: ChangeEvent<HTMLInputElement>) => {
      const typed = event.target.value;
      setValues((now) => ({ ...now, [field]: typed }));
      setEditedSinceSubmit(true);
      // The server's complaint was about the old password.
      if (field === "newPassword" && serverSaysTooShort) resetPassword.reset();
    };
  }

  function editAnswer(index: number) {
    return (event: ChangeEvent<HTMLInputElement>) => {
      const typed = event.target.value;
      setValues((now) => {
        const answers: Answers = [...now.answers];
        answers[index] = typed;
        return { ...now, answers };
      });
      setEditedSinceSubmit(true);
    };
  }

  function submit(event: FormEvent) {
    event.preventDefault();
    setEditedSinceSubmit(false);
    const checks = checkAll(values);
    const problem = hasProblem([checks.username, ...checks.answers, checks.newPassword, checks.confirm]);
    setShowProblems(problem);
    if (problem) {
      // If the passwords differ the person has to be told, even when Confirm is still empty.
      if (checks.confirm !== undefined) setConfirmTouched(true);
      setAttempts((count) => count + 1);
      return;
    }
    const username = values.username.trim();
    resetPassword.mutate(
      { username, answers: values.answers, newPassword: values.newPassword },
      {
        onSuccess: () => {
          const arrival: SignInArrival = { passwordChanged: true, username };
          void navigate(signInTo, { replace: true, state: arrival });
        },
        onError: (error) => {
          const failure = refusalOf(error);
          const until = pauseEnd(failure, ["wrong_answer", "locked"]);
          if (until === null) return;
          // A wrong answer is what locks the reset; a locked answer means the lock was already there.
          setPause({ until, justLocked: failure?.body.error === "wrong_answer" });
          // Nothing typed stays behind while the page waits: the answers and the new password are gone, the name stays.
          setValues((now) => ({ ...EMPTY, username: now.username }));
        },
      },
    );
  }

  // The pause is over: the form comes back as it was left, empty of everything but the name.
  function backToForm() {
    setPause(null);
    setShowProblems(false);
    setConfirmTouched(false);
    setAfterPause(true);
  }

  if (pause !== null) {
    return <LockedPanel kind="reset" until={pause.until} justLocked={pause.justLocked} onTryAgain={backToForm} />;
  }

  return (
    <AuthLayout
      tagline="Reset your password."
      tagsub={`Answer all three questions. One wrong answer locks resetting for ${LOCK_MINUTES} minutes.`}
    >
      <h1 className={form.title}>Answer your security questions</h1>
      <p className={form.lead}>Capitals and extra spaces don't matter.</p>
      <form ref={formRef} className={form.form} onSubmit={submit} noValidate>
        <Field label="Username" error={found?.username} announce={announce} className={form.field}>
          <Input
            autoComplete="username"
            autoCapitalize="none"
            spellCheck={false}
            autoFocus={!afterPause}
            value={values.username}
            onChange={edit("username")}
          />
        </Field>
        {SECURITY_QUESTIONS.map((question, index) => (
          <QuestionField
            key={question}
            number={index + 1}
            question={question}
            error={found?.answers[index]}
            announce={announce}
          >
            <PasswordInput
              showLabel={`Show answer ${index + 1}`}
              autoComplete="off"
              autoFocus={afterPause && index === 0}
              value={values.answers[index]}
              onChange={editAnswer(index)}
            />
          </QuestionField>
        ))}
        <div className={cx(form.two, form.afterAnswers)}>
          <Field
            label="New password"
            error={found?.newPassword ?? (serverSaysTooShort ? refusal?.body.message : undefined)}
            announce={announce}
            className={form.field}
          >
            <PasswordInput
              showLabel="Show new password"
              autoComplete="new-password"
              placeholder="New password"
              value={values.newPassword}
              onChange={edit("newPassword")}
            />
          </Field>
          <Field
            label={
              <>
                Confirm<span className={form.visuallyHidden}> new password</span>
              </>
            }
            error={confirmProblem}
            announce={announce}
            className={form.field}
          >
            <PasswordInput
              showLabel="Show confirm new password"
              autoComplete="new-password"
              placeholder="Again"
              value={values.confirm}
              onChange={edit("confirm")}
              onBlur={() => setConfirmTouched(true)}
            />
          </Field>
        </div>
        {refusal && !serverSaysTooShort && (
          <Alert tone="bad" className={form.alertBeforeButton}>
            {refusal.body.message}
          </Alert>
        )}
        <Button type="submit" variant="primary" loading={resetPassword.isPending} className={form.submit}>
          Reset password
        </Button>
        <div className={cx(form.row, form.rowCentered)}>
          <Link to={signInTo}>
            <span aria-hidden="true">←</span> Back to sign in
          </Link>
        </div>
      </form>
    </AuthLayout>
  );
}
