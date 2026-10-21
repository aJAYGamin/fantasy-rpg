import { mkdirSync, writeFileSync } from "node:fs";
import { type AddressInfo, connect } from "node:net";
import { dirname, join } from "node:path";
import type { FastifyInstance } from "fastify";
import { describe, expect, test } from "vitest";
import { countAccounts } from "../src/auth/accounts.js";
import { loadConfig } from "../src/config.js";
import { OWNER_PASSWORD, dbOf, ownerApp, setupBody, testApp, tmpFile } from "./helpers.js";

// A built web app in a temporary folder: a page and one asset.
function builtWebApp(): string {
  const dir = dirname(tmpFile());
  writeFileSync(join(dir, "index.html"), "<!doctype html><title>built page</title>");
  mkdirSync(join(dir, "assets"));
  writeFileSync(join(dir, "assets", "app.js"), "console.log('built asset');");
  return dir;
}

const requestAs = (app: FastifyInstance, host: string, url: string) =>
  app.inject({ method: "GET", url, headers: { host } });

const HOST_REFUSAL = {
  error: "host_not_allowed",
  message: "This dashboard doesn't answer to that host name; add it to AMETHYST_ALLOWED_HOSTS to allow it.",
};

// ---- the Host allowlist (R43) -----------------------------------------------------------------------

describe("the Host allowlist", () => {
  // A DNS-rebinding page reaches 127.0.0.1 under its own name, so the name in Host is what gives it away.
  test("a foreign host name is refused everywhere, the built page and assets included, even before setup", async () => {
    const app = await testApp({ config: { webDist: builtWebApp() } });
    for (const url of ["/api/auth/state", "/api/health", "/api/nope", "/", "/assets/app.js", "/debug/party"]) {
      const res = await requestAs(app, "rebind.example:4517", url);
      expect(res.statusCode, url).toBe(403);
      expect(res.json(), url).toEqual(HOST_REFUSAL);
    }
    // First-run setup is the prize: it creates the owner account.
    const setup = await app.inject({
      method: "POST",
      url: "/api/auth/setup",
      payload: setupBody(),
      headers: { host: "rebind.example", "x-amethyst-request": "1" },
    });
    expect(setup.statusCode).toBe(403);
    expect(setup.json()).toEqual(HOST_REFUSAL);
    expect(setup.cookies).toEqual([]);
    expect(countAccounts(dbOf(app))).toBe(0);
  });

  test("the host is checked before anything else, even the request header", async () => {
    const app = await ownerApp();
    const res = await app.inject({
      method: "POST",
      url: "/api/auth/signin",
      payload: { username: "owner", password: OWNER_PASSWORD },
      headers: { host: "rebind.example" },
    });
    expect(res.statusCode).toBe(403);
    expect(res.json()).toEqual(HOST_REFUSAL);
  });

  test("the loopback names pass, with or without a port, in any case", async () => {
    const app = await testApp({ config: { webDist: builtWebApp() } });
    for (const host of ["localhost", "localhost:5173", "LocalHost:80", "127.0.0.1", "127.0.0.1:4517", "[::1]", "[::1]:4517"]) {
      expect((await requestAs(app, host, "/api/health")).statusCode, host).toBe(200);
      expect((await requestAs(app, host, "/")).statusCode, host).toBe(200);
    }
  });

  test("names that only look like a loopback one, and unreadable ones, are refused", async () => {
    const app = await testApp();
    for (const host of [
      "localhost.rebind.example",
      "127.0.0.1.nip.io",
      "127.0.0.2",
      "localhost.",
      "localhost:abc",
      "localhost:4517:4517",
      "[::1",
      "[::1]x",
      "user@localhost",
    ]) {
      const res = await requestAs(app, host, "/api/health");
      expect(res.statusCode, host).toBe(403);
      expect(res.json().error, host).toBe("host_not_allowed");
    }
  });

  // Only a real connection can leave Host out (an HTTP/1.0 request may); an injected one always has one.
  test("a request with no Host header at all is refused", async () => {
    const app = await testApp();
    await app.listen({ port: 0, host: "127.0.0.1" });
    const { port } = app.server.address() as AddressInfo;
    const answer = await new Promise<string>((resolve, reject) => {
      let text = "";
      const socket = connect(port, "127.0.0.1", () => socket.end("GET /api/health HTTP/1.0\r\n\r\n"));
      socket.on("data", (chunk) => {
        text += chunk.toString();
      });
      socket.on("end", () => resolve(text));
      socket.on("error", reject);
    });
    expect(answer).toMatch(/^HTTP\/1\.[01] 403 /);
    expect(answer).toContain('"error":"host_not_allowed"');
  });

  test("the configured listening address is allowed too, unless it means every address", async () => {
    const named = await testApp({ config: { host: "mac-mini.local" } });
    expect((await requestAs(named, "mac-mini.local:4517", "/api/health")).statusCode).toBe(200);
    expect((await requestAs(named, "localhost", "/api/health")).statusCode).toBe(200);

    for (const [host, header] of [["0.0.0.0", "0.0.0.0:4517"], ["::", "[::]:4517"]]) {
      const everywhere = await testApp({ config: { host } });
      expect((await requestAs(everywhere, header, "/api/health")).statusCode, host).toBe(403);
      expect((await requestAs(everywhere, "127.0.0.1:4517", "/api/health")).statusCode, host).toBe(200);
    }
  });

  test("AMETHYST_ALLOWED_HOSTS adds names, and only those", async () => {
    const { allowedHosts } = loadConfig({ AMETHYST_ALLOWED_HOSTS: "dash.lan, Studio.Local,[fe80::1]" });
    const app = await testApp({ config: { allowedHosts } });
    for (const host of ["dash.lan", "dash.lan:4517", "studio.local", "STUDIO.LOCAL:80", "[fe80::1]:4517"]) {
      expect((await requestAs(app, host, "/api/health")).statusCode, host).toBe(200);
    }
    expect((await requestAs(app, "other.lan", "/api/health")).statusCode).toBe(403);
  });
});

