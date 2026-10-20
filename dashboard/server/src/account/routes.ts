import fastifyMultipart from "@fastify/multipart";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import type { User } from "../../../shared/src/api.js";
import { AVATAR_MAX_BYTES, MAX_WRONG_PASSWORDS } from "../../../shared/src/constants.js";
import {
  type Account,
  cleanDisplayName,
  clearAvatar,
  findById,
  getAvatar,
  setAnswerHashes,
  setAvatar,
  setDisplayName,
  setPasswordHash,
} from "../auth/accounts.js";
import { hashAnswers, normalizeAnswer } from "../auth/answers.js";
import { sessionTokenOf, toUser } from "../auth/guard.js";
import { checkPasswordPolicy, hashPassword, verifyPassword } from "../auth/passwords.js";
import { clearWrongPasswords, findSession, registerWrongPassword, revokeAllSessions } from "../auth/sessions.js";
import { isAnswers, isObject } from "../bodies.js";
import type { Db } from "../db/database.js";
import { sendError } from "../errors.js";
import { addNotification } from "../notifications/notifications.js";
import { sniffImageType } from "./images.js";

// Registered inside the signed-in scope. Async because it adds the multipart parser to that scope (and only that
// scope: nowhere else accepts an upload).
export async function accountRoutes(app: FastifyInstance, deps: { db: Db; now: () => Date }): Promise<void> {
  const { db, now } = deps;

  // One file, no bigger than the limit; a bigger one is a 413 as it streams in, so it is never held whole.
  await app.register(fastifyMultipart, { limits: { fileSize: AVATAR_MAX_BYTES, files: 1, fields: 8, parts: 16 } });

  // The signed-in account's own row. A session whose account is gone cannot happen (sessions cascade), but if it did
  // the person is simply signed out.
  const accountOf = (request: { user: User }): Account | null => findById(db, request.user.id);

  // Checks the current password the person typed. Resolves null when it is right, otherwise the reply to send.
  // This is the only thing between a stolen session and the account's credentials, so wrong guesses are counted per
  // session, across both routes that ask: the fifth ends that session. They are never counted toward the sign-in lock
  // (the real owner must still be able to sign in). A right one starts the count again.
  async function checkCurrentPassword(
    request: FastifyRequest,
    reply: FastifyReply,
    account: Account,
    typed: string,
  ): Promise<FastifyReply | null> {
    const token = sessionTokenOf(request);
    if (token === undefined) return sendError(reply, 401, "signed_out");
    // A stored hash that cannot be read rejects here: a server fault (500), not a wrong password.
    const right = await verifyPassword(account.passwordHash, typed);

    // No await from here: the count is read and written in one go, with the notice that goes with it.
    const outcome = db.transaction((): "right" | "counted" | "ended" | "gone" => {
      if (right) return clearWrongPasswords(db, token) ? "right" : "gone";
      const counted = registerWrongPassword(db, token, MAX_WRONG_PASSWORDS);
      if (counted === "ended") {
        const why = `${MAX_WRONG_PASSWORDS} wrong current passwords in a row were typed, so that sign-in was ended.`;
        addNotification(db, account.id, "security", "Signed out after wrong passwords", why, now());
      }
      return counted;
    })();
    if (outcome === "right") return null;
    return outcome === "counted" ? sendError(reply, 401, "wrong_password") : sendError(reply, 401, "signed_out");
  }

  app.get("/api/account", async (request): Promise<User> => request.user);

  app.patch("/api/account", async (request, reply) => {
    const body = request.body;
    if (!isObject(body) || typeof body.displayName !== "string") return sendError(reply, 400, "bad_request");
    const displayName = cleanDisplayName(body.displayName);
    if (displayName === null) return sendError(reply, 400, "invalid_display_name");
    setDisplayName(db, request.user.id, displayName);
    return toUser(accountOf(request) as Account);
  });

  app.post("/api/account/password", async (request, reply) => {
    const body = request.body;
    if (!isObject(body) || typeof body.currentPassword !== "string" || typeof body.newPassword !== "string") {
      return sendError(reply, 400, "bad_request");
    }
    const { currentPassword, newPassword } = body;
    const account = accountOf(request);
    if (account === null) return sendError(reply, 401, "signed_out");

    const refused = await checkCurrentPassword(request, reply, account, currentPassword);
    if (refused !== null) return refused;
    if (checkPasswordPolicy(newPassword) === "too_short") return sendError(reply, 400, "too_short");
    const newHash = await hashPassword(newPassword);

    // No await from here on. If this session ended while we were hashing, or the password changed (another change,
    // or a reset), what the person typed is no longer the current password: nothing is written.
    const token = sessionTokenOf(request) as string;
    const at = now();
    const outcome = db.transaction((): "changed" | "signed_out" | "stale" => {
      if (findSession(db, token, at) === null) return "signed_out";
      if (findById(db, account.id)?.passwordHash !== account.passwordHash) return "stale";
      setPasswordHash(db, account.id, newHash);
      revokeAllSessions(db, account.id, token);
      const why = "Your password was changed from your account settings. Every other sign-in was ended.";
      addNotification(db, account.id, "security", "Password changed", why, at);
      return "changed";
    })();
    if (outcome === "signed_out") return sendError(reply, 401, "signed_out");
    if (outcome === "stale") return sendError(reply, 401, "wrong_password");
    return reply.code(204).send();
  });

  app.post("/api/account/answers", async (request, reply) => {
    const body = request.body;
    if (!isObject(body) || typeof body.currentPassword !== "string" || !isAnswers(body.answers)) {
      return sendError(reply, 400, "bad_request");
    }
    const { currentPassword, answers } = body;
    const account = accountOf(request);
    if (account === null) return sendError(reply, 401, "signed_out");

    const refused = await checkCurrentPassword(request, reply, account, currentPassword);
    if (refused !== null) return refused;
    if (answers.some((answer) => normalizeAnswer(answer) === "")) return sendError(reply, 400, "missing_answer");
    const answerHashes = await hashAnswers(answers);

    // Same rule as a password change: nothing is written if the session ended or the password changed meanwhile.
    const token = sessionTokenOf(request) as string;
    const at = now();
    const outcome = db.transaction((): "changed" | "signed_out" | "stale" => {
      if (findSession(db, token, at) === null) return "signed_out";
      if (findById(db, account.id)?.passwordHash !== account.passwordHash) return "stale";
      setAnswerHashes(db, account.id, answerHashes);
      const why = "Your security answers were changed from your account settings.";
      addNotification(db, account.id, "security", "Security answers changed", why, at);
      return "changed";
    })();
    if (outcome === "signed_out") return sendError(reply, 401, "signed_out");
    if (outcome === "stale") return sendError(reply, 401, "wrong_password");
    return reply.code(204).send();
  });

  // The file must be what it says it is: its first bytes and the type the sender declared both have to name
  // png, jpeg or webp, and the same one. Only then is it stored, and it is served back under that type.
  app.put("/api/account/avatar", async (request, reply) => {
    if (!request.isMultipart()) return sendError(reply, 415, "unsupported_media_type");
    const part = await request.file();
    if (part === undefined) return sendError(reply, 400, "bad_request");
    const bytes = await part.toBuffer(); // throws a 413 past the size limit
    if (part.fieldname !== "file") return sendError(reply, 400, "bad_request");
    const type = sniffImageType(bytes);
    if (type === null || part.mimetype.toLowerCase() !== type) return sendError(reply, 415, "unsupported_media_type");
    setAvatar(db, request.user.id, { bytes, type });
    return reply.code(204).send();
  });

  // Never cached, so a new picture shows at once. nosniff keeps a browser from second-guessing the type.
  app.get("/api/account/avatar", async (request, reply) => {
    const avatar = getAvatar(db, request.user.id);
    if (avatar === null) return sendError(reply, 404, "not_found");
    return reply
      .header("Content-Type", avatar.type)
      .header("Cache-Control", "no-store")
      .header("X-Content-Type-Options", "nosniff")
      .send(avatar.bytes);
  });

  app.delete("/api/account/avatar", async (request, reply) => {
    clearAvatar(db, request.user.id);
    return reply.code(204).send();
  });
}
