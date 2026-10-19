// Names, questions and limits used by both the server and the web app.

export const PRODUCT_NAME = "Amethyst Dashboard";

export const SECURITY_QUESTIONS: readonly [string, string, string] = [
  "What is my favorite holiday?",
  "Which city was I born in?",
  "What is my favorite board game?",
];

export const LOCK_MINUTES = 5;
export const MAX_WRONG_PASSWORDS = 5;
export const MIN_PASSWORD_LENGTH = 10;

export const SESSION_HOURS_DEFAULT = 12;
export const KEEP_SIGNED_IN_DAY_CHOICES = [7, 30, 90] as const;

export const DEFAULT_GAME_PORT = 47821;

export const SESSION_COOKIE = "amethyst_session";
// Sent on every state-changing request; the server answers 403 without it.
export const REQUEST_HEADER = "X-Amethyst-Request";
