import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import { act } from "react";
import { HttpResponse, http } from "msw";
import { describe, expect, test, vi } from "vitest";
import type { Notification, NotificationKind } from "../../shared/src/api";
import { REQUEST_HEADER } from "../../shared/src/constants";
import { NAV } from "../src/shell/nav";
import { relativeTime } from "../src/shell/relativeTime";
import { type SearchEntry, buildIndex, groupResults, search } from "../src/shell/searchIndex";
import { click, keyboard, renderShellAt, settled, topBar, type } from "./helpers";
import { holdNotificationReplies, lastRequest, mockNotifications, requestsTo, server } from "./msw";

const MINUTE = 60_000;
const HOUR = 60 * MINUTE;

const nowIso = () => new Date().toISOString();
const ago = (ms: number) => new Date(Date.now() - ms).toISOString();

function note(id: number, kind: NotificationKind, title: string, extra: Partial<Notification> = {}): Notification {
  return { id, kind, title, body: `${title}: details.`, createdAt: nowIso(), read: false, ...extra };
}

const bell = () => within(topBar()).getByRole("button", { name: /^Notifications/ });
const panel = () => screen.getByRole("dialog", { name: "Notifications" });
const items = () => within(panel()).getAllByRole("listitem");

describe("notifications panel", () => {
  test("the bell shows the unread count and mark all clears it", async () => {
    mockNotifications([{ id: 1, kind: "security", title: "Failed sign-in", body: "…", createdAt: nowIso(), read: false }], 1);
    const { queryClient } = renderShellAt("/");
    expect(within(bell()).getByText("1")).toBeVisible();
    await click(bell());
    await click(screen.getByRole("button", { name: "Mark all as read" }));
    await waitFor(() => expect(lastRequest("/api/notifications/read-all")).toBeDefined());
    expect(lastRequest("/api/notifications/read-all")?.method).toBe("POST");
    expect(lastRequest("/api/notifications/read-all")?.headers.get(REQUEST_HEADER)).toBe("1");
    await waitFor(() => expect(lastRequest("/api/notifications/read-all")?.body).toEqual({}));
    await waitFor(() => expect(bell()).toHaveAccessibleName("Notifications"));
    await settled(queryClient);
  });

  test("the panel lists the notifications in the order the server sent them: icon, title, body, time, unread dot", async () => {
    mockNotifications([
      note(3, "security", "Sign-in locked", { body: "Too many wrong passwords.", createdAt: ago(2 * MINUTE) }),
      note(2, "game", "Game connected", { body: "The game is linked.", createdAt: ago(3 * HOUR), read: true }),
      note(1, "changes", "Changes applied", { body: "4 changes were applied.", createdAt: ago(2 * 24 * HOUR) }),
    ]);
    const { queryClient } = renderShellAt("/");
    await click(bell());
    const [locked, connected, applied] = items();

    expect(within(locked).getByText("Sign-in locked")).toBeVisible();
    expect(within(locked).getByText("Too many wrong passwords.")).toBeVisible();
    expect(within(locked).getByText("2 min ago")).toBeVisible();
    expect(locked.querySelector("svg.lucide-shield-alert")).not.toBeNull();
    expect(within(locked).getByText("Unread")).toBeInTheDocument();

    expect(within(connected).getByText("Game connected")).toBeVisible();
    expect(within(connected).getByText("3 hr ago")).toBeVisible();
    expect(connected.querySelector("svg.lucide-gamepad-2")).not.toBeNull();
    expect(within(connected).queryByText("Unread")).toBeNull();

    expect(within(applied).getByText("2 days ago")).toBeVisible();
    expect(applied.querySelector("svg.lucide-sparkles")).not.toBeNull();
    expect(within(panel()).getByRole("heading", { name: "Notifications" })).toBeVisible();
    await settled(queryClient);
  });

  test("with nothing to show the panel says You're all caught up.", async () => {
    const { queryClient } = renderShellAt("/");
    await click(bell());
    expect(within(panel()).getByText("You're all caught up.")).toBeVisible();
    expect(within(panel()).queryByRole("list")).toBeNull();
    // Nothing to mark: the button is there but does nothing.
    const markAll = within(panel()).getByRole("button", { name: "Mark all as read" });
    expect(markAll).toHaveAttribute("aria-disabled", "true");
    await click(markAll);
    expect(requestsTo("/api/notifications/read-all")).toEqual([]);
    await settled(queryClient);
  });

  test("opening an unread notification marks it read at once, and goes nowhere", async () => {
    mockNotifications([note(8, "security", "Failed sign-in"), note(7, "security", "Failed sign-in")]);
    const release = holdNotificationReplies();
    const { router, queryClient } = renderShellAt("/party");
    expect(bell()).toHaveAccessibleName("Notifications, 2 unread");
    await click(bell());
    await click(within(items()[1]).getByRole("button"));

    // Before the server has answered: the count dropped, the dot went, and the panel and page are as they were.
    expect(bell()).toHaveAccessibleName("Notifications, 1 unread");
    expect(within(items()[1]).queryByText("Unread")).toBeNull();
    expect(within(items()[0]).getByText("Unread")).toBeInTheDocument();
    expect(panel()).toBeInTheDocument();
    expect(router.state.location.pathname).toBe("/party");

    release();
    await waitFor(() => expect(lastRequest("/api/notifications/7/read")?.body).toEqual({}));
    expect(lastRequest("/api/notifications/7/read")?.method).toBe("POST");
    expect(lastRequest("/api/notifications/7/read")?.headers.get(REQUEST_HEADER)).toBe("1");
    await settled(queryClient);
    expect(bell()).toHaveAccessibleName("Notifications, 1 unread");
  });

  test("a notification that is already read sends nothing when opened", async () => {
    mockNotifications([note(5, "game", "Game connected", { read: true })]);
    const { queryClient } = renderShellAt("/");
    await click(bell());
    await click(within(items()[0]).getByRole("button"));
    expect(requestsTo("/api/notifications/5/read")).toEqual([]);
    await settled(queryClient);
  });

  test("Mark all as read shows at once, before the server answers", async () => {
    mockNotifications([note(2, "security", "Failed sign-in"), note(1, "game", "Game connected")]);
    const release = holdNotificationReplies();
    const { queryClient } = renderShellAt("/");
    await click(bell());
    await click(within(panel()).getByRole("button", { name: "Mark all as read" }));

    expect(bell()).toHaveAccessibleName("Notifications");
    expect(within(panel()).queryByText("Unread")).toBeNull();
    expect(within(panel()).getByRole("button", { name: "Mark all as read" })).toHaveAttribute("aria-disabled", "true");
    release();
    await settled(queryClient);
    expect(bell()).toHaveAccessibleName("Notifications");
    expect(requestsTo("/api/notifications/read-all")).toHaveLength(1);
  });

  test("the keyboard marks all as read and the focus stays put", async () => {
    mockNotifications([note(1, "security", "Failed sign-in")]);
    const { queryClient } = renderShellAt("/");
    bell().focus();
    await keyboard("{Enter}");
    const markAll = within(panel()).getByRole("button", { name: "Mark all as read" });
    expect(markAll).toHaveFocus();
    await keyboard("{Enter}");
    await waitFor(() => expect(requestsTo("/api/notifications/read-all")).toHaveLength(1));
    expect(markAll).toHaveFocus();
    expect(panel()).toBeInTheDocument();
    await settled(queryClient);
    await keyboard("{Escape}");
    expect(bell()).toHaveFocus();
  });

  test("a kind that is switched off doesn't lower the bell's count when its notification is opened", async () => {
    // The server's `unread` already leaves the muted kinds out, so the client must not take one off for them.
    mockNotifications([note(2, "game", "Game connected"), note(1, "security", "Failed sign-in")], 1);
    const { queryClient } = renderShellAt("/", { settings: { notify: { security: true, game: false, changes: true } } });
    expect(bell()).toHaveAccessibleName("Notifications, 1 unread");
    await click(bell());
    await click(within(items()[0]).getByRole("button"));
    expect(within(items()[0]).queryByText("Unread")).toBeNull();
    await waitFor(() => expect(lastRequest("/api/notifications/2/read")).toBeDefined());
    await settled(queryClient);
    expect(bell()).toHaveAccessibleName("Notifications, 1 unread");
  });

  test("a refusal puts the notifications back and says so", async () => {
    mockNotifications([note(1, "security", "Failed sign-in")]);
    server.use(
      http.post("/api/notifications/read-all", () =>
        HttpResponse.json({ error: "server_error", message: "Something went wrong on the server." }, { status: 500 }),
      ),
    );
    const { queryClient } = renderShellAt("/");
    await click(bell());
    await click(within(panel()).getByRole("button", { name: "Mark all as read" }));
    expect(await within(panel()).findByRole("alert")).toHaveTextContent("Couldn't update your notifications. Try again.");
    await settled(queryClient);
    expect(bell()).toHaveAccessibleName("Notifications, 1 unread");
    expect(within(items()[0]).getByText("Unread")).toBeInTheDocument();

    // Trying again clears the message.
    server.resetHandlers();
    await click(within(panel()).getByRole("button", { name: "Mark all as read" }));
    await waitFor(() => expect(within(panel()).queryByRole("alert")).toBeNull());
    await settled(queryClient);
    expect(bell()).toHaveAccessibleName("Notifications");
  });

  test("the times keep counting while the panel is open, on the browser's clock", async () => {
    mockNotifications([note(1, "security", "Failed sign-in")]);
    const { queryClient } = renderShellAt("/");
    // Faked after the first render, before the panel opens: the panel's own ticking is what is under test.
    vi.useFakeTimers({ toFake: ["Date", "setInterval", "clearInterval"] });
    try {
      await click(bell());
      expect(within(items()[0]).getByText("Just now")).toBeVisible();
      act(() => {
        vi.advanceTimersByTime(3 * MINUTE);
      });
      expect(within(items()[0]).getByText("3 min ago")).toBeVisible();
      act(() => {
        vi.advanceTimersByTime(2 * HOUR);
      });
      expect(within(items()[0]).getByText("2 hr ago")).toBeVisible();
    } finally {
      vi.useRealTimers();
    }
    await settled(queryClient);
  });
});

