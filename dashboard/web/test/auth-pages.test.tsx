import { act, render, screen, waitFor, within } from "@testing-library/react";
import type { UserEvent } from "@testing-library/user-event";
import { HttpResponse, http } from "msw";
import { MemoryRouter } from "react-router";
import { afterEach, describe, expect, test, vi } from "vitest";
import {
  DISPLAY_NAME_MAX,
  LOCK_MINUTES,
  MIN_PASSWORD_LENGTH,
  SECURITY_QUESTIONS,
  USERNAME_MAX,
  USERNAME_MIN,
} from "../../shared/src/constants";
import { LockedPanel } from "../src/auth/LockedPanel";
import { passwordStrength } from "../src/auth/strength";
import { spokenDuration } from "../src/auth/spokenDuration";
import { checkConfirmation, checkDisplayName, checkNewPassword, checkNewUsername } from "../src/auth/validation";
import { renderAt, settled } from "./helpers";
import {
  NO_ACCOUNT,
  SIGNED_OUT,
  TEST_PASSWORD,
  inMinutes,
  lastRequest,
  mockAuthState,
  mockForgot,
  mockSetup,
  mockSignin,
  requestsTo,
  server,
} from "./msw";

// Every answer in this file is invented. Real answers only ever go into the running app's own form.
const ANSWERS: [string, string, string] = ["Candlemas", "Brindlemoor", "Rook and Ladder"];

/** Clears a field and puts `text` in it (pasting is quick, and handles emoji). */
async function replace(user: UserEvent, field: HTMLElement, text: string) {
  await user.clear(field);
  if (text === "") return;
  await user.click(field);
  await user.paste(text);
}

/** The field for one of the three security questions (its label holds the question's number as well). */
const answerFor = (index: number) =>
  screen.getByLabelText(new RegExp(SECURITY_QUESTIONS[index].replace("?", "\\?")));

const button = (name: string) => screen.getByRole("button", { name });

// ---- first-run setup ----

type SetupValues = {
  displayName: string;
  username: string;
  password: string;
  confirm: string;
  answers: [string, string, string];
};

const SETUP: SetupValues = {
  displayName: "Test Owner",
  username: "owner",
  password: TEST_PASSWORD,
  confirm: TEST_PASSWORD,
  answers: ANSWERS,
};

async function openSetup() {
  mockAuthState(NO_ACCOUNT);
  const view = renderAt("/setup");
  await screen.findByRole("heading", { name: "Create your account" });
  return view;
}

async function fillSetup(user: UserEvent, overrides: Partial<SetupValues> = {}) {
  const values = { ...SETUP, ...overrides };
  await replace(user, screen.getByLabelText("Display name"), values.displayName);
  await replace(user, screen.getByLabelText("Username"), values.username);
  await replace(user, screen.getByLabelText("Password"), values.password);
  await replace(user, screen.getByLabelText("Confirm password"), values.confirm);
  for (const index of [0, 1, 2]) await replace(user, answerFor(index), values.answers[index]);
}

// Errors the page shows because of something the person just did (a failed submit) are alerts; ones that come and
// go as they type are polite live regions. This reads either kind.
const alertTexts = () => screen.queryAllByRole("alert").map((element) => element.textContent);
const errorTexts = () =>
  [...document.querySelectorAll('[role="alert"], [aria-live="polite"]')].map((element) => element.textContent);

