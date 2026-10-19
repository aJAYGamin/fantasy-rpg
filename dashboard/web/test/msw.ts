// The fake server every web test talks to. Each route answers from a small in-memory state that tests change
// with the mock* helpers; anything a test does not mock fails loudly (onUnhandledFrame: "error" in setup.ts).

import { http, HttpResponse } from "msw";
import { setupServer } from "msw/node";
import {
  type AuthState,
  DEFAULT_SETTINGS,
  type GameStatus,
  type Notification,
  type NotificationList,
  type Settings,
  type SettingsPatch,
  type SetupRequest,
  type User,
} from "../../shared/src/api";
import {
  INVALID_DISPLAY_NAME_MESSAGE,
  INVALID_USERNAME_MESSAGE,
  TOO_SHORT_MESSAGE,
} from "../../shared/src/constants";

export const TEST_OWNER: User = {
  id: 1,
  username: "owner",
  displayName: "Test Owner",
  role: "owner",
  hasAvatar: false,
};

/** An invented password for tests; never a real one. */
export const TEST_PASSWORD = "lantern-moss-42";

export const SIGNED_IN: AuthState = { setupRequired: false, user: TEST_OWNER };
export const SIGNED_OUT: AuthState = { setupRequired: false, user: null };
export const NO_ACCOUNT: AuthState = { setupRequired: true, user: null };

type MockState = {
  auth: AuthState;
  settings: Settings;
  notifications: NotificationList;
  game: GameStatus;
};

function freshState(): MockState {
  return {
    auth: SIGNED_IN,
    settings: structuredClone(DEFAULT_SETTINGS),
    notifications: { items: [], unread: 0 },
    game: { connected: false, state: "waiting" },
  };
}

let state = freshState();

export function mockAuthState(auth: AuthState): void {
  state.auth = auth;
}

export function mockSettings(patch: Partial<Settings>): void {
  state.settings = { ...state.settings, ...patch };
}

/** The bell's list; `unread` defaults to the unread ones listed (the server counts beyond the list too). */
export function mockNotifications(items: Notification[], unread = items.filter((item) => !item.read).length): void {
  state.notifications = { items, unread };
}

/** What the fake server would answer right now, e.g. to put it in the cache before the first render. */
export function mockedAnswers(): Readonly<Pick<MockState, "auth" | "settings" | "notifications">> {
  return { auth: state.auth, settings: state.settings, notifications: state.notifications };
}

function applySettingsPatch(patch: SettingsPatch): void {
  state.settings = { ...state.settings, ...patch, notify: { ...state.settings.notify, ...patch.notify } };
}

const handlers = [
  http.get("/api/auth/state", () => HttpResponse.json(state.auth)),
  http.post("/api/auth/signin", () => {
    state.auth = SIGNED_IN;
    return HttpResponse.json(TEST_OWNER);
  }),
  http.post("/api/auth/setup", async ({ request }) => {
    const { username, displayName } = (await request.json()) as SetupRequest;
    const user: User = { ...TEST_OWNER, username, displayName };
    state.auth = { setupRequired: false, user };
    return HttpResponse.json(user, { status: 201 });
  }),
  http.post("/api/auth/forgot", () => new HttpResponse(null, { status: 204 })),
  http.post("/api/auth/signout", () => {
    state.auth = SIGNED_OUT;
    return new HttpResponse(null, { status: 204 });
  }),
  http.get("/api/settings", () => HttpResponse.json(state.settings)),
  http.patch("/api/settings", async ({ request }) => {
    applySettingsPatch((await request.json()) as SettingsPatch);
    return HttpResponse.json(state.settings);
  }),
  http.get("/api/notifications", () => HttpResponse.json(state.notifications)),
  http.get("/api/game/status", () => HttpResponse.json(state.game)),
];

export const server = setupServer(...handlers);

// ---- refusals the sign-in screens must handle ----