describe("relative times", () => {
  const now = new Date("2026-10-19T15:00:00").getTime();
  const at = (msBefore: number) => new Date(now - msBefore).toISOString();

  test.each([
    [0, "Just now"],
    [44_000, "Just now"],
    [60_000, "1 min ago"],
    [2 * MINUTE + 5_000, "2 min ago"],
    [59 * MINUTE, "59 min ago"],
    [HOUR, "1 hr ago"],
    [23 * HOUR + 59 * MINUTE, "23 hr ago"],
    [24 * HOUR, "1 day ago"],
    [47 * HOUR, "1 day ago"],
    [48 * HOUR, "2 days ago"],
    [6 * 24 * HOUR, "6 days ago"],
  ])("%i ms ago reads %s", (msBefore, text) => {
    expect(relativeTime(at(msBefore), now)).toBe(text);
  });

  test("a time in the future (a clock that runs ahead) reads Just now", () => {
    expect(relativeTime(at(-5 * MINUTE), now)).toBe("Just now");
  });

  test("a week or more ago reads as a date, with the year only when it isn't this one", () => {
    expect(relativeTime(at(7 * 24 * HOUR), now)).toBe(new Date(now - 7 * 24 * HOUR).toLocaleDateString(undefined, { month: "short", day: "numeric" }));
    const lastYear = "2025-03-02T10:00:00";
    expect(relativeTime(new Date(lastYear).toISOString(), now)).toBe(
      new Date(lastYear).toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" }),
    );
  });
});