describe("first-run setup", () => {
  test("shows the three questions in order and creates the account", async () => {
    const { user, router, queryClient } = await openSetup();
    const questions = screen.getAllByTestId("security-question").map((element) => element.textContent);
    expect(questions).toEqual([...SECURITY_QUESTIONS]);

    await fillSetup(user, { password: "short", confirm: "short" });
    await user.click(button("Create account"));
    expect(screen.getByRole("alert")).toHaveTextContent("Passwords need at least 10 characters.");
    expect(requestsTo("/api/auth/setup")).toHaveLength(0);

    await fillSetup(user);
    await user.click(button("Create account"));
    await waitFor(() => expect(router.state.location.pathname).toBe("/"));
    expect(lastRequest("/api/auth/setup")?.body).toEqual({
      username: "owner",
      displayName: "Test Owner",
      password: TEST_PASSWORD,
      answers: ANSWERS,
    });
    await settled(queryClient);
  });

  test("the brand panel welcomes the new owner and says this only appears once", async () => {
    await openSetup();
    expect(screen.getByText("Welcome. Let's set up your account.")).toBeInTheDocument();
    expect(
      screen.getByText(
        "This only appears once. After this, nobody can sign up. You'll create any other accounts yourself, from inside.",
      ),
    ).toBeInTheDocument();
    expect(screen.getByText("The Amethyst Requiem · dev dashboard")).toBeInTheDocument();
    expect(screen.getByText("You'll be the owner of this dashboard.")).toBeInTheDocument();
    expect(screen.getByText("SECURITY QUESTIONS")).toBeInTheDocument();
  });

  test("password length counts characters, not code units: 5 emoji are too short, 10 are enough", async () => {
    const { user, router, queryClient } = await openSetup();
    await fillSetup(user, { password: "😀".repeat(5), confirm: "😀".repeat(5) });
    await user.click(button("Create account"));
    expect(screen.getByRole("alert")).toHaveTextContent("Passwords need at least 10 characters.");
    expect(requestsTo("/api/auth/setup")).toHaveLength(0);

    await fillSetup(user, { password: "😀".repeat(10), confirm: "😀".repeat(10) });
    await user.click(button("Create account"));
    await waitFor(() => expect(router.state.location.pathname).toBe("/"));
    expect((lastRequest("/api/auth/setup")?.body as { password: string }).password).toBe("😀".repeat(10));
    await settled(queryClient);
  });

  test("an empty form shows every problem under its own field, announces them, and sends nothing", async () => {
    const { user } = await openSetup();
    await user.click(button("Create account"));

    expect(alertTexts()).toEqual([
      "Display names are 1 to 40 characters.",
      "Usernames are 3 to 32 characters, with no invisible characters.",
      "Passwords need at least 10 characters.",
      "Enter an answer.",
      "Enter an answer.",
      "Enter an answer.",
    ]);
    const displayName = screen.getByLabelText("Display name");
    expect(displayName).toHaveAttribute("aria-invalid", "true");
    expect(displayName).toHaveAccessibleDescription("Display names are 1 to 40 characters.");
    // The first problem is where the cursor goes, so it is seen even when it has scrolled out of view.
    expect(displayName).toHaveFocus();
    expect(requestsTo("/api/auth/setup")).toHaveLength(0);
  });

  test("passwords that differ are caught under the confirmation", async () => {
    const { user } = await openSetup();
    await fillSetup(user, { confirm: `${TEST_PASSWORD}x` });
    await user.click(button("Create account"));
    expect(screen.getByRole("alert")).toHaveTextContent("The passwords don't match.");
    expect(screen.getByLabelText("Confirm password")).toHaveFocus();
    expect(requestsTo("/api/auth/setup")).toHaveLength(0);
  });

  test("a blank or over-long name and a bad username are caught before anything is sent", async () => {
    const { user } = await openSetup();
    await fillSetup(user, { displayName: "   ", username: "ab" });
    await user.click(button("Create account"));
    expect(alertTexts()).toEqual([
      "Display names are 1 to 40 characters.",
      "Usernames are 3 to 32 characters, with no invisible characters.",
    ]);
    await replace(user, screen.getByLabelText("Username"), "owner");
    await replace(user, screen.getByLabelText("Display name"), "x".repeat(41));
    expect(errorTexts()).toEqual(["Display names are 1 to 40 characters."]);
    await replace(user, screen.getByLabelText("Display name"), "x".repeat(40));
    expect(errorTexts()).toEqual([]);
    expect(requestsTo("/api/auth/setup")).toHaveLength(0);
  });

  test("a username with spaces, an apostrophe and stray spaces at the ends is accepted and sent trimmed", async () => {
    const { user, router, queryClient } = await openSetup();
    await fillSetup(user, { username: " aJAY Gamin\u2019 " });
    await user.click(button("Create account"));
    await waitFor(() => expect(router.state.location.pathname).toBe("/"));
    expect((lastRequest("/api/auth/setup")?.body as { username: string }).username).toBe("aJAY Gamin'");
    await settled(queryClient);
  });

  test("a problem goes away as soon as it is fixed", async () => {
    const { user } = await openSetup();
    await user.click(button("Create account"));
    expect(errorTexts()).toHaveLength(6);
    await user.type(screen.getByLabelText("Display name"), "Test Owner");
    expect(errorTexts()).toHaveLength(5);
    expect(screen.getByLabelText("Display name")).not.toHaveAttribute("aria-invalid");
  });

  test("errors from pressing the button interrupt a screen reader; once typing starts they wait for a pause", async () => {
    const { user } = await openSetup();
    await user.click(button("Create account"));
    expect(alertTexts()).toHaveLength(6);

    await user.type(screen.getByLabelText("Display name"), "Test Owner");
    // Still wrong, now shown as the person works on them: polite, not alerts.
    expect(alertTexts()).toEqual([]);
    expect(errorTexts()).toHaveLength(5);

    await user.click(button("Create account"));
    expect(alertTexts()).toHaveLength(5);
  });

  test("Confirm says nothing about a mismatch until it has something in it or has been left", async () => {
    const { user } = await openSetup();
    await user.click(button("Create account"));
    expect(screen.getByLabelText("Confirm password")).not.toHaveAttribute("aria-invalid");

    // Typing the password, with Confirm still waiting its turn, is not a mismatch yet.
    await replace(user, screen.getByLabelText("Password"), TEST_PASSWORD);
    expect(screen.getByLabelText("Confirm password")).not.toHaveAttribute("aria-invalid");
    expect(errorTexts()).not.toContain("The passwords don't match.");

    await user.type(screen.getByLabelText("Confirm password"), "lantern");
    expect(errorTexts()).toContain("The passwords don't match.");
    await replace(user, screen.getByLabelText("Confirm password"), TEST_PASSWORD);
    expect(errorTexts()).not.toContain("The passwords don't match.");
  });

  test("leaving Confirm empty counts as having been there: the mismatch shows once it has been left", async () => {
    const { user } = await openSetup();
    await user.click(button("Create account"));
    await replace(user, screen.getByLabelText("Password"), TEST_PASSWORD);
    await user.click(screen.getByLabelText("Confirm password"));
    await user.tab();
    expect(errorTexts()).toContain("The passwords don't match.");
  });

  test("a password that differs from an empty Confirm is still reported when that is all that is wrong", async () => {
    const { user } = await openSetup();
    await fillSetup(user, { confirm: "" });
    await user.click(button("Create account"));
    expect(screen.getByRole("alert")).toHaveTextContent("The passwords don't match.");
    expect(requestsTo("/api/auth/setup")).toHaveLength(0);
  });

  test("every answer field turns off spell-check, auto-correct and auto-capitalise", async () => {
    await openSetup();
    for (const index of [0, 1, 2]) {
      expect(answerFor(index)).toHaveAttribute("spellcheck", "false");
      expect(answerFor(index)).toHaveAttribute("autocorrect", "off");
      expect(answerFor(index)).toHaveAttribute("autocapitalize", "off");
      expect(answerFor(index)).toHaveAttribute("autocomplete", "off");
    }
  });

  test("the strength meter has four steps and the hint says which one you are on", async () => {
    const { user } = await openSetup();
    const meter = () => screen.getByRole("meter", { name: "Password strength" });
    expect(meter()).toHaveAttribute("aria-valuemax", "4");
    expect(meter()).toHaveAttribute("aria-valuenow", "0");
    expect(screen.getByText("At least 10 characters")).toBeInTheDocument();

    await replace(user, screen.getByLabelText("Password"), "short");
    expect(meter()).toHaveAttribute("aria-valuenow", "1");
    expect(screen.getByText("Weak · at least 10 characters")).toBeInTheDocument();

    await replace(user, screen.getByLabelText("Password"), TEST_PASSWORD);
    expect(meter()).toHaveAttribute("aria-valuenow", "4");
    expect(meter()).toHaveAttribute("aria-valuetext", "Strong");
    expect(screen.getByText("Strong · at least 10 characters")).toBeInTheDocument();
  });

  test("answers and passwords are typed in fields that keep their own Show switch", async () => {
    const { user } = await openSetup();
    expect(screen.getByLabelText("Password")).toHaveAttribute("type", "password");
    await user.click(button("Show password"));
    expect(screen.getByLabelText("Password")).toHaveAttribute("type", "text");
    expect(screen.getByLabelText("Confirm password")).toHaveAttribute("type", "password");
    expect(button("Show confirm password")).toBeInTheDocument();
  });

  test.each([
    ["invalid_username", "Username", "Usernames are 3 to 32 characters, with no invisible characters."],
    ["invalid_display_name", "Display name", "Display names are 1 to 40 characters."],
    ["too_short", "Password", "Passwords need at least 10 characters."],
  ])("when the server says %s, it shows under %s", async (error, label, message) => {
    // The page checks these first, so the server only gets to say them when its rule is stricter or has changed.
    mockSetup(400, { error });
    const { user, queryClient } = await openSetup();
    await fillSetup(user);
    await user.click(button("Create account"));
    const field = await screen.findByLabelText(label);
    await waitFor(() => expect(field).toHaveAttribute("aria-invalid", "true"));
    expect(screen.getByRole("alert")).toHaveTextContent(message);
    expect(field).toHaveFocus();
    await settled(queryClient);
  });

  test("an account that already exists is said so, with a way to sign in", async () => {
    mockSetup(409, { error: "already_set_up" });
    const { user, router, queryClient } = await openSetup();
    await fillSetup(user);
    await user.click(button("Create account"));
    expect(await screen.findByRole("alert")).toHaveTextContent("An account already exists.");

    // Someone created it elsewhere; the page asks the server again before leaving, or it would bounce back here.
    mockAuthState(SIGNED_OUT);
    await user.click(screen.getByRole("link", { name: "Go to sign in" }));
    expect(await screen.findByRole("heading", { name: "Sign in" })).toBeInTheDocument();
    expect(router.state.location.pathname).toBe("/signin");
    await settled(queryClient);
  });

  test("a failure the page does not know is shown as the server worded it, and the form keeps what was typed", async () => {
    mockSetup(500, { error: "server_error" });
    const { user, queryClient } = await openSetup();
    await fillSetup(user);
    await user.click(button("Create account"));
    expect(await screen.findByRole("alert")).toHaveTextContent("Something went wrong on the server.");
    expect(screen.getByLabelText("Username")).toHaveValue("owner");
    await settled(queryClient);
  });
});

