import { act, render, screen, waitFor, within } from "@testing-library/react";
import { describe, expect, test, vi } from "vitest";
import type { Notification } from "../../shared/src/api";
import { PageHeader } from "../src/shell/PageHeader";
import { click, keyboard, mockMatchMedia, renderShellAt, settled, type } from "./helpers";
import { lastRequest, mockNotifications, requestsTo } from "./msw";

const banner = () => screen.getByRole("banner");
const topButton = (name: string) => within(banner()).getByRole("button", { name });
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
    const buttons = within(banner()).getAllByRole("button");
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
    await click(within(banner()).getByRole("link", { name: "Settings" }));
    expect(router.state.location.pathname).toBe("/settings");
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

  test("the colour theme menu shows Amethyst chosen and more themes coming later", async () => {
    const { queryClient } = renderShellAt("/");
    const trigger = topButton("Colour theme");
    await click(trigger);
    const menu = screen.getByRole("menu", { name: "Colour theme" });
    const amethyst = within(menu).getByRole("menuitemradio", { name: "Amethyst" });
    expect(amethyst).toHaveAttribute("aria-checked", "true");
    expect(amethyst).toHaveFocus();
    const later = within(menu).getByRole("menuitem", { name: "More themes coming later" });
    expect(later).toHaveAttribute("aria-disabled", "true");
    await keyboard("{ArrowDown}");
    expect(later).toHaveFocus();
    await keyboard("{Enter}");
    expect(screen.getByRole("menu", { name: "Colour theme" })).toBeInTheDocument();
    await click(amethyst);
    expect(screen.queryByRole("menu")).toBeNull();
    expect(trigger).toHaveFocus();
    expect(requestsTo("/api/settings").filter((seen) => seen.method === "PATCH")).toEqual([]);
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
    expect(router.state.location.pathname).toBe("/settings");
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
      within(banner()).getByRole("link", { name: "Settings" }),
      topButton("Switch to dark mode"),
      topButton("Colour theme"),
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
