import { act, render, screen, waitFor, within } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { describe, expect, test, vi } from "vitest";
import type { Notification } from "../../shared/src/api";
import { COLOR_THEMES, colorThemeName } from "../../shared/src/colorThemes";
import tooltipCss from "../src/components/Tooltip.module.css?raw";
import { Dialog } from "../src/components";
import { PageHeader } from "../src/shell/PageHeader";
import { queryKeys } from "../src/api/hooks";
import { click, keyboard, mockMatchMedia, renderAt, renderShellAt, settled, signInThroughForm, topBar, type } from "./helpers";
import { NO_ACCOUNT, SIGNED_OUT, lastRequest, mockAuthState, mockNotifications, requestsTo, server } from "./msw";

const topButton = (name: string) => within(topBar()).getByRole("button", { name });
const PAGES = ["Overview", "Party", "Inventory", "Gear", "Location", "Admin"];

function unread(id: number, title: string): Notification {
  return { id, kind: "security", title, body: "From a test.", createdAt: new Date().toISOString(), read: false };
}

describe("sidebar", () => {
  test("the sidebar shows the three groups and filters", async () => {
    const { queryClient } = renderShellAt("/");
    expect(screen.getByText("OVERVIEW")).toBeVisible();
    expect(screen.getByText("DEBUG")).toBeVisible();
    expect(screen.getByText("ADMIN")).toBeVisible();
    expect(screen.getByText("In development")).toBeVisible();
    await type(screen.getByPlaceholderText("Filter"), "gea");
    expect(screen.getByRole("link", { name: "Gear" })).toBeVisible();
    expect(screen.queryByRole("link", { name: "Party" })).toBeNull();
    expect(screen.queryByText("ADMIN")).toBeNull();
    await settled(queryClient);
  });

  test("the filter ignores capitals, says when nothing matches, and Escape clears it", async () => {
    const { queryClient } = renderShellAt("/");
    const filter = screen.getByPlaceholderText("Filter");
    await type(filter, "LOC");
    expect(screen.getAllByRole("link").filter((link) => PAGES.includes(link.textContent ?? ""))).toHaveLength(1);
    expect(screen.getByRole("link", { name: "Location" })).toBeVisible();
    await type(filter, "kraken");
    expect(screen.getByText("No pages match")).toBeVisible();
    expect(screen.queryByText("DEBUG")).toBeNull();
    await keyboard("{Escape}");
    expect(filter).toHaveValue("");
    for (const name of PAGES) expect(screen.getByRole("link", { name })).toBeVisible();
    await settled(queryClient);
  });

  test("the page you're on is marked, and the In development badge describes Admin", async () => {
    const { queryClient } = renderShellAt("/party?hero=kael");
    expect(screen.getByRole("link", { name: "Party" })).toHaveAttribute("aria-current", "page");
    expect(screen.getByRole("link", { name: "Overview" })).not.toHaveAttribute("aria-current");
    expect(screen.getByRole("link", { name: "Admin" })).toHaveAccessibleDescription("In development");
    await settled(queryClient);
  });

  test("a sidebar link goes to its page", async () => {
    const { router, queryClient } = renderShellAt("/");
    await click(screen.getByRole("link", { name: "Gear" }));
    expect(router.state.location.pathname).toBe("/gear");
    expect(screen.getByRole("heading", { level: 1, name: "Gear" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Gear" })).toHaveAttribute("aria-current", "page");
    await settled(queryClient);
  });

  test("collapse keeps every page reachable by icon", async () => {
    const { queryClient } = renderShellAt("/", { settings: { sidebar: "icons" } });
    for (const name of PAGES) expect(screen.getByRole("link", { name })).toBeInTheDocument();
    expect(screen.queryByPlaceholderText("Filter")).toBeNull();
    await settled(queryClient);
  });

  test("folding the sidebar clears the filter, so unfolding shows every page again", async () => {
    const { queryClient } = renderShellAt("/");
    await type(screen.getByPlaceholderText("Filter"), "gea");
    expect(screen.queryByRole("link", { name: "Party" })).toBeNull();
    await click(topButton("Collapse sidebar"));
    await click(topButton("Expand sidebar"));
    expect(screen.getByPlaceholderText("Filter")).toHaveValue("");
    for (const name of PAGES) expect(screen.getByRole("link", { name })).toBeVisible();
    await settled(queryClient);
  });

  test("the collapse button folds the sidebar to icons and back, and saves it", async () => {
    const { queryClient } = renderShellAt("/");
    await click(topButton("Collapse sidebar"));
    await waitFor(() => expect(lastRequest("/api/settings")?.body).toEqual({ sidebar: "icons" }));
    expect(screen.queryByPlaceholderText("Filter")).toBeNull();
    for (const name of PAGES) expect(screen.getByRole("link", { name })).toBeInTheDocument();
    await click(topButton("Expand sidebar"));
    await waitFor(() => expect(lastRequest("/api/settings")?.body).toEqual({ sidebar: "expanded" }));
    expect(screen.getByPlaceholderText("Filter")).toBeVisible();
    await settled(queryClient);
  });
});

describe("top bar", () => {
  test("every top-bar button has a name", async () => {
    const { queryClient } = renderShellAt("/");
    const buttons = within(topBar()).getAllByRole("button");
    expect(buttons.length).toBeGreaterThanOrEqual(6);
    for (const b of buttons) expect(b).toHaveAccessibleName();
    await settled(queryClient);
  });

  test("the theme button flips light and dark and saves it", async () => {
    const { queryClient } = renderShellAt("/", { settings: { appearance: "light" } });
    await click(screen.getByRole("button", { name: "Switch to dark mode" }));
    await waitFor(() => expect(lastRequest("/api/settings")?.body).toEqual({ appearance: "dark" }));
    expect(document.documentElement.dataset.theme).toBe("dark");
    await click(screen.getByRole("button", { name: "Switch to light mode" }));
    await waitFor(() => expect(lastRequest("/api/settings")?.body).toEqual({ appearance: "light" }));
    expect(document.documentElement.dataset.theme).toBe("light");
    await settled(queryClient);
  });

  test("following a dark Mac, the theme button offers light", async () => {
    mockMatchMedia(true);
    const { queryClient } = renderShellAt("/", { settings: { appearance: "system" } });
    await click(screen.getByRole("button", { name: "Switch to light mode" }));
    await waitFor(() => expect(lastRequest("/api/settings")?.body).toEqual({ appearance: "light" }));
    await settled(queryClient);
  });

  test("the settings icon goes to Settings", async () => {
    const { router, queryClient } = renderShellAt("/");
    await click(within(topBar()).getByRole("link", { name: "Settings" }));
    // /settings opens the first section (R31).
    expect(router.state.location.pathname).toBe("/settings/appearance");
    await settled(queryClient);
  });

  test("the search box, ⌘K and Ctrl+K open search from anywhere; Escape closes it", async () => {
    const { queryClient } = renderShellAt("/");
    const box = topButton("Search");
    expect(box).toHaveTextContent("Search for anything — a hero, an item, a map…");
    await click(box);
    const search = screen.getByRole("dialog", { name: "Search" });
    expect(within(search).getByPlaceholderText("Search for anything — a hero, an item, a map…")).toHaveFocus();
    await keyboard("{Escape}");
    expect(screen.queryByRole("dialog", { name: "Search" })).toBeNull();
    expect(box).toHaveFocus();

    // From inside a text field too, and the K doesn't land in it.
    const filter = screen.getByPlaceholderText("Filter");
    await click(filter);
    await keyboard("{Meta>}k{/Meta}");
    expect(screen.getByRole("dialog", { name: "Search" })).toBeInTheDocument();
    await keyboard("{Escape}");
    expect(filter).toHaveFocus();
    await keyboard("{Control>}k{/Control}");
    expect(screen.getByRole("dialog", { name: "Search" })).toBeInTheDocument();
    await keyboard("{Escape}");
    expect(filter).toHaveValue("");
    await settled(queryClient);
  });

  test("a keydown with no key at all (Chrome's autofill sends those) is ignored, not an error", async () => {
    const { queryClient } = renderShellAt("/");
    const errors: unknown[] = [];
    const onError = (event: ErrorEvent) => {
      errors.push(event.error);
      event.preventDefault();
    };
    window.addEventListener("error", onError);
    try {
      document.dispatchEvent(new Event("keydown"));
    } finally {
      window.removeEventListener("error", onError);
    }
    expect(errors).toEqual([]);
    expect(screen.queryByRole("dialog", { name: "Search" })).toBeNull();
    await settled(queryClient);
  });

  test("⌘K does nothing while another dialog is open", async () => {
    const { queryClient } = renderShellAt("/");
    render(
      <Dialog open onClose={() => {}} title="Reset to before debugging?">
        <p>This rewinds the game.</p>
      </Dialog>,
    );
    await keyboard("{Meta>}k{/Meta}");
    await keyboard("{Control>}k{/Control}");
    expect(screen.queryByRole("dialog", { name: "Search" })).toBeNull();
    expect(screen.getByRole("dialog", { name: "Reset to before debugging?" })).toBeInTheDocument();
    await settled(queryClient);
  });

  test("on a Mac, Ctrl+K in a text field is left to the field; ⌘K, or Ctrl+K elsewhere, opens search", async () => {
    Object.defineProperty(navigator, "platform", { configurable: true, get: () => "MacIntel" });
    try {
      const { queryClient } = renderShellAt("/");
      const filter = screen.getByPlaceholderText("Filter");
      await click(filter);
      await keyboard("{Control>}k{/Control}");
      expect(screen.queryByRole("dialog", { name: "Search" })).toBeNull();
      await keyboard("{Meta>}k{/Meta}");
      expect(screen.getByRole("dialog", { name: "Search" })).toBeInTheDocument();
      await keyboard("{Escape}");
      expect(filter).toHaveFocus();

      topButton("Collapse sidebar").focus();
      await keyboard("{Control>}k{/Control}");
      expect(screen.getByRole("dialog", { name: "Search" })).toBeInTheDocument();
      await keyboard("{Escape}");
      await settled(queryClient);
    } finally {
      Reflect.deleteProperty(navigator, "platform");
    }
  });

  test("the bell shows the unread count in its badge and its name, and opens the notifications", async () => {
    mockNotifications([unread(1, "Failed sign-in"), unread(2, "Failed sign-in"), unread(3, "Sign-in locked")]);
    const { queryClient } = renderShellAt("/");
    const bell = topButton("Notifications, 3 unread");
    expect(within(bell).getByText("3")).toBeVisible();
    await click(bell);
    expect(screen.getByRole("dialog", { name: "Notifications" })).toBeInTheDocument();
    await keyboard("{Escape}");
    expect(screen.queryByRole("dialog", { name: "Notifications" })).toBeNull();
    expect(bell).toHaveFocus();
    await settled(queryClient);
  });

  test("with nothing unread the bell has no badge", async () => {
    const { queryClient } = renderShellAt("/");
    const bell = topButton("Notifications");
    expect(within(bell).queryByText("0")).toBeNull();
    expect(bell.textContent).toBe("");
    await settled(queryClient);
  });

  test("the palette button opens the twenty color themes in the cursor wheel's order, Amethyst chosen", async () => {
    const { queryClient } = renderShellAt("/");
    await click(topButton("Color theme"));
    const panel = screen.getByRole("dialog", { name: "Color theme" });
    const themes = within(panel).getByRole("radiogroup", { name: "Color theme" });
    const radios = within(themes).getAllByRole("radio");
    expect(radios.map((radio) => radio.textContent)).toEqual(COLOR_THEMES.map(colorThemeName));
    const amethyst = within(themes).getByRole("radio", { name: "Amethyst" });
    expect(amethyst).toHaveAttribute("aria-checked", "true");
    expect(amethyst).toHaveFocus();
    await settled(queryClient);
  });

  test("picking a color theme saves it and recolors the dashboard at once", async () => {
    const { queryClient } = renderShellAt("/");
    await click(topButton("Color theme"));
    await click(screen.getByRole("radio", { name: "Garnet" }));
    expect(document.documentElement.dataset.color).toBe("garnet");
    expect(screen.getByRole("radio", { name: "Garnet" })).toHaveAttribute("aria-checked", "true");
    await waitFor(() => expect(lastRequest("/api/settings")?.body).toEqual({ colorTheme: "garnet" }));
    await settled(queryClient);
  });

  test("the arrow keys move through the grid of themes: across a row, and up and down a column", async () => {
    const { queryClient } = renderShellAt("/");
    await click(topButton("Color theme"));
    const chosen = () => screen.getByRole("radio", { checked: true });
    await keyboard("{ArrowRight}");
    expect(chosen()).toHaveAccessibleName("Arcane");
    expect(chosen()).toHaveFocus();
    await keyboard("{ArrowDown}");
    expect(chosen()).toHaveAccessibleName("Gilded");
    await keyboard("{ArrowUp}{ArrowUp}");
    expect(chosen()).toHaveAccessibleName("Void");
    await keyboard("{ArrowLeft}{ArrowLeft}");
    expect(chosen()).toHaveAccessibleName("Tidal");
    await keyboard("{End}");
    expect(chosen()).toHaveAccessibleName("Lunar");
    await keyboard("{Home}");
    expect(chosen()).toHaveAccessibleName("Amethyst");
    await waitFor(() => expect(lastRequest("/api/settings")?.body).toEqual({ colorTheme: "amethyst" }));
    await settled(queryClient);
  });

  test("Escape closes the color themes and gives the focus back to the palette button", async () => {
    const { queryClient } = renderShellAt("/");
    const trigger = topButton("Color theme");
    await click(trigger);
    await keyboard("{Escape}");
    expect(screen.queryByRole("dialog", { name: "Color theme" })).toBeNull();
    expect(trigger).toHaveFocus();
    expect(requestsTo("/api/settings").filter((seen) => seen.method === "PATCH")).toEqual([]);
    await settled(queryClient);
  });

  test("a saved color theme shows chosen when the palette opens", async () => {
    const { queryClient } = renderShellAt("/", { settings: { colorTheme: "storm" } });
    await click(topButton("Color theme"));
    expect(screen.getByRole("radio", { name: "Storm" })).toHaveAttribute("aria-checked", "true");
    expect(screen.getByRole("radio", { name: "Storm" })).toHaveFocus();
    await settled(queryClient);
  });

  test("full screen goes in and out, and the button says which", async () => {
    const enter = vi.fn(() => Promise.resolve());
    const exit = vi.fn(() => Promise.resolve());
    const root = document.documentElement;
    Object.defineProperty(root, "requestFullscreen", { configurable: true, value: enter });
    Object.defineProperty(document, "exitFullscreen", { configurable: true, value: exit });
    const fullscreen = (element: Element | null) =>
      act(() => {
        Object.defineProperty(document, "fullscreenElement", { configurable: true, value: element });
        document.dispatchEvent(new Event("fullscreenchange"));
      });
    try {
      const { queryClient } = renderShellAt("/");
      await click(topButton("Full screen"));
      expect(enter).toHaveBeenCalledTimes(1);
      fullscreen(root);
      await click(topButton("Exit full screen"));
      expect(exit).toHaveBeenCalledTimes(1);
      // Leaving with the Esc key (the browser's own way out) swaps the button back too.
      fullscreen(null);
      expect(topButton("Full screen")).toBeInTheDocument();
      await settled(queryClient);
    } finally {
      Reflect.deleteProperty(root, "requestFullscreen");
      Reflect.deleteProperty(document, "exitFullscreen");
      Reflect.deleteProperty(document, "fullscreenElement");
    }
  });
});

describe("avatar menu", () => {
  test("the avatar shows the owner's initials, or their picture", async () => {
    const { queryClient, unmount } = renderShellAt("/");
    expect(within(topButton("Account menu")).getByText("TO")).toBeVisible();
    await settled(queryClient);
    unmount();

    const second = renderShellAt("/", { user: { hasAvatar: true } });
    const picture = topButton("Account menu").querySelector("img");
    expect(picture).toHaveAttribute("src", "/api/account/avatar");
    expect(picture).toHaveAttribute("alt", "");
    await settled(second.queryClient);
  });

  test("the avatar menu signs out", async () => {
    const { router, queryClient } = renderShellAt("/party");
    await click(topButton("Account menu"));
    await click(screen.getByRole("menuitem", { name: "Sign out" }));
    await waitFor(() => expect(router.state.location.pathname).toBe("/signin"));
    expect(requestsTo("/api/auth/signout")).toHaveLength(1);
    expect(lastRequest("/api/auth/signout")?.body).toEqual({});
    // R25: signing out on purpose is not an interrupted visit, so sign-in doesn't offer to go back to Party.
    await settled(queryClient);
    expect(router.state.location.search).toBe("");
    expect(screen.getByRole("heading", { name: "Sign in" })).toBeInTheDocument();
  });

  test("a sign-out the server refuses keeps the menu open and says so; trying again works", async () => {
    server.use(
      http.post("/api/auth/signout", () =>
        HttpResponse.json({ error: "server_error", message: "Something went wrong on the server." }, { status: 500 }),
      ),
    );
    const { router, queryClient } = renderShellAt("/party");
    await click(topButton("Account menu"));
    await click(screen.getByRole("menuitem", { name: "Sign out" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("Couldn't sign out. Try again.");
    expect(screen.getByRole("menu")).toBeInTheDocument();
    expect(router.state.location.pathname).toBe("/party");
    const signOut = screen.getByRole("menuitem", { name: "Sign out" });
    expect(signOut).not.toHaveAttribute("aria-disabled");

    server.resetHandlers();
    await click(signOut);
    await waitFor(() => expect(router.state.location.pathname).toBe("/signin"));
    await settled(queryClient);
  });

  test("Sign out can't be sent twice while the first is on its way", async () => {
    let answer = () => {};
    const answered = new Promise<void>((resolve) => {
      answer = resolve;
    });
    server.use(
      http.post("/api/auth/signout", async () => {
        await answered;
        mockAuthState(SIGNED_OUT);
        return new HttpResponse(null, { status: 204 });
      }),
    );
    const { router, queryClient } = renderShellAt("/");
    await click(topButton("Account menu"));
    const signOut = screen.getByRole("menuitem", { name: "Sign out" });
    await click(signOut);
    await waitFor(() => expect(signOut).toHaveAttribute("aria-disabled", "true"));
    expect(screen.getByRole("menu")).toBeInTheDocument();
    await click(signOut);
    answer();
    await waitFor(() => expect(router.state.location.pathname).toBe("/signin"));
    expect(requestsTo("/api/auth/signout")).toHaveLength(1);
    await settled(queryClient);
  });

  // R29: the answer to a sign-out belongs to the sign-out, not to the menu that sent it.
  function heldSignOut(outcome: "signed-out" | "refused") {
    let answer = () => {};
    const answered = new Promise<void>((resolve) => {
      answer = resolve;
    });
    server.use(
      http.post("/api/auth/signout", async () => {
        await answered;
        if (outcome === "refused") {
          return HttpResponse.json({ error: "server_error", message: "Something went wrong on the server." }, { status: 500 });
        }
        mockAuthState(SIGNED_OUT);
        return new HttpResponse(null, { status: 204 });
      }),
    );
    return answer;
  }

  test("a sign-out that succeeds after the menu was dismissed still lands on the sign-in page", async () => {
    const answer = heldSignOut("signed-out");
    const { router, queryClient } = renderShellAt("/party");
    await click(topButton("Account menu"));
    await click(screen.getByRole("menuitem", { name: "Sign out" }));
    await keyboard("{Escape}");
    expect(screen.queryByRole("menu")).toBeNull();
    expect(router.state.location.pathname).toBe("/party");
    answer();
    await waitFor(() => expect(router.state.location.pathname).toBe("/signin"));
    await settled(queryClient);
    expect(router.state.location.search).toBe("");
    expect(screen.getByRole("heading", { name: "Sign in" })).toBeInTheDocument();
  });

  test("a sign-out that fails after the menu was dismissed says so in the shell, and the notice can be dismissed", async () => {
    const answer = heldSignOut("refused");
    const { router, queryClient } = renderShellAt("/party");
    await click(topButton("Account menu"));
    await click(screen.getByRole("menuitem", { name: "Sign out" }));
    await keyboard("{Escape}");
    expect(screen.queryByRole("menu")).toBeNull();
    answer();
    const notice = await screen.findByRole("alert");
    expect(notice).toHaveTextContent("Couldn't sign out. Try again.");
    expect(screen.queryByRole("menu")).toBeNull();
    expect(router.state.location.pathname).toBe("/party");
    await click(within(notice).getByRole("button", { name: "Dismiss" }));
    expect(screen.queryByRole("alert")).toBeNull();
    await settled(queryClient);
  });

  test("the shell's sign-out notice goes when sign-out is tried again", async () => {
    const answer = heldSignOut("refused");
    const { router, queryClient } = renderShellAt("/party");
    await click(topButton("Account menu"));
    await click(screen.getByRole("menuitem", { name: "Sign out" }));
    await keyboard("{Escape}");
    answer();
    await screen.findByRole("alert");

    server.resetHandlers();
    await click(topButton("Account menu"));
    // The notice is not in the way of the menu, and does not repeat what the menu would say.
    await click(screen.getByRole("menuitem", { name: "Sign out" }));
    await waitFor(() => expect(router.state.location.pathname).toBe("/signin"));
    expect(screen.queryByRole("alert")).toBeNull();
    await settled(queryClient);
  });

  test("a sign-out notice from an earlier session is gone once the owner signs in again", async () => {
    // The sign-out failed after its menu was gone, so the shell showed its notice. Then the session ended on the
    // server and the owner signed in again: the old notice must not greet the new session.
    const answer = heldSignOut("refused");
    const { router, queryClient, user } = renderShellAt("/party");
    await click(topButton("Account menu"));
    await click(screen.getByRole("menuitem", { name: "Sign out" }));
    await keyboard("{Escape}");
    answer();
    expect(await screen.findByRole("alert")).toHaveTextContent("Couldn't sign out. Try again.");

    mockAuthState(SIGNED_OUT);
    await act(() => queryClient.invalidateQueries({ queryKey: queryKeys.auth }));
    await waitFor(() => expect(router.state.location.pathname).toBe("/signin"));
    expect(router.state.location.search).toBe("?next=%2Fparty");

    await signInThroughForm(user);
    await waitFor(() => expect(router.state.location.pathname).toBe("/party"));
    expect(await screen.findByRole("heading", { name: "Party" })).toBeInTheDocument();
    expect(screen.queryByRole("alert")).toBeNull();
    await settled(queryClient);
  });

  test("a failed sign-out with the menu still open is announced once, in the menu", async () => {
    const answer = heldSignOut("refused");
    const { queryClient } = renderShellAt("/party");
    await click(topButton("Account menu"));
    await click(screen.getByRole("menuitem", { name: "Sign out" }));
    answer();
    const alerts = await screen.findAllByRole("alert");
    expect(alerts).toHaveLength(1);
    expect(within(screen.getByRole("menu")).getByRole("alert")).toHaveTextContent("Couldn't sign out. Try again.");
    await settled(queryClient);
  });

  test("the avatar menu names the account and links to the profile", async () => {
    const { router, queryClient } = renderShellAt("/");
    await click(topButton("Account menu"));
    const menu = screen.getByRole("menu", { name: "Test Owner (owner)" });
    expect(within(menu).getByText("Test Owner")).toBeVisible();
    expect(within(menu).getByText("owner")).toBeVisible();
    expect(within(menu).getAllByRole("menuitem").map((item) => item.textContent)).toEqual([
      "Profile",
      "Settings",
      "Sign out",
    ]);
    expect(within(menu).getByRole("separator")).toBeInTheDocument();
    await click(within(menu).getByRole("menuitem", { name: "Profile" }));
    expect(router.state.location.pathname).toBe("/settings/account");
    expect(screen.queryByRole("menu")).toBeNull();
    await settled(queryClient);
  });

  test("the avatar menu is a real menu: arrows, Home and End move, Escape goes back to the button", async () => {
    const { router, queryClient } = renderShellAt("/");
    const trigger = topButton("Account menu");
    trigger.focus();
    await keyboard("{Enter}");
    const items = within(screen.getByRole("menu")).getAllByRole("menuitem");
    expect(items[0]).toHaveFocus();
    await keyboard("{ArrowDown}");
    expect(items[1]).toHaveFocus();
    await keyboard("{ArrowDown}{ArrowDown}");
    expect(items[0]).toHaveFocus();
    await keyboard("{ArrowUp}");
    expect(items[2]).toHaveFocus();
    await keyboard("{Home}");
    expect(items[0]).toHaveFocus();
    await keyboard("{End}");
    expect(items[2]).toHaveFocus();
    await keyboard("{Escape}");
    expect(screen.queryByRole("menu")).toBeNull();
    expect(trigger).toHaveFocus();

    // Arrow keys on the button open it too: Up lands on the last item. Space picks a link item.
    await keyboard("{ArrowUp}");
    expect(within(screen.getByRole("menu")).getAllByRole("menuitem")[2]).toHaveFocus();
    await keyboard("{Escape}{ArrowDown}");
    expect(within(screen.getByRole("menu")).getAllByRole("menuitem")[0]).toHaveFocus();
    await keyboard("{ArrowDown}");
    await keyboard(" ");
    expect(router.state.location.pathname).toBe("/settings/appearance");
    expect(screen.queryByRole("menu")).toBeNull();
    await settled(queryClient);
  });
});

describe("keyboard", () => {
  test("Tab reaches everything in order, starting with a skip link to the page", async () => {
    const { queryClient } = renderShellAt("/");
    const order = [
      screen.getByRole("link", { name: "Skip to content" }),
      screen.getByPlaceholderText("Filter"),
      ...PAGES.map((name) => screen.getByRole("link", { name })),
      topButton("Collapse sidebar"),
      topButton("Search"),
      within(topBar()).getByRole("link", { name: "Settings" }),
      topButton("Switch to dark mode"),
      topButton("Color theme"),
      topButton("Notifications"),
      topButton("Account menu"),
    ];
    for (const element of order) {
      await keyboard("{Tab}");
      expect(element).toHaveFocus();
    }
    order[0].focus();
    await keyboard("{Enter}");
    expect(screen.getByRole("main")).toHaveFocus();
    await settled(queryClient);
  });
});

describe("page header", () => {
  test("the page header shows the title, the breadcrumb from Dashboard, and what goes on the right", () => {
    render(<PageHeader title="Party" crumbs={["Debug", "Party"]} right={<span>Exploring</span>} />);
    expect(screen.getByRole("heading", { level: 1, name: "Party" })).toBeInTheDocument();
    expect(screen.getByText("Dashboard / Debug / Party")).toBeInTheDocument();
    expect(screen.getByText("Exploring")).toBeInTheDocument();
  });

  test("every signed-in page has its header inside the shell", async () => {
    const { queryClient } = renderShellAt("/location");
    const main = screen.getByRole("main");
    expect(within(main).getByRole("heading", { level: 1, name: "Location" })).toBeInTheDocument();
    expect(within(main).getByText("Dashboard / Debug / Location")).toBeInTheDocument();
    await settled(queryClient);
  });
});

describe("page titles", () => {
  const announcer = () => screen.getByTestId("page-announcer");

  test.each([
    ["/", "Overview · Amethyst Dashboard"],
    ["/party", "Party · Amethyst Dashboard"],
    ["/inventory", "Inventory · Amethyst Dashboard"],
    ["/gear", "Gear · Amethyst Dashboard"],
    ["/location", "Location · Amethyst Dashboard"],
    ["/admin", "Admin · Amethyst Dashboard"],
    ["/settings", "Appearance · Settings · Amethyst Dashboard"],
    ["/settings/appearance", "Appearance · Settings · Amethyst Dashboard"],
    ["/settings/account", "Account · Settings · Amethyst Dashboard"],
    ["/settings/sign-in", "Sign-in · Settings · Amethyst Dashboard"],
    ["/settings/game-connection", "Game connection · Settings · Amethyst Dashboard"],
    ["/settings/notifications", "Notifications · Settings · Amethyst Dashboard"],
  ])("%s is titled %j in the browser tab", async (path, title) => {
    const { queryClient } = renderShellAt(path);
    await waitFor(() => expect(document.title).toBe(title));
    await settled(queryClient);
  });

  test.each([
    ["/signin", "Sign in · Amethyst Dashboard", SIGNED_OUT],
    ["/forgot", "Reset your password · Amethyst Dashboard", SIGNED_OUT],
    ["/setup", "Create your account · Amethyst Dashboard", NO_ACCOUNT],
  ])("%s is titled %j", async (path, title, auth) => {
    mockAuthState(auth);
    const { queryClient } = renderAt(path);
    await waitFor(() => expect(document.title).toBe(title));
    await settled(queryClient);
  });

  test("the screen for a server that can't be reached has a title too", async () => {
    server.use(http.get("/api/auth/state", () => HttpResponse.error()));
    const { queryClient } = renderAt("/party");
    await waitFor(() => expect(document.title).toBe("Can't reach the server · Amethyst Dashboard"));
    await settled(queryClient);
  });

  test("moving to another page reads its title out politely, once, and leaves the focus where it was", async () => {
    const { queryClient } = renderShellAt("/");
    await waitFor(() => expect(document.title).toBe("Overview · Amethyst Dashboard"));
    // One live region for the whole shell. The page a visit starts on isn't read: the browser reads it as it loads.
    expect(screen.getAllByTestId("page-announcer")).toHaveLength(1);
    expect(announcer()).toHaveAttribute("role", "status");
    expect(announcer()).toBeEmptyDOMElement();

    const party = screen.getByRole("link", { name: "Party" });
    await click(party);
    expect(announcer()).toHaveTextContent("Party · Amethyst Dashboard");
    expect(document.title).toBe("Party · Amethyst Dashboard");
    expect(party).toHaveFocus();

    // /settings goes on to its first section; only where it lands is read.
    await click(within(topBar()).getByRole("link", { name: "Settings" }));
    expect(announcer()).toHaveTextContent("Appearance · Settings · Amethyst Dashboard");
    const sections = within(screen.getByRole("navigation", { name: "Settings sections" }));
    await click(sections.getByRole("link", { name: "Account" }));
    expect(announcer()).toHaveTextContent("Account · Settings · Amethyst Dashboard");
    expect(sections.getByRole("link", { name: "Account" })).toHaveFocus();
    await settled(queryClient);
  });

  test("a page that is only passed through on the way somewhere else isn't read out", async () => {
    const { queryClient, router } = renderShellAt("/admin");
    await waitFor(() => expect(document.title).toBe("Admin · Amethyst Dashboard"));
    const heard: string[] = [];
    const observer = new MutationObserver(() => heard.push(announcer().textContent ?? ""));
    observer.observe(announcer(), { childList: true, characterData: true, subtree: true });
    await act(() => router.navigate("/settings"));
    await waitFor(() => expect(announcer()).toHaveTextContent("Appearance · Settings · Amethyst Dashboard"));
    observer.disconnect();
    expect(heard.filter((text) => text !== "")).toEqual(["Appearance · Settings · Amethyst Dashboard"]);
    await settled(queryClient);
  });
});

describe("tooltips", () => {
  test("with reduced motion a tooltip stops fading but still waits for the pointer to rest", () => {
    const css = tooltipCss.replace(/\/\*[\s\S]*?\*\//g, "");
    expect(css).toMatch(/\.anchor:hover > \.bubble\s*\{[^}]*transition-delay:\s*350ms/);
    const reduced = /@media \(prefers-reduced-motion: reduce\)\s*\{([\s\S]*)\}\s*$/.exec(css)?.[1] ?? "";
    expect(reduced).toMatch(/\.bubble/);
    expect(reduced).not.toMatch(/transition:\s*none/);
    expect(reduced).not.toMatch(/transition-delay/);
  });
});
