import { act, render, screen, waitFor } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { RouterProvider, createMemoryRouter } from "react-router";
import { describe, expect, test, vi } from "vitest";
import { finishSignOut, queryKeys } from "../src/api/hooks";
import { routes } from "../src/router";
import { renderAt, settled, signInThroughForm } from "./helpers";
import {
  NO_ACCOUNT,
  SIGNED_IN,
  SIGNED_OUT,
  TEST_OWNER,
  TEST_PASSWORD,
  lastRequest,
  mockAuthState,
  server,
} from "./msw";

describe("with no account yet", () => {
  // Review Focus 4
  test.each(["/inventory", "/", "/signin", "/forgot", "/settings/account"])(
    "no account yet: %s lands on Create your account",
    async (path) => {
      mockAuthState(NO_ACCOUNT);
      const { router } = renderAt(path);
      expect(await screen.findByRole("heading", { name: "Create your account" })).toBeInTheDocument();
      expect(router.state.location.pathname).toBe("/setup");
    },
  );
});

describe("signed out", () => {
  test("signed out: a deep link goes to sign in, then back to the page asked for", async () => {
    // Review Focus 4
    mockAuthState(SIGNED_OUT);
    const { router, user, queryClient } = renderAt("/gear");
    await waitFor(() => expect(router.state.location.pathname).toBe("/signin"));
    expect(router.state.location.search).toBe("?next=%2Fgear");
    await signInThroughForm(user); // msw answers 200 + switches auth state
    await waitFor(() => expect(router.state.location.pathname).toBe("/gear"));
    expect(lastRequest("/api/auth/signin")?.body).toEqual({
      username: TEST_OWNER.username,
      password: TEST_PASSWORD,
      keepSignedIn: true,
    });
    await settled(queryClient);
  });

  test("the page asked for keeps its query string through sign-in", async () => {
    mockAuthState(SIGNED_OUT);
    const { router, user, queryClient } = renderAt("/party?hero=kael");
    await waitFor(() => expect(router.state.location.pathname).toBe("/signin"));
    expect(router.state.location.search).toBe("?next=%2Fparty%3Fhero%3Dkael");
    await signInThroughForm(user);
    await waitFor(() => expect(router.state.location.pathname).toBe("/party"));
    expect(router.state.location.search).toBe("?hero=kael");
    await settled(queryClient);
  });

  test("the Overview needs no next: it is where sign-in goes anyway", async () => {
    mockAuthState(SIGNED_OUT);
    const { router } = renderAt("/");
    await waitFor(() => expect(router.state.location.pathname).toBe("/signin"));
    expect(router.state.location.search).toBe("");
  });

  test("once the account exists, the first-run page sends you to sign in", async () => {
    mockAuthState(SIGNED_OUT);
    const { router } = renderAt("/setup");
    await waitFor(() => expect(router.state.location.pathname).toBe("/signin"));
  });

  test.each([
    "https://evil.example/",
    "//evil.example/",
    "/\\evil.example",
    "/\t/evil.example/gear", // parsing drops the tab, leaving //evil.example/gear: another site's page
    // Dot-segments collapse after parsing and leave a path that starts with "//" or "/\": another site.
    "/.//evil.example",
    "/..//evil.example",
    "/%2e//evil.example",
    "/a/..//evil.example",
    "/x/../\\evil.example",
    "javascript:alert(1)",
    "/signin",
    "gear",
  ])(
    "after sign-in, a next that isn't a page in the app (%s) goes to the Overview",
    async (next) => {
      mockAuthState(SIGNED_OUT);
      const { router, user, queryClient } = renderAt(`/signin?next=${encodeURIComponent(next)}`);
      await signInThroughForm(user);
      await waitFor(() => expect(router.state.location.pathname).toBe("/"));
      expect(router.state.location.search).toBe("");
      await settled(queryClient);
    },
  );
});

describe("when the server can't be reached", () => {
  test("every page says so and offers to try again", async () => {
    server.use(http.get("/api/auth/state", () => HttpResponse.error()));
    const { user, queryClient } = renderAt("/party");
    expect(await screen.findByRole("heading", { name: "Can't reach the dashboard's server" })).toBeInTheDocument();
    server.resetHandlers();
    await user.click(screen.getByRole("button", { name: "Try again" }));
    expect(await screen.findByRole("heading", { name: "Party" })).toBeInTheDocument();
    await settled(queryClient);
  });
});

