import type { FastifyInstance } from "fastify";
import type { NotificationKind, NotificationList } from "../../../shared/src/api.js";
import type { Db } from "../db/database.js";
import { sendError } from "../errors.js";
import { readSettings } from "../settings/settings.js";
import { listNotifications, markAllRead, markRead } from "./notifications.js";

// Registered inside the signed-in scope.
export function notificationRoutes(app: FastifyInstance, deps: { db: Db; now: () => Date }): void {
  const { db, now } = deps;

  app.get("/api/notifications", async (request): Promise<NotificationList> => {
    const { notify } = readSettings(db, request.user.id);
    const counted = (Object.keys(notify) as NotificationKind[]).filter((kind) => notify[kind]);
    return listNotifications(db, request.user.id, counted);
  });

  app.post("/api/notifications/read-all", async (request, reply) => {
    markAllRead(db, request.user.id, now());
    return reply.code(204).send();
  });

  // Someone else's notification is the same 404 as one that does not exist.
  app.post<{ Params: { id: string } }>("/api/notifications/:id/read", async (request, reply) => {
    const { id } = request.params;
    const found = /^[1-9]\d{0,14}$/.test(id) && markRead(db, request.user.id, Number(id), now());
    return found ? reply.code(204).send() : sendError(reply, 404, "not_found");
  });
}
