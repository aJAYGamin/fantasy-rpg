import { screen, waitFor, within } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { describe, expect, test } from "vitest";
import waitingCss from "../src/pages/WaitingForGame.module.css?raw";
import { click, keyboard, renderShellAt, settled } from "./helpers";
import { captureRequests, requestsTo, server } from "./msw";

const REASON = "Available once the game is running";

/**
 * getByText reads only an element's own text nodes, and the decorative ○ and ✦ are separate aria-hidden spans, so the
 * full line ("○ Waiting for the game") is found by its text content instead: the deepest element that reads exactly so.
 */
const hasFullText = (text: string) => (_own: string, element: Element | null) =>
  element !== null &&
  element.textContent === text &&
  !Array.from(element.children).some((child) => child.textContent === text);
const fullText = (text: string) => screen.getByText(hasFullText(text));
const findFullText = (text: string) => screen.findByText(hasFullText(text));

const main = () => screen.getByRole("main");
const region = (name: string) => screen.getByRole("region", { name });

/** The game answering "connected", the way stage 2 will: only the fact that it is connected matters here. */
function gameIsRunning() {
  server.use(http.get("/api/game/status", () => HttpResponse.json({ connected: true })));
}

describe("the Debug pages", () => {
  test.each([
    ["/party", "Party"],
    ["/inventory", "Inventory"],
    ["/gear", "Gear"],
    ["/location", "Location"],
  ])("%s waits for the game", async (path, title) => {
    const { queryClient } = renderShellAt(path);
    expect(await findFullText("✦ The game isn't running ✦")).toBeVisible();
    expect(fullText("○ Waiting for the game")).toBeVisible();
    expect(screen.getByRole("heading", { name: title, level: 1 })).toBeVisible();
    expect(screen.getByText(`Dashboard / Debug / ${title}`)).toBeVisible();
    expect(screen.getByText("Start it from Godot and this page will connect on its own.")).toBeVisible();
    expect(screen.getByText("Waiting for the game · checking every few seconds")).toBeVisible();
    await settled(queryClient);
  });

  test("the heading and the status pill read plainly: their ✦ and ○ are decoration", async () => {
    const { queryClient } = renderShellAt("/party");
    // The accessible name leaves the glyphs out, which aria-hidden does and plain text could not.
    const heading = within(main()).getByRole("heading", { name: "The game isn't running", level: 2 });
    expect(heading).toHaveTextContent("✦ The game isn't running ✦");
    const glyphs = Array.from(heading.querySelectorAll('[aria-hidden="true"]'));
    expect(glyphs.map((glyph) => glyph.textContent)).toEqual(["✦", "✦"]);

    const pill = fullText("○ Waiting for the game");
    expect(pill.querySelector('[aria-hidden="true"]')).toHaveTextContent("○");
    await settled(queryClient);
  });

  test("a short reminder says applied changes stay if the game is saved, and where Reset lives", async () => {
    const { queryClient } = renderShellAt("/gear");
    const strip = screen.getByText(/Changes you apply here stay if you save the game\./);
    expect(strip).toBeVisible();
    expect(strip).toHaveTextContent(
      "Changes you apply here stay if you save the game. Reset to before debugging on the Overview rewinds everything to before your first Apply.",
    );
    expect(within(strip).getByText("Reset to before debugging")).toBeVisible();
    await settled(queryClient);
  });

  test.each(["/party", "/inventory", "/gear", "/location"])(
    "%s still shows the waiting state when the game's status can't be had",
    async (path) => {
      server.use(http.get("/api/game/status", () => HttpResponse.json({ error: "server_error" }, { status: 500 })));
      const { queryClient } = renderShellAt(path);
      expect(await findFullText("✦ The game isn't running ✦")).toBeVisible();
      await settled(queryClient);
      expect(fullText("✦ The game isn't running ✦")).toBeVisible();
      expect(fullText("○ Waiting for the game")).toBeVisible();
      expect(screen.queryByRole("alert")).toBeNull();
    },
  );

  test("the waiting state goes away on its own once the game reports it is connected", async () => {
    gameIsRunning();
    const { queryClient } = renderShellAt("/party");
    await waitFor(() => expect(screen.queryByText(hasFullText("✦ The game isn't running ✦"))).toBeNull());
    expect(screen.queryByText(hasFullText("○ Waiting for the game"))).toBeNull();
    // The page itself stays: its header and the reminder are not part of the waiting state.
    expect(screen.getByRole("heading", { name: "Party", level: 1 })).toBeVisible();
    expect(screen.getByText(/Changes you apply here stay/)).toBeVisible();
    await settled(queryClient);
  });

  test("the pulsing gem holds still when the Mac asks for less motion", () => {
    const css = waitingCss.replace(/\/\*[\s\S]*?\*\//g, "");
    expect(css).toMatch(/@keyframes/);
    expect(css).toMatch(/animation:\s*[^;]*pulse/);
    const reduced = /@media \(prefers-reduced-motion: reduce\)\s*\{([\s\S]*)\}\s*$/.exec(css)?.[1] ?? "";
    expect(reduced).toMatch(/animation:\s*none/);
  });
});

describe("the Overview while waiting", () => {
  const ACTIONS = [
    "Heal party + full resonance",
    "Unlock all moves",
    "Max out gold",
    "Save the game now",
    "Go",
    "Reset to before debugging",
  ];

  test("the header's mini-stats show a dash for each number", async () => {
    const { queryClient } = renderShellAt("/");
    expect(screen.getByRole("heading", { name: "Overview", level: 1 })).toBeVisible();
    expect(screen.getByText("Dashboard / Overview")).toBeVisible();
    for (const label of ["Gold", "Party level", "Debug changes"]) {
      const stat = screen.getByText(label).closest("div");
      expect(stat).toHaveTextContent("—");
      // Read aloud as "no data yet", not as a dash.
      expect(stat).toHaveTextContent("No data yet");
    }
    await settled(queryClient);
  });

  test("the Game Status card says the game is not running", async () => {
    const { queryClient } = renderShellAt("/");
    const card = region("Game Status");
    expect(within(card).getByText(hasFullText("○ Waiting for the game"))).toBeVisible();
    expect(within(card).getByRole("heading", { name: "The game isn't running", level: 3 })).toBeVisible();
    expect(within(card).getByText("Start it from Godot and this page will connect on its own.")).toBeVisible();
    expect(within(card).getByText("Waiting for the game · checking every few seconds")).toBeVisible();
    await settled(queryClient);
  });

  test("the page asks for the game's status once, not once for each card that shows it", async () => {
    const { queryClient } = renderShellAt("/");
    await settled(queryClient);
    expect(requestsTo("/api/game/status")).toHaveLength(1);
  });

  test("the Debug reminder is only on the Debug pages", async () => {
    const { queryClient } = renderShellAt("/");
    expect(screen.queryByText(/Changes you apply here stay/)).toBeNull();
    await settled(queryClient);
  });

  test("every quick action is shown but unavailable, and says why to the eye and to screen readers", async () => {
    const { queryClient } = renderShellAt("/");
    const card = region("Quick Actions");
    expect(within(card).getByText("Applies right away")).toBeVisible();
    expect(within(card).getByText("Quick actions skip the Apply step. They wait if you're in a battle or conversation.")).toBeVisible();

    const controls = [
      ...ACTIONS.map((name) => within(card).getByRole("button", { name })),
      within(card).getByRole("combobox", { name: "Teleport to…" }),
    ];
    expect(controls).toHaveLength(7);
    for (const control of controls) {
      // aria-disabled, not disabled: a disabled button gets no hover or focus, so its tooltip could never show (R37).
      expect(control).toHaveAttribute("aria-disabled", "true");
      expect(control).not.toBeDisabled();
      expect(control).toHaveAccessibleDescription(REASON);
      // The tooltip drawn beside it, for the eye.
      expect(control.parentElement).toHaveTextContent(REASON);
    }

    const difficulty = within(card).getByRole("radiogroup", { name: "Difficulty" });
    expect(difficulty).toHaveAccessibleDescription(REASON);
    expect(difficulty.parentElement).toHaveTextContent(REASON);
    const radios = within(difficulty).getAllByRole("radio");
    expect(radios.map((radio) => radio.textContent)).toEqual(["Easy", "Normal", "Hard"]);
    for (const radio of radios) {
      expect(radio).toHaveAttribute("aria-disabled", "true");
      expect(radio).toHaveAttribute("aria-checked", "false");
      expect(radio).not.toBeDisabled();
    }
    await settled(queryClient);
  });

  test("clicking or pressing Enter or Space on a quick action does nothing and sends no request", async () => {
    const { queryClient } = renderShellAt("/");
    await settled(queryClient);
    const card = region("Quick Actions");
    const sent = captureRequests();
    const controls = [
      ...ACTIONS.map((name) => within(card).getByRole("button", { name })),
      within(card).getByRole("combobox", { name: "Teleport to…" }),
      ...within(card).getAllByRole("radio"),
    ];
    for (const control of controls) {
      await click(control);
      control.focus();
      await keyboard("{Enter}");
      await keyboard(" ");
    }
    await settled(queryClient);
    expect(sent).toEqual([]);
    // Nothing was chosen or opened.
    for (const radio of within(card).getAllByRole("radio")) expect(radio).toHaveAttribute("aria-checked", "false");
    expect(within(card).getByRole("combobox", { name: "Teleport to…" })).toHaveAttribute("aria-expanded", "false");
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  test("Tab reaches every quick action in turn, then moves on", async () => {
    const { queryClient } = renderShellAt("/");
    main().focus();
    const reached: string[] = [];
    for (let step = 0; step < 9; step++) {
      await keyboard("{Tab}");
      const element = document.activeElement as HTMLElement;
      reached.push(element.getAttribute("aria-label") ?? element.textContent ?? "");
    }
    expect(reached).toEqual([
      "Heal party + full resonance",
      "Unlock all moves",
      "Max out gold",
      "Save the game now",
      "Teleport to…",
      "Go",
      // The difficulty options are one Tab stop (a radio group); the arrows would move within it.
      "Easy",
      "Reset to before debugging",
      "Open Party →",
    ]);
    await settled(queryClient);
  });

  test("the stat strip, the party summary and the debug activity are empty frames saying no data yet", async () => {
    const { queryClient } = renderShellAt("/");
    const gauges = screen.getAllByRole("progressbar");
    expect(gauges.map((gauge) => gauge.getAttribute("aria-label"))).toEqual([
      "Party HP",
      "Party MP",
      "Moves unlocked",
      "Items carried",
    ]);
    for (const gauge of gauges) {
      expect(gauge).toHaveAttribute("aria-valuetext", "No data yet");
      expect(gauge).toHaveTextContent("—");
    }
    for (const label of ["Party HP", "Party MP", "Moves unlocked", "Items carried"]) {
      expect(screen.getByText(label, { selector: "div" })).toBeVisible();
    }

    expect(within(region("Party")).getByText("No data yet")).toBeVisible();
    expect(within(region("Debug Activity")).getByText("No data yet")).toBeVisible();
    await settled(queryClient);
  });

  test("Open Party goes to the Party page", async () => {
    const { router, queryClient } = renderShellAt("/");
    await click(within(region("Party")).getByRole("link", { name: "Open Party" }));
    await waitFor(() => expect(router.state.location.pathname).toBe("/party"));
    expect(await findFullText("✦ The game isn't running ✦")).toBeVisible();
    await settled(queryClient);
  });

  test("a dropped connection to the server leaves the page drawn, with no alert", async () => {
    server.use(http.get("/api/game/status", () => HttpResponse.error()));
    const { queryClient } = renderShellAt("/");
    await settled(queryClient);
    expect(screen.getByRole("heading", { name: "Overview", level: 1 })).toBeVisible();
    expect(region("Quick Actions")).toBeVisible();
    expect(fullText("○ Waiting for the game")).toBeVisible();
    expect(screen.queryByRole("alert")).toBeNull();
  });

  test("a failed status request still shows the waiting state", async () => {
    server.use(http.get("/api/game/status", () => HttpResponse.json({ error: "server_error" }, { status: 500 })));
    const { queryClient } = renderShellAt("/");
    await settled(queryClient);
    expect(within(region("Game Status")).getByText(hasFullText("○ Waiting for the game"))).toBeVisible();
    expect(within(region("Game Status")).getByRole("heading", { name: "The game isn't running" })).toBeVisible();
  });

  test("the waiting message leaves the Game Status card once the game reports it is connected", async () => {
    gameIsRunning();
    const { queryClient } = renderShellAt("/");
    await waitFor(() => expect(screen.queryByText(hasFullText("✦ The game isn't running ✦"))).toBeNull());
    expect(screen.queryByText(hasFullText("○ Waiting for the game"))).toBeNull();
    await settled(queryClient);
  });
});
