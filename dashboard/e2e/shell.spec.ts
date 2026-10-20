import { type Page, expect, test } from "@playwright/test";
import { STATE_CHANGE, ensureOwner, nextSettingsSave, signIn, solidPng } from "./support.js";

// This file's own server starts with an empty database; the owner is made once, through the API, and every test
// signs in afresh (its own browser context) with the look put back to the defaults.
test.beforeAll(async ({ playwright }, testInfo) => {
  const request = await playwright.request.newContext({ baseURL: testInfo.project.use.baseURL });
  await ensureOwner(request);
  await request.dispose();
});

test.beforeEach(async ({ page }) => {
  await signIn(page);
  const reset = await page.request.patch("/api/settings", {
    headers: STATE_CHANGE,
    data: { appearance: "light", sidebar: "expanded" },
  });
  expect(reset.ok()).toBe(true);
});

const topBar = (page: Page) => page.getByRole("banner");

async function openOverview(page: Page): Promise<void> {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Overview", level: 1 })).toBeVisible();
}

test("⌘K, then “loc” and Enter, opens the Location page, which says the game isn't running", async ({ page }) => {
  await openOverview(page);
  await page.keyboard.press("ControlOrMeta+k");
  const box = page.getByRole("combobox", { name: "Search" });
  await expect(box).toBeFocused();
  await page.keyboard.type("loc");
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(/\/location$/);
  await expect(page.getByRole("heading", { name: "Location", level: 1 })).toBeVisible();
  await expect(page.getByRole("heading", { name: "The game isn't running" })).toBeVisible();
});

test("the theme button turns the page dark, and a reload is dark from its very first paint", async ({ page }) => {
  await openOverview(page);
  const html = page.locator("html");
  await expect(html).toHaveAttribute("data-theme", "light");
  const saved = nextSettingsSave(page);
  await topBar(page).getByRole("button", { name: "Switch to dark mode" }).click();
  await expect(html).toHaveAttribute("data-theme", "dark");
  expect((await saved).ok()).toBe(true);

  // Before any of the page's own scripts: note every value data-theme takes, and the one the first frame is drawn with.
  await page.addInitScript(() => {
    const record = { values: [] as Array<string | null>, firstFrame: undefined as string | undefined };
    (window as unknown as { themeRecord: typeof record }).themeRecord = record;
    new MutationObserver((changes) => {
      for (const change of changes) record.values.push((change.target as Element).getAttribute("data-theme"));
    }).observe(document, { attributes: true, attributeFilter: ["data-theme"], subtree: true });
    requestAnimationFrame(() => {
      record.firstFrame = document.documentElement.dataset.theme;
    });
  });
  await page.reload();
  await expect(topBar(page).getByRole("button", { name: "Switch to light mode" })).toBeVisible();
  const record = await page.evaluate(
    () => (window as unknown as { themeRecord: { values: Array<string | null>; firstFrame?: string } }).themeRecord,
  );
  expect(record.firstFrame).toBe("dark");
  expect(record.values.length).toBeGreaterThan(0);
  expect(record.values.every((value) => value === "dark")).toBe(true);
  await expect(html).toHaveAttribute("data-theme", "dark");
});

test("a folded sidebar stays folded after a reload, and it is the account's setting, not just this browser's", async ({
  page,
}) => {
  await openOverview(page);
  const sidebar = page.getByRole("navigation", { name: "Main" });
  await expect(sidebar).toHaveCSS("width", "250px");
  const saved = nextSettingsSave(page);
  await topBar(page).getByRole("button", { name: "Collapse sidebar" }).click();
  await expect(sidebar).toHaveCSS("width", "72px");
  expect((await saved).ok()).toBe(true);

  await page.reload();
  await expect(topBar(page).getByRole("button", { name: "Expand sidebar" })).toBeVisible();
  await expect(sidebar).toHaveCSS("width", "72px");
  await expect(page.getByRole("textbox", { name: "Filter pages" })).toHaveCount(0);

  // With nothing remembered in the browser, the saved setting still folds it.
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await expect(topBar(page).getByRole("button", { name: "Expand sidebar" })).toBeVisible();
  await expect(sidebar).toHaveCSS("width", "72px");
});

