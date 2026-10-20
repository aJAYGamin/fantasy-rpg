import { type ChildProcess, spawn } from "node:child_process";
import { once } from "node:events";
import { realpathSync } from "node:fs";
import { createServer } from "node:net";
import { dirname, join, resolve } from "node:path";
import { afterEach, expect, test, vi } from "vitest";
import { tmpFile } from "./helpers.js";

const dashboard = resolve(import.meta.dirname, "../..");
const running: ChildProcess[] = [];

afterEach(async () => {
  for (const child of running.splice(0)) {
    if (child.exitCode === null) {
      child.kill("SIGTERM");
      await once(child, "exit");
    }
  }
});

// A port nothing is using right now, so the real server can start on it.
async function freePort(): Promise<number> {
  const probe = createServer();
  await new Promise<void>((done) => probe.listen(0, "127.0.0.1", done));
  const { port } = probe.address() as { port: number };
  await new Promise<void>((done) => probe.close(() => done()));
  return port;
}

// The real entry point, started as `npm run dev` starts it, from a folder of its own so a relative path has to be
// resolved against it.
test("the server says once, as it starts, which database file it uses, as a full path", { timeout: 30_000 }, async () => {
  const folder = dirname(tmpFile());
  const child = spawn(join(dashboard, "node_modules", ".bin", "tsx"), [join(dashboard, "server", "src", "index.ts")], {
    cwd: folder,
    env: { ...process.env, AMETHYST_PORT: String(await freePort()), AMETHYST_DB: join("data", "amethyst.db") },
    stdio: ["ignore", "pipe", "pipe"],
  });
  running.push(child);
  let output = "";
  child.stdout?.on("data", (chunk: Buffer) => {
    output += chunk.toString();
  });
  child.stderr?.on("data", (chunk: Buffer) => {
    output += chunk.toString();
  });
  await vi.waitFor(() => expect(output).toContain("listening on"), { timeout: 25_000, interval: 100 });

  // The server's working folder as it sees it (on a Mac the temp folder is reached through a link).
  const full = join(realpathSync(folder), "data", "amethyst.db");
  expect(output.split("\n").filter((line) => line.includes("amethyst.db"))).toEqual([`Amethyst Dashboard database: ${full}`]);
});
