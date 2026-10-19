import { MIN_PASSWORD_LENGTH } from "../../../shared/src/constants";

// These repeat the server's rules (server/src/auth/routes.ts and accounts.ts) so a mistake is caught before it is
// sent. The server stays the authority: the pages also show its own refusals, in its own words.
const USERNAME_RULE = /^[A-Za-z0-9_.-]{3,32}$/;
const DISPLAY_NAME_MAX = 40;

const MESSAGES = {
  displayName: "Display names are 1 to 40 characters.",
  username: "Usernames are 3 to 32 letters, digits, dots, dashes or underscores.",
  tooShort: `Passwords need at least ${MIN_PASSWORD_LENGTH} characters.`,
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
  return characters >= 1 && characters <= DISPLAY_NAME_MAX ? undefined : MESSAGES.displayName;
}

export const checkNewUsername = (typed: string): Problem =>
  USERNAME_RULE.test(typed.trim()) ? undefined : MESSAGES.username;

export const checkNewPassword = (password: string): Problem =>
  length(password) >= MIN_PASSWORD_LENGTH ? undefined : MESSAGES.tooShort;

export const checkConfirmation = (password: string, confirmation: string): Problem =>
  password === confirmation ? undefined : MESSAGES.mismatch;

export const checkAnswer = (answer: string): Problem => (answer.trim() === "" ? MESSAGES.answer : undefined);

/** Signing in only needs something typed; whether it is right is the server's to say (and to count). */
export const checkUsernameGiven = (typed: string): Problem => (typed.trim() === "" ? MESSAGES.needUsername : undefined);
export const checkPasswordGiven = (password: string): Problem => (password === "" ? MESSAGES.needPassword : undefined);

export const hasProblem = (problems: ReadonlyArray<Problem>): boolean =>
  problems.some((problem) => problem !== undefined);