// The server's own sentence for each code, so a test can tell the app's wording from the server's.
const SERVER_MESSAGES: Record<string, string> = {
  wrong_password: "That password isn't right.",
  wrong_answer: "One or more answers didn't match.",
  locked: "Too many tries. Try again when the timer runs out.",
  too_short: TOO_SHORT_MESSAGE,
  invalid_username: INVALID_USERNAME_MESSAGE,
  invalid_display_name: INVALID_DISPLAY_NAME_MESSAGE,
  missing_answer: "Answer all three security questions.",
  already_set_up: "An account already exists.",
  server_error: "Something went wrong on the server.",
};

type Refusal = { error: string; triesLeft?: number; lockedUntil?: string };

/** An ISO time `minutes` after `from` (default: now), for a lockedUntil. */
export function inMinutes(minutes: number, from: number = Date.now()): string {
  return new Date(from + minutes * 60_000).toISOString();
}

// What a refusal can be: a fixed answer, or a function of the server's clock so a lockedUntil is worked out when the
// answer is sent, not when the test starts.
type Refusing = Refusal | ((serverNow: number) => Refusal);

type RefuseOptions = {
  /**
   * Makes the server's clock this many ms ahead of this computer's, and says so in the answer's Date header (which
   * has whole-second precision, as a real one does).
   */
  clockAhead?: number;
};

function refuse(path: string, status: number, refusal: Refusing, { clockAhead }: RefuseOptions = {}): void {
  server.use(
    http.post(path, () => {
      const serverNow =
        clockAhead === undefined ? Date.now() : Math.floor((Date.now() + clockAhead) / 1000) * 1000;
      const body = typeof refusal === "function" ? refusal(serverNow) : refusal;
      const headers = clockAhead === undefined ? undefined : { Date: new Date(serverNow).toUTCString() };
      return HttpResponse.json({ message: SERVER_MESSAGES[body.error], ...body }, { status, headers });
    }),
  );
}

/** Makes sign-in answer with a refusal, e.g. mockSignin(401, { error: "wrong_password", triesLeft: 3 }). */
export const mockSignin = (status: number, refusal: Refusing, options?: RefuseOptions) =>
  refuse("/api/auth/signin", status, refusal, options);

/** Makes first-run setup answer with a refusal. */
export const mockSetup = (status: number, refusal: Refusing, options?: RefuseOptions) =>
  refuse("/api/auth/setup", status, refusal, options);

/** Makes the password reset answer with a refusal. */
export const mockForgot = (status: number, refusal: Refusing, options?: RefuseOptions) =>
  refuse("/api/auth/forgot", status, refusal, options);

// ---- what the app sent ----

export type SeenRequest = {
  method: string;
  /** Path plus query string, e.g. "/api/settings". */
  path: string;
  headers: Headers;
  /** The parsed JSON body (or the raw text when it isn't JSON); undefined when there was none. */
  body: unknown;
};

let log: SeenRequest[] = [];
let captures: SeenRequest[][] = [];

server.events.on("request:start", (event) => {
  const { request } = event;
  const url = new URL(request.url);
  const seen: SeenRequest = {
    method: request.method,
    path: url.pathname + url.search,
    headers: request.headers,
    body: undefined,
  };
  log.push(seen);
  for (const capture of captures) capture.push(seen);
  // The body is read off a copy so the handler can still read the original.
  void request
    .clone()
    .text()
    .then((text) => {
      if (text === "") return;
      try {
        seen.body = JSON.parse(text);
      } catch {
        seen.body = text;
      }
    });
});

/** Every request made from now until the end of the test, oldest first. */
export function captureRequests(): SeenRequest[] {
  const capture: SeenRequest[] = [];
  captures.push(capture);
  return capture;
}

/** The latest request to `path` (query string ignored) in this test, if any. */
export function lastRequest(path: string): SeenRequest | undefined {
  return log.findLast((seen) => seen.path.split("?")[0] === path);
}

/** Every request to `path` (query string ignored) in this test. */
export function requestsTo(path: string): SeenRequest[] {
  return log.filter((seen) => seen.path.split("?")[0] === path);
}

/** Back to a signed-in owner with default settings, and an empty request log. Runs after every test. */
export function resetMocks(): void {
  state = freshState();
  log = [];
  captures = [];
}
