import type { FastifyInstance } from "fastify";
import type { Settings } from "../../../shared/src/api.js";
import { isObject } from "../bodies.js";
import type { Db } from "../db/database.js";
import { sendError } from "../errors.js";
import { checkSettingsPatch, readSettings, saveSettings } from "./settings.js";

// Registered inside the signed-in scope.
export function settingsRoutes(app: FastifyInstance, deps: { db: Db }): void {
  const { db } = deps;

  app.get("/api/settings", async (request): Promise<Settings> => readSettings(db, request.user.id));

  // All or nothing: one bad value saves none of the others. The refusal names the key in `setting`, beside the usual
  // sentence, so the page can say what was wrong with it.
  app.patch("/api/settings", async (request, reply) => {
    if (!isObject(request.body)) return sendError(reply, 400, "bad_request");
    const checked = checkSettingsPatch(request.body);
    if ("badKey" in checked) return sendError(reply, 400, "invalid_setting", { setting: checked.badKey });
    return saveSettings(db, request.user.id, checked.patch);
  });
}