describe("search index", () => {
  test("search ranks prefix matches first", () => {
    expect(search(buildIndex(), "a").map((entry) => entry.label).slice(0, 3)).toEqual(["Account", "Admin", "Appearance"]);
  });

  test("it holds every page, the three heroes and the five settings sections", () => {
    const index = buildIndex();
    const of = (group: SearchEntry["group"]) => index.filter((entry) => entry.group === group).map((entry) => [entry.label, entry.path]);
    expect(of("Pages")).toEqual([
      ["Overview", "/"],
      ["Party", "/party"],
      ["Inventory", "/inventory"],
      ["Gear", "/gear"],
      ["Location", "/location"],
      ["Admin", "/admin"],
      ["Settings", "/settings"],
    ]);
    for (const { items } of NAV) for (const item of items) expect(of("Pages")).toContainEqual([item.label, item.path]);
    expect(of("Heroes")).toEqual([
      ["Aria", "/party?hero=aria"],
      ["Kael", "/party?hero=kael"],
      ["Lyra", "/party?hero=lyra"],
    ]);
    expect(of("Settings")).toEqual([
      ["Appearance", "/settings/appearance"],
      ["Account", "/settings/account"],
      ["Sign-in", "/settings/sign-in"],
      ["Game connection", "/settings/game-connection"],
      ["Notifications", "/settings/notifications"],
    ]);
    expect(new Set(index.map((entry) => entry.id)).size).toBe(index.length);
  });

  test("matching ignores capitals and surrounding spaces, and finds words in the label or the keywords", () => {
    const index = buildIndex();
    expect(search(index, "  GEA ").map((entry) => entry.label)).toEqual(["Gear"]);
    expect(search(index, "kael").map((entry) => entry.label)).toEqual(["Kael"]);
    expect(search(index, "map").map((entry) => entry.label)).toContain("Location");
    expect(search(index, "dark").map((entry) => entry.label)).toContain("Appearance");
    expect(search(index, "zzzz")).toEqual([]);
  });

  test("label-prefix matches come first, then the rest; each alphabetical", () => {
    const entry = (label: string, keywords?: string[]): SearchEntry => ({ id: label, label, group: "Pages", path: "/", keywords });
    const index = [entry("Moonstone", ["gem"]), entry("Big gem"), entry("Gem Staff"), entry("Aqua gem"), entry("Gem Axe")];
    expect(search(index, "gem").map((e) => e.label)).toEqual(["Gem Axe", "Gem Staff", "Aqua gem", "Big gem", "Moonstone"]);
  });

  test("at most 20 results", () => {
    const many = Array.from({ length: 30 }, (_, n): SearchEntry => ({ id: `${n}`, label: `Item ${String(n).padStart(2, "0")}`, group: "Pages", path: "/" }));
    const found = search(many, "item");
    expect(found).toHaveLength(20);
    expect(found[0].label).toBe("Item 00");
    expect(search(many, "")).toHaveLength(20);
  });

  test("results are gathered under their group, groups in the palette's order, each keeping its ranking", () => {
    const grouped = groupResults(search(buildIndex(), "a"));
    expect(grouped.map((g) => g.group)).toEqual(["Pages", "Heroes", "Settings"]);
    expect(grouped[0].entries.map((e) => e.label)).toEqual(["Admin", "Gear", "Inventory", "Location", "Overview", "Party"]);
    expect(grouped[2].entries.map((e) => e.label)).toEqual(["Account", "Appearance", "Game connection", "Notifications"]);
    expect(groupResults(search(buildIndex(), "kael")).map((g) => g.group)).toEqual(["Heroes"]);
    expect(groupResults([])).toEqual([]);
  });

  test("an empty query lists the index as it stands, so the palette opens on the sidebar's order", () => {
    const index = buildIndex();
    expect(search(index, "").map((entry) => entry.id)).toEqual(index.map((entry) => entry.id));
    expect(search(index, "   ")).toHaveLength(index.length);
  });
});

