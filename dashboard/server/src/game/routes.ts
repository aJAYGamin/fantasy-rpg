import type { FastifyInstance } from "fastify";
import type { GameStatus } from "../../../shared/src/api.js";

// Registered inside the signed-in scope. There is no link to the game in stage 1, so it is always waiting.
export function gameRoutes(app: FastifyInstance): void {
  app.get("/api/game/status", async (): Promise<GameStatus> => ({ connected: false, state: "waiting" }));
}
