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

// The account rules. The server enforces them; the sign-in forms check the same values before sending, so the
// two can't drift apart. Lengths count characters as a person sees them (an emoji is one). The username rule
// itself is in username.ts.
export const USERNAME_MIN = 3;
export const USERNAME_MAX = 32;
export const DISPLAY_NAME_MAX = 40;

// The sentence for each of those rules, shown by the forms and sent by the server alike.
export const TOO_SHORT_MESSAGE = `Passwords need at least ${MIN_PASSWORD_LENGTH} characters.`;
export const INVALID_USERNAME_MESSAGE =
  `Usernames are ${USERNAME_MIN} to ${USERNAME_MAX} characters, with no invisible characters.`;
export const INVALID_DISPLAY_NAME_MESSAGE = `Display names are 1 to ${DISPLAY_NAME_MAX} characters.`;

export const SESSION_HOURS_DEFAULT = 12;
export const KEEP_SIGNED_IN_DAY_CHOICES = [7, 30, 90] as const;

export const DEFAULT_GAME_PORT = 47821;
export const GAME_PORT_MIN = 1024;
export const GAME_PORT_MAX = 65535;
export const INVALID_GAME_PORT_MESSAGE = `Use a port from ${GAME_PORT_MIN} to ${GAME_PORT_MAX}.`;

// The profile picture: what the server accepts, and what the Settings page checks before sending.
export const AVATAR_TYPES = ["image/png", "image/jpeg", "image/webp"] as const;
export const AVATAR_MAX_BYTES = 2 * 1024 * 1024;

export const SESSION_COOKIE = "amethyst_session";
// Sent on every state-changing request; the server answers 403 without it.
export const REQUEST_HEADER = "X-Amethyst-Request";