// ---- security headers (R43) -------------------------------------------------------------------------

const SECURITY_HEADERS = {
  "x-frame-options": "DENY",
  "content-security-policy": "frame-ancestors 'none'",
  "referrer-policy": "no-referrer",
  "x-content-type-options": "nosniff",
};

describe("security headers", () => {
  test("every response carries them: the API, the page, an asset and a deep link", async () => {
    const app = await testApp({ config: { webDist: builtWebApp() } });
    for (const url of ["/api/health", "/api/auth/state", "/", "/index.html", "/assets/app.js", "/debug/party"]) {
      const res = await app.inject({ method: "GET", url });
      expect(res.statusCode, url).toBe(200);
      expect(res.headers, url).toMatchObject(SECURITY_HEADERS);
    }
  });

  test("errors carry them too: a 404, a refused host, a missing request header and a malformed URL", async () => {
    const app = await testApp({ config: { webDist: builtWebApp() } });
    const responses = [
      await app.inject({ method: "GET", url: "/api/nope" }),
      await requestAs(app, "rebind.example", "/"),
      await app.inject({ method: "POST", url: "/api/auth/signout" }),
      await app.inject({ method: "GET", url: "/api/%E0%A4%A" }),
    ];
    expect(responses.map((res) => res.statusCode)).toEqual([404, 403, 403, 400]);
    for (const res of responses) expect(res.headers).toMatchObject(SECURITY_HEADERS);
  });

  test("a malformed URL from a foreign host is refused for the host", async () => {
    const app = await testApp();
    const res = await requestAs(app, "rebind.example", "/api/%E0%A4%A");
    expect(res.statusCode).toBe(403);
    expect(res.json()).toEqual(HOST_REFUSAL);
    expect(res.headers).toMatchObject(SECURITY_HEADERS);
  });
});
