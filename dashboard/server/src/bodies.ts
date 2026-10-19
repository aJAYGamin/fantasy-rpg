import type { Answers } from "./auth/answers.js";

// Checks for request bodies, which arrive as `unknown`: a wrong shape is a 400, never a crash or an attempt.

export type Body = Record<string, unknown>;

export const isObject = (value: unknown): value is Body =>
  typeof value === "object" && value !== null && !Array.isArray(value);

// Exactly three pieces of text; whether they are blank is for the caller to judge.
export const isAnswers = (value: unknown): value is Answers =>
  Array.isArray(value) && value.length === 3 && value.every((answer) => typeof answer === "string");
