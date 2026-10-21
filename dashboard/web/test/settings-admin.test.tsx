import { act, fireEvent, screen, waitFor, within } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { describe, expect, test, vi } from "vitest";
import {
  AVATAR_MAX_BYTES,
  INVALID_DISPLAY_NAME_MESSAGE,
  INVALID_GAME_PORT_MESSAGE,
  SECURITY_QUESTIONS,
  TOO_SHORT_MESSAGE,
} from "../../shared/src/constants";
import { DEFAULT_SETTINGS, type SettingsPatch } from "../../shared/src/api";
import { ApiFailure } from "../src/api/client";
import { queryKeys } from "../src/api/hooks";
import { problemWithSetting } from "../src/pages/settings/useSettingsSaver";
import { click, keyboard, renderAt, renderShellAt, replace, settled, topBar, upload } from "./helpers";
import {
  SIGNED_OUT,
  TEST_PASSWORD,
  lastRequest,
  mockAuthState,
  mockRefusal,
  mockUploadRefusal,
  requestsTo,
  server,
} from "./msw";

// Every password and answer in this file is invented.
const NEW_PASSWORD = "willow-brook-77-fern";
const ANSWERS: [string, string, string] = ["Midwinter", "Tarnwick", "Lanterns and Lanes"];

const region = (name: string) => screen.getByRole("region", { name });
const topButton = (name: string) => within(topBar()).getByRole("button", { name });
const settingsPatches = () => requestsTo("/api/settings").filter((request) => request.method === "PATCH");
const savedBodies = () => settingsPatches().map((request) => request.body);
const focus = (element: HTMLElement) => act(() => element.focus());
const questionPattern = (index: number) => new RegExp(SECURITY_QUESTIONS[index].replace("?", "\\?"));

function picture(name = "me.png", type = "image/png", bytes = 64): File {
  return new File([new Uint8Array(bytes)], name, { type });
}

describe("the Settings page", () => {
  test("a bare /settings and an unknown section both open Appearance", async () => {
    const first = renderShellAt("/settings");
    await waitFor(() => expect(first.router.state.location.pathname).toBe("/settings/appearance"));
    expect(region("Appearance")).toBeVisible();
    await settled(first.queryClient);
    first.unmount();

    const second = renderShellAt("/settings/no-such-section");
    await waitFor(() => expect(second.router.state.location.pathname).toBe("/settings/appearance"));
    expect(region("Appearance")).toBeVisible();
    // Replaced, not pushed: Back doesn't land on an address that only redirects.
    expect(second.router.state.historyAction).toBe("REPLACE");
    await settled(second.queryClient);
  });

  test("a list of the five sections sits at the left, and the open one is marked", async () => {
    const { router, queryClient } = renderShellAt("/settings/sign-in");
    expect(screen.getByRole("heading", { name: "Settings", level: 1 })).toBeVisible();
    expect(screen.getByText("Dashboard / Settings")).toBeVisible();
    const list = within(screen.getByRole("navigation", { name: "Settings sections" }));
    expect(list.getAllByRole("link").map((link) => link.textContent)).toEqual([
      "Appearance",
      "Account",
      "Sign-in",
      "Game connection",
      "Notifications",
    ]);
    expect(list.getByRole("link", { name: "Sign-in" })).toHaveAttribute("aria-current", "page");
    expect(list.getByRole("link", { name: "Account" })).not.toHaveAttribute("aria-current");
    expect(region("Sign-in")).toBeVisible();

    await click(list.getByRole("link", { name: "Game connection" }));
    expect(router.state.location.pathname).toBe("/settings/game-connection");
    expect(region("Game connection")).toBeVisible();
    expect(list.getByRole("link", { name: "Game connection" })).toHaveAttribute("aria-current", "page");
    await settled(queryClient);
  });

  test("the section list works from the keyboard: Enter on a focused link opens that section", async () => {
    const { router, queryClient } = renderShellAt("/settings/appearance");
    const notifications = within(screen.getByRole("navigation", { name: "Settings sections" })).getByRole("link", {
      name: "Notifications",
    });
    focus(notifications);
    await keyboard("{Enter}");
    expect(router.state.location.pathname).toBe("/settings/notifications");
    await settled(queryClient);
  });
});

describe("when the settings aren't in yet", () => {
  test("a section that needs them says it is loading, then shows them", async () => {
    let release = () => {};
    const held = new Promise<void>((resolve) => {
      release = resolve;
    });
    server.use(
      http.get("/api/settings", async () => {
        await held;
        return HttpResponse.json({ ...DEFAULT_SETTINGS, appearance: "dark" });
      }),
    );
    const { queryClient } = renderAt("/settings/appearance");
    expect(await screen.findByText("Loading…")).toBeVisible();
    release();
    expect(await screen.findByRole("radio", { name: "Dark" })).toHaveAttribute("aria-checked", "true");
    await settled(queryClient);
  });

  test("if they can't be had it says why, and Try again asks once more", async () => {
    server.use(http.get("/api/settings", () => HttpResponse.error()));
    const { queryClient } = renderAt("/settings/sign-in");
    expect(await screen.findByRole("alert")).toHaveTextContent("Can't reach the dashboard's server.");
    server.resetHandlers();
    await click(screen.getByRole("button", { name: "Try again" }));
    expect(await screen.findByRole("radio", { name: "30 days" })).toBeVisible();
    await settled(queryClient);
  });

  test("the account section doesn't wait for them", async () => {
    server.use(http.get("/api/settings", () => HttpResponse.error()));
    const { queryClient } = renderAt("/settings/account");
    expect(await screen.findByRole("region", { name: "Account" })).toBeVisible();
    expect(screen.queryByRole("alert")).toBeNull();
    await settled(queryClient);
  });
});

