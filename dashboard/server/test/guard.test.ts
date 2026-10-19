import { expect, test } from "vitest";
import { ownerApp, signedIn, testApp } from "./helpers.js";

// ---- malformed requests -----------------------------------------------------------------------------

test("a malformed URL is the normal 400 error and does not echo the path", async () => {
  const app = await testApp();
  for (const url of ["/api/%E0%A4%A", "/%E0%A4%A", "/api/auth/%FF"]) {
    const res = await app.inject({ method: "GET", url });
    expect(res.statusCode, url).toBe(400);
    expect(res.headers["content-type"], url).toContain("application/json");
    expect(res.json(), url).toEqual({ error: "bad_request", message: "That request couldn't be read." });
    expect(res.body, url).not.toMatch(/%|\/api|FST_/);
  }
});

// ---- the request header -----------------------------------------------------------------------------

// Methods Fastify can route, so each one reaches the guard rather than being turned away by the parser.
const CHANGING_METHODS = ["POST", "PUT", "PATCH", "DELETE", "PROPFIND", "MKCOL", "SEARCH", "TRACE"] as const;

test("every method except GET, HEAD and OPTIONS needs the request header", async () => {
  const app = await ownerApp();
  for (const method of CHANGING_METHODS) {
    const without = await app.inject({ method, url: "/api/anything" });
    expect(without.statusCode, method).toBe(403);
    expect(without.json(), method).toEqual({ error: "bad_request_header", message: "Missing request header." });
    const wrong = await app.inject({ method, url: "/api/anything", headers: { "x-amethyst-request": "yes" } });
    expect(wrong.statusCode, method).toBe(403);
    const withHeader = await app.inject({ method, url: "/api/anything", headers: { "x-amethyst-request": "1" } });
    expect(withHeader.statusCode, method).toBe(404);
  }
  for (const method of ["GET", "HEAD", "OPTIONS"] as const) {
    const res = await app.inject({ method, url: "/api/anything" });
    expect(res.statusCode, method).toBe(404);
  }
});

test("a signed-in change without the request header is refused, even with a valid session", async () => {
  const { app, cookie } = await signedIn();
  for (const method of ["POST", "PUT", "PATCH", "DELETE"] as const) {
    const res = await app.inject({ method, url: "/api/game/status", headers: { cookie } });
    expect(res.statusCode, method).toBe(403);
    expect(res.json().error, method).toBe("bad_request_header");
  }
});

// ---- fail closed ------------------------------------------------------------------------------------

// Every route the app has registered, read from Fastify's own route table: "/api/x/:id (GET, HEAD)" lines.
function registeredRoutes(app: Awaited<ReturnType<typeof testApp>>): { path: string; methods: string[] }[] {
  const lines = app.printRoutes({ commonPrefix: false }).split("\n").filter((line) => line.trim() !== "");
  return lines.map((line) => {
    const match = /(\/\S*) \(([A-Z, ]+)\)$/.exec(line);
    if (!match) throw new Error(`Could not read a route from: ${line}`);
    return { path: match[1] as string, methods: (match[2] as string).split(", ") };
  });
}

const OPEN_ROUTES = /^\/api\/(auth\/|health$)/;

test("every route outside sign-in and health answers 401 without a session", async () => {
  const app = await ownerApp();
  const routes = registeredRoutes(app);
  const guarded = routes.filter((route) => !OPEN_ROUTES.test(route.path));

  // If reading the route table ever drifts, this fails instead of quietly checking nothing.
  expect(routes.length).toBeGreaterThan(guarded.length);
  expect(guarded.map((route) => route.path)).toContain("/api/game/status");

  for (const { path, methods } of guarded) {
    for (const method of methods) {
      const res = await app.inject({
        method: method as "GET",
        url: path.replace(/:\w+/g, "1"),
        headers: { "x-amethyst-request": "1" },
      });
      expect(res.statusCode, `${method} ${path}`).toBe(401);
      // A HEAD answer has no body to read.
      if (method !== "HEAD") {
        expect(res.json(), `${method} ${path}`).toEqual({ error: "signed_out", message: "Please sign in." });
      }
    }
  }
});
