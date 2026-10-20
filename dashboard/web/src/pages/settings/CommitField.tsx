import { type ChangeEvent, type KeyboardEvent, type ReactNode, useRef, useState } from "react";
import { Field, Input, type InputProps } from "../../components";
import { refusalOf } from "../../auth/refusal";

export type CommitFieldProps = Omit<InputProps, "value" | "defaultValue" | "onChange" | "onBlur" | "onKeyDown" | "id"> & {
  label: string;
  hint?: ReactNode;
  /** The value as it is saved now. */
  saved: string;
  /** What is wrong with the (trimmed) text, if anything. */
  check: (typed: string) => string | undefined;
  /** Saves the (trimmed) text, and shows whatever tells the person it worked. Rejects when the server refuses it. */
  save: (typed: string) => Promise<unknown>;
  /** The sentence for a refusal; nothing when there is nothing to say. */
  problemOf?: (error: unknown) => string | undefined;
};

// A session that has ended is already on its way to the sign-in page; any other refusal says what it says.
function refusalMessage(error: unknown): string | undefined {
  const refusal = refusalOf(error);
  if (refusal === null) return "Something went wrong.";
  return refusal.body.error === "signed_out" ? undefined : refusal.body.message;
}

/**
 * A text field that saves when the person is done with it, not on every keystroke (R32): on Enter, or on leaving
 * the field, if the text changed and is valid. Escape puts the saved text back. A problem with what was typed shows
 * when it is committed (and then follows the typing, so it goes as soon as it is put right); the server's refusal
 * shows as it said it, and the field goes back to what is saved.
 */
export function CommitField({
  label,
  hint,
  saved,
  check,
  save,
  problemOf = refusalMessage,
  className,
  ...input
}: CommitFieldProps) {
  // What has been typed, or null while the field simply shows the saved text.
  const [draft, setDraft] = useState<string | null>(null);
  const [problem, setProblem] = useState<string>();
  const [refused, setRefused] = useState<string>();
  const sending = useRef(false);

  function edit(event: ChangeEvent<HTMLInputElement>) {
    const text = event.target.value;
    setDraft(text);
    setRefused(undefined);
    if (problem !== undefined) setProblem(check(text.trim()));
  }

  async function commit() {
    if (draft === null || sending.current) return;
    const text = draft.trim();
    if (text === saved) {
      setDraft(null);
      setProblem(undefined);
      return;
    }
    const found = check(text);
    setProblem(found);
    if (found !== undefined) return;

    sending.current = true;
    try {
      await save(text);
    } catch (error) {
      setRefused(problemOf(error));
    } finally {
      sending.current = false;
      // Unless more was typed while it was on its way, the field shows what is saved: the new text, or the old if refused.
      setDraft((now) => (now === draft ? null : now));
    }
  }

  function onKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === "Enter") {
      event.preventDefault();
      void commit();
    } else if (event.key === "Escape") {
      setDraft(null);
      setProblem(undefined);
      setRefused(undefined);
    }
  }

  const error = problem ?? refused;
  return (
    <Field
      label={label}
      hint={hint}
      error={error}
      // A refusal comes from something the person just did, so it interrupts; a problem found in their text waits.
      announce={problem === undefined && refused !== undefined ? "assertive" : "polite"}
      className={className}
    >
      <Input {...input} value={draft ?? saved} onChange={edit} onBlur={() => void commit()} onKeyDown={onKeyDown} />
    </Field>
  );
}
