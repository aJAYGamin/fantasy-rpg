import { type Page, expect, test } from "@playwright/test";
import { ANSWERS, OWNER, SECURITY_QUESTIONS } from "./support.js";

// One account, made by the first test, on this file's own server: it started with an empty database, and its locks
// last 3 seconds (AMETHYST_LOCK_SECONDS, honoured only under NODE_ENV=test). Each test picks up where the last left it.
test.describe.configure({ mode: "serial" });

// Invented, like everything else here.
const NEW_PASSWORD = "harbour-lights-58-moth";

async function expectOverview(page: Page): Promise<void> {
  await expect(page).toHaveURL(/\/$/);
  await expect(page.getByRole("heading", { name: "Overview", level: 1 })).toBeVisible();
}

async function signInWithForm(page: Page, password: string): Promise<void> {
  await page.getByLabel("Password", { exact: true }).fill(password);
  await page.getByRole("button", { name: "Sign in" }).click();
}

/** The pause screen's countdown runs out by itself, and then Try again wakes up. */
async function waitOutThePause(page: Page): Promise<void> {
  const tryAgain = page.getByRole("button", { name: "Try again" });
  await expect(page.getByRole("timer")).toHaveText(/^0:0[1-3]$/);
  await expect(tryAgain).toBeDisabled();
  await expect(page.getByText("You can try again now.")).toBeVisible({ timeout: 10_000 });
  await expect(page.getByRole("timer")).toHaveText("0:00");
  await expect(tryAgain).toBeEnabled();
  await tryAgain.click();
}

test("a first visit creates the owner account and lands on the Overview, and Sign out leaves it", async ({ page }) => {
  await page.goto("/");
  await expect(page).toHaveURL(/\/setup$/);
  await expect(page.getByRole("heading", { name: "Create your account" })).toBeVisible();

  await page.getByLabel("Display name").fill(OWNER.displayName);
  await page.getByLabel("Username").fill(OWNER.username);
  await page.getByLabel("Password", { exact: true }).fill(OWNER.password);
  await page.getByLabel("Confirm password", { exact: true }).fill(OWNER.password);
  for (const [index, question] of SECURITY_QUESTIONS.entries()) {
    await page.getByLabel(question).fill(ANSWERS[index]);
  }
  await page.getByRole("button", { name: "Create account" }).click();
  await expectOverview(page);

  await page.getByRole("button", { name: "Account menu" }).click();
  await page.getByRole("menuitem", { name: "Sign out" }).click();
  await expect(page).toHaveURL(/\/signin$/);
  await expect(page.getByRole("heading", { name: "Sign in" })).toBeVisible();

  // The first-run screen is gone for good.
  await page.goto("/setup");
  await expect(page).toHaveURL(/\/signin$/);
});

test("five wrong passwords pause sign-in, and once the countdown ends the right one signs in", async ({ page }) => {
  await page.goto("/signin");
  await page.getByLabel("Username").fill(OWNER.username);
  for (const triesLeft of [4, 3, 2, 1]) {
    await signInWithForm(page, "not-the-password");
    const plural = triesLeft === 1 ? "try" : "tries";
    await expect(page.getByRole("alert")).toHaveText(
      `That password isn't right. ${triesLeft} ${plural} left before a 5-minute pause.`,
    );
  }
  await signInWithForm(page, "not-the-password");
  await expect(page.getByRole("heading", { name: "Sign-in is paused" })).toBeVisible();
  await expect(page.getByText("That was 5 wrong passwords in a row.")).toBeVisible();

  await waitOutThePause(page);
  await expect(page.getByLabel("Username")).toHaveValue(OWNER.username);
  await signInWithForm(page, OWNER.password);
  await expectOverview(page);
});

test("one wrong answer locks password reset; after it ends the right answers set a new password", async ({ page }) => {
  await page.goto("/signin");
  await page.getByRole("link", { name: "Forgot password?" }).click();
  await expect(page).toHaveURL(/\/forgot$/);
  // The address changes a moment before the page does.
  await expect(page.getByRole("heading", { name: "Answer your security questions" })).toBeVisible();

  async function fillTheForm(answers: readonly string[]): Promise<void> {
    for (const [index, question] of SECURITY_QUESTIONS.entries()) {
      await page.getByLabel(question).fill(answers[index]);
    }
    await page.getByLabel("New password", { exact: true }).fill(NEW_PASSWORD);
    await page.getByLabel("Confirm new password", { exact: true }).fill(NEW_PASSWORD);
    await page.getByRole("button", { name: "Reset password" }).click();
  }

  await page.getByLabel("Username").fill(OWNER.username);
  // Capitals and spaces don't matter, but the second answer is wrong.
  await fillTheForm(["  MIDWINTER ", "Somewhere Else", "lanterns  and lanes"]);
  await expect(page.getByRole("heading", { name: "Password reset is locked" })).toBeVisible();
  await expect(page.getByText("One of the answers didn't match.")).toBeVisible();

  await waitOutThePause(page);
  // The form is back with the name kept and everything else cleared.
  await expect(page.getByLabel("Username")).toHaveValue(OWNER.username);
  await expect(page.getByLabel(SECURITY_QUESTIONS[0])).toHaveValue("");
  await fillTheForm(["  MIDWINTER ", "tarnwick", "lanterns  and lanes"]);

  await expect(page).toHaveURL(/\/signin$/);
  await expect(page.getByText("Password changed. Sign in with your new password.")).toBeVisible();
  await expect(page.getByLabel("Username")).toHaveValue(OWNER.username);

  // The old password is no longer it; the new one is.
  await signInWithForm(page, OWNER.password);
  await expect(page.getByRole("alert")).toContainText("That password isn't right.");
  await signInWithForm(page, NEW_PASSWORD);
  await expectOverview(page);
});