describe("when a page breaks", () => {
  test("the app's own error page says so and offers a reload, instead of the router's raw one", async () => {
    // React and the router both report the thrown error; that report is expected here.
    const report = vi.spyOn(console, "error").mockImplementation(() => {});
    try {
      function Broken(): never {
        throw new Error("broken on purpose");
      }
      // The app's own root route, with a page that throws under it.
      const router = createMemoryRouter(
        [{ errorElement: routes[0].errorElement, children: [{ path: "/broken", element: <Broken /> }] }],
        { initialEntries: ["/broken"] },
      );
      render(<RouterProvider router={router} />);
      expect(await screen.findByRole("heading", { name: "Something went wrong" })).toBeInTheDocument();
      expect(screen.getByRole("button", { name: "Reload" })).toBeInTheDocument();
      expect(screen.queryByText(/Unexpected Application Error/)).toBeNull();
    } finally {
      report.mockRestore();
    }
  });
});

describe("signed in", () => {
  test.each(["/signin", "/setup", "/forgot"])("signed in: %s goes to the Overview", async (path) => {
    const { router, queryClient } = renderAt(path);
    await waitFor(() => expect(router.state.location.pathname).toBe("/"));
    await settled(queryClient);
  });

  test.each([
    ["/", "Overview"],
    ["/party", "Party"],
    ["/inventory", "Inventory"],
    ["/gear", "Gear"],
    ["/location", "Location"],
    ["/admin", "Admin"],
    ["/settings", "Settings"],
    ["/settings/account", "Settings"],
  ])("signed in: %s shows the %s page", async (path, heading) => {
    const { queryClient } = renderAt(path);
    expect(await screen.findByRole("heading", { name: heading })).toBeInTheDocument();
    await settled(queryClient);
  });

  test("when you sign out on purpose, the guard's own redirect leaves the sign-in address plain too", async () => {
    // useSignOut navigates to /signin itself, but the guard sees the signed-out state too and redirects; whichever
    // of the two lands last, the address must come out the same (this used to be a race).
    const { router, queryClient } = renderAt("/party");
    expect(await screen.findByRole("heading", { name: "Party" })).toBeInTheDocument();
    act(() => finishSignOut(queryClient));
    await waitFor(() => expect(router.state.location.pathname).toBe("/signin"));
    await settled(queryClient);
    expect(router.state.location.search).toBe("");
  });

  test("once someone is signed in again, an earlier sign-out on purpose is forgotten, so a later expiry keeps its way back", async () => {
    const { router, queryClient } = renderAt("/party");
    expect(await screen.findByRole("heading", { name: "Party" })).toBeInTheDocument();
    act(() => finishSignOut(queryClient));
    await waitFor(() => expect(router.state.location.pathname).toBe("/signin"));
    expect(router.state.location.search).toBe("");

    // Another tab signs in; this one finds out and moves on.
    mockAuthState(SIGNED_IN);
    await act(() => queryClient.invalidateQueries({ queryKey: queryKeys.auth }));
    await waitFor(() => expect(router.state.location.pathname).toBe("/"));
    await act(() => router.navigate("/party"));
    expect(await screen.findByRole("heading", { name: "Party" })).toBeInTheDocument();

    // Later the session ends on its own. It isn't a sign-out on purpose, so it must remember where it was.
    mockAuthState(SIGNED_OUT);
    await act(() => queryClient.invalidateQueries({ queryKey: queryKeys.auth }));
    await waitFor(() => expect(router.state.location.pathname).toBe("/signin"));
    expect(router.state.location.search).toBe("?next=%2Fparty");
    await settled(queryClient);
  });

  test("a signed_out answer from any route sends you to sign in, back to where you were", async () => {
    // The session ended on the server (expired, revoked, or signed out in another tab).
    server.use(
      http.get("/api/settings", () => {
        mockAuthState(SIGNED_OUT);
        return HttpResponse.json({ error: "signed_out", message: "Please sign in." }, { status: 401 });
      }),
    );
    const { router, queryClient } = renderAt("/party");
    await waitFor(() => expect(router.state.location.pathname).toBe("/signin"));
    expect(router.state.location.search).toBe("?next=%2Fparty");
    await settled(queryClient);
  });
});