describe("Appearance", () => {
  test("appearance options save and apply", async () => {
    const { queryClient } = renderShellAt("/settings/appearance");
    await click(screen.getByRole("radio", { name: "Follow my Mac" }));
    await waitFor(() => expect(savedBodies()).toEqual([{ appearance: "system" }]));
    expect(screen.getByRole("radio", { name: "Follow my Mac" })).toHaveAttribute("aria-checked", "true");
    expect(within(region("Appearance")).getByText("Saved")).toBeVisible();
    await settled(queryClient);
  });

  test("Dark turns the whole page dark at once", async () => {
    const { queryClient } = renderShellAt("/settings/appearance");
    expect(document.documentElement.dataset.theme).toBe("light");
    await click(screen.getByRole("radio", { name: "Dark" }));
    expect(document.documentElement.dataset.theme).toBe("dark");
    await waitFor(() => expect(savedBodies()).toEqual([{ appearance: "dark" }]));
    await settled(queryClient);
  });

  test("the choices show what is saved, including the color theme", async () => {
    const { queryClient } = renderShellAt("/settings/appearance", {
      settings: { appearance: "dark", sidebar: "icons", colorTheme: "tidal" },
    });
    expect(screen.getByRole("radio", { name: "Dark" })).toHaveAttribute("aria-checked", "true");
    expect(screen.getByRole("radio", { name: "Light" })).toHaveAttribute("aria-checked", "false");
    expect(screen.getByRole("radio", { name: "Icons only" })).toHaveAttribute("aria-checked", "true");
    expect(screen.getByRole("radio", { name: "Expanded" })).toHaveAttribute("aria-checked", "false");
    const themes = screen.getByRole("radiogroup", { name: "Color theme" });
    expect(within(themes).getAllByRole("radio")).toHaveLength(20);
    expect(within(themes).getByRole("radio", { name: "Tidal" })).toHaveAttribute("aria-checked", "true");
    await settled(queryClient);
  });

  test("picking a color theme in Settings saves it, recolors the dashboard and says Saved", async () => {
    const { queryClient } = renderShellAt("/settings/appearance");
    await click(screen.getByRole("radio", { name: "Storm" }));
    expect(document.documentElement.dataset.color).toBe("storm");
    await waitFor(() => expect(lastRequest("/api/settings")?.body).toEqual({ colorTheme: "storm" }));
    expect(await screen.findByText("Saved")).toBeVisible();
    await settled(queryClient);
  });

  test("choosing what is already chosen sends nothing and doesn't say Saved", async () => {
    const { queryClient } = renderShellAt("/settings/appearance");
    await click(screen.getByRole("radio", { name: "Amethyst" }));
    await click(screen.getByRole("radio", { name: "Light" }));
    await click(screen.getByRole("radio", { name: "Expanded" }));
    await settled(queryClient);
    expect(settingsPatches()).toEqual([]);
    expect(within(region("Appearance")).queryByText("Saved")).toBeNull();
  });

  test("Icons only folds the sidebar, and it is saved", async () => {
    const { queryClient } = renderShellAt("/settings/appearance");
    expect(topButton("Collapse sidebar")).toBeVisible();
    await click(screen.getByRole("radio", { name: "Icons only" }));
    await waitFor(() => expect(savedBodies()).toEqual([{ sidebar: "icons" }]));
    expect(topButton("Expand sidebar")).toBeVisible();
    await settled(queryClient);
  });

  test("the arrow keys move the choice and save it", async () => {
    const { queryClient } = renderShellAt("/settings/appearance");
    focus(screen.getByRole("radio", { name: "Light" }));
    await keyboard("{ArrowRight}");
    await waitFor(() => expect(savedBodies()).toEqual([{ appearance: "dark" }]));
    expect(screen.getByRole("radio", { name: "Dark" })).toHaveFocus();
    await keyboard("{ArrowRight}");
    await waitFor(() => expect(savedBodies()).toEqual([{ appearance: "dark" }, { appearance: "system" }]));
    await settled(queryClient);
  });

  test("a refused change is undone and says so, in the app's own sentence", async () => {
    mockRefusal("patch", "/api/settings", 400, { error: "invalid_setting", setting: "appearance" });
    const { queryClient } = renderShellAt("/settings/appearance");
    await click(screen.getByRole("radio", { name: "Dark" }));
    expect(await within(region("Appearance")).findByRole("alert")).toHaveTextContent(
      "That setting couldn't be saved.",
    );
    await settled(queryClient);
    expect(screen.getByRole("radio", { name: "Light" })).toHaveAttribute("aria-checked", "true");
    expect(document.documentElement.dataset.theme).toBe("light");
    expect(within(region("Appearance")).queryByText("Saved")).toBeNull();
    // The next change that works takes the message away.
    server.resetHandlers();
    await click(screen.getByRole("radio", { name: "Icons only" }));
    await settled(queryClient);
    expect(within(region("Appearance")).queryByRole("alert")).toBeNull();
  });

  test("a refusal still says so when another change was made before it came back", async () => {
    let release = () => {};
    const held = new Promise<void>((resolve) => {
      release = resolve;
    });
    // Dark is refused, but only once Icons only has been sent (and saved) behind it.
    server.use(
      http.patch("/api/settings", async ({ request }) => {
        const patch = (await request.clone().json()) as SettingsPatch;
        if (patch.appearance !== "dark") return undefined;
        await held;
        return HttpResponse.json(
          { error: "invalid_setting", message: "That setting isn't valid.", setting: "appearance" },
          { status: 400 },
        );
      }),
    );
    const { queryClient } = renderShellAt("/settings/appearance");
    await click(screen.getByRole("radio", { name: "Dark" }));
    await click(screen.getByRole("radio", { name: "Icons only" }));
    await waitFor(() => expect(savedBodies()).toEqual([{ appearance: "dark" }, { sidebar: "icons" }]));
    release();
    expect(await within(region("Appearance")).findByRole("alert")).toHaveTextContent(
      "That setting couldn't be saved.",
    );
    await settled(queryClient);
    // Dark is undone; Icons only, which the server took, stays.
    expect(document.documentElement.dataset.theme).toBe("light");
    expect(screen.getByRole("radio", { name: "Light" })).toHaveAttribute("aria-checked", "true");
    expect(screen.getByRole("radio", { name: "Icons only" })).toHaveAttribute("aria-checked", "true");
    expect(within(topBar()).getByRole("button", { name: "Expand sidebar" })).toBeVisible();
  });

  test("a refused setting whose name isn't one the app knows gets the general sentence", () => {
    // Names an ordinary object answers to by itself must not be taken for a sentence.
    for (const name of ["constructor", "toString", "__proto__", "hasOwnProperty", "somethingNew"]) {
      const refusal = new ApiFailure(400, { error: "invalid_setting", message: "That setting isn't valid.", setting: name });
      expect(problemWithSetting(refusal)).toBe("That setting couldn't be saved.");
    }
    const port = new ApiFailure(400, { error: "invalid_setting", message: "That setting isn't valid.", setting: "gamePort" });
    expect(problemWithSetting(port)).toBe(INVALID_GAME_PORT_MESSAGE);
    // The setting is named in its own field; a message that happens to read "gamePort" names nothing.
    const unnamed = new ApiFailure(400, { error: "invalid_setting", message: "gamePort" });
    expect(problemWithSetting(unnamed)).toBe("That setting couldn't be saved.");
  });

  test("Saved goes away by itself after a couple of seconds", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    try {
      const { queryClient } = renderShellAt("/settings/appearance");
      await click(screen.getByRole("radio", { name: "Dark" }));
      expect(await within(region("Appearance")).findByText("Saved")).toBeVisible();
      act(() => {
        vi.advanceTimersByTime(2_500);
      });
      expect(within(region("Appearance")).queryByText("Saved")).toBeNull();
      await settled(queryClient);
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("Sign-in", () => {
  test("Keep me signed in lasts 7, 30 or 90 days, and the choice is saved", async () => {
    const { queryClient } = renderShellAt("/settings/sign-in");
    const group = screen.getByRole("radiogroup", { name: "Keep me signed in lasts" });
    expect(within(group).getAllByRole("radio").map((radio) => radio.textContent)).toEqual([
      "7 days",
      "30 days",
      "90 days",
    ]);
    expect(within(group).getByRole("radio", { name: "30 days" })).toHaveAttribute("aria-checked", "true");
    await click(within(group).getByRole("radio", { name: "90 days" }));
    await waitFor(() => expect(savedBodies()).toEqual([{ keepSignedInDays: 90 }]));
    expect(within(region("Sign-in")).getByText("Saved")).toBeVisible();
    // The same one again is no change.
    await click(within(group).getByRole("radio", { name: "90 days" }));
    await settled(queryClient);
    expect(settingsPatches()).toHaveLength(1);
    await settled(queryClient);
  });
});

describe("Game connection", () => {
  const port = () => screen.getByLabelText("Port");

  test("the port must be a valid number", async () => {
    const { queryClient } = renderShellAt("/settings/game-connection");
    await replace(port(), "80");
    await keyboard("{Enter}");
    expect(screen.getByText("Use a port from 1024 to 65535.")).toBeInTheDocument();
    expect(INVALID_GAME_PORT_MESSAGE).toBe("Use a port from 1024 to 65535.");
    expect(port()).toBeInvalid();
    await settled(queryClient);
    expect(settingsPatches()).toEqual([]);
  });

  test("it starts at the saved port, and the default is mentioned", async () => {
    const { queryClient } = renderShellAt("/settings/game-connection", { settings: { gamePort: 50123 } });
    expect(port()).toHaveValue("50123");
    expect(screen.getByText("Default: 47821")).toBeVisible();
    expect(screen.getByText("The game connection arrives in the next stage.")).toBeVisible();
    await settled(queryClient);
  });

  test.each([
    ["80", "below the range"],
    ["1023", "just below the range"],
    ["65536", "just above the range"],
    ["47x21", "not a number"],
    ["", "empty"],
    ["4782.5", "not a whole number"],
  ])("%j (%s) is refused before anything is sent", async (typed) => {
    const { queryClient } = renderShellAt("/settings/game-connection");
    await replace(port(), typed);
    await keyboard("{Enter}");
    expect(within(region("Game connection")).getByText("Use a port from 1024 to 65535.")).toBeVisible();
    await settled(queryClient);
    expect(settingsPatches()).toEqual([]);
  });

  test("leaving the field with a wrong port shows the problem too, and fixing it clears it as you type", async () => {
    const { queryClient } = renderShellAt("/settings/game-connection");
    await replace(port(), "80");
    expect(screen.queryByText("Use a port from 1024 to 65535.")).toBeNull();
    await keyboard("{Tab}");
    expect(screen.getByText("Use a port from 1024 to 65535.")).toBeVisible();
    await replace(port(), "8080");
    expect(screen.queryByText("Use a port from 1024 to 65535.")).toBeNull();
    expect(port()).not.toBeInvalid();
    await settled(queryClient);
    expect(settingsPatches()).toEqual([]);
  });

  test("Enter saves a valid port as a number, and Saved shows", async () => {
    const { queryClient } = renderShellAt("/settings/game-connection");
    await replace(port(), "50000");
    expect(settingsPatches()).toEqual([]);
    await keyboard("{Enter}");
    await waitFor(() => expect(savedBodies()).toEqual([{ gamePort: 50000 }]));
    expect(await within(region("Game connection")).findByText("Saved")).toBeVisible();
    expect(port()).toHaveValue("50000");
    await settled(queryClient);
  });

  test("leaving the field saves it (spaces around the number are ignored), and leaving it again sends nothing", async () => {
    const { queryClient } = renderShellAt("/settings/game-connection");
    await replace(port(), "  1024 ");
    await keyboard("{Tab}");
    await waitFor(() => expect(savedBodies()).toEqual([{ gamePort: 1024 }]));
    focus(port());
    await keyboard("{Tab}");
    await settled(queryClient);
    expect(settingsPatches()).toHaveLength(1);
  });

  test("a port that hasn't changed sends nothing, on Enter or on leaving", async () => {
    const { queryClient } = renderShellAt("/settings/game-connection");
    focus(port());
    await keyboard("{Enter}");
    await keyboard("{Tab}");
    await settled(queryClient);
    expect(settingsPatches()).toEqual([]);
    expect(within(region("Game connection")).queryByText("Saved")).toBeNull();
  });

  test("Escape puts the saved port back and sends nothing", async () => {
    const { queryClient } = renderShellAt("/settings/game-connection");
    await replace(port(), "9999");
    await keyboard("{Escape}");
    expect(port()).toHaveValue("47821");
    await keyboard("{Tab}");
    await settled(queryClient);
    expect(settingsPatches()).toEqual([]);
  });

  test("a refused port shows the app's sentence for it and goes back to the saved one", async () => {
    mockRefusal("patch", "/api/settings", 400, { error: "invalid_setting", setting: "gamePort" });
    const { queryClient } = renderShellAt("/settings/game-connection");
    await replace(port(), "50000");
    await keyboard("{Enter}");
    expect(await within(region("Game connection")).findByRole("alert")).toHaveTextContent(
      "Use a port from 1024 to 65535.",
    );
    await settled(queryClient);
    expect(port()).toHaveValue("47821");
    expect(queryClient.getQueryData<{ gamePort: number }>(queryKeys.settings)?.gamePort).toBe(47821);
    expect(within(region("Game connection")).queryByText("Saved")).toBeNull();
  });

  test("Reconnect automatically is a switch: a click or Space flips it and saves", async () => {
    const { queryClient } = renderShellAt("/settings/game-connection");
    const reconnect = screen.getByRole("switch", { name: "Reconnect automatically when the game restarts" });
    expect(reconnect).toBeChecked();
    await click(reconnect);
    await waitFor(() => expect(savedBodies()).toEqual([{ autoReconnect: false }]));
    expect(reconnect).not.toBeChecked();
    focus(reconnect);
    await keyboard(" ");
    await waitFor(() => expect(savedBodies()).toEqual([{ autoReconnect: false }, { autoReconnect: true }]));
    expect(reconnect).toBeChecked();
    await settled(queryClient);
  });
});

describe("Notifications", () => {
  test.each([
    ["Account security", { notify: { security: false } }],
    ["Game connection", { notify: { game: false } }],
    ["Changes", { notify: { changes: false } }],
  ])("the %s switch is on, and turning it off saves just that kind", async (name, patch) => {
    const { queryClient } = renderShellAt("/settings/notifications");
    const kind = within(region("Notifications")).getByRole("switch", { name });
    expect(kind).toBeChecked();
    await click(kind);
    await waitFor(() => expect(savedBodies()).toEqual([patch]));
    expect(kind).not.toBeChecked();
    expect(within(region("Notifications")).getByText("Saved")).toBeVisible();
    await settled(queryClient);
  });

  test("each switch's dim line under it is its description", async () => {
    const { queryClient } = renderShellAt("/settings/notifications");
    const notifications = within(region("Notifications"));
    for (const [name, hint] of [
      ["Account security", "Failed sign-ins, pauses, and changes to your password or answers."],
      ["Game connection", "The game connecting and disconnecting."],
      ["Changes", "Debug changes applied, waiting or failed."],
    ]) {
      expect(notifications.getByRole("switch", { name }), name).toHaveAccessibleDescription(hint);
    }
    await settled(queryClient);
  });

  test("the switches show what is saved", async () => {
    const { queryClient } = renderShellAt("/settings/notifications", {
      settings: { notify: { security: true, game: false, changes: true } },
    });
    const switches = within(region("Notifications")).getAllByRole("switch");
    expect(switches.map((control) => [control.getAttribute("aria-checked")])).toEqual([["true"], ["false"], ["true"]]);
    await settled(queryClient);
  });
});

describe("Account: the profile", () => {
  const profile = () => region("Account");

  test("it shows the picture's place (initials), the display name, and the username that can't change", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    expect(within(profile()).getByText("TO")).toBeVisible();
    expect(within(profile()).getByRole("button", { name: "Upload picture" })).toBeVisible();
    expect(within(profile()).queryByRole("button", { name: "Remove picture" })).toBeNull();
    expect(within(profile()).getByLabelText("Display name")).toHaveValue("Test Owner");
    expect(within(profile()).getByText("owner")).toBeVisible();
    expect(within(profile()).queryByRole("textbox", { name: "Username" })).toBeNull();
    await settled(queryClient);
  });

  test("the display name saves on Enter, and the top bar and menu follow at once", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    const name = within(profile()).getByLabelText("Display name");
    await replace(name, "Ada Vale");
    await keyboard("{Enter}");
    await waitFor(() => expect(lastRequest("/api/account")?.body).toEqual({ displayName: "Ada Vale" }));
    expect(lastRequest("/api/account")?.method).toBe("PATCH");
    expect(await within(profile()).findByText("Saved")).toBeVisible();
    expect(within(topButton("Account menu")).getByText("AV")).toBeVisible();
    expect(name).toHaveValue("Ada Vale");
    await settled(queryClient);
  });

  test("the display name saves when the field is left, trimmed, and not when it hasn't changed", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    const name = within(profile()).getByLabelText("Display name");
    focus(name);
    await keyboard("{Tab}");
    await replace(name, "  Bo Pell  ");
    await keyboard("{Tab}");
    await waitFor(() => expect(lastRequest("/api/account")?.body).toEqual({ displayName: "Bo Pell" }));
    await settled(queryClient);
    expect(requestsTo("/api/account")).toHaveLength(1);
  });

  test("an empty or too long display name is refused before anything is sent", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    const name = within(profile()).getByLabelText("Display name");
    await replace(name, "   ");
    await keyboard("{Enter}");
    expect(within(profile()).getByText(INVALID_DISPLAY_NAME_MESSAGE)).toBeVisible();
    expect(name).toBeInvalid();
    await replace(name, "x".repeat(41));
    expect(within(profile()).getByText(INVALID_DISPLAY_NAME_MESSAGE)).toBeVisible();
    await keyboard("{Enter}");
    await replace(name, "x".repeat(40));
    expect(within(profile()).queryByText(INVALID_DISPLAY_NAME_MESSAGE)).toBeNull();
    await settled(queryClient);
    expect(requestsTo("/api/account")).toEqual([]);
  });

  test("Escape puts the saved display name back", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    const name = within(profile()).getByLabelText("Display name");
    await replace(name, "Somebody Else");
    await keyboard("{Escape}");
    expect(name).toHaveValue("Test Owner");
    await keyboard("{Tab}");
    await settled(queryClient);
    expect(requestsTo("/api/account")).toEqual([]);
  });

  test("an Enter that finishes composing text (Japanese, Chinese, Korean) doesn't save", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    const name = within(profile()).getByLabelText("Display name");
    await replace(name, "Ada Vale");
    // Chromium and Firefox mark that Enter as composing; Safari sends it with the composition key code, 229.
    fireEvent.keyDown(name, { key: "Enter", isComposing: true });
    fireEvent.keyDown(name, { key: "Enter", keyCode: 229 });
    await settled(queryClient);
    expect(requestsTo("/api/account")).toEqual([]);
    expect(name).toHaveValue("Ada Vale");
    // The Enter after it is an ordinary one, and saves.
    fireEvent.keyDown(name, { key: "Enter", keyCode: 13 });
    await waitFor(() => expect(requestsTo("/api/account")).toHaveLength(1));
    await settled(queryClient);
  });

  test("a problem found by pressing Enter is announced at once; leaving the field or typing on, politely", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    const name = within(profile()).getByLabelText("Display name");
    await replace(name, "   ");
    await keyboard("{Enter}");
    expect(within(profile()).getByRole("alert")).toHaveTextContent(INVALID_DISPLAY_NAME_MESSAGE);
    // Typing on, the problem follows the text without interrupting.
    await replace(name, "x".repeat(41));
    expect(within(profile()).getByText(INVALID_DISPLAY_NAME_MESSAGE)).toHaveAttribute("aria-live", "polite");
    expect(within(profile()).queryByRole("alert")).toBeNull();

    await keyboard("{Escape}");
    await replace(name, "   ");
    await keyboard("{Tab}");
    expect(within(profile()).getByText(INVALID_DISPLAY_NAME_MESSAGE)).toHaveAttribute("aria-live", "polite");
    expect(within(profile()).queryByRole("alert")).toBeNull();
    await settled(queryClient);
    expect(requestsTo("/api/account")).toEqual([]);
  });

  test("a display name the server refuses shows its sentence and goes back to the saved one", async () => {
    mockRefusal("patch", "/api/account", 400, { error: "invalid_display_name" });
    const { queryClient } = renderShellAt("/settings/account");
    const name = within(profile()).getByLabelText("Display name");
    await replace(name, "Ada Vale");
    await keyboard("{Enter}");
    expect(await within(profile()).findByRole("alert")).toHaveTextContent(INVALID_DISPLAY_NAME_MESSAGE);
    await settled(queryClient);
    expect(name).toHaveValue("Test Owner");
    expect(within(topButton("Account menu")).getByText("TO")).toBeVisible();
  });

  test("choosing a picture uploads it, and the top bar and this page both show it at once", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    const chooser = within(profile()).getByLabelText("Choose a picture");
    await upload(chooser, picture("me.png", "image/png"));

    await waitFor(() => expect(lastRequest("/api/account/avatar")).toBeDefined());
    const sent = lastRequest("/api/account/avatar");
    expect(sent?.method).toBe("PUT");
    expect(sent?.headers.get("X-Amethyst-Request")).toBe("1");
    expect((sent?.body as FormData).get("file")).toMatchObject({ name: "me.png", type: "image/png" });

    expect(await within(profile()).findByText("Saved")).toBeVisible();
    const small = topButton("Account menu").querySelector("img");
    const large = profile().querySelector("img");
    expect(small).toHaveAttribute("src", "/api/account/avatar?v=1");
    expect(large).toHaveAttribute("src", "/api/account/avatar?v=1");
    expect(within(profile()).queryByText("TO")).toBeNull();
    expect(within(profile()).getByRole("button", { name: "Remove picture" })).toBeVisible();
    await settled(queryClient);
  });

  test("a picture that is the wrong kind or too big is refused before anything is sent", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    const chooser = within(profile()).getByLabelText("Choose a picture");
    // The chooser's accept list hides other kinds, but "All files" lets anything through, and user-event's upload
    // would filter it out; a change event is what the browser sends in that case.
    const choose = (file: File) => fireEvent.change(chooser, { target: { files: [file] } });

    choose(picture("loop.gif", "image/gif"));
    expect(await within(profile()).findByRole("alert")).toHaveTextContent("Pictures must be PNG, JPEG or WebP.");
    choose(picture("huge.png", "image/png", AVATAR_MAX_BYTES + 1));
    await waitFor(() =>
      expect(within(profile()).getByRole("alert")).toHaveTextContent("Pictures can be at most 2 MB."),
    );
    await settled(queryClient);
    expect(requestsTo("/api/account/avatar")).toEqual([]);

    // One of exactly the largest size is fine, and takes the message away.
    choose(picture("ok.webp", "image/webp", AVATAR_MAX_BYTES));
    await waitFor(() => expect(requestsTo("/api/account/avatar")).toHaveLength(1));
    await waitFor(() => expect(within(profile()).queryByRole("alert")).toBeNull());
    await settled(queryClient);
  });

  test.each([
    [413, "too_large", "Pictures can be at most 2 MB."],
    [415, "unsupported_media_type", "Pictures must be PNG, JPEG or WebP."],
    [500, "server_error", "Something went wrong on the server."],
  ])("the server's %i (%s) is shown as a sentence, and the picture stays as it was", async (status, error, sentence) => {
    mockUploadRefusal(status, { error });
    const { queryClient } = renderShellAt("/settings/account");
    await upload(within(profile()).getByLabelText("Choose a picture"), picture());
    expect(await within(profile()).findByRole("alert")).toHaveTextContent(sentence);
    await settled(queryClient);
    expect(within(profile()).getByText("TO")).toBeVisible();
    expect(topButton("Account menu").querySelector("img")).toBeNull();
  });

  test.each([
    [413, "Pictures can be at most 2 MB."],
    [415, "Pictures must be PNG, JPEG or WebP."],
  ])("a %i that isn't in the server's words (a page from something in between) still gets its sentence", async (status, sentence) => {
    mockUploadRefusal(status, "<html><body><h1>Refused</h1></body></html>");
    const { queryClient } = renderShellAt("/settings/account");
    await upload(within(profile()).getByLabelText("Choose a picture"), picture());
    expect(await within(profile()).findByRole("alert")).toHaveTextContent(sentence);
    await settled(queryClient);
    expect(within(profile()).getByText("TO")).toBeVisible();
  });

  test("the upload button opens the file chooser, from the keyboard too", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    const chooser = within(profile()).getByLabelText("Choose a picture");
    const opened = vi.spyOn(chooser, "click");
    focus(within(profile()).getByRole("button", { name: "Upload picture" }));
    await keyboard("{Enter}");
    expect(opened).toHaveBeenCalledTimes(1);
    expect(chooser).toHaveAttribute("accept", "image/png,image/jpeg,image/webp");
    await settled(queryClient);
  });

  test("Remove picture takes it away: initials come back everywhere and the focus stays on the page", async () => {
    const { queryClient } = renderShellAt("/settings/account", { user: { hasAvatar: true } });
    expect(profile().querySelector("img")).not.toBeNull();
    await click(within(profile()).getByRole("button", { name: "Remove picture" }));
    await waitFor(() => expect(lastRequest("/api/account/avatar")?.method).toBe("DELETE"));
    expect(lastRequest("/api/account/avatar")?.headers.get("X-Amethyst-Request")).toBe("1");
    expect(await within(profile()).findByText("Saved")).toBeVisible();
    expect(within(profile()).getByText("TO")).toBeVisible();
    expect(within(topButton("Account menu")).getByText("TO")).toBeVisible();
    expect(topButton("Account menu").querySelector("img")).toBeNull();
    expect(within(profile()).queryByRole("button", { name: "Remove picture" })).toBeNull();
    // The button that was pressed is gone; the focus goes to the one beside it, not to nowhere.
    expect(within(profile()).getByRole("button", { name: "Upload picture" })).toHaveFocus();
    await settled(queryClient);
  });

  test("a picture that failed to load is tried again once a new one is uploaded", async () => {
    // The top bar's avatar used to give up for good after one failed load.
    const { queryClient } = renderShellAt("/settings/account", { user: { hasAvatar: true } });
    const broken = topButton("Account menu").querySelector("img");
    expect(broken).not.toBeNull();
    fireEvent.error(broken as HTMLImageElement);
    expect(within(topButton("Account menu")).getByText("TO")).toBeVisible();
    expect(topButton("Account menu").querySelector("img")).toBeNull();

    await upload(within(profile()).getByLabelText("Choose a picture"), picture());
    await waitFor(() => expect(topButton("Account menu").querySelector("img")).not.toBeNull());
    expect(topButton("Account menu").querySelector("img")).toHaveAttribute("src", "/api/account/avatar?v=1");
    await settled(queryClient);
  });
});

