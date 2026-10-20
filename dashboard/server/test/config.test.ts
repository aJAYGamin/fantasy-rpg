import { expect, test } from "vitest";
import { loadConfig } from "../src/config.js";

test("defaults match the documented ones", () => {
  expect(loadConfig({})).toEqual({
    port: 4517,
    host: "127.0.0.1",
    dbPath: "data/amethyst.db",
    secureCookies: false,
    webDist: null,
    lockMs: 5 * 60_000,
    allowedHosts: [],
  });
});

test("every documented env name is read", () => {
  const config = loadConfig({
    AMETHYST_PORT: "5000",
    AMETHYST_HOST: "0.0.0.0",
    AMETHYST_DB: "/tmp/other.db",
    AMETHYST_SECURE_COOKIES: "1",
    AMETHYST_ALLOWED_HOSTS: "dash.lan",
  });
  expect(config).toMatchObject({
    port: 5000,
    host: "0.0.0.0",
    dbPath: "/tmp/other.db",
    secureCookies: true,
    allowedHosts: ["dash.lan"],
  });
});

test("AMETHYST_ALLOWED_HOSTS is a comma list of host names, kept lower-case and without ports or brackets", () => {
  const { allowedHosts } = loadConfig({ AMETHYST_ALLOWED_HOSTS: " Dash.LAN , mac-mini.local:4517,[fe80::1],, " });
  expect(allowedHosts).toEqual(["dash.lan", "mac-mini.local", "fe80::1"]);
  expect(loadConfig({ AMETHYST_ALLOWED_HOSTS: "" }).allowedHosts).toEqual([]);
});

test("an entry of AMETHYST_ALLOWED_HOSTS that isn't a host name is refused instead of silently dropped", () => {
  for (const bad of ["dash.lan:http", "two words", "[::1", "http://dash.lan"]) {
    expect(() => loadConfig({ AMETHYST_ALLOWED_HOSTS: `localhost,${bad}` }), bad).toThrow(/AMETHYST_ALLOWED_HOSTS/);
  }
});

test("an unusable port is refused instead of silently replaced", () => {
  expect(() => loadConfig({ AMETHYST_PORT: "abc" })).toThrow(/AMETHYST_PORT/);
  expect(() => loadConfig({ AMETHYST_PORT: "70000" })).toThrow(/AMETHYST_PORT/);
});

test("the built web app is served only in production", () => {
  expect(loadConfig({ NODE_ENV: "production" }).webDist).toBe("dist/web");
  expect(loadConfig({ NODE_ENV: "development" }).webDist).toBeNull();
});

test("AMETHYST_WEB_DIST names the built web app to serve, in any NODE_ENV", () => {
  for (const NODE_ENV of [undefined, "test", "development", "production"]) {
    expect(loadConfig({ NODE_ENV, AMETHYST_WEB_DIST: "/tmp/web" }).webDist).toBe("/tmp/web");
  }
  // Left empty, it changes nothing: production still serves dist/web and development still leaves it to Vite.
  expect(loadConfig({ NODE_ENV: "production", AMETHYST_WEB_DIST: "" }).webDist).toBe("dist/web");
  expect(loadConfig({ NODE_ENV: "test", AMETHYST_WEB_DIST: "" }).webDist).toBeNull();
});

test("the lock length can be shortened only when NODE_ENV is test", () => {
  const realLock = 5 * 60_000;
  expect(loadConfig({ NODE_ENV: "test", AMETHYST_LOCK_SECONDS: "3" }).lockMs).toBe(3000);
  expect(loadConfig({ NODE_ENV: "production", AMETHYST_LOCK_SECONDS: "3" }).lockMs).toBe(realLock);
  expect(loadConfig({ NODE_ENV: "development", AMETHYST_LOCK_SECONDS: "3" }).lockMs).toBe(realLock);
  expect(loadConfig({ AMETHYST_LOCK_SECONDS: "3" }).lockMs).toBe(realLock);
});

test("a nonsense test lock length never shortens the real lock", () => {
  for (const bad of ["0", "-5", "abc", ""]) {
    expect(loadConfig({ NODE_ENV: "test", AMETHYST_LOCK_SECONDS: bad }).lockMs).toBe(5 * 60_000);
  }
});
