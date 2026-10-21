import { type RefObject, useEffect } from "react";

function focusFirstInvalid(form: RefObject<HTMLElement | null>): void {
  form.current?.querySelector<HTMLElement>('[aria-invalid="true"]')?.focus();
}

/**
 * Puts the cursor on the first field marked invalid when a submit fails: `attempts` counts the pages' own failed
 * checks, `refusal` is the server's refusal (null when there is none). A long form can have the problem out of
 * sight, and a keyboard or screen-reader user has no other way to find it.
 */
export function useFocusFirstInvalid(
  form: RefObject<HTMLElement | null>,
  attempts: number,
  refusal: unknown,
): void {
  useEffect(() => {
    if (attempts > 0) focusFirstInvalid(form);
  }, [form, attempts]);
  useEffect(() => {
    if (refusal) focusFirstInvalid(form);
  }, [form, refusal]);
}