// ---- sign in ----

async function openSignIn(path = "/signin") {
  mockAuthState(SIGNED_OUT);
  const view = renderAt(path);
  await screen.findByRole("heading", { name: "Sign in" });
  return view;
}

async function signInWith(user: UserEvent, username: string, password: string) {
  await replace(user, screen.getByLabelText("Username"), username);
  await replace(user, screen.getByLabelText("Password"), password);
  await user.click(button("Sign in"));
}

describe("sign in", () => {
  test("shows the sign-in form with Keep me signed in ticked", async () => {
    await openSignIn();
    expect(screen.getByText("Use the account you created.")).toBeInTheDocument();
    expect(screen.getByText("Welcome back.")).toBeInTheDocument();
    expect(screen.getByLabelText("Keep me signed in")).toBeChecked();
    expect(screen.getByRole("link", { name: "Forgot password?" })).toHaveAttribute("href", "/forgot");
  });

  test("a wrong password shows the tries left, and the password is ready to retype", async () => {
    mockSignin(401, { error: "wrong_password", triesLeft: 3 });
    const { user, queryClient } = await openSignIn();
    await signInWith(user, "owner", "nope-nope-nope");
    expect(await screen.findByText(/3 tries left/)).toBeInTheDocument();
    expect(screen.getByRole("alert")).toHaveTextContent(
      `That password isn't right. 3 tries left before a ${LOCK_MINUTES}-minute pause.`,
    );
    const password = screen.getByLabelText("Password");
    expect(password).toHaveAttribute("aria-invalid", "true");
    expect(password).toHaveAccessibleDescription(/That password isn't right/);
    expect(password).toHaveFocus();
    expect(password).toHaveValue("nope-nope-nope");
    await settled(queryClient);
  });

  test("the last try says '1 try left'", async () => {
    mockSignin(401, { error: "wrong_password", triesLeft: 1 });
    const { user, queryClient } = await openSignIn();
    await signInWith(user, "owner", "nope-nope-nope");
    expect(await screen.findByText("1 try left")).toBeInTheDocument();
    await settled(queryClient);
  });

  test("a blank username or password is caught here, so it cannot use up a try", async () => {
    const { user } = await openSignIn();
    await user.click(button("Sign in"));
    expect(alertTexts()).toEqual(["Enter your username.", "Enter your password."]);
    expect(screen.getByLabelText("Username")).toHaveFocus();
    expect(requestsTo("/api/auth/signin")).toHaveLength(0);
  });

  test("Enter in the password field signs in, and unticking Keep me signed in is sent", async () => {
    const { user, router, queryClient } = await openSignIn();
    await replace(user, screen.getByLabelText("Username"), "owner");
    await user.click(screen.getByLabelText("Keep me signed in"));
    await user.type(screen.getByLabelText("Password"), `${TEST_PASSWORD}{Enter}`);
    await waitFor(() => expect(router.state.location.pathname).toBe("/"));
    expect(lastRequest("/api/auth/signin")?.body).toEqual({
      username: "owner",
      password: TEST_PASSWORD,
      keepSignedIn: false,
    });
    await settled(queryClient);
  });

  test("when the server cannot be reached, it says so and keeps what was typed", async () => {
    server.use(http.post("/api/auth/signin", () => HttpResponse.error()));
    const { user, queryClient } = await openSignIn();
    await signInWith(user, "owner", "whatever-it-is");
    expect(await screen.findByRole("alert")).toHaveTextContent("Can't reach the dashboard's server. Check that it's running.");
    expect(screen.getByLabelText("Username")).toHaveValue("owner");
    await settled(queryClient);
  });

  test("Forgot password? goes to the reset page and keeps the page asked for", async () => {
    const { user, router } = await openSignIn("/signin?next=%2Fgear");
    await user.click(screen.getByRole("link", { name: "Forgot password?" }));
    expect(await screen.findByRole("heading", { name: "Answer your security questions" })).toBeInTheDocument();
    expect(router.state.location.pathname).toBe("/forgot");
    expect(router.state.location.search).toBe("?next=%2Fgear");
  });

  test("what was typed does not outlive the screen: a finished request is collected as soon as the page lets go", async () => {
    mockSignin(401, { error: "wrong_password", triesLeft: 3 });
    const { user, queryClient, unmount } = await openSignIn();
    await signInWith(user, "owner", "nope-nope-nope");
    await screen.findByText(/3 tries left/);
    expect(queryClient.getMutationCache().getAll()).toHaveLength(1);
    unmount();
    // The sent password is in the request's variables; with the default five-minute keep it would sit here.
    await waitFor(() => expect(queryClient.getMutationCache().getAll()).toHaveLength(0));
  });
});

// ---- the pause ----

describe("a locked sign-in", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  test("counts down and unlocks itself", async () => {
    // The clock runs on its own as well as by hand, so typing and the fake server still work.
    vi.useFakeTimers({ shouldAdvanceTime: true });
    mockSignin(423, () => ({ error: "locked", lockedUntil: inMinutes(5) }));
    const { user, queryClient } = await openSignIn();
    await signInWith(user, "owner", "x");

    expect(await screen.findByRole("heading", { name: "Sign-in is paused" })).toBeInTheDocument();
    expect(screen.getByText("5:00")).toBeInTheDocument();
    expect(screen.getByText("Taking a short pause.")).toBeInTheDocument();
    expect(screen.getByText("The page unlocks on its own. No need to refresh.")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Try again" })).toBeDisabled();

    act(() => {
      vi.advanceTimersByTime(5 * 60_000);
    });
    expect(screen.getByRole("button", { name: "Try again" })).toBeEnabled();
    expect(screen.getByRole("status")).toHaveTextContent("You can try again now.");

    // Trying again brings the form back: the username stays, the password does not, and typing can start.
    await user.click(screen.getByRole("button", { name: "Try again" }));
    expect(screen.getByRole("heading", { name: "Sign in" })).toBeInTheDocument();
    expect(screen.getByLabelText("Username")).toHaveValue("owner");
    expect(screen.getByLabelText("Password")).toHaveValue("");
    expect(screen.getByLabelText("Password")).toHaveFocus();
    await settled(queryClient);
  });

  test("Back to sign in leaves the pause screen at once, to try another name", async () => {
    mockSignin(423, () => ({ error: "locked", lockedUntil: inMinutes(5) }));
    const { user, queryClient } = await openSignIn();
    await signInWith(user, "owner", "x");
    await screen.findByRole("heading", { name: "Sign-in is paused" });
    await user.click(screen.getByRole("link", { name: "Back to sign in" }));
    expect(await screen.findByRole("heading", { name: "Sign in" })).toBeInTheDocument();
    await settled(queryClient);
  });

  test("the fifth wrong password says what went wrong", async () => {
    mockSignin(401, { error: "wrong_password", triesLeft: 1 });
    const { user, queryClient } = await openSignIn();
    await signInWith(user, "owner", "nope-nope-nope");
    await screen.findByText("1 try left");
    mockSignin(423, () => ({ error: "locked", lockedUntil: inMinutes(5) }));
    await user.click(button("Sign in"));
    await screen.findByRole("heading", { name: "Sign-in is paused" });
    expect(
      screen.getByText("That was 5 wrong passwords in a row. You can try again when the timer runs out."),
    ).toBeInTheDocument();
    await settled(queryClient);
  });

  test("a pause that was already there only says it is on, because the page can't know why", async () => {
    mockSignin(423, () => ({ error: "locked", lockedUntil: inMinutes(5) }));
    const { user, queryClient } = await openSignIn();
    await signInWith(user, "owner", "x");
    await screen.findByRole("heading", { name: "Sign-in is paused" });
    expect(screen.getByText("Too many tries recently. You can try again when the timer runs out.")).toBeInTheDocument();
    expect(screen.queryByText(/5 wrong passwords/)).toBeNull();
    await settled(queryClient);
  });

  test("a pause that arrives after a different name's last try is not blamed on this attempt either", async () => {
    mockSignin(401, { error: "wrong_password", triesLeft: 1 });
    const { user, queryClient } = await openSignIn();
    await signInWith(user, "owner", "nope-nope-nope");
    await screen.findByText("1 try left");
    mockSignin(423, () => ({ error: "locked", lockedUntil: inMinutes(5) }));
    await signInWith(user, "someone-else", "nope-nope-nope");
    await screen.findByRole("heading", { name: "Sign-in is paused" });
    expect(screen.getByText("Too many tries recently. You can try again when the timer runs out.")).toBeInTheDocument();
    await settled(queryClient);
  });

  test("the countdown follows the server's clock when it is not this computer's", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    // The server's clock is a minute and a half ahead: its five minutes from its "now" is 5:00 from now here too.
    mockSignin(423, (serverNow) => ({ error: "locked", lockedUntil: inMinutes(5, serverNow) }), { clockAhead: 90_000 });
    const { user, queryClient } = await openSignIn();
    await signInWith(user, "owner", "x");
    await screen.findByRole("heading", { name: "Sign-in is paused" });
    expect(screen.getByRole("timer")).toHaveTextContent("5:00");
    expect(screen.getByRole("progressbar")).toHaveAttribute("aria-valuetext", "5 minutes");
    act(() => {
      vi.advanceTimersByTime(5 * 60_000);
    });
    expect(screen.getByRole("button", { name: "Try again" })).toBeEnabled();
    await settled(queryClient);
  });

  test("a lock with no usable end time is shown as the plain message it is", async () => {
    mockSignin(423, { error: "locked" });
    const { user, queryClient } = await openSignIn();
    await signInWith(user, "owner", "x");
    expect(await screen.findByRole("alert")).toHaveTextContent("Too many tries. Try again when the timer runs out.");
    await settled(queryClient);
  });
});

