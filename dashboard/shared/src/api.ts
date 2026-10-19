// The shapes the server sends and the web app reads.

export type User = {
  id: number;
  username: string;
  displayName: string;
  role: "owner";
  hasAvatar: boolean;
};

export type AuthState = { setupRequired: boolean; user: User | null };

// Every error body: `error` is a stable code to branch on, `message` a short sentence to show.
export type ApiError = {
  error: string;
  message: string;
  /** Sign-in only: wrong passwords left before the pause. */
  triesLeft?: number;
  /** ISO time a sign-in or reset pause ends. */
  lockedUntil?: string;
};

export type SetupRequest = {
  username: string;
  displayName: string;
  password: string;
  answers: [string, string, string];
};

export type SigninRequest = { username: string; password: string; keepSignedIn: boolean };

export type ForgotRequest = {
  username: string;
  answers: [string, string, string];
  newPassword: string;
};

export type QuestionsResponse = { questions: readonly [string, string, string] };

// Stage 1 has no link to the game, so this is always "waiting".
export type GameStatus = { connected: false; state: "waiting" };

export type NotificationKind = "security" | "game" | "changes";
