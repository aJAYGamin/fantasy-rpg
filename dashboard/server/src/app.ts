import { resolve } from "node:path";
import fastifyStatic from "@fastify/static";
import Fastify, { type FastifyInstance } from "fastify";
import { PRODUCT_NAME } from "../../shared/src/constants.js";
import type { Config } from "./config.js";

const isApiPath = (url: string) => /^\/api(\/|\?|$)/.test(url);

export interface AppOptions {
  config: Config;
  now?: () => Date;
}

export async function buildApp(opts: AppOptions): Promise<FastifyInstance> {
  const { config } = opts;
  const app = Fastify({ logger: { level: "warn" } });

  app.get("/api/health", async () => ({ ok: true, name: PRODUCT_NAME }));

  if (config.webDist !== null) {
    await app.register(fastifyStatic, { root: resolve(config.webDist) });
    // Deep links belong to the web app's router; an unknown /api route stays a JSON 404.
    app.setNotFoundHandler((request, reply) => {
      if (request.method === "GET" && !isApiPath(request.url)) {
        return reply.sendFile("index.html");
      }
      return reply.code(404).send({ error: "Not found" });
    });
  }

  return app;
}