test("Tab from the top of the page reaches every top-bar button in order, each with a visible focus ring", async ({
  page,
}) => {
  await openOverview(page);
  const expected = [
    "Collapse sidebar",
    "Search",
    "Settings",
    "Switch to dark mode",
    "Colour theme",
    "Full screen",
    "Notifications",
    "Account menu",
  ];
  // The ring's solid line is --focus-line, as the browser writes colours in a box-shadow.
  const ringColour = await page.evaluate(() => {
    const probe = document.createElement("span");
    probe.style.color = getComputedStyle(document.documentElement).getPropertyValue("--focus-line");
    document.body.append(probe);
    const colour = getComputedStyle(probe).color;
    probe.remove();
    return colour;
  });

  // The ring fades in (a short transition), so the check waits for it to be drawn in full.
  const ring = new RegExp(`${ringColour.replace(/[()]/g, "\\$&")} 0px 0px 0px 2px`);

  const reached: string[] = [];
  // Skip to content, then the sidebar's filter and pages come first; the top bar follows.
  for (let presses = 0; presses < 30 && reached.length < expected.length; presses += 1) {
    await page.keyboard.press("Tab");
    const focused = page.locator(":focus");
    const name = await focused.evaluate((element) =>
      element.closest("header") === null ? null : (element.getAttribute("aria-label") ?? element.textContent ?? ""),
    );
    if (name === null) continue;
    reached.push(name);
    expect(await focused.evaluate((element) => element.matches(":focus-visible")), name).toBe(true);
    await expect(focused, name).toHaveCSS("box-shadow", ring);
  }
  expect(reached).toEqual(expected);
});

test("Escape gives the focus back to the search box, and to a menu's button when ⌘K came from the open menu", async ({
  page,
}) => {
  await openOverview(page);
  const searchBox = topBar(page).getByRole("button", { name: "Search" });
  const palette = page.getByRole("dialog", { name: "Search" });
  await searchBox.click();
  await expect(palette).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(palette).toHaveCount(0);
  await expect(searchBox).toBeFocused();

  // The bell's panel closes as the palette takes the focus; the bell, which opened it, gets the focus back.
  const bell = topBar(page).getByRole("button", { name: /^Notifications/ });
  await bell.click();
  await expect(page.getByRole("dialog", { name: "Notifications" })).toBeVisible();
  await page.keyboard.press("ControlOrMeta+k");
  await expect(page.getByRole("combobox", { name: "Search" })).toBeFocused();
  await expect(page.getByRole("dialog", { name: "Notifications" })).toHaveCount(0);
  await page.keyboard.press("Escape");
  await expect(bell).toBeFocused();

  // The menu closes as the palette takes the focus; the avatar, which opened it, gets the focus back.
  const avatar = topBar(page).getByRole("button", { name: "Account menu" });
  await avatar.click();
  await expect(page.getByRole("menuitem", { name: "Profile" })).toBeFocused();
  await page.keyboard.press("ControlOrMeta+k");
  await expect(page.getByRole("combobox", { name: "Search" })).toBeFocused();
  await expect(page.getByRole("menu")).toHaveCount(0);
  await page.keyboard.press("Escape");
  await expect(avatar).toBeFocused();
});

test("a picture chosen in Settings is saved as the account's, and the top bar shows it", async ({ page }) => {
  await page.goto("/settings/account");
  await expect(page.getByRole("button", { name: "Upload picture" })).toBeVisible();
  const picture = solidPng(8, 8, [126, 79, 224]);

  const uploaded = page.waitForResponse(
    (response) => response.url().endsWith("/api/account/avatar") && response.request().method() === "PUT",
  );
  await page.getByLabel("Choose a picture").setInputFiles({ name: "me.png", mimeType: "image/png", buffer: picture });
  expect((await uploaded).status()).toBe(204);

  const stored = await page.request.get("/api/account/avatar");
  expect(stored.status()).toBe(200);
  expect(stored.headers()["content-type"]).toBe("image/png");
  expect((await stored.body()).equals(picture)).toBe(true);

  const shown = topBar(page).getByRole("button", { name: "Account menu" }).locator("img");
  await expect(shown).toHaveAttribute("src", /^\/api\/account\/avatar/);
  // Drawn from the file, not the initials: the image loaded at the picture's own size.
  await expect.poll(() => shown.evaluate((image: HTMLImageElement) => image.complete && image.naturalWidth)).toBe(8);
  await expect(page.getByRole("button", { name: "Remove picture" })).toBeVisible();
});
