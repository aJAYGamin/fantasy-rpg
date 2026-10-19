import type { FastifyInstance, FastifyReply } from "fastify";
import type { AuthState } from "../../../shared/src/api.js";
import { MAX_WRONG_PASSWORDS, SECURITY_QUESTIONS, SESSION_COOKIE } from "../../../shared/src/constants.js";
import type { Config } from "../config.js";
import type { Db } from "../db/database.js";
import { sendError } from "../errors.js";
import { addNotification } from "../notifications/notifications.js";
import { readKeepSignedInDays } from "../settings/settings.js";
import {
  type Account,
  AccountExistsError,
  countAccounts,
  createOwner,
  findById,
  findByUsername,
  setPasswordHash,
} from "./accounts.js";
import { type Answers, hashAnswers, normalizeAnswer, verifyAnswers } from "./answers.js";
import { sessionTokenOf, toUser, userForToken } from "./guard.js";
import { type LockState, clearLock, isLocked, readLock, registerFailure, triesLeft, writeLock } from "./locks.js";
import { checkPasswordPolicy, hashPassword, verifyPassword } from "./passwords.js";
import { createSession, revokeAllSessions, revokeSession } from "./sessions.js";

export interface AuthDeps {
  db: Db;
  config: Config;
  now: () => Date;
  /**
   * A real argon2id hash of a throwaway random string, made once at startup. Checking a typed password or answers
   * against it when the username is unknown keeps the response time the same as for a real account.
   */
  dummyHash: string;
}

const USERNAME_RULE = /^[A-Za-z0-9_.-]{3,32}$/;
const USERNAME_MAX = 32;
const DISPLAY_NAME_MAX = 40;
const DAY_SECONDS = 86_400;

type Body = Record<string, unknown>;
const isObject = (value: unknown): value is Body =>
  typeof value === "object" && value !== null && !Array.isArray(value);
const isAnswers = (value: unknown): value is Answers =>
  Array.isArray(value) && value.length === 3 && value.every((answer) => typeof answer === "string");

// The typed username as a lock key: trimmed and cut to the longest name an account can have, so a stranger typing a
// huge name cannot fill the lock table with huge rows. Cut by character, never through the middle of one.
function lockKey(typed: string): string {
  let key = "";
  let count = 0;
  for (const char of typed.trim()) {
    if (count === USERNAME_MAX) break;
    key += char;
    count++;
  }
  return key;
}

function describeDuration(ms: number): string {
  const seconds = Math.round(ms / 1000);
  if (seconds % 60 !== 0) return `${seconds} seconds`;
  const minutes = seconds / 60;
  return minutes === 1 ? "1 minute" : `${minutes} minutes`;
}

function lockedUntilOf(lock: LockState): string {
  if (lock.lockedUntil === null) throw new Error("An unlocked state has no end time");
  return lock.lockedUntil.toISOString();
}

