import { type ChangeEvent, type FormEvent, useRef, useState } from "react";
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
  type Problem,
  checkAnswer,
  checkConfirmation,
  checkNewPassword,
  checkUsernameGiven,
  hasProblem,
} from "./validation";

type Answers = [string, string, string];
type Values = { username: string; answers: Answers; newPassword: string; confirm: string };

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
  // Set once the pause screen has been left, so the cursor starts on the first answer instead of the name.
  const [afterPause, setAfterPause] = useState(false);

  const refusal = refusalOf(resetPassword.error);
  const pausedUntil = pauseEnd(refusal, ["wrong_answer", "locked"]);
  const serverSaysTooShort = refusal?.body.error === "too_short";
  const found = showProblems ? checkAll(values) : undefined;

  useFocusFirstInvalid(formRef, attempts, refusal);

  function edit(field: "username" | "newPassword" | "confirm") {
    return (event: ChangeEvent<HTMLInputElement>) => {
      setValues((now) => ({ ...now, [field]: event.target.value }));
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
    };
  }

  function submit(event: FormEvent) {
    event.preventDefault();
    const checks = checkAll(values);
    const problem = hasProblem([checks.username, ...checks.answers, checks.newPassword, checks.confirm]);
    setShowProblems(problem);
    if (problem) {
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
      },
    );
  }

  // The pause is over: the form comes back with the name kept, and the answers and passwords typed before are gone.
  function backToForm() {
    resetPassword.reset();
    setValues((now) => ({ ...EMPTY, username: now.username }));
    setShowProblems(false);
    setAfterPause(true);
  }

  if (pausedUntil !== null) return <LockedPanel kind="reset" until={pausedUntil} onTryAgain={backToForm} />;

  return (
    <AuthLayout
      tagline="Reset your password."
      tagsub={`Answer all three questions. One wrong answer locks resetting for ${LOCK_MINUTES} minutes.`}
    >
      <h1 className={form.title}>Answer your security questions</h1>
      <p className={form.lead}>Capitals and extra spaces don't matter.</p>
      <form ref={formRef} className={form.form} onSubmit={submit} noValidate>
        <Field label="Username" error={found?.username}>
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
          <QuestionField key={question} number={index + 1} question={question} error={found?.answers[index]}>
            <PasswordInput
              showLabel={`Show answer ${index + 1}`}
              autoComplete="off"
              autoFocus={afterPause && index === 0}
              value={values.answers[index]}
              onChange={editAnswer(index)}
            />
          </QuestionField>
        ))}
        <div className={form.two}>
          <Field
            label="New password"
            error={found?.newPassword ?? (serverSaysTooShort ? refusal?.body.message : undefined)}
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
            error={found?.confirm}
          >
            <PasswordInput
              showLabel="Show confirm new password"
              autoComplete="new-password"
              placeholder="Again"
              value={values.confirm}
              onChange={edit("confirm")}
            />
          </Field>
        </div>
        {refusal && !serverSaysTooShort && <Alert tone="bad">{refusal.body.message}</Alert>}
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
