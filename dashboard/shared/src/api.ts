// The shapes the server sends and the web app reads.

import { DEFAULT_GAME_PORT } from "./constants.js";

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
  /** invalid_setting only: the setting that was refused, e.g. "gamePort" or "notify.game". */
  setting?: string;
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

export type Settings = {
  appearance: "light" | "dark" | "system";
  colorTheme: "amethyst";
  sidebar: "expanded" | "icons";
  keepSignedInDays: 7 | 30 | 90;
  gamePort: number;
  autoReconnect: boolean;
  /** Which kinds of notification count toward the bell's unread number. */
  notify: Record<NotificationKind, boolean>;
};

export const DEFAULT_SETTINGS: Settings = {
  appearance: "light",
  colorTheme: "amethyst",
  sidebar: "expanded",
  keepSignedInDays: 30,
  gamePort: DEFAULT_GAME_PORT,
  autoReconnect: true,
  notify: { security: true, game: true, changes: true },
};

/** Any subset of the settings; `notify` may name just the kinds being changed. */
export type SettingsPatch = Partial<Omit<Settings, "notify">> & { notify?: Partial<Settings["notify"]> };

export type Notification = {
  id: number;
  kind: NotificationKind;
  title: string;
  body: string;
  /** ISO time. */
  createdAt: string;
  read: boolean;
};

/** Newest first, at most 100. `unread` counts every unread one of a kind that is switched on, not just those listed. */
export type NotificationList = { items: Notification[]; unread: number };

export type UpdateAccountRequest = { displayName: string };

export type ChangePasswordRequest = { currentPassword: string; newPassword: string };

export type ChangeAnswersRequest = { currentPassword: string; answers: [string, string, string] };