export function authRoutes(app: FastifyInstance, deps: AuthDeps): void {
  const { db, config, now, dummyHash } = deps;
  const cookieOptions = { path: "/", httpOnly: true, sameSite: "lax", secure: config.secureCookies } as const;
  const pause = describeDuration(config.lockMs);

  const sendLocked = (reply: FastifyReply, lock: LockState) =>
    sendError(reply, 423, "locked", { lockedUntil: lockedUntilOf(lock) });

  // A lasting cookie and its server-side session end together; otherwise the cookie dies with the browser.
  function startSession(reply: FastifyReply, account: Account, persistent: boolean, at: Date): void {
    const keepDays = readKeepSignedInDays(db, account.id);
    const { token } = createSession(db, account.id, persistent, keepDays, at);
    const options = persistent ? { ...cookieOptions, maxAge: keepDays * DAY_SECONDS } : cookieOptions;
    reply.setCookie(SESSION_COOKIE, token, options);
  }

  // A name that breaks the username rule cannot belong to an account, so it is treated as unknown rather than
  // looked up (a long name must never match an account through its first 32 characters).
  const accountFor = (typed: string): Account | null => (USERNAME_RULE.test(typed) ? findByUsername(db, typed) : null);

  app.get("/api/auth/state", async (request): Promise<AuthState> => {
    const token = sessionTokenOf(request);
    return {
      setupRequired: countAccounts(db) === 0,
      user: token === undefined ? null : userForToken(db, token, now()),
    };
  });

  app.get("/api/auth/questions", async () => ({ questions: SECURITY_QUESTIONS }));

  app.post("/api/auth/setup", async (request, reply) => {
    const body = request.body;
    if (
      !isObject(body) ||
      typeof body.username !== "string" ||
      typeof body.displayName !== "string" ||
      typeof body.password !== "string" ||
      !isAnswers(body.answers)
    ) {
      return sendError(reply, 400, "bad_request");
    }
    // The cheap check first; createOwner repeats it inside a transaction, which is what makes a race safe.
    if (countAccounts(db) > 0) return sendError(reply, 409, "already_set_up");

    const username = body.username.trim();
    const displayName = body.displayName.trim();
    const displayNameLength = [...displayName].length;
    if (!USERNAME_RULE.test(username)) return sendError(reply, 400, "invalid_username");
    if (displayNameLength < 1 || displayNameLength > DISPLAY_NAME_MAX) {
      return sendError(reply, 400, "invalid_display_name");
    }
    if (checkPasswordPolicy(body.password) === "too_short") return sendError(reply, 400, "too_short");
    if (body.answers.some((answer) => normalizeAnswer(answer) === "")) return sendError(reply, 400, "missing_answer");

    const [passwordHash, answerHashes] = await Promise.all([hashPassword(body.password), hashAnswers(body.answers)]);
    const at = now();
    let account: Account;
    try {
      account = createOwner(db, { username, displayName, passwordHash, answerHashes }, at);
    } catch (error) {
      if (error instanceof AccountExistsError) return sendError(reply, 409, "already_set_up");
      throw error;
    }
    startSession(reply, account, false, at);
    return reply.code(201).send(toUser(account));
  });

  // Everything between reading the lock and writing it back runs without an await, so overlapping guesses cannot
  // all see "not locked yet": the password is checked first, then the lock is read again and updated in one go.
  app.post("/api/auth/signin", async (request, reply) => {
    const body = request.body;
    if (
      !isObject(body) ||
      typeof body.username !== "string" ||
      typeof body.password !== "string" ||
      (body.keepSignedIn !== undefined && typeof body.keepSignedIn !== "boolean")
    ) {
      return sendError(reply, 400, "bad_request");
    }
    const { password } = body;
    const keepSignedIn = body.keepSignedIn === true;
    const typed = body.username.trim();
    const key = lockKey(typed);

    // A locked name is turned away before any hashing is spent on it.
    const before = readLock(db, key, "signin");
    if (isLocked(before, now())) return sendLocked(reply, before);

    const account = accountFor(typed);
    // Unknown names get a real argon2 check too, so the time taken does not say which names exist. A stored hash
    // that cannot be read makes this reject: that is a server fault (a 500), never a wrong password to count.
    const correct = await verifyPassword(account?.passwordHash ?? dummyHash, password);

    // No await from here to the end: nothing else can run between reading the lock and writing it.
    const at = now();
    const lock = readLock(db, key, "signin");
    // A lock landed while we were checking: even the right password has to wait.
    if (isLocked(lock, at)) return sendLocked(reply, lock);

    // If the password changed while we were checking (a reset finished meanwhile), the old one must not get in.
    const unchanged = account !== null && findById(db, account.id)?.passwordHash === account.passwordHash;
    if (account !== null && correct && unchanged) {
      clearLock(db, key, "signin");
      startSession(reply, account, keepSignedIn, at);
      return reply.send(toUser(account));
    }

    const next = registerFailure("signin", lock, at, config.lockMs);
    writeLock(db, key, "signin", next);
    if (account !== null) {
      const what = "A wrong password was entered for this account.";
      addNotification(db, account.id, "security", "Failed sign-in", what, at);
    }
    if (isLocked(next, at)) {
      if (account !== null) {
        const why = `${MAX_WRONG_PASSWORDS} wrong passwords in a row. Sign-in is paused for ${pause}.`;
        addNotification(db, account.id, "security", "Sign-in locked", why, at);
      }
      return sendLocked(reply, next);
    }
    return sendError(reply, 401, "wrong_password", { triesLeft: triesLeft(next) });
  });

  app.post("/api/auth/signout", async (request, reply) => {
    const token = sessionTokenOf(request);
    if (token !== undefined) revokeSession(db, token);
    reply.clearCookie(SESSION_COOKIE, cookieOptions);
    return reply.code(204).send();
  });

  // Any wrong answer locks reset (the 401 already carries the end time); the same sync-after-await rule applies.
  app.post("/api/auth/forgot", async (request, reply) => {
    const body = request.body;
    if (
      !isObject(body) ||
      typeof body.username !== "string" ||
      typeof body.newPassword !== "string" ||
      !isAnswers(body.answers)
    ) {
      return sendError(reply, 400, "bad_request");
    }
    const { newPassword, answers } = body;
    const typed = body.username.trim();
    const key = lockKey(typed);

    const before = readLock(db, key, "reset");
    if (isLocked(before, now())) return sendLocked(reply, before);
    if (checkPasswordPolicy(newPassword) === "too_short") return sendError(reply, 400, "too_short");

    const account = accountFor(typed);
    // The new password is hashed alongside the answer checks, whatever they turn out to be, so the lock decision
    // below is the last thing that happens and no await sits between reading the lock and writing it.
    const [matches, newHash] = await Promise.all([
      verifyAnswers(account?.answerHashes ?? [dummyHash, dummyHash, dummyHash], answers),
      hashPassword(newPassword),
    ]);

    const at = now();
    const lock = readLock(db, key, "reset");
    if (isLocked(lock, at)) return sendLocked(reply, lock);

    if (account !== null && matches.every(Boolean)) {
      db.transaction(() => {
        setPasswordHash(db, account.id, newHash);
        clearLock(db, key, "reset");
        revokeAllSessions(db, account.id);
        const why = "Your password was changed with your security questions. Every sign-in was ended.";
        addNotification(db, account.id, "security", "Password changed", why, at);
      })();
      return reply.code(204).send();
    }

    const next = registerFailure("reset", lock, at, config.lockMs);
    writeLock(db, key, "reset", next);
    if (account !== null) {
      const why = `A security answer didn't match. Password reset is paused for ${pause}.`;
      addNotification(db, account.id, "security", "Password reset locked", why, at);
    }
    return sendError(reply, 401, "wrong_answer", { lockedUntil: lockedUntilOf(next) });
  });
}
