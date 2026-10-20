import { type ChangeEvent, type FormEvent, useRef, useState } from "react";
import { SECURITY_QUESTIONS } from "../../../../shared/src/constants";
import { useChangeAnswers } from "../../api/hooks";
import { Alert } from "../../auth/Alert";
import { QuestionField } from "../../auth/QuestionField";
import { useFocusFirstInvalid } from "../../auth/focus";
import { refusalOf } from "../../auth/refusal";
import { type Problem, checkAnswer, checkPasswordGiven, hasProblem } from "../../auth/validation";
import { Button, Card, Field, Input, PasswordInput } from "../../components";
import styles from "./Forms.module.css";

type Answers = [string, string, string];

const NO_ANSWERS: Answers = ["", "", ""];

// A slot the server would take for blank even though it isn't empty (it normalises like this before it looks).
const isBlank = (answer: string) => answer.normalize("NFKC").trim() === "";

/**
 * Change security answers: the current password, then all three answers again (new ones replace all three). It
 * has its own button; nothing is saved until it is pressed.
 */
export function AnswersForm() {
  const change = useChangeAnswers();
  const formRef = useRef<HTMLFormElement>(null);
  const [current, setCurrent] = useState("");
  const [answers, setAnswers] = useState<Answers>(NO_ANSWERS);
  const [showProblems, setShowProblems] = useState(false);
  const [attempts, setAttempts] = useState(0);
  // A problem that comes from pressing the button interrupts a screen reader; once typing starts it only waits.
  const [editedSinceSubmit, setEditedSinceSubmit] = useState(false);
  const [done, setDone] = useState(false);

  const refusal = refusalOf(change.error);
  const code = refusal?.body.error;
  const announce = editedSinceSubmit ? "polite" : "assertive";
  const currentProblem: Problem = showProblems ? checkPasswordGiven(current) : undefined;
  // Which slot the server's "answer all three" is about: the first one it would find empty.
  const blankSlot = Math.max(0, answers.findIndex(isBlank));
  const answerProblem = (index: number): Problem =>
    (showProblems ? checkAnswer(answers[index]) : undefined) ??
    (code === "missing_answer" && index === blankSlot ? refusal?.body.message : undefined);

  useFocusFirstInvalid(formRef, attempts, refusal);

  function editCurrent(event: ChangeEvent<HTMLInputElement>) {
    setCurrent(event.target.value);
    setEditedSinceSubmit(true);
    setDone(false);
    if (code === "wrong_password") change.reset();
  }

  function editAnswer(index: number) {
    return (event: ChangeEvent<HTMLInputElement>) => {
      const typed = event.target.value;
      setAnswers((now) => {
        const next: Answers = [...now];
        next[index] = typed;
        return next;
      });
      setEditedSinceSubmit(true);
      setDone(false);
      if (code === "missing_answer") change.reset();
    };
  }

  function submit(event: FormEvent) {
    event.preventDefault();
    setEditedSinceSubmit(false);
    setDone(false);
    const problem = hasProblem([checkPasswordGiven(current), ...answers.map(checkAnswer)]);
    setShowProblems(problem);
    if (problem) {
      setAttempts((count) => count + 1);
      return;
    }
    change.mutate(
      { currentPassword: current, answers },
      {
        onSuccess: () => {
          setCurrent("");
          setAnswers(NO_ANSWERS);
          setShowProblems(false);
          setDone(true);
          // The request holds what was typed; let it go now rather than when this page is left.
          change.reset();
        },
      },
    );
  }

  // The refusals that have no field of their own. A session that has ended needs no word here: it is on its way to sign-in.
  const alert =
    refusal && code !== "wrong_password" && code !== "missing_answer" && code !== "signed_out"
      ? refusal.body.message
      : undefined;

  return (
    <Card title="Change security answers">
      <form ref={formRef} className={styles.form} onSubmit={submit} noValidate>
        <Field
          label="Current password"
          error={currentProblem ?? (code === "wrong_password" ? refusal?.body.message : undefined)}
          announce={announce}
          className={styles.field}
        >
          <PasswordInput
            showLabel="Show current password"
            autoComplete="current-password"
            value={current}
            onChange={editCurrent}
          />
        </Field>
        <fieldset className={styles.group}>
          <legend className={styles.legend}>
            New answers <span className={styles.legendNote}>· all three replace the old ones</span>
          </legend>
          {SECURITY_QUESTIONS.map((question, index) => (
            <QuestionField
              key={question}
              number={index + 1}
              question={question}
              error={answerProblem(index)}
              announce={announce}
            >
              <Input
                autoComplete="off"
                spellCheck={false}
                autoCorrect="off"
                autoCapitalize="off"
                placeholder="Your answer"
                value={answers[index]}
                onChange={editAnswer(index)}
              />
            </QuestionField>
          ))}
        </fieldset>
        {alert !== undefined && (
          <Alert tone="bad" className={styles.alert}>
            {alert}
          </Alert>
        )}
        {done && (
          <Alert tone="ok" className={styles.alert}>
            Security answers saved.
          </Alert>
        )}
        <Button type="submit" variant="primary" loading={change.isPending} className={styles.submit}>
          Save answers
        </Button>
      </form>
    </Card>
  );
}
