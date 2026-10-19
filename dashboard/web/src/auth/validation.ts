import {
  DISPLAY_NAME_MAX,
  INVALID_DISPLAY_NAME_MESSAGE,
  INVALID_USERNAME_MESSAGE,
  MIN_PASSWORD_LENGTH,
  TOO_SHORT_MESSAGE,
  USERNAME_RULE,
} from "../../../shared/src/constants";

// The account rules and their sentences come from shared/, the same values the server enforces; checking here
// only saves a round trip. The server stays the authority, and the pages also show its own refusals.
const MESSAGES = {
  mismatch: "The passwords don't match.",
  answer: "Enter an answer.",
  needUsername: "Enter your username.",
  needPassword: "Enter your password.",
} as const;

/** A problem to show under a field, or undefined when the value is fine. */
export type Problem = string | undefined;

// Lengths count code points (an emoji is one character), as the server counts them.
const length = (text: string) => [...text].length;

export function checkDisplayName(typed: string): Problem {
  const characters = length(typed.trim());
  return characters >= 1 && characters <= DISPLAY_NAME_MAX ? undefined : INVALID_DISPLAY_NAME_MESSAGE;
}

export const checkNewUsername = (typed: string): Problem =>
  USERNAME_RULE.test(typed.trim()) ? undefined : INVALID_USERNAME_MESSAGE;

export const checkNewPassword = (password: string): Problem =>
  length(password) >= MIN_PASSWORD_LENGTH ? undefined : TOO_SHORT_MESSAGE;

export const checkConfirmation = (password: string, confirmation: string): Problem =>
  password === confirmation ? undefined : MESSAGES.mismatch;

export const checkAnswer = (answer: string): Problem => (answer.trim() === "" ? MESSAGES.answer : undefined);

/** Signing in only needs something typed; whether it is right is the server's to say (and to count). */
export const checkUsernameGiven = (typed: string): Problem => (typed.trim() === "" ? MESSAGES.needUsername : undefined);
export const checkPasswordGiven = (password: string): Problem => (password === "" ? MESSAGES.needPassword : undefined);

export const hasProblem = (problems: ReadonlyArray<Problem>): boolean =>
  problems.some((problem) => problem !== undefined);
