import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterAll, afterEach, beforeAll, beforeEach } from "vitest";
import { clearQueryClients, mockMatchMedia } from "./helpers";
import { fakeUploads, resetMocks, restoreUploads, server } from "./msw";

// A request no test mocked is a bug in the test (or the app), so it fails instead of warning.
beforeAll(() => {
  server.listen({ onUnhandledFrame: "error" });
  fakeUploads();
});

// jsdom has no matchMedia; by default the Mac is in light mode.
beforeEach(() => {
  mockMatchMedia(false);
});

// Without vitest globals, Testing Library cannot register its own cleanup.
afterEach(() => {
  cleanup();
  clearQueryClients();
  server.resetHandlers();
  resetMocks();
  localStorage.clear();
  delete document.documentElement.dataset.theme;
});

afterAll(() => {
  restoreUploads();
  server.close();
});
