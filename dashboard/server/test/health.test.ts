import { afterEach, expect, test } from "vitest";
import type { FastifyInstance } from "fastify";
import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";

let app: FastifyInstance | undefined;

afterEach(async () => {
  await app?.close();
  app = undefined;
});

test("health answers with the product name", async () => {
  app = await buildApp({ config: loadConfig({}) });
  const res = await app.inject({ method: "GET", url: "/api/health" });
  expect(res.statusCode).toBe(200);
  expect(res.json()).toEqual({ ok: true, name: "Amethyst Dashboard" });
});

test("config reads its env names and keeps safe defaults", () => {
  expect(loadConfig({}).host).toBe("127.0.0.1");
  expect(loadConfig({ AMETHYST_PORT: "5000" }).port).toBe(5000);
});
