import { randomBytes } from "node:crypto";
import { resolve } from "node:path";
import fastifyCookie from "@fastify/cookie";
import fastifyStatic from "@fastify/static";
import Fastify, { type FastifyError, type FastifyInstance, type FastifyServerOptions } from "fastify";
import type { User } from "../../shared/src/api.js";
import { PRODUCT_NAME, REQUEST_HEADER } from "../../shared/src/constants.js";
import { requireUser } from "./auth/guard.js";
import { hashPassword } from "./auth/passwords.js";
import { authRoutes } from "./auth/routes.js";
import type { Config } from "./config.js";
import type { Db } from "./db/database.js";
import { type ErrorCode, sendError } from "./errors.js";
import { gameRoutes } from "./game/routes.js";

const isApiPath = (url: string) => /^\/api(\/|\?|$)/.test(url);
const MUTATING_METHODS = new Set(["POST", "PUT", "PATCH", "DELETE"]);

export interface AppOptions {
  config: Config;
  /** Opened and closed by the caller, not by the app. */
  db: Db;
  now?: () => Date;
  /** Fastify's logger setting; warnings and errors only by default. Request bodies and cookies are never logged. */
  logger?: FastifyServerOptions["logger"];
}

export async function buildApp(opts: AppOptions): Promise<FastifyInstance> {
  const { config, db } = opts;
  const now = opts.now ?? (() => new Date());
  const app = Fastify({ logger: opts.logger ?? { level: "warn" } });

  await app.register(fastifyCookie);
  // Declared up front so every request has the same shape; requireUser fills it in before a guarded handler runs.
  app.decorateRequest("user", null as unknown as User);

  // A cross-site page can make a browser send a form post but cannot add a custom header, so every
  // state-changing request must carry ours. Checked first, before the body is read or anything is looked up.
  app.addHook("onRequest", async (request, reply) => {
    if (MUTATING_METHODS.has(request.method) && request.headers[REQUEST_HEADER.toLowerCase()] !== "1") {
      return sendError(reply, 403, "bad_request_header");
    }
  });

  // Every error is the same { error, message } shape. A 5xx never shows its cause to the browser; the cause
  // goes to the log (Fastify's error objects carry no request body, password or token).
  app.setErrorHandler((error: FastifyError, request, reply) => {
    const status = error.statusCode ?? 500;
    if (status >= 400 && status < 500) {
      const code: ErrorCode = status === 413 ? "too_large" : status === 415 ? "unsupported_media_type" : "bad_request";
      return sendError(reply, status, code);
    }
    request.log.error(error);
    return sendError(reply, 500, "server_error");
  });

  // One not-found handler for every mode. Deep links belong to the web app's router, so a built web app answers
  // them with index.html; everything else, and every API path, is a JSON 404.
  if (config.webDist !== null) await app.register(fastifyStatic, { root: resolve(config.webDist) });
  app.setNotFoundHandler((request, reply) => {
    if (config.webDist !== null && request.method === "GET" && !isApiPath(request.url)) {
      return reply.sendFile("index.html");
    }
    return sendError(reply, 404, "not_found");
  });

  app.get("/api/health", async () => ({ ok: true, name: PRODUCT_NAME }));

  // A real hash of a throwaway string: unknown usernames are checked against it so they cost the same time.
  const dummyHash = await hashPassword(randomBytes(32).toString("hex"));
  authRoutes(app, { db, config, now, dummyHash });

  // Everything else needs a signed-in user. New routes go in here.
  await app.register(async (signedIn) => {
    signedIn.addHook("onRequest", requireUser({ db, now }));
    gameRoutes(signedIn);
  });

  return app;
}
