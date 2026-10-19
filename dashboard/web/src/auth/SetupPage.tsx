import { useQueryClient } from "@tanstack/react-query";
import { type ChangeEvent, type FormEvent, type MouseEvent, useRef, useState } from "react";
import { Link, useNavigate } from "react-router";
import { MIN_PASSWORD_LENGTH, SECURITY_QUESTIONS } from "../../../shared/src/constants";
import { queryKeys, useSetup } from "../api/hooks";
import { Button, Field, Input, PasswordInput } from "../components";
import { cx } from "../components/cx";
import { Alert } from "./Alert";
import { AuthLayout } from "./AuthLayout";
import form from "./AuthForm.module.css";
import { QuestionField } from "./QuestionField";
import { StrengthMeter } from "./StrengthMeter";
import { useFocusFirstInvalid } from "./focus";
import { refusalOf } from "./refusal";
import { STRENGTH_WORDS, passwordStrength } from "./strength";
import {
  type Problem,
  checkAnswer,
  checkConfirmation,
  checkDisplayName,
  checkNewPassword,
  checkNewUsername,
  hasProblem,
} from "./validation";

type Answers = [string, string, string];
type Values = { displayName: string; username: string; password: string; confirm: string; answers: Answers };
type FieldName = "displayName" | "username" | "password" | "confirm";

const EMPTY: Values = { displayName: "", username: "", password: "", confirm: "", answers: ["", "", ""] };

// The server's refusals that belong under one particular field.
const FIELD_FOR_REFUSAL: Record<string, FieldName> = {
  invalid_display_name: "displayName",
  invalid_username: "username",
  too_short: "password",
};

function checkAll(values: Values): Record<FieldName, Problem> & { answers: Problem[] } {
  return {
    displayName: checkDisplayName(values.displayName),
    username: checkNewUsername(values.username),
    password: checkNewPassword(values.password),
    confirm: checkConfirmation(values.password, values.confirm),
    answers: values.answers.map(checkAnswer),
  };
}

/** First run: the owner account. Reached only while no account exists (the router sends everyone else away). */
export function SetupPage() {
  const setup = useSetup();
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const formRef = useRef<HTMLFormElement>(null);
  const [values, setValues] = useState<Values>(EMPTY);
  const [showProblems, setShowProblems] = useState(false);
  const [attempts, setAttempts] = useState(0);
  // "The passwords don't match" is only fair once there is something in Confirm to compare, or it has been left.
  const [confirmTouched, setConfirmTouched] = useState(false);
  // Errors that come from pressing Create account interrupt a screen reader; once typing starts they only wait
  // for a pause.
  const [editedSinceSubmit, setEditedSinceSubmit] = useState(false);

  const refusal = refusalOf(setup.error);
  const refusedField = refusal ? FIELD_FOR_REFUSAL[refusal.body.error] : undefined;
  const found = showProblems ? checkAll(values) : undefined;
  const announce = editedSinceSubmit ? "polite" : "assertive";
  // What to show under a field: this page's own check first, otherwise what the server said about it.
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
      // The server's complaint was about the old value.
      if (refusedField === field) setup.reset();
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
    const problem = hasProblem([
      checks.displayName,
      checks.username,
      checks.password,
      checks.confirm,
      ...checks.answers,
    ]);
    setShowProblems(problem);
    if (problem) {
      // If the passwords differ the person has to be told, even when Confirm is still empty.
      if (checks.confirm !== undefined) setConfirmTouched(true);
      setAttempts((count) => count + 1);
      return;
    }
    setup.mutate({
      username: values.username.trim(),
      displayName: values.displayName.trim(),
      password: values.password,
      answers: values.answers,
    });
  }

  // Someone made the account in the meantime. The router still believes there is none, so it has to be told
  // before leaving, or it would send the person straight back here.
  async function goToSignIn(event: MouseEvent<HTMLAnchorElement>) {
    // Opening it in a new tab or window needs no help: that page asks the server for itself.
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    await queryClient.invalidateQueries({ queryKey: queryKeys.auth });
    void navigate("/signin");
  }

  const strength = passwordStrength(values.password);
  const hint =
    strength === 0
      ? `At least ${MIN_PASSWORD_LENGTH} characters`
      : `${STRENGTH_WORDS[strength]} · at least ${MIN_PASSWORD_LENGTH} characters`;
  const alreadySetUp = refusal?.body.error === "already_set_up";

  return (
    <AuthLayout
      tagline={
        <>
          Welcome. <br />
          {"Let's set up your account."}
        </>
      }
      tagsub="This only appears once. After this, nobody can sign up. You'll create any other accounts yourself, from inside."
    >
      <div className={form.steps} aria-hidden="true">
        <span />
        <span />
      </div>
      <h1 className={form.title}>Create your account</h1>
      <p className={form.lead}>You'll be the owner of this dashboard.</p>
      <form ref={formRef} className={form.form} onSubmit={submit} noValidate>
        <div className={form.two}>
          <Field label="Display name" error={problemFor("displayName")} announce={announce} className={form.field}>
            <Input
              autoComplete="name"
              autoFocus
              placeholder="Your name"
              value={values.displayName}
              onChange={edit("displayName")}
            />
          </Field>
          <Field label="Username" error={problemFor("username")} announce={announce} className={form.field}>
            <Input
              autoComplete="username"
              autoCapitalize="none"
              spellCheck={false}
              value={values.username}
              onChange={edit("username")}
            />
          </Field>
        </div>
        <Field
          label="Password"
          hint={hint}
          error={problemFor("password")}
          announce={announce}
          className={form.field}
        >
          <PasswordInput
            showLabel="Show password"
            autoComplete="new-password"
            value={values.password}
            onChange={edit("password")}
          />
          <StrengthMeter level={strength} />
        </Field>
        <Field label="Confirm password" error={problemFor("confirm")} announce={announce} className={form.field}>
          <PasswordInput
            showLabel="Show confirm password"
            autoComplete="new-password"
            value={values.confirm}
            onChange={edit("confirm")}
            onBlur={() => setConfirmTouched(true)}
          />
        </Field>
        <fieldset className={form.group}>
          <legend className={form.legend}>
            SECURITY QUESTIONS <span className={form.legendNote}>· used to reset your password</span>
          </legend>
          {SECURITY_QUESTIONS.map((question, index) => (
            <QuestionField
              key={question}
              number={index + 1}
              question={question}
              error={found?.answers[index]}
              announce={announce}
            >
              <Input
                autoComplete="off"
                spellCheck={false}
                autoCorrect="off"
                autoCapitalize="off"
                placeholder="Your answer"
                value={values.answers[index]}
                onChange={editAnswer(index)}
              />
            </QuestionField>
          ))}
        </fieldset>
        {refusal && !refusedField && (
          <Alert tone="bad" className={form.alertAfterAnswers}>
            {refusal.body.message}
            {alreadySetUp && (
              <>
                {" "}
                <Link to="/signin" onClick={goToSignIn}>
                  Go to sign in
                </Link>
              </>
            )}
          </Alert>
        )}
        <Button
          type="submit"
          variant="primary"
          loading={setup.isPending}
          className={cx(form.submit, form.submitAfterAnswers)}
        >
          Create account
        </Button>
      </form>
    </AuthLayout>
  );
}