// ---- forgot password ----

type ForgotValues = { username: string; answers: [string, string, string]; newPassword: string; confirm: string };

const FORGOT: ForgotValues = {
  username: "owner",
  answers: ANSWERS,
  newPassword: "a brand new password",
  confirm: "a brand new password",
};

async function openForgot(path = "/forgot") {
  mockAuthState(SIGNED_OUT);
  const view = renderAt(path);
  await screen.findByRole("heading", { name: "Answer your security questions" });
  return view;
}

async function fillForgot(user: UserEvent, overrides: Partial<ForgotValues> = {}) {
  const values = { ...FORGOT, ...overrides };
  await replace(user, screen.getByLabelText("Username"), values.username);
  for (const index of [0, 1, 2]) await replace(user, answerFor(index), values.answers[index]);
  await replace(user, screen.getByLabelText("New password"), values.newPassword);
  await replace(user, screen.getByLabelText("Confirm new password"), values.confirm);
}

const resetButton = () => button("Reset password");

describe("forgot password", () => {
  test("asks the three questions with the answers hidden until shown", async () => {
    const { user } = await openForgot();
    expect(screen.getByText("Capitals and extra spaces don't matter.")).toBeInTheDocument();
    expect(screen.getByText("Reset your password.")).toBeInTheDocument();
    expect(screen.getByText(`Answer all three questions. One wrong answer locks resetting for ${LOCK_MINUTES} minutes.`)).toBeInTheDocument();
    expect(screen.getAllByTestId("security-question").map((element) => element.textContent)).toEqual([...SECURITY_QUESTIONS]);

    for (const index of [0, 1, 2]) expect(answerFor(index)).toHaveAttribute("type", "password");
    await user.click(button("Show answer 2"));
    expect(answerFor(1)).toHaveAttribute("type", "text");
    expect(answerFor(0)).toHaveAttribute("type", "password");
    expect(answerFor(2)).toHaveAttribute("type", "password");
  });

  test("a right reset goes back to sign-in with a note, the name filled in, and the password next", async () => {
    const { user, router, queryClient } = await openForgot("/forgot?next=%2Fgear");
    await fillForgot(user, { username: "  owner  " });
    await user.click(resetButton());

    await waitFor(() => expect(router.state.location.pathname).toBe("/signin"));
    expect(router.state.location.search).toBe("?next=%2Fgear");
    expect(lastRequest("/api/auth/forgot")?.body).toEqual({
      username: "owner",
      answers: ANSWERS,
      newPassword: "a brand new password",
    });
    expect(screen.getByRole("status")).toHaveTextContent("Password changed. Sign in with your new password.");
    expect(screen.getByLabelText("Username")).toHaveValue("owner");
    expect(screen.getByLabelText("Password")).toHaveFocus();

    // The reset cleared the sign-in pause (R11), so signing in works straight away.
    await user.type(screen.getByLabelText("Password"), "a brand new password");
    await user.click(button("Sign in"));
    await waitFor(() => expect(router.state.location.pathname).toBe("/gear"));
    await settled(queryClient);
  });

  test("a wrong answer locks reset with a countdown", async () => {
    mockForgot(401, () => ({ error: "wrong_answer", lockedUntil: inMinutes(5) }));
    const { user, queryClient } = await openForgot();
    await fillForgot(user);
    await user.click(resetButton());
    expect(await screen.findByRole("heading", { name: "Password reset is locked" })).toBeInTheDocument();
    expect(screen.getByText("One of the answers didn't match. You can try again when the timer runs out.")).toBeInTheDocument();
    expect(screen.getByText("This stops anyone from guessing over and over.")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Try again" })).toBeDisabled();
    await settled(queryClient);
  });

  test("a reset that is already locked shows the same countdown", async () => {
    mockForgot(423, () => ({ error: "locked", lockedUntil: inMinutes(3) }));
    const { user, queryClient } = await openForgot();
    await fillForgot(user);
    await user.click(resetButton());
    expect(await screen.findByRole("heading", { name: "Password reset is locked" })).toBeInTheDocument();
    expect(screen.getByRole("timer")).toHaveTextContent(/^[23]:\d\d$/);
    // No answer was judged this time, so nothing is said about one.
    expect(screen.getByText("Too many tries recently. You can try again when the timer runs out.")).toBeInTheDocument();
    expect(screen.queryByText(/answers didn't match/)).toBeNull();
    await settled(queryClient);
  });

  test("while the reset is locked, the answers and new password that were typed are not kept anywhere", async () => {
    mockForgot(401, () => ({ error: "wrong_answer", lockedUntil: inMinutes(5) }));
    const { user, queryClient } = await openForgot();
    await fillForgot(user);
    await user.click(resetButton());
    await screen.findByRole("heading", { name: "Password reset is locked" });
    // The request that held them is let go, and the form's own copy is emptied (the next test shows it empty).
    await waitFor(() => expect(queryClient.getMutationCache().getAll()).toHaveLength(0));
    expect(document.body.textContent).not.toContain(ANSWERS[0]);
  });

  test("every answer field turns off spell-check, auto-correct and auto-capitalise, shown or hidden", async () => {
    const { user } = await openForgot();
    const check = () => {
      for (const index of [0, 1, 2]) {
        expect(answerFor(index)).toHaveAttribute("spellcheck", "false");
        expect(answerFor(index)).toHaveAttribute("autocorrect", "off");
        expect(answerFor(index)).toHaveAttribute("autocapitalize", "off");
        expect(answerFor(index)).toHaveAttribute("autocomplete", "off");
      }
    };
    check();
    await user.click(button("Show answer 1"));
    await user.click(button("Show answer 3"));
    check();
  });

  test("Confirm says nothing about a mismatch until it has something in it or has been left", async () => {
    const { user } = await openForgot();
    await user.click(resetButton());
    await replace(user, screen.getByLabelText("New password"), "a brand new password");
    expect(errorTexts()).not.toContain("The passwords don't match.");
    await user.type(screen.getByLabelText("Confirm new password"), "a brand");
    expect(errorTexts()).toContain("The passwords don't match.");
  });

  test("Back to sign in on the pause screen goes to sign-in", async () => {
    mockForgot(401, () => ({ error: "wrong_answer", lockedUntil: inMinutes(5) }));
    const { user, router, queryClient } = await openForgot();
    await fillForgot(user);
    await user.click(resetButton());
    await screen.findByRole("heading", { name: "Password reset is locked" });
    await user.click(screen.getByRole("link", { name: "Back to sign in" }));
    expect(await screen.findByRole("heading", { name: "Sign in" })).toBeInTheDocument();
    expect(router.state.location.pathname).toBe("/signin");
    await settled(queryClient);
  });

  test("after the pause, Try again brings the form back with the name kept and the secrets cleared", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    try {
      mockForgot(401, () => ({ error: "wrong_answer", lockedUntil: inMinutes(5) }));
      const { user, queryClient } = await openForgot();
      await fillForgot(user);
      await user.click(resetButton());
      await screen.findByRole("heading", { name: "Password reset is locked" });
      act(() => {
        vi.advanceTimersByTime(5 * 60_000);
      });
      await user.click(screen.getByRole("button", { name: "Try again" }));

      expect(screen.getByRole("heading", { name: "Answer your security questions" })).toBeInTheDocument();
      expect(screen.getByLabelText("Username")).toHaveValue("owner");
      for (const index of [0, 1, 2]) expect(answerFor(index)).toHaveValue("");
      expect(screen.getByLabelText("New password")).toHaveValue("");
      expect(answerFor(0)).toHaveFocus();
      await settled(queryClient);
    } finally {
      vi.useRealTimers();
    }
  });

  test("a blank answer is caught here: sending it would only lock the reset", async () => {
    const { user } = await openForgot();
    await fillForgot(user, { answers: [ANSWERS[0], "   ", ANSWERS[2]] });
    await user.click(resetButton());
    expect(screen.getByRole("alert")).toHaveTextContent("Enter an answer.");
    expect(answerFor(1)).toHaveFocus();
    expect(requestsTo("/api/auth/forgot")).toHaveLength(0);
  });

  test("a blank username, a short new password and a mismatch are caught before anything is sent", async () => {
    const { user } = await openForgot();
    await fillForgot(user, { username: "", newPassword: "short", confirm: "other" });
    await user.click(resetButton());
    expect(alertTexts()).toEqual([
      "Enter your username.",
      "Passwords need at least 10 characters.",
      "The passwords don't match.",
    ]);
    expect(screen.getByLabelText("Username")).toHaveFocus();
    expect(requestsTo("/api/auth/forgot")).toHaveLength(0);
  });

  test("a new password the server finds too short shows under it and locks nothing", async () => {
    mockForgot(400, { error: "too_short" });
    const { user, queryClient } = await openForgot();
    await fillForgot(user);
    await user.click(resetButton());
    expect(await screen.findByRole("alert")).toHaveTextContent("Passwords need at least 10 characters.");
    expect(screen.getByLabelText("New password")).toHaveAttribute("aria-invalid", "true");
    expect(screen.queryByRole("heading", { name: "Password reset is locked" })).toBeNull();
    await settled(queryClient);
  });

  test("a failure the page does not know is shown as the server worded it, and the form keeps what was typed", async () => {
    mockForgot(500, { error: "server_error" });
    const { user, queryClient } = await openForgot();
    await fillForgot(user);
    await user.click(resetButton());
    expect(await screen.findByRole("alert")).toHaveTextContent("Something went wrong on the server.");
    expect(answerFor(0)).toHaveValue(ANSWERS[0]);
    expect(screen.queryByRole("heading", { name: "Password reset is locked" })).toBeNull();
    await settled(queryClient);
  });

  test("Back to sign in goes back, keeping the page asked for", async () => {
    const { user, router } = await openForgot("/forgot?next=%2Fgear");
    await user.click(screen.getByRole("link", { name: "Back to sign in" }));
    expect(await screen.findByRole("heading", { name: "Sign in" })).toBeInTheDocument();
    expect(router.state.location.search).toBe("?next=%2Fgear");
  });
});

// ---- the pause screen on its own ----

function renderLocked(untilMs: number, props: Partial<Parameters<typeof LockedPanel>[0]> = {}) {
  const onTryAgain = vi.fn();
  render(
    <MemoryRouter>
      <LockedPanel kind="reset" until={new Date(untilMs)} justLocked onTryAgain={onTryAgain} {...props} />
    </MemoryRouter>,
  );
  return { onTryAgain };
}

describe("LockedPanel", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  test("the ring is named, says the time left in words, and is as full as the time left", () => {
    const start = Date.parse("2026-10-19T10:00:00.000Z");
    vi.useFakeTimers({ now: start });
    renderLocked(start + 246_000);

    const ring = screen.getByRole("progressbar", { name: "Time until you can try again" });
    expect(ring).toHaveAttribute("aria-valuetext", "4 minutes 6 seconds");
    expect(ring).toHaveAttribute("aria-valuenow", "82");
    expect(within(ring).getByRole("timer")).toHaveTextContent("4:06");

    act(() => {
      vi.advanceTimersByTime(1_000);
    });
    expect(ring).toHaveAttribute("aria-valuetext", "4 minutes 5 seconds");
    expect(within(ring).getByRole("timer")).toHaveTextContent("4:05");
  });

  test("reset and sign-in each say what happened when this attempt caused the pause", () => {
    const start = Date.now();
    renderLocked(start + 60_000, { kind: "signin" });
    expect(screen.getByRole("heading", { name: "Sign-in is paused" })).toBeInTheDocument();
    expect(screen.getByText("That was 5 wrong passwords in a row. You can try again when the timer runs out.")).toBeInTheDocument();
  });

  test.each(["signin", "reset"] as const)("a %s pause that was already there does not claim a cause", (kind) => {
    renderLocked(Date.now() + 60_000, { kind, justLocked: false });
    expect(screen.getByText("Too many tries recently. You can try again when the timer runs out.")).toBeInTheDocument();
  });

  test("the number is right the moment the page is looked at again, after timers ran late", () => {
    // A hidden tab's timers are slowed or stopped; the clock moved on without them.
    const start = Date.parse("2026-10-19T10:00:00.000Z");
    vi.useFakeTimers({ now: start });
    renderLocked(start + 300_000);
    const ring = screen.getByRole("progressbar", { name: "Time until you can try again" });
    expect(screen.getByRole("timer")).toHaveTextContent("5:00");

    vi.setSystemTime(start + 200_000); // moves the clock without running the timers
    expect(screen.getByRole("timer")).toHaveTextContent("5:00");
    act(() => {
      document.dispatchEvent(new Event("visibilitychange"));
    });
    expect(screen.getByRole("timer")).toHaveTextContent("1:40");
    expect(ring).toHaveAttribute("aria-valuetext", "1 minute 40 seconds");

    // And it keeps ticking from there, once, not twice.
    act(() => {
      vi.advanceTimersByTime(1_000);
    });
    expect(screen.getByRole("timer")).toHaveTextContent("1:39");
  });

  test("the heading takes the cursor, so a screen reader starts at what changed", () => {
    renderLocked(Date.now() + 60_000);
    expect(screen.getByRole("heading", { name: "Password reset is locked" })).toHaveFocus();
  });

  test("Try again stays off until the time is up, then asks the page to bring the form back", async () => {
    const start = Date.parse("2026-10-19T10:00:00.000Z");
    vi.useFakeTimers({ now: start });
    const { onTryAgain } = renderLocked(start + 3_000);
    expect(screen.getByRole("button", { name: "Try again" })).toBeDisabled();
    act(() => {
      vi.advanceTimersByTime(2_999);
    });
    expect(screen.getByRole("button", { name: "Try again" })).toBeDisabled();
    act(() => {
      vi.advanceTimersByTime(1);
    });
    const tryAgain = screen.getByRole("button", { name: "Try again" });
    expect(tryAgain).toBeEnabled();
    tryAgain.click();
    expect(onTryAgain).toHaveBeenCalledTimes(1);
  });

  test("a time already past opens ready to try again", () => {
    renderLocked(Date.now() - 5_000);
    expect(screen.getByRole("button", { name: "Try again" })).toBeEnabled();
    expect(screen.getByRole("timer")).toHaveTextContent("0:00");
  });
});

// ---- small pure helpers ----

describe("passwordStrength", () => {
  test.each([
    ["", 0],
    ["short", 1],
    ["aaaaaaaaaaaaaaaaaaaaaaaa", 1], // long, but one letter repeated
    ["ninechars", 1],
    ["tencharsok", 2],
    ["a longer passphrase", 3],
    ["lantern-moss-42", 4], // 15 characters in three kinds
    ["correct horse battery staple", 4],
    ["😀😀😀😀😀", 1], // 5 characters, not 10
    ["\u3392\u2121\u2116\u3371\u338f1", 4], // 6 typed, but "MHzTELNohPakg1" (14) once normalized, as the server counts
  ])("%j is %i", (password, level) => {
    expect(passwordStrength(password)).toBe(level);
  });
});

describe("spokenDuration", () => {
  test.each([
    [246, "4 minutes 6 seconds"],
    [300, "5 minutes"],
    [61, "1 minute 1 second"],
    [60, "1 minute"],
    [59, "59 seconds"],
    [1, "1 second"],
    [0, "0 seconds"],
  ])("%i seconds is %j", (seconds, words) => {
    expect(spokenDuration(seconds)).toBe(words);
  });
});

// ---- the account rules, shared with the server ----

describe("account rules", () => {
  test("usernames: the shared length limits are the ones the form applies", () => {
    expect(checkNewUsername("a".repeat(USERNAME_MIN - 1))).toBeDefined();
    expect(checkNewUsername("a".repeat(USERNAME_MIN))).toBeUndefined();
    expect(checkNewUsername("a".repeat(USERNAME_MAX))).toBeUndefined();
    expect(checkNewUsername("a".repeat(USERNAME_MAX + 1))).toBeDefined();
    expect(checkNewUsername("aJAY Gamin'")).toBeUndefined();
    expect(checkNewUsername("own​er")).toBeDefined(); // a zero-width space
    expect(checkNewUsername(" owner ")).toBeUndefined(); // trimmed, as the server does
    expect(checkNewUsername(" ab ")).toBeDefined(); // two characters once trimmed
  });

  test("display names count characters, not code units", () => {
    expect(checkDisplayName("   ")).toBeDefined();
    expect(checkDisplayName("😀".repeat(DISPLAY_NAME_MAX))).toBeUndefined();
    expect(checkDisplayName("😀".repeat(DISPLAY_NAME_MAX + 1))).toBeDefined();
  });

  test("passwords: the minimum is the shared one, counted in characters", () => {
    expect(checkNewPassword("a".repeat(MIN_PASSWORD_LENGTH - 1))).toBeDefined();
    expect(checkNewPassword("a".repeat(MIN_PASSWORD_LENGTH))).toBeUndefined();
    expect(checkNewPassword("😀".repeat(MIN_PASSWORD_LENGTH))).toBeUndefined();
  });

  // R42: the server normalizes a password (NFKC) before it counts it, so the form counts the same way.
  test("passwords are counted once normalized, as the server counts them", () => {
    // Letter + combining accent: two code points each, one character once normalized.
    expect(checkNewPassword("e\u0301".repeat(MIN_PASSWORD_LENGTH - 1))).toBeDefined();
    expect(checkNewPassword("e\u0301".repeat(MIN_PASSWORD_LENGTH))).toBeUndefined();
    // Four "ffi" ligatures are twelve letters.
    expect(checkNewPassword("\ufb03".repeat(4))).toBeUndefined();
  });

  test("a confirmation is the same password when only the way an accent was typed differs", () => {
    expect(checkConfirmation("Caf\u00e9 au lait 42", "Cafe\u0301 au lait 42")).toBeUndefined();
    expect(checkConfirmation("Caf\u00e9 au lait 42", "Cafe au lait 42")).toBeDefined();
    expect(checkConfirmation("Caf\u00e9 au lait 42", "caf\u00e9 au lait 42")).toBeDefined();
  });
});