describe("search palette", () => {
  const palette = () => screen.getByRole("dialog", { name: "Search" });
  const box = () => screen.getByRole("combobox", { name: "Search" });
  const options = () => within(palette()).queryAllByRole("option");
  const names = () => options().map((option) => option.textContent);
  const highlighted = () => options().filter((option) => option.getAttribute("aria-selected") === "true");

  test("⌘K opens search and the keyboard picks a result", async () => {
    const { router, queryClient } = renderShellAt("/");
    await keyboard("{Meta>}k{/Meta}");
    await type(box(), "gea");
    await keyboard("{ArrowDown}{Enter}");
    expect(router.state.location.pathname).toBe("/gear");
    expect(screen.queryByRole("dialog", { name: "Search" })).toBeNull();
    await settled(queryClient);
  });

  test("it opens on every page and hero and settings section, in groups, with the first highlighted", async () => {
    const { queryClient } = renderShellAt("/");
    await keyboard("{Meta>}k{/Meta}");
    expect(box()).toHaveFocus();
    expect(box()).toHaveAttribute("placeholder", "Search for anything — a hero, an item, a map…");
    expect(within(screen.getByRole("group", { name: "Pages" })).getAllByRole("option")).toHaveLength(7);
    expect(within(screen.getByRole("group", { name: "Heroes" })).getAllByRole("option").map((o) => o.textContent)).toEqual(["Aria", "Kael", "Lyra"]);
    expect(within(screen.getByRole("group", { name: "Settings" })).getAllByRole("option")).toHaveLength(5);
    expect(screen.getAllByRole("group")).toHaveLength(3);
    expect(highlighted().map((option) => option.textContent)).toEqual(["Overview"]);
    expect(box()).toHaveAttribute("aria-activedescendant", highlighted()[0].id);
    expect(box()).toHaveAttribute("aria-expanded", "true");
    expect(box()).toHaveAttribute("aria-controls", screen.getByRole("listbox").id);
    await settled(queryClient);
  });

  test("typing narrows the groups to what matches", async () => {
    const { queryClient } = renderShellAt("/");
    await keyboard("{Meta>}k{/Meta}");
    await type(box(), "ka");
    expect(names()).toEqual(["Kael"]);
    expect(screen.queryByRole("group", { name: "Pages" })).toBeNull();
    expect(screen.queryByRole("group", { name: "Settings" })).toBeNull();
    await settled(queryClient);
  });

  test("the arrows move the highlight, wrap at both ends, and the focus stays in the box", async () => {
    const { queryClient } = renderShellAt("/");
    await keyboard("{Meta>}k{/Meta}");
    await keyboard("{ArrowDown}");
    expect(highlighted().map((option) => option.textContent)).toEqual(["Party"]);
    expect(box()).toHaveAttribute("aria-activedescendant", highlighted()[0].id);
    await keyboard("{ArrowUp}{ArrowUp}");
    // Up from the first result wraps to the last one, in the order they are drawn.
    expect(highlighted().map((option) => option.textContent)).toEqual(["Notifications"]);
    await keyboard("{ArrowDown}");
    expect(highlighted().map((option) => option.textContent)).toEqual(["Overview"]);
    expect(box()).toHaveFocus();
    await settled(queryClient);
  });

  test("Enter opens the highlighted result and closes the palette", async () => {
    const { router, queryClient } = renderShellAt("/");
    await keyboard("{Meta>}k{/Meta}");
    await type(box(), "aria");
    await keyboard("{Enter}");
    expect(router.state.location.pathname).toBe("/party");
    expect(router.state.location.search).toBe("?hero=aria");
    expect(screen.queryByRole("dialog", { name: "Search" })).toBeNull();

    await keyboard("{Meta>}k{/Meta}");
    await type(box(), "game conn");
    await keyboard("{Enter}");
    expect(router.state.location.pathname).toBe("/settings/game-connection");
    expect(screen.queryByRole("dialog", { name: "Search" })).toBeNull();
    await settled(queryClient);
  });

  test("typing puts the highlight back on the first result", async () => {
    const { queryClient } = renderShellAt("/");
    await keyboard("{Meta>}k{/Meta}");
    await keyboard("{ArrowDown}{ArrowDown}");
    await type(box(), "s");
    expect(highlighted()[0]).toBe(options()[0]);
    await settled(queryClient);
  });

  test("the pointer highlights a result and a click opens it", async () => {
    const { router, user, queryClient } = renderShellAt("/");
    await keyboard("{Meta>}k{/Meta}");
    const kael = within(palette()).getByRole("option", { name: "Kael" });
    await user.hover(kael);
    expect(highlighted()).toEqual([kael]);
    await click(kael);
    expect(router.state.location.pathname).toBe("/party");
    expect(router.state.location.search).toBe("?hero=kael");
    expect(screen.queryByRole("dialog", { name: "Search" })).toBeNull();
    await settled(queryClient);
  });

  test("Escape closes it without going anywhere, and it opens empty next time", async () => {
    const { router, queryClient } = renderShellAt("/party");
    await keyboard("{Meta>}k{/Meta}");
    await type(box(), "gea");
    await keyboard("{Escape}");
    expect(screen.queryByRole("dialog", { name: "Search" })).toBeNull();
    expect(router.state.location.pathname).toBe("/party");
    await keyboard("{Meta>}k{/Meta}");
    expect(box()).toHaveValue("");
    await settled(queryClient);
  });

  test("when nothing matches it says so, and Enter does nothing", async () => {
    const { router, queryClient } = renderShellAt("/");
    await keyboard("{Meta>}k{/Meta}");
    await type(box(), "excalibur");
    expect(within(palette()).getByText("Nothing found. Items, gear and maps appear here once the game is connected.")).toBeVisible();
    expect(options()).toEqual([]);
    expect(screen.queryByRole("listbox")).toBeNull();
    expect(box()).toHaveAttribute("aria-expanded", "false");
    expect(box()).not.toHaveAttribute("aria-activedescendant");
    await keyboard("{ArrowDown}{Enter}");
    expect(palette()).toBeInTheDocument();
    expect(router.state.location.pathname).toBe("/");
    await settled(queryClient);
  });

  test("an Enter that finishes composing text isn't a choice", async () => {
    const { router, queryClient } = renderShellAt("/");
    await keyboard("{Meta>}k{/Meta}");
    await type(box(), "gea");
    fireEvent.keyDown(box(), { key: "Enter", isComposing: true });
    expect(router.state.location.pathname).toBe("/");
    expect(palette()).toBeInTheDocument();
    await settled(queryClient);
  });

  test("Tab can't leave the field while it is open", async () => {
    const { queryClient } = renderShellAt("/");
    await keyboard("{Meta>}k{/Meta}");
    await keyboard("{Tab}");
    expect(box()).toHaveFocus();
    await keyboard("{Shift>}{Tab}{/Shift}");
    expect(box()).toHaveFocus();
    await settled(queryClient);
  });

  test("opening search puts the notifications panel away", async () => {
    const { queryClient } = renderShellAt("/");
    await click(bell());
    expect(panel()).toBeInTheDocument();
    await keyboard("{Meta>}k{/Meta}");
    expect(screen.queryByRole("dialog", { name: "Notifications" })).toBeNull();
    expect(palette()).toBeInTheDocument();
    await settled(queryClient);
  });

  test("the top-bar box opens it, and Escape gives the focus back to the box", async () => {
    const { queryClient } = renderShellAt("/");
    const opener = within(topBar()).getByRole("button", { name: "Search" });
    await click(opener);
    expect(box()).toHaveFocus();
    await keyboard("{Escape}");
    expect(opener).toHaveFocus();
    await settled(queryClient);
  });
});
