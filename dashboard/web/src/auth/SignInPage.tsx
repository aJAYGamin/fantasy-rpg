import { type FormEvent, useEffect, useId, useRef, useState } from "react";
import { Link, useLocation } from "react-router";
import { LOCK_MINUTES } from "../../../shared/src/constants";
import { useSignIn } from "../api/hooks";
import { Button, Checkbox, Field, Input, PasswordInput } from "../components";
import { Alert } from "./Alert";
import { AuthLayout } from "./AuthLayout";
import form from "./AuthForm.module.css";
import { LockedPanel } from "./LockedPanel";
import { useFocusFirstInvalid } from "./focus";
import { readArrival, useForgotTo } from "./links";
import { pauseEnd, refusalOf } from "./refusal";
import { checkPasswordGiven, checkUsernameGiven, hasProblem } from "./validation";

const triesText = (count: number) => `${count} ${count === 1 ? "try" : "tries"} left`;

type Pause = { until: Date; justLocked: boolean };

export function SignInPage() {
  const signIn = useSignIn();
  const arrival = readArrival(useLocation().state);
  const forgotTo = useForgotTo();
  const alertId = useId();
  const formRef = useRef<HTMLFormElement>(null);
  const usernameRef = useRef<HTMLInputElement>(null);
  const passwordRef = useRef<HTMLInputElement>(null);

  // Arriving from a password reset, the name is already filled in and the password is next.
  const [username, setUsername] = useState(arrival?.username ?? "");
  const [password, setPassword] = useState("");
  const [keepSignedIn, setKeepSignedIn] = useState(true);
  const [showProblems, setShowProblems] = useState(false);
  const [attempts, setAttempts] = useState(0);
  // Errors that come from pressing Sign in interrupt a screen reader; once typing starts they only wait for a pause.
  const [editedSinceSubmit, setEditedSinceSubmit] = useState(false);
  const [pause, setPause] = useState<Pause | null>(null);
  // The "password changed" note is for the moment of arrival; after an attempt it has done its job.
  const [attempted, setAttempted] = useState(false);
  // What the last wrong password said, so a lock that arrives next can be told from one that was already there.
  const lastTries = useRef<{ username: string; triesLeft: number } | null>(null);

  const refusal = refusalOf(signIn.error);
  const wrongPassword = refusal?.body.error === "wrong_password";
  const paused = pause !== null;
  const announce = editedSinceSubmit ? "polite" : "assertive";
  const problems = showProblems
    ? { username: checkUsernameGiven(username), password: checkPasswordGiven(password) }
    : { username: undefined, password: undefined };

  useFocusFirstInvalid(formRef, attempts, null);

  // Once the pause screen is up, the attempt that caused it is let go: it holds the password that was typed.
  useEffect(() => {
    if (paused) signIn.reset();
  }, [paused, signIn.reset]);

  // After a refusal the cursor goes back to the password, selected, ready to be typed over.
  useEffect(() => {
    if (refusal === null) return;
    passwordRef.current?.focus();
    passwordRef.current?.select();
  }, [refusal]);

  // Back from the pause screen the form is new again; put the cursor on the first thing still to fill in.
  const wasPaused = useRef(false);
  useEffect(() => {
    if (wasPaused.current && !paused) (username ? passwordRef : usernameRef).current?.focus();
    wasPaused.current = paused;
  }, [paused, username]);

  function backToForm() {
    setPause(null);
    setPassword("");
    setShowProblems(false);
    lastTries.current = null;
  }

  function submit(event: FormEvent) {
    event.preventDefault();
    setEditedSinceSubmit(false);
    const found = hasProblem([checkUsernameGiven(username), checkPasswordGiven(password)]);
    setShowProblems(found);
    if (found) {
      // A blank form never reaches the server: it would count as a wrong password.
      setAttempts((count) => count + 1);
      return;
    }
    setAttempted(true);
    const request = { username: username.trim(), password, keepSignedIn };
    signIn.mutate(request, {
      onError: (error) => {
        const failure = refusalOf(error);
        const until = pauseEnd(failure, ["locked"]);
        if (until !== null) {
          // The fifth wrong password is what locks, and its answer is the same 423 a lock that was already there
          // gives. The answer before it said so: one try left.
          const before = lastTries.current;
          setPause({ until, justLocked: before?.username === request.username && before.triesLeft === 1 });
          // Nothing typed stays behind while the page waits.
          setPassword("");
          lastTries.current = null;
        } else if (failure?.body.error === "wrong_password" && failure.body.triesLeft !== undefined) {
          lastTries.current = { username: request.username, triesLeft: failure.body.triesLeft };
        } else {
          lastTries.current = null;
        }
      },
    });
  }

  if (pause !== null) {
    return (
      <LockedPanel
        kind="signin"
        until={pause.until}
        justLocked={pause.justLocked}
        onTryAgain={backToForm}
        onBack={backToForm}
      />
    );
  }

  const tries = refusal?.body.triesLeft;
  return (
    <AuthLayout tagline="Welcome back." tagsub="Debug and admin tools for The Amethyst Requiem.">
      <h1 className={form.title}>Sign in</h1>
      <p className={form.lead}>Use the account you created.</p>
      <form ref={formRef} className={form.form} onSubmit={submit} noValidate>
        {refusal ? (
          <Alert tone="bad" id={alertId} className={form.alertAbove}>
            {wrongPassword && tries !== undefined ? (
              <>
                That password isn't right. <b>{triesText(tries)}</b> before a {LOCK_MINUTES}-minute pause.
              </>
            ) : (
              refusal.body.message
            )}
          </Alert>
        ) : (
          arrival &&
          !attempted && (
            <Alert tone="ok" className={form.alertAbove}>
              Password changed. Sign in with your new password.
            </Alert>
          )
        )}
        <Field label="Username" error={problems.username} announce={announce} className={form.field}>
          <Input
            ref={usernameRef}
            autoComplete="username"
            autoCapitalize="none"
            spellCheck={false}
            autoFocus={!arrival}
            value={username}
            onChange={(event) => {
              setUsername(event.target.value);
              setEditedSinceSubmit(true);
            }}
          />
        </Field>
        <Field label="Password" error={problems.password} announce={announce} className={form.field}>
          <PasswordInput
            ref={passwordRef}
            showLabel="Show password"
            autoComplete="current-password"
            autoFocus={Boolean(arrival)}
            invalid={wrongPassword || undefined}
            aria-describedby={refusal ? alertId : undefined}
            value={password}
            onChange={(event) => {
              setPassword(event.target.value);
              setEditedSinceSubmit(true);
            }}
          />
        </Field>
        <div className={form.row}>
          <Checkbox
            label="Keep me signed in"
            checked={keepSignedIn}
            onChange={(event) => setKeepSignedIn(event.target.checked)}
          />
          <Link to={forgotTo}>Forgot password?</Link>
        </div>
        <Button type="submit" variant="primary" loading={signIn.isPending} className={form.submit}>
          Sign in
        </Button>
      </form>
    </AuthLayout>
  );
}
