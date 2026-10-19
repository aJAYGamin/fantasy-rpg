import { afterEach, expect, test } from "vitest";
import type { FastifyInstance } from "fastify";
import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { type Db, openDatabase } from "../src/db/database.js";

let app: FastifyInstance | undefined;
let db: Db | undefined;

afterEach(async () => {
  await app?.close();
  app = undefined;
  db?.close();
  db = undefined;
});

test("health answers with the product name", async () => {
  db = openDatabase(":memory:");
  app = await buildApp({ config: loadConfig({}), db });
  const res = await app.inject({ method: "GET", url: "/api/health" });
  expect(res.statusCode).toBe(200);
  expect(res.json()).toEqual({ ok: true, name: "Amethyst Dashboard" });
});

test("config reads its env names and keeps safe defaults", () => {
  expect(loadConfig({}).host).toBe("127.0.0.1");
  expect(loadConfig({ AMETHYST_PORT: "5000" }).port).toBe(5000);
});
