import type { FastifyRequest, onRequestAsyncHookHandler } from "fastify";
import type { User } from "../../../shared/src/api.js";
import { SESSION_COOKIE } from "../../../shared/src/constants.js";
import type { Db } from "../db/database.js";
import { sendError } from "../errors.js";
import { type Account, findById } from "./accounts.js";
import { findSession } from "./sessions.js";

declare module "fastify" {
  interface FastifyRequest {
    /** Set by requireUser, so only routes behind it can rely on it. */
    user: User;
  }
}

// Only what the browser may see: never the hashes.
export function toUser(account: Account): User {
  return {
    id: account.id,
    username: account.username,
    displayName: account.displayName,
    role: account.role,
    hasAvatar: account.hasAvatar,
  };
}

export function sessionTokenOf(request: FastifyRequest): string | undefined {
  return request.cookies[SESSION_COOKIE];
}

export function userForToken(db: Db, token: string, now: Date): User | null {
  const session = findSession(db, token, now);
  const account = session ? findById(db, session.accountId) : null;
  return account ? toUser(account) : null;
}

// Runs on onRequest rather than preHandler so a signed-out caller is turned away before its body is even read.
export function requireUser(deps: { db: Db; now: () => Date }): onRequestAsyncHookHandler {
  return async (request, reply) => {
    const token = sessionTokenOf(request);
    const user = token === undefined ? null : userForToken(deps.db, token, deps.now());
    if (user === null) return sendError(reply, 401, "signed_out");
    request.user = user;
  };
}