describe("Account: change password", () => {
  const card = () => within(region("Change password"));

  async function fillPassword({
    current = TEST_PASSWORD,
    next = NEW_PASSWORD,
    confirm = next,
  }: { current?: string; next?: string; confirm?: string } = {}) {
    await replace(card().getByLabelText("Current password"), current);
    await replace(card().getByLabelText("New password"), next);
    await replace(card().getByLabelText("Confirm new password"), confirm);
  }
  const submit = () => click(card().getByRole("button", { name: "Change password" }));

  test("it asks for the current password, the new one twice, and shows how strong the new one is", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    expect(card().getByLabelText("Current password")).toHaveAttribute("autocomplete", "current-password");
    expect(card().getByLabelText("New password")).toHaveAttribute("autocomplete", "new-password");
    expect(card().getByLabelText("Confirm new password")).toHaveAttribute("autocomplete", "new-password");
    expect(card().getByRole("meter", { name: "Password strength" })).toHaveAttribute("aria-valuenow", "0");
    await replace(card().getByLabelText("New password"), NEW_PASSWORD);
    expect(card().getByRole("meter", { name: "Password strength" })).not.toHaveAttribute("aria-valuenow", "0");
    for (const name of ["Show current password", "Show new password", "Show confirm new password"]) {
      expect(card().getByRole("button", { name })).toHaveAttribute("aria-pressed", "false");
    }
    await settled(queryClient);
  });

  test("changing it sends both passwords, then clears the form and says what happened", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    await fillPassword();
    await submit();
    expect(await card().findByText("Password changed. Every other sign-in was ended.")).toBeVisible();
    expect(lastRequest("/api/account/password")?.method).toBe("POST");
    expect(lastRequest("/api/account/password")?.body).toEqual({
      currentPassword: TEST_PASSWORD,
      newPassword: NEW_PASSWORD,
    });
    for (const label of ["Current password", "New password", "Confirm new password"]) {
      expect(card().getByLabelText(label)).toHaveValue("");
    }
    // What was typed isn't kept in the request that carried it.
    await waitFor(() => expect(queryClient.getMutationCache().getAll()).toHaveLength(0));
    await settled(queryClient);
  });

  test("Enter in a field submits the form too", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    await fillPassword();
    await keyboard("{Enter}");
    expect(await card().findByText("Password changed. Every other sign-in was ended.")).toBeVisible();
    await settled(queryClient);
  });

  test("starting to type again takes the good news away", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    await fillPassword();
    await submit();
    await card().findByText("Password changed. Every other sign-in was ended.");
    await replace(card().getByLabelText("Current password"), "x");
    expect(card().queryByText("Password changed. Every other sign-in was ended.")).toBeNull();
    await settled(queryClient);
  });

  test("checks that don't need the server are made first, and the cursor goes to the first problem", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    await fillPassword({ current: "", next: "short", confirm: "different" });
    await submit();
    expect(card().getByText("Enter your password.")).toBeVisible();
    expect(card().getByText(TOO_SHORT_MESSAGE)).toBeVisible();
    expect(card().getByText("The passwords don't match.")).toBeVisible();
    expect(card().getByLabelText("Current password")).toHaveFocus();
    await settled(queryClient);
    expect(requestsTo("/api/account/password")).toEqual([]);
  });

  test("a new password that doesn't match its confirmation isn't sent", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    await fillPassword({ confirm: `${NEW_PASSWORD}-typo` });
    await submit();
    expect(card().getByText("The passwords don't match.")).toBeVisible();
    expect(card().getByLabelText("Confirm new password")).toHaveFocus();
    await settled(queryClient);
    expect(requestsTo("/api/account/password")).toEqual([]);
  });

  test("a wrong current password is said at that field, and the cursor goes there", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    await fillPassword({ current: "not-the-password" });
    await submit();
    const error = await card().findByText("That password isn't right.");
    expect(error).toHaveAttribute("role", "alert");
    expect(card().getByLabelText("Current password")).toBeInvalid();
    await waitFor(() => expect(card().getByLabelText("Current password")).toHaveFocus());
    // Nothing else was lost, and nothing says it worked.
    expect(card().getByLabelText("New password")).toHaveValue(NEW_PASSWORD);
    expect(card().queryByText(/Password changed/)).toBeNull();
    await settled(queryClient);
  });

  test("typing in the field the refusal was about takes the refusal away", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    await fillPassword({ current: "not-the-password" });
    await submit();
    await card().findByText("That password isn't right.");
    await replace(card().getByLabelText("Current password"), TEST_PASSWORD);
    expect(card().queryByText("That password isn't right.")).toBeNull();
    await submit();
    expect(await card().findByText("Password changed. Every other sign-in was ended.")).toBeVisible();
    await settled(queryClient);
  });

  test("a session the server ended (the fifth wrong password) goes to sign-in, with nothing said here", async () => {
    mockRefusal("post", "/api/account/password", 401, { error: "signed_out" });
    const { router, queryClient } = renderShellAt("/settings/account");
    // The page was drawn signed in; by the time it asks, the server has ended the session.
    mockAuthState(SIGNED_OUT);
    await fillPassword({ current: "not-the-password" });
    await submit();
    await waitFor(() => expect(router.state.location.pathname).toBe("/signin"));
    expect(router.state.location.search).toBe("?next=%2Fsettings%2Faccount");
    expect(screen.queryByText("That password isn't right.")).toBeNull();
    await settled(queryClient);
  });

  test("the server's own too-short refusal goes under the new password", async () => {
    mockRefusal("post", "/api/account/password", 400, { error: "too_short" });
    const { queryClient } = renderShellAt("/settings/account");
    await fillPassword();
    await submit();
    expect(await card().findByText(TOO_SHORT_MESSAGE)).toHaveAttribute("role", "alert");
    expect(card().getByLabelText("New password")).toBeInvalid();
    await waitFor(() => expect(card().getByLabelText("New password")).toHaveFocus());
    await settled(queryClient);
  });

  test("anything else that goes wrong is shown in an alert above the button", async () => {
    mockRefusal("post", "/api/account/password", 500, { error: "server_error" });
    const { queryClient } = renderShellAt("/settings/account");
    await fillPassword();
    await submit();
    expect(await card().findByRole("alert")).toHaveTextContent("Something went wrong on the server.");
    expect(card().getByLabelText("Current password")).not.toBeInvalid();
    await settled(queryClient);
  });

  test("when the server can't be reached it says so", async () => {
    server.use(http.post("/api/account/password", () => HttpResponse.error()));
    const { queryClient } = renderShellAt("/settings/account");
    await fillPassword();
    await submit();
    expect(await card().findByRole("alert")).toHaveTextContent("Can't reach the dashboard's server.");
    await settled(queryClient);
  });
});

