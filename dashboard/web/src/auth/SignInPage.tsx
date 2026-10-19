import { type FormEvent, useState } from "react";
import { ApiFailure } from "../api/client";
import { useSignIn } from "../api/hooks";
import { Button, Checkbox, Field, Input, PasswordInput } from "../components";
import { AuthLayout } from "./AuthLayout";
import styles from "./AuthLayout.module.css";

// Placeholder until the sign-in screens are built: a working form, without the tries-left and lock screens.
export function SignInPage() {
  const signIn = useSignIn();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [keepSignedIn, setKeepSignedIn] = useState(true);

  const problem = signIn.error instanceof ApiFailure ? signIn.error.body.message : undefined;

  function submit(event: FormEvent) {
    event.preventDefault();
    signIn.mutate({ username, password, keepSignedIn });
  }

  return (
    <AuthLayout>
      <h1>Sign in</h1>
      <form className={styles.form} onSubmit={submit} noValidate>
        <Field label="Username">
          <Input autoComplete="username" value={username} onChange={(event) => setUsername(event.target.value)} />
        </Field>
        <Field label="Password" error={problem}>
          <PasswordInput
            showLabel="Show password"
            autoComplete="current-password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
          />
        </Field>
        <Checkbox
          label="Keep me signed in"
          checked={keepSignedIn}
          onChange={(event) => setKeepSignedIn(event.target.checked)}
        />
        <Button type="submit" variant="primary" loading={signIn.isPending}>
          Sign in
        </Button>
      </form>
    </AuthLayout>
  );
}
