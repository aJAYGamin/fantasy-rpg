import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { FastifyInstance } from "fastify";
import { afterEach, beforeEach, expect, test } from "vitest";
import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";

let dir: string;
let app: FastifyInstance | undefined;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "amethyst-web-"));
  writeFileSync(join(dir, "index.html"), "<!doctype html><title>built page</title>");
  mkdirSync(join(dir, "assets"));
  writeFileSync(join(dir, "assets", "app.js"), "console.log('built asset');");
});

afterEach(async () => {
  await app?.close();
  app = undefined;
  rmSync(dir, { recursive: true, force: true });
});

async function served() {
  app = await buildApp({ config: { ...loadConfig({}), webDist: dir } });
  return app;
}

test("serves the built page and its assets", async () => {
  const server = await served();
  const page = await server.inject({ method: "GET", url: "/" });
  expect(page.statusCode).toBe(200);
  expect(page.body).toContain("built page");
  const asset = await server.inject({ method: "GET", url: "/assets/app.js" });
  expect(asset.statusCode).toBe(200);
  expect(asset.body).toContain("built asset");
});

test("a deep link falls back to the page so the router can handle it", async () => {
  const res = await (await served()).inject({ method: "GET", url: "/debug/party" });
  expect(res.statusCode).toBe(200);
  expect(res.body).toContain("built page");
});

test("an unknown API route stays a JSON 404, never the page", async () => {
  const server = await served();
  for (const url of ["/api", "/api/nope", "/api?x=1"]) {
    const res = await server.inject({ method: "GET", url });
    expect(res.statusCode, url).toBe(404);
    expect(res.headers["content-type"], url).toContain("application/json");
  }
});

test("without a built web app the server answers only the API", async () => {
  app = await buildApp({ config: loadConfig({}) });
  const res = await app.inject({ method: "GET", url: "/" });
  expect(res.statusCode).toBe(404);
});
