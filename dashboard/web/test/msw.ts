// The fake server every web test talks to. Each route answers from a small in-memory state that tests change
// with the mock* helpers; anything a test does not mock fails loudly (onUnhandledFrame: "error" in setup.ts).

import { http, HttpResponse } from "msw";
import { setupServer } from "msw/node";
import { vi } from "vitest";
import {
  type AuthState,
  DEFAULT_SETTINGS,
  type GameStatus,
  type Notification,
  type NotificationList,
  type Settings,
  type SettingsPatch,
  type SetupRequest,
  type UpdateAccountRequest,
  type User,
} from "../../shared/src/api";
import {
  DISPLAY_NAME_MAX,
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

/**
 * Makes the notification routes wait before they answer, so a test can look at the screen in between. Returns the
 * function that lets them go; they do their work (the change is kept) at that moment.
 */
export function holdNotificationReplies(): () => void {
  let release = () => {};
  const released = new Promise<void>((resolve) => {
    release = resolve;
  });
  server.use(
    http.post("/api/notifications/read-all", async () => {
      await released;
      return readAllReply();
    }),
    http.post("/api/notifications/:id/read", async ({ params }) => {
      await released;
      return readOneReply(Number(params.id));
    }),
  );
  return release;
}

/** What the fake server would answer right now, e.g. to put it in the cache before the first render. */
export function mockedAnswers(): Readonly<Pick<MockState, "auth" | "settings" | "notifications">> {
  return { auth: state.auth, settings: state.settings, notifications: state.notifications };
}

function applySettingsPatch(patch: SettingsPatch): void {
  state.settings = { ...state.settings, ...patch, notify: { ...state.settings.notify, ...patch.notify } };
}

function setHasAvatar(hasAvatar: boolean): void {
  if (state.auth.user) state.auth = { ...state.auth, user: { ...state.auth.user, hasAvatar } };
}

// A 1 × 1 transparent PNG.
const TINY_PNG = Uint8Array.from(
  atob("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="),
  (character) => character.charCodeAt(0),
);

/** Marks notifications read like the real server: `unread` only drops for the kinds the settings count. */
function markNotificationsRead(ids: ReadonlySet<number> | "all"): boolean {
  const { items, unread } = state.notifications;
  const targets = items.filter((item) => !item.read && (ids === "all" || ids.has(item.id)));
  const counted = targets.filter((item) => state.settings.notify[item.kind]).length;
  const named = ids === "all" || items.some((item) => ids.has(item.id));
  state.notifications = {
    items: items.map((item) => (targets.includes(item) ? { ...item, read: true } : item)),
    unread: ids === "all" ? 0 : Math.max(0, unread - counted),
  };
  return named;
}

const readAllReply = () => {
  markNotificationsRead("all");
  return new HttpResponse(null, { status: 204 });
};

const readOneReply = (id: number) =>
  markNotificationsRead(new Set([id]))
    ? new HttpResponse(null, { status: 204 })
    : HttpResponse.json({ error: "not_found", message: "Not found" }, { status: 404 });

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
  http.patch("/api/account", async ({ request }) => {
    const { displayName } = (await request.json()) as UpdateAccountRequest;
    const name = displayName.trim();
    const length = [...name].length;
    if (state.auth.user === null) return refusalReply(401, "signed_out");
    if (length < 1 || length > DISPLAY_NAME_MAX) return refusalReply(400, "invalid_display_name");
    const user: User = { ...state.auth.user, displayName: name };
    state.auth = { ...state.auth, user };
    return HttpResponse.json(user);
  }),
  // Like the real server, a wrong current password is a 401; every other check is up to the test (mockRefusal).
  http.post("/api/account/password", async ({ request }) => {
    const { currentPassword } = (await request.json()) as { currentPassword: string };
    return currentPassword === TEST_PASSWORD ? new HttpResponse(null, { status: 204 }) : refusalReply(401, "wrong_password");
  }),
  http.post("/api/account/answers", async ({ request }) => {
    const { currentPassword } = (await request.json()) as { currentPassword: string };
    return currentPassword === TEST_PASSWORD ? new HttpResponse(null, { status: 204 }) : refusalReply(401, "wrong_password");
  }),
  // The upload (PUT) is answered by fakeUploads below: jsdom's File can't travel through Node's fetch.
  http.get("/api/account/avatar", () =>
    state.auth.user?.hasAvatar
      ? new HttpResponse(TINY_PNG, { headers: { "Content-Type": "image/png", "Cache-Control": "no-store" } })
      : refusalReply(404, "not_found"),
  ),
  http.delete("/api/account/avatar", () => {
    setHasAvatar(false);
    return new HttpResponse(null, { status: 204 });
  }),
  http.get("/api/settings", () => HttpResponse.json(state.settings)),
  http.patch("/api/settings", async ({ request }) => {
    applySettingsPatch((await request.json()) as SettingsPatch);
    return HttpResponse.json(state.settings);
  }),
  http.get("/api/notifications", () => HttpResponse.json(state.notifications)),
  http.post("/api/notifications/read-all", () => readAllReply()),
  http.post("/api/notifications/:id/read", ({ params }) => readOneReply(Number(params.id))),
  http.get("/api/game/status", () => HttpResponse.json(state.game)),
];