describe("Account: change security answers", () => {
  const card = () => within(region("Change security answers"));
  const answer = (index: number) => card().getByLabelText(questionPattern(index));

  async function fillAnswers(current = TEST_PASSWORD, answers: readonly string[] = ANSWERS) {
    await replace(card().getByLabelText("Current password"), current);
    for (const [index, text] of answers.entries()) await replace(answer(index), text);
  }
  const submit = () => click(card().getByRole("button", { name: "Save answers" }));

  test("changing answers needs the current password and shows the three questions", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    expect(screen.getAllByTestId("security-question")).toHaveLength(3);
    expect(screen.getAllByTestId("security-question").map((question) => question.textContent)).toEqual([
      ...SECURITY_QUESTIONS,
    ]);
    await fillAnswers("wrong current");
    await submit();
    expect(await card().findByText("That password isn't right.")).toBeVisible();
    await settled(queryClient);
  });

  test("a wrong current password is said at that field, the answers typed are kept, and the cursor goes there", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    await fillAnswers("wrong current");
    await submit();
    expect(await card().findByText("That password isn't right.")).toHaveAttribute("role", "alert");
    expect(card().getByLabelText("Current password")).toBeInvalid();
    await waitFor(() => expect(card().getByLabelText("Current password")).toHaveFocus());
    expect(answer(0)).toHaveValue(ANSWERS[0]);
    await settled(queryClient);
  });

  test("saving sends the password and the three answers in order, then clears the form", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    await fillAnswers();
    await submit();
    expect(await card().findByText("Security answers saved.")).toBeVisible();
    expect(lastRequest("/api/account/answers")?.method).toBe("POST");
    expect(lastRequest("/api/account/answers")?.body).toEqual({ currentPassword: TEST_PASSWORD, answers: ANSWERS });
    expect(card().getByLabelText("Current password")).toHaveValue("");
    for (const index of [0, 1, 2]) expect(answer(index)).toHaveValue("");
    await waitFor(() => expect(queryClient.getMutationCache().getAll()).toHaveLength(0));
    expect(document.body.textContent).not.toContain(ANSWERS[1]);
    await settled(queryClient);
  });

  test("every answer is asked for, and the current password too, before anything is sent", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    await fillAnswers("", [ANSWERS[0], "  ", ""]);
    await submit();
    expect(card().getByText("Enter your password.")).toBeVisible();
    expect(card().getAllByText("Enter an answer.")).toHaveLength(2);
    expect(card().getByLabelText("Current password")).toHaveFocus();
    expect(answer(0)).not.toBeInvalid();
    expect(answer(1)).toBeInvalid();
    await settled(queryClient);
    expect(requestsTo("/api/account/answers")).toEqual([]);
  });

  test("the server's missing-answer refusal is shown at the first answer", async () => {
    mockRefusal("post", "/api/account/answers", 400, { error: "missing_answer" });
    const { queryClient } = renderShellAt("/settings/account");
    await fillAnswers();
    await submit();
    expect(await card().findByText("Answer all three security questions.")).toBeVisible();
    expect(answer(0)).toBeInvalid();
    await settled(queryClient);
  });

  test("a session the server ended goes to sign-in with nothing said here", async () => {
    mockRefusal("post", "/api/account/answers", 401, { error: "signed_out" });
    const { router, queryClient } = renderShellAt("/settings/account");
    mockAuthState(SIGNED_OUT);
    await fillAnswers("wrong current");
    await submit();
    await waitFor(() => expect(router.state.location.pathname).toBe("/signin"));
    expect(router.state.location.search).toBe("?next=%2Fsettings%2Faccount");
    await settled(queryClient);
  });

  test("anything else that goes wrong is shown in an alert", async () => {
    mockRefusal("post", "/api/account/answers", 500, { error: "server_error" });
    const { queryClient } = renderShellAt("/settings/account");
    await fillAnswers();
    await submit();
    expect(await card().findByRole("alert")).toHaveTextContent("Something went wrong on the server.");
    await settled(queryClient);
  });

  test("answer fields turn off spell-check, auto-correct, auto-capitalise and autofill", async () => {
    const { queryClient } = renderShellAt("/settings/account");
    for (const index of [0, 1, 2]) {
      expect(answer(index)).toHaveAttribute("autocomplete", "off");
      expect(answer(index)).toHaveAttribute("spellcheck", "false");
      expect(answer(index)).toHaveAttribute("autocorrect", "off");
      expect(answer(index)).toHaveAttribute("autocapitalize", "off");
    }
    expect(card().getByLabelText("Current password")).toHaveAttribute("autocomplete", "current-password");
    await settled(queryClient);
  });
});

describe("the Admin page", () => {
  const inDevelopment = () => within(screen.getByRole("main")).getByRole("heading", { name: "In development" });

  test("admin says in development, with or without the game", async () => {
    // Stage 1 never has the game, so "without" is the only state the server can report (R33).
    const { queryClient } = renderShellAt("/admin");
    expect(screen.getByRole("heading", { name: "Admin", level: 1 })).toBeVisible();
    expect(screen.getByText("Dashboard / Admin")).toBeVisible();
    expect(inDevelopment()).toBeVisible();
    expect(
      within(screen.getByRole("main")).getByText("Admin tools will appear here once you decide what they should be."),
    ).toBeVisible();
    expect(screen.getByRole("main").querySelector("svg.lucide-shield")).not.toBeNull();
    await settled(queryClient);
  });

  test("it reads nothing about the game, so it is the same when the game's status can't be had", async () => {
    server.use(http.get("/api/game/status", () => HttpResponse.error()));
    const { queryClient } = renderShellAt("/admin");
    expect(inDevelopment()).toBeVisible();
    await settled(queryClient);
    expect(requestsTo("/api/game/status")).toEqual([]);
    expect(screen.queryByRole("alert")).toBeNull();
  });
});
