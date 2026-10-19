// The fake server every web test talks to. Each route answers from a small in-memory state that tests change
// with the mock* helpers; anything a test does not mock fails loudly (onUnhandledFrame: "error" in setup.ts).

import { http, HttpResponse } from "msw";
import { setupServer } from "msw/node";
import {
  type AuthState,
  DEFAULT_SETTINGS,
  type GameStatus,
  type NotificationList,
  type Settings,
  type SettingsPatch,
  type User,
} from "../../shared/src/api";

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

function applySettingsPatch(patch: SettingsPatch): void {
  state.settings = { ...state.settings, ...patch, notify: { ...state.settings.notify, ...patch.notify } };
}

const handlers = [
  http.get("/api/auth/state", () => HttpResponse.json(state.auth)),
  http.post("/api/auth/signin", () => {
    state.auth = SIGNED_IN;
    return HttpResponse.json(TEST_OWNER);
  }),
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
