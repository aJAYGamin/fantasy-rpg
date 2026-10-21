import { type QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook, waitFor } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import type { ReactNode } from "react";
import { MemoryRouter } from "react-router";
import { afterEach, expect, test, vi } from "vitest";
import { DEFAULT_SETTINGS } from "../../shared/src/api";
import {
  createQueryClient,
  queryKeys,
  useAuthState,
  useGameStatus,
  useNotifications,
  useSettings,
  useSetup,
  useSignIn,
  useSignOut,
  useSignOutFailed,
  useSignedOutByChoice,
  useUpdateSettings,
} from "../src/api/hooks";
import { SIGNED_OUT, TEST_PASSWORD, requestsTo, server } from "./msw";

const clients: QueryClient[] = [];

function renderWithData<T>(hook: () => T) {
  const queryClient = createQueryClient();
  queryClient.setDefaultOptions({ queries: { retry: false }, mutations: { retry: false } });
  clients.push(queryClient);
  const wrapper = ({ children }: { children: ReactNode }) => (
    // The router is there for useSignOut, which goes to the sign-in page when it is done.
    <QueryClientProvider client={queryClient}>
      <MemoryRouter>{children}</MemoryRouter>
    </QueryClientProvider>
  );
  return { ...renderHook(hook, { wrapper }), queryClient };
}

afterEach(() => {
  vi.useRealTimers();
  for (const client of clients.splice(0)) client.clear();
});

test("a settings change shows at once, before the server answers, and stays once saved", async () => {
  let answer = () => {};
  const answered = new Promise<void>((resolve) => {
    answer = resolve;
  });
  server.use(
    http.patch("/api/settings", async () => {
      await answered;
      return HttpResponse.json({ ...DEFAULT_SETTINGS, appearance: "dark" });
    }),
  );
  const { result } = renderWithData(() => ({ settings: useSettings(), update: useUpdateSettings() }));
  await waitFor(() => expect(result.current.settings.data?.appearance).toBe("light"));

  act(() => result.current.update.mutate({ appearance: "dark" }));
  await waitFor(() => expect(result.current.settings.data?.appearance).toBe("dark"));
  expect(result.current.update.isPending).toBe(true);

  answer();
  await waitFor(() => expect(result.current.update.isSuccess).toBe(true));
  expect(result.current.settings.data?.appearance).toBe("dark");
});

test("a settings change the server refuses is undone", async () => {
  server.use(
    http.patch("/api/settings", () =>
      HttpResponse.json(
        { error: "invalid_setting", message: "That setting isn't valid.", setting: "appearance" },
        { status: 400 },
      ),
    ),
  );
  const { result } = renderWithData(() => ({ settings: useSettings(), update: useUpdateSettings() }));
  await waitFor(() => expect(result.current.settings.data?.appearance).toBe("light"));
  act(() => result.current.update.mutate({ appearance: "dark" }));
  await waitFor(() => expect(result.current.update.isError).toBe(true));
  expect(result.current.settings.data?.appearance).toBe("light");
});

test("signing out forgets the account's data and leaves the auth state signed out", async () => {
  // As in the app: settings are only asked for while someone is signed in.
  const { result, queryClient } = renderWithData(() => {
    const auth = useAuthState();
    return { auth, settings: useSettings({ enabled: Boolean(auth.data?.user) }), signOut: useSignOut() };
  });
  await waitFor(() => expect(result.current.settings.isSuccess).toBe(true));
  act(() => result.current.signOut.mutate());
  await waitFor(() => expect(result.current.signOut.isSuccess).toBe(true));
  expect(requestsTo("/api/auth/signout")).toHaveLength(1);
  expect(queryClient.getQueryData(queryKeys.auth)).toEqual(SIGNED_OUT);
  expect(queryClient.getQueryData(queryKeys.settings)).toBeUndefined();
});

test.each<[string, number, string, () => unknown]>([
  ["game status", 3_000, "/api/game/status", useGameStatus],
  ["notifications", 30_000, "/api/notifications", useNotifications],
])("%s: asked for again every %i ms", async (_name, every, path, hook) => {
  vi.useFakeTimers({ toFake: ["setInterval", "clearInterval"] });
  renderWithData(hook);
  await vi.waitFor(() => expect(requestsTo(path)).toHaveLength(1));
  await act(() => vi.advanceTimersByTimeAsync(every - 100));
  expect(requestsTo(path)).toHaveLength(1);
  await act(() => vi.advanceTimersByTimeAsync(100));
  await vi.waitFor(() => expect(requestsTo(path)).toHaveLength(2));
});

// The two notes about an earlier sign-out are private to hooks.ts; these are their keys, and the hooks that read them.
const SIGNED_OUT_BY_CHOICE = ["auth", "signed-out-by-choice"];
const SIGN_OUT_FAILED = ["notice", "sign-out-failed"];

async function renderWithOldSignOut<T>(hook: () => T) {
  const rendered = renderWithData(() => ({
    mutation: hook(),
    byChoice: useSignedOutByChoice(),
    failed: useSignOutFailed().failed,
  }));
  act(() => {
    rendered.queryClient.setQueryData(SIGNED_OUT_BY_CHOICE, true);
    rendered.queryClient.setQueryData(SIGN_OUT_FAILED, true);
  });
  await waitFor(() => expect(rendered.result.current).toMatchObject({ byChoice: true, failed: true }));
  return rendered;
}

test("signing in forgets an earlier sign-out: where it was going, and that it had failed", async () => {
  const { result } = await renderWithOldSignOut(useSignIn);
  act(() => result.current.mutation.mutate({ username: "owner", password: TEST_PASSWORD, keepSignedIn: false }));
  await waitFor(() => expect(result.current.mutation.isSuccess).toBe(true));
  expect(result.current).toMatchObject({ byChoice: false, failed: false });
});

test("creating the account forgets an earlier sign-out too", async () => {
  const { result } = await renderWithOldSignOut(useSetup);
  act(() =>
    result.current.mutation.mutate({
      username: "owner",
      displayName: "Test Owner",
      password: TEST_PASSWORD,
      answers: ["Midwinter", "Tarnwick", "Lanterns and Lanes"],
    }),
  );
  await waitFor(() => expect(result.current.mutation.isSuccess).toBe(true));
  expect(result.current).toMatchObject({ byChoice: false, failed: false });
});
