import { render, screen } from "@testing-library/react";
import { expect, test } from "vitest";
import { App } from "../src/App";
import { NO_ACCOUNT, mockAuthState } from "./msw";

test("the app starts in the router: with no account yet it opens on Create your account", async () => {
  mockAuthState(NO_ACCOUNT);
  render(<App />);
  expect(await screen.findByRole("heading", { name: "Create your account" })).toBeInTheDocument();
  expect(window.location.pathname).toBe("/setup");
});
