// Web test helpers: render the real app at a path, fake the Mac's light/dark setting, run index.html's theme script.

import type { QueryClient } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent, { type UserEvent } from "@testing-library/user-event";
import { createMemoryRouter } from "react-router";
import { expect } from "vitest";
import indexHtml from "../index.html?raw";
import { AppProviders } from "../src/App";
import { createQueryClient } from "../src/api/hooks";
import { routes } from "../src/router";
import { TEST_OWNER, TEST_PASSWORD } from "./msw";

const openClients: QueryClient[] = [];

/** Renders the whole app (router, data, theme) at `path`, e.g. "/gear" or "/signin?next=%2Fparty". */
export function renderAt(path: string) {
  const queryClient = createQueryClient();
  // A failed request in a test is the answer under test, not something to retry.
  queryClient.setDefaultOptions({
    queries: { ...queryClient.getDefaultOptions().queries, retry: false },
    mutations: { retry: false },
  });
  openClients.push(queryClient);
  const router = createMemoryRouter(routes, { initialEntries: [path] });
  const user = userEvent.setup();
  const view = render(<AppProviders queryClient={queryClient} router={router} />);
  return { ...view, router, queryClient, user };
}

/** Drops every query client renderAt made, so no refetch timer outlives its test. */
export function clearQueryClients(): void {
  for (const client of openClients.splice(0)) client.clear();
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
