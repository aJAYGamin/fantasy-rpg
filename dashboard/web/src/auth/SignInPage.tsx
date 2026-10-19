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

  const refusal = refusalOf(signIn.error);
  const pausedUntil = pauseEnd(refusal, ["locked"]);
  const wrongPassword = refusal?.body.error === "wrong_password";
  const problems = showProblems
    ? { username: checkUsernameGiven(username), password: checkPasswordGiven(password) }
    : { username: undefined, password: undefined };

  useFocusFirstInvalid(formRef, attempts, null);

  // After a refusal the cursor goes back to the password, selected, ready to be typed over.
  useEffect(() => {
    if (refusal === null) return;
    passwordRef.current?.focus();
    passwordRef.current?.select();
  }, [refusal]);

  // Back from the pause screen the form is new again; put the cursor on the first thing still to fill in.
  const paused = pausedUntil !== null;
  const wasPaused = useRef(false);
  useEffect(() => {
    if (wasPaused.current && !paused) (username ? passwordRef : usernameRef).current?.focus();
    wasPaused.current = paused;
  }, [paused, username]);

  function backToForm() {
    signIn.reset();
    setPassword("");
    setShowProblems(false);
  }

  function submit(event: FormEvent) {
    event.preventDefault();
    const found = hasProblem([checkUsernameGiven(username), checkPasswordGiven(password)]);
    setShowProblems(found);
    if (found) {
      // A blank form never reaches the server: it would count as a wrong password.
      setAttempts((count) => count + 1);
      return;
    }
    signIn.mutate({ username: username.trim(), password, keepSignedIn });
  }

  if (pausedUntil !== null) {
    return <LockedPanel kind="signin" until={pausedUntil} onTryAgain={backToForm} onBack={backToForm} />;
  }

  const tries = refusal?.body.triesLeft;
  return (
    <AuthLayout tagline="Welcome back." tagsub="Debug and admin tools for The Amethyst Requiem.">
      <h1 className={form.title}>Sign in</h1>
      <p className={form.lead}>Use the account you created.</p>
      <form ref={formRef} className={form.form} onSubmit={submit} noValidate>
        {refusal ? (
          <Alert tone="bad" id={alertId}>
            {wrongPassword && tries !== undefined ? (
              <>
                That password isn't right. <b>{triesText(tries)}</b> before a {LOCK_MINUTES}-minute pause.
              </>
            ) : (
              refusal.body.message
            )}
          </Alert>
        ) : (
          arrival && <Alert tone="ok">Password changed. Sign in with your new password.</Alert>
        )}
        <Field label="Username" error={problems.username}>
          <Input
            ref={usernameRef}
            autoComplete="username"
            autoCapitalize="none"
            spellCheck={false}
            autoFocus={!arrival}
            value={username}
            onChange={(event) => setUsername(event.target.value)}
          />
        </Field>
        <Field label="Password" error={problems.password}>
          <PasswordInput
            ref={passwordRef}
            showLabel="Show password"
            autoComplete="current-password"
            autoFocus={Boolean(arrival)}
            invalid={wrongPassword || undefined}
            aria-describedby={refusal ? alertId : undefined}
            value={password}
            onChange={(event) => setPassword(event.target.value)}
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