export const server = setupServer(...handlers);

// ---- refusals the pages must handle ----

// The server's own sentence for each code, so a test can tell the app's wording from the server's.
const SERVER_MESSAGES: Record<string, string> = {
  wrong_password: "That password isn't right.",
  wrong_answer: "One or more answers didn't match.",
  locked: "Too many tries. Try again when the timer runs out.",
  too_short: TOO_SHORT_MESSAGE,
  invalid_username: INVALID_USERNAME_MESSAGE,
  invalid_display_name: INVALID_DISPLAY_NAME_MESSAGE,
  invalid_setting: "That setting isn't valid.",
  missing_answer: "Answer all three security questions.",
  already_set_up: "An account already exists.",
  signed_out: "Please sign in.",
  too_large: "That request is too large.",
  unsupported_media_type: "That kind of request isn't supported.",
  not_found: "Not found",
  server_error: "Something went wrong on the server.",
};

type Refusal = { error: string; message?: string; triesLeft?: number; lockedUntil?: string };

const refusalBody = (refusal: Refusal) => ({ message: SERVER_MESSAGES[refusal.error], ...refusal });

function refusalReply(status: number, error: string) {
  return HttpResponse.json(refusalBody({ error }), { status });
}

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

type RefusedMethod = "post" | "patch" | "put" | "delete";

function refuse(
  method: RefusedMethod,
  path: string,
  status: number,
  refusal: Refusing,
  { clockAhead }: RefuseOptions = {},
): void {
  server.use(
    http[method](path, () => {
      const serverNow =
        clockAhead === undefined ? Date.now() : Math.floor((Date.now() + clockAhead) / 1000) * 1000;
      const body = typeof refusal === "function" ? refusal(serverNow) : refusal;
      const headers = clockAhead === undefined ? undefined : { Date: new Date(serverNow).toUTCString() };
      return HttpResponse.json(refusalBody(body), { status, headers });
    }),
  );
}

/**
 * Makes one route answer with a refusal, e.g. mockRefusal("post", "/api/account/answers", 400, { error: "missing_answer" }).
 * A `message` overrides the code's usual sentence (invalid_setting's message is the setting's key).
 */
export const mockRefusal = (method: RefusedMethod, path: string, status: number, refusal: Refusing) =>
  refuse(method, path, status, refusal);

/** Makes sign-in answer with a refusal, e.g. mockSignin(401, { error: "wrong_password", triesLeft: 3 }). */
export const mockSignin = (status: number, refusal: Refusing, options?: RefuseOptions) =>
  refuse("post", "/api/auth/signin", status, refusal, options);

/** Makes first-run setup answer with a refusal. */
export const mockSetup = (status: number, refusal: Refusing, options?: RefuseOptions) =>
  refuse("post", "/api/auth/setup", status, refusal, options);

/** Makes the password reset answer with a refusal. */
export const mockForgot = (status: number, refusal: Refusing, options?: RefuseOptions) =>
  refuse("post", "/api/auth/forgot", status, refusal, options);

// ---- what the app sent ----

export type SeenRequest = {
  method: string;
  /** Path plus query string, e.g. "/api/settings". */
  path: string;
  headers: Headers;
  /** The parsed JSON body (or the raw text when it isn't JSON; the FormData of an upload); undefined when there was none. */
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

// ---- uploads ----

// jsdom's File can't travel through Node's fetch (its body never finishes streaming, and the pipe then breaks with an
// unhandled error), so the one upload the app makes is answered before it gets that far. It is logged like any other
// request (its body is the FormData itself, its path the address the app asked for) and answered as the server would.
let uploadRefusal: { status: number; refusal: Refusal | string } | null = null;
let stopFakingUploads = () => {};

/** Answers uploads (a FormData body) itself, from now until stopFakingUploads. Call it after server.listen(). */
export function fakeUploads(): void {
  const network = globalThis.fetch;
  const spy = vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    if (typeof input !== "string" || !(init?.body instanceof FormData)) return network(input, init);
    const seen: SeenRequest = {
      method: init.method ?? "GET",
      path: input,
      headers: new Headers(init.headers),
      body: init.body,
    };
    log.push(seen);
    for (const capture of captures) capture.push(seen);
    if (uploadRefusal) {
      const { status, refusal } = uploadRefusal;
      if (typeof refusal === "string") return new Response(refusal, { status, headers: { "Content-Type": "text/html" } });
      return Response.json(refusalBody(refusal), { status });
    }
    setHasAvatar(true);
    return new Response(null, { status: 204 });
  });
  stopFakingUploads = () => spy.mockRestore();
}

export const restoreUploads = () => stopFakingUploads();

/**
 * Makes the next uploads answer with a refusal, e.g. mockUploadRefusal(413, { error: "too_large" }). A string is sent
 * as an HTML page instead of the server's JSON, as something between the browser and the server might answer.
 */
export function mockUploadRefusal(status: number, refusal: Refusal | string): void {
  uploadRefusal = { status, refusal };
}

/** Back to a signed-in owner with default settings, and an empty request log. Runs after every test. */
export function resetMocks(): void {
  state = freshState();
  log = [];
  captures = [];
  uploadRefusal = null;
}
