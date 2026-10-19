import { defineConfig, devices } from "@playwright/test";

// Minimal for now; the end-to-end task adds the web server and the specs.
export default defineConfig({
  testDir: "e2e",
  outputDir: "test-results",
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 900 } },
    },
  ],
});
