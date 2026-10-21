import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { FastifyInstance } from "fastify";
import { afterEach } from "vitest";
import { type AppOptions, buildApp } from "../src/app.js";
import { createOwner } from "../src/auth/accounts.js";
import { hashAnswers } from "../src/auth/answers.js";
import { hashPassword } from "../src/auth/passwords.js";
import { type Config, loadConfig } from "../src/config.js";
import { type Db, openDatabase } from "../src/db/database.js";

// Every tmpFile() gets its own folder under the OS temp folder; all are removed after each test.
const folders: string[] = [];
// Every app testApp() builds is closed (and its database with it) after each test.
const apps: FastifyInstance[] = [];
const databases = new WeakMap<FastifyInstance, Db>();

afterEach(async () => {
  for (const app of apps.splice(0)) await app.close();
  for (const folder of folders.splice(0)) rmSync(folder, { recursive: true, force: true });
});

export function tmpFile(name = "amethyst.db"): string {
  const folder = mkdtempSync(join(tmpdir(), "amethyst-test-"));
  folders.push(folder);
  return join(folder, name);
}

// A minimal accounts row. The hashes are placeholders: database tests never check a password.
export function insertAccount(db: Db, username: string): number {
  const result = db
    .prepare(
      "INSERT INTO accounts (username, display_name, password_hash, answer_hashes, role, created_at) VALUES (?, ?, ?, ?, 'owner', ?)",
    )
    .run(username, username, "placeholder-hash", JSON.stringify(["a", "b", "c"]), new Date().toISOString());
  return Number(result.lastInsertRowid);
}

// The one owner account with placeholder hashes, for tests that need an account but never sign in as it.
export function seedOwner(db: Db): number {
  return createOwner(
    db,
    { username: "owner", displayName: "Owner", passwordHash: "placeholder-hash", answerHashes: ["a", "b", "c"] },
    new Date(),
  ).id;
}

export const OWNER_PASSWORD = "correct horse battery";
// Invented answers: the real ones are only ever typed into the running app.
export const OWNER_ANSWERS: [string, string, string] = ["Lanternfall", "Port Quillon", "Dragonbridge"];

export function setupBody(overrides: Record<string, unknown> = {}) {
  return {
    username: "owner",
    displayName: "Owner",
    password: OWNER_PASSWORD,
    answers: [...OWNER_ANSWERS],
    ...overrides,
  };
}

export function forgotBody(overrides: Record<string, unknown> = {}) {
  return { username: "owner", answers: [...OWNER_ANSWERS], newPassword: "a brand new password", ...overrides };
}

// A clock the test moves by hand. `now` is what buildApp takes.
export function fakeClock(startIso: string) {
  let time = new Date(startIso).getTime();
  return {
    now: () => new Date(time),
    advance(ms: number) {
      time += ms;
    },
  };
}

export type TestAppOptions = {
  /** A database file to open (the same file twice is a restart); in memory when omitted. */
  dbPath?: string;
  clock?: ReturnType<typeof fakeClock>;
  config?: Partial<Config>;
  logger?: AppOptions["logger"];
};

// An app over a fresh database, with no accounts. Silent unless a test asks for a logger.
export async function testApp(opts: TestAppOptions = {}): Promise<FastifyInstance> {
  const db = openDatabase(opts.dbPath ?? ":memory:");
  const app = await buildApp({
    config: { ...loadConfig({}), ...opts.config },
    db,
    now: opts.clock?.now,
    logger: opts.logger ?? false,
  });
  app.addHook("onClose", async () => {
    db.close();
  });
  apps.push(app);
  databases.set(app, db);
  return app;
}

// The database behind a test app, for the tests that look at or tamper with stored rows.
export function dbOf(app: FastifyInstance): Db {
  const db = databases.get(app);
  if (!db) throw new Error("dbOf needs an app made by testApp");
  return db;
}

// Hashing is slow on purpose, so the owner's hashes are made once for the whole test run.
let ownerHashes: Promise<{ passwordHash: string; answerHashes: string[] }> | undefined;
function hashesForOwner() {
  ownerHashes ??= (async () => ({
    passwordHash: await hashPassword(OWNER_PASSWORD),
    answerHashes: await hashAnswers(OWNER_ANSWERS),
  }))();
  return ownerHashes;
}

// An app whose database already holds the owner "owner" (password OWNER_PASSWORD, answers OWNER_ANSWERS).
export async function ownerApp(opts: TestAppOptions = {}): Promise<FastifyInstance> {
  const app = await testApp(opts);
  const hashes = await hashesForOwner();
  createOwner(dbOf(app), { username: "owner", displayName: "Owner", ...hashes }, opts.clock?.now() ?? new Date());
  return app;
}

export function get(app: FastifyInstance, url: string, cookie?: string) {
  return app.inject({ method: "GET", url, headers: cookie ? { cookie } : {} });
}

// Every request that changes something carries the header the server demands.
function change(method: "POST" | "PATCH" | "PUT" | "DELETE") {
  return (app: FastifyInstance, url: string, body?: unknown, cookie?: string) =>
    app.inject({
      method,
      url,
      // Serialised here so a body that is just a string or a number is still sent as JSON.
      ...(body === undefined ? {} : { payload: JSON.stringify(body) }),
      headers: {
        "x-amethyst-request": "1",
        ...(body === undefined ? {} : { "content-type": "application/json" }),
        ...(cookie ? { cookie } : {}),
      },
    });
}

const sendPost = change("POST");
export const post = (app: FastifyInstance, url: string, body: unknown = {}, cookie?: string) =>
  sendPost(app, url, body, cookie);
export const patch = change("PATCH");
// A DELETE has no body; a JSON content type with nothing in it is a bad request.
export const del = (app: FastifyInstance, url: string, cookie?: string) => change("DELETE")(app, url, undefined, cookie);

export function signin(app: FastifyInstance, password: string, username = "owner", keepSignedIn = false) {
  return post(app, "/api/auth/signin", { username, password, keepSignedIn });
}

// The "name=value" a browser would send back, taken from a response that set the session cookie.
export function cookieOf(res: Awaited<ReturnType<typeof get>>): string {
  const cookie = res.cookies.find((c) => c.name === "amethyst_session");
  if (!cookie) throw new Error(`no session cookie in the ${res.statusCode} response`);
  return `${cookie.name}=${cookie.value}`;
}

export async function signinCookie(app: FastifyInstance, password = OWNER_PASSWORD): Promise<string> {
  return cookieOf(await signin(app, password));
}

// An owner app plus the cookie of a session already signed in.
export async function signedIn(opts: TestAppOptions = {}) {
  const app = await ownerApp(opts);
  return { app, cookie: await signinCookie(app) };
}
