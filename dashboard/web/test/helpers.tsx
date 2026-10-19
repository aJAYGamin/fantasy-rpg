// Web test helpers: render the real app at a path, fake the Mac's light/dark setting, run index.html's theme script.

import type { QueryClient } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent, { type UserEvent } from "@testing-library/user-event";
import { createMemoryRouter } from "react-router";
import { expect } from "vitest";
import type { Settings, User } from "../../shared/src/api";
import indexHtml from "../index.html?raw";
import { AppProviders } from "../src/App";
import { createQueryClient, queryKeys } from "../src/api/hooks";
import { routes } from "../src/router";
import { TEST_OWNER, TEST_PASSWORD, mockAuthState, mockSettings, mockedAnswers } from "./msw";

const openClients: QueryClient[] = [];
// The user-event session of the latest render, for click / type / keyboard.
let latestUser: UserEvent | null = null;

/**
 * Renders the whole app (router, data, theme) at `path`, e.g. "/gear" or "/signin?next=%2Fparty". `prime` runs
 * against the fresh query client before the first render, e.g. to put answers in its cache.
 */
export function renderAt(path: string, prime?: (queryClient: QueryClient) => void) {
  const queryClient = createQueryClient();
  // A failed request in a test is the answer under test, not something to retry.
  queryClient.setDefaultOptions({
    queries: { ...queryClient.getDefaultOptions().queries, retry: false },
    mutations: { ...queryClient.getDefaultOptions().mutations, retry: false },
  });
  openClients.push(queryClient);
  prime?.(queryClient);
  const router = createMemoryRouter(routes, { initialEntries: [path] });
  const user = userEvent.setup();
  latestUser = user;
  const view = render(<AppProviders queryClient={queryClient} router={router} />);
  return { ...view, router, queryClient, user };
}

export type ShellOptions = {
  /** Settings the signed-in owner has saved (the rest are the defaults). */
  settings?: Partial<Settings>;
  /** Changes to the signed-in owner's account. */
  user?: Partial<User>;
};

/**
 * Renders a signed-in page inside the app shell, already drawn: the auth state, settings and notifications the
 * fake server holds are put in the cache first, so the sidebar and top bar are there on the first render.
 */
export function renderShellAt(path: string, { settings, user }: ShellOptions = {}) {
  if (settings) mockSettings(settings);
  if (user) mockAuthState({ setupRequired: false, user: { ...TEST_OWNER, ...user } });
  const answers = mockedAnswers();
  return renderAt(path, (queryClient) => {
    queryClient.setQueryData(queryKeys.auth, answers.auth);
    queryClient.setQueryData(queryKeys.settings, answers.settings);
    queryClient.setQueryData(queryKeys.notifications, answers.notifications);
  });
}

function currentUser(): UserEvent {
  latestUser ??= userEvent.setup();
  return latestUser;
}

/** Clicks like a person would (pointer events, focus), in the latest render's user-event session. */
export const click = (element: Element) => currentUser().click(element);

/** Types into `element`, clicking it first. */
export const type = (element: Element, text: string) => currentUser().type(element, text);

/** Presses keys where the focus is, in user-event's syntax, e.g. "{Meta>}k{/Meta}". */
export const keyboard = (keys: string) => currentUser().keyboard(keys);

/** Drops every query client renderAt made, so no refetch timer outlives its test, and its user-event session. */
export function clearQueryClients(): void {
  for (const client of openClients.splice(0)) client.clear();
  latestUser = null;
}

/** Waits until no request the app started is still in flight. */
export async function settled(queryClient: QueryClient): Promise<void> {
  await waitFor(() => expect(queryClient.isFetching() + queryClient.isMutating()).toBe(0));
}

/** Fills the sign-in form with the test owner's details and submits it. */
export async function signInThroughForm(user: UserEvent = userEvent.setup()): Promise<void> {
  await user.type(await screen.findByLabelText("Username"), TEST_OWNER.username);
  await user.type(screen.getByLabelText("Password"), TEST_PASSWORD);
  await user.click(screen.getByRole("button", { name: "Sign in" }));
}

export type FakeMediaQuery = { setMatches(matches: boolean): void };

/** Fakes `(prefers-color-scheme: dark)`: `matches` is the Mac's current setting; setMatches flips it live. */
export function mockMatchMedia(matches: boolean): FakeMediaQuery {
  let current = matches;
  const listeners = new Set<(event: MediaQueryListEvent) => void>();
  const query = {
    get matches() {
      return current;
    },
    media: "(prefers-color-scheme: dark)",
    onchange: null,
    addEventListener: (_type: string, listener: (event: MediaQueryListEvent) => void) => listeners.add(listener),
    removeEventListener: (_type: string, listener: (event: MediaQueryListEvent) => void) =>
      listeners.delete(listener),
    addListener: (listener: (event: MediaQueryListEvent) => void) => listeners.add(listener),
    removeListener: (listener: (event: MediaQueryListEvent) => void) => listeners.delete(listener),
    dispatchEvent: () => true,
  };
  Object.defineProperty(window, "matchMedia", {
    configurable: true,
    writable: true,
    value: () => query,
  });
  return {
    setMatches(next) {
      current = next;
      for (const listener of [...listeners]) listener({ matches: next, media: query.media } as MediaQueryListEvent);
    },
  };
}

/** Runs the inline theme script exactly as index.html ships it, as the browser would before React loads. */
export function runIndexHtmlThemeScript(): void {
  const found = /<script id="theme-boot">([\s\S]*?)<\/script>/.exec(indexHtml);
  if (!found) throw new Error('index.html has no <script id="theme-boot">');
  new Function(found[1])();
}
