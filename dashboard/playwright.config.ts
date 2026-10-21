import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { defineConfig, devices } from "@playwright/test";

// Each spec file gets a server of its own with an empty database, so neither depends on what the other did. The
// ports stay clear of the dev server's 4517 (and Vite's 5173), so a dev session can keep running alongside.
const SERVERS = { auth: 4618, shell: 4619 } as const;

// One fresh temporary folder per run holds both databases. Playwright loads this file again in every worker process;
// the environment hands them the folder the first load made, and only that first process removes it, as it exits:
// by then the servers have stopped (Playwright stops them after any globalTeardown, too late for one to clean up).
function runFolder(): string {
  const handedDown = process.env.AMETHYST_E2E_DIR;
  if (handedDown) return handedDown;
  const made = mkdtempSync(join(tmpdir(), "amethyst-e2e-"));
  process.env.AMETHYST_E2E_DIR = made;
  process.once("exit", () => rmSync(made, { recursive: true, force: true }));
  return made;
}
const dataDir = runFolder();

const chromium = { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 900 } };

function server(name: keyof typeof SERVERS) {
  const port = SERVERS[name];
  return {
    // The built server and web app (npm run build first); not `npm start`, which pins NODE_ENV=production.
    command: "node dist/server/server/src/index.js",
    url: `http://127.0.0.1:${port}/api/health`,
    // Never someone else's server, or a leftover with an old database: a port in use fails the run instead.
    reuseExistingServer: false,
    env: {
      // Only NODE_ENV=test lets the lock be shortened (to 3 seconds here), so the pauses can be waited out.
      NODE_ENV: "test",
      AMETHYST_LOCK_SECONDS: "3",
      AMETHYST_DB: join(dataDir, `${name}.db`),
      AMETHYST_WEB_DIST: "dist/web",
      AMETHYST_PORT: String(port),
      AMETHYST_HOST: "127.0.0.1",
      AMETHYST_SECURE_COOKIES: "0",
    },
    stdout: "ignore" as const,
    stderr: "pipe" as const,
    // SIGTERM lets the server close its database as a Ctrl+C would.
    gracefulShutdown: { signal: "SIGTERM" as const, timeout: 5_000 },
  };
}

export default defineConfig({
  testDir: "e2e",
  outputDir: "test-results",
  // The tests in a file run in order against that file's one account.
  fullyParallel: false,
  forbidOnly: Boolean(process.env.CI),
  reporter: "list",
  use: { trace: "retain-on-failure" },
  projects: [
    {
      name: "auth",
      testMatch: "auth.spec.ts",
      use: { ...chromium, baseURL: `http://127.0.0.1:${SERVERS.auth}` },
    },
    {
      name: "shell",
      testMatch: "shell.spec.ts",
      use: { ...chromium, baseURL: `http://127.0.0.1:${SERVERS.shell}` },
    },
  ],
  webServer: [server("auth"), server("shell")],
});
