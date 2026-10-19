import { HttpResponse, http } from "msw";
import { expect, test, vi } from "vitest";
import { ApiFailure, api, onSignedOut } from "../src/api/client";
import { captureRequests, server } from "./msw";

const failureOf = (promise: Promise<unknown>) =>
  promise.then(
    () => {
      throw new Error("expected the request to fail");
    },
    (error: unknown) => error,
  );

test("the API client marks state-changing requests", async () => {
  const seen = captureRequests();
  await api("POST", "/api/auth/signout");
  expect(seen[0].headers.get("X-Amethyst-Request")).toBe("1");
});

test("reads go without the request header", async () => {
  const seen = captureRequests();
  await api("GET", "/api/game/status");
  expect(seen[0].headers.get("X-Amethyst-Request")).toBeNull();
});

test("a POST without a body still sends an empty JSON object, which the server can read", async () => {
  // Fastify answers 400 to Content-Type: application/json with an empty body.
  const seen = captureRequests();
  await api("POST", "/api/auth/signout");
  expect(seen[0].headers.get("Content-Type")).toBe("application/json");
  await vi.waitFor(() => expect(seen[0].body).toEqual({}));
});

test("a body is sent as JSON and the JSON answer comes back", async () => {
  const seen = captureRequests();
  const settings = await api<{ appearance: string }>("PATCH", "/api/settings", { appearance: "dark" });
  expect(settings.appearance).toBe("dark");
  await vi.waitFor(() => expect(seen[0].body).toEqual({ appearance: "dark" }));
});

test("an answer with no content resolves with nothing", async () => {
  await expect(api("POST", "/api/auth/signout")).resolves.toBeUndefined();
});

test("a refusal carries the status and the server's error body", async () => {
  const refusal = { error: "wrong_password", message: "That password isn't right.", triesLeft: 3 };
  server.use(http.post("/api/auth/signin", () => HttpResponse.json(refusal, { status: 401 })));
  const failure = await failureOf(api("POST", "/api/auth/signin", { username: "owner", password: "nope" }));
  expect(failure).toBeInstanceOf(ApiFailure);
  expect(failure).toMatchObject({ status: 401, body: refusal });
});

test("an error page that isn't JSON still becomes an error the app can show", async () => {
  server.use(http.get("/api/settings", () => new HttpResponse("Bad gateway", { status: 502 })));
  const failure = await failureOf(api("GET", "/api/settings"));
  expect(failure).toMatchObject({ status: 502, body: { error: "server_error" } });
  expect((failure as ApiFailure).body.message).not.toBe("");
});

test("an unreachable server becomes an error the app can show", async () => {
  server.use(http.get("/api/settings", () => HttpResponse.error()));
  const failure = await failureOf(api("GET", "/api/settings"));
  expect(failure).toMatchObject({ status: 0, body: { error: "network_error" } });
});

test("a signed_out answer from any route is reported; other 401s are not", async () => {
  const heard = vi.fn();
  const stop = onSignedOut(heard);
  try {
    server.use(
      http.get("/api/notifications", () =>
        HttpResponse.json({ error: "signed_out", message: "Please sign in." }, { status: 401 }),
      ),
      http.post("/api/auth/signin", () =>
        HttpResponse.json({ error: "wrong_password", message: "That password isn't right." }, { status: 401 }),
      ),
    );
    await failureOf(api("POST", "/api/auth/signin", { username: "owner", password: "nope" }));
    expect(heard).not.toHaveBeenCalled();
    await failureOf(api("GET", "/api/notifications"));
    expect(heard).toHaveBeenCalledTimes(1);
  } finally {
    stop();
  }
});
