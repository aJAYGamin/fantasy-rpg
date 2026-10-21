import { LOCK_MINUTES } from "../../shared/src/constants.js";
import { hostnameOf } from "./hosts.js";

export interface Config {
  port: number;
  host: string;
  dbPath: string;
  secureCookies: boolean;
  /** Folder of the built web app to serve, or null when Vite serves it (development). */
  webDist: string | null;
  /** How long a sign-in or reset lock lasts, in milliseconds. */
  lockMs: number;
  /** Host names to answer to besides the loopback ones and `host` (lower-case, no port). See hosts.ts. */
  allowedHosts: string[];
}

function parsePort(value: string | undefined): number {
  if (value === undefined) return 4517;
  const port = Number(value);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`AMETHYST_PORT must be a whole number from 1 to 65535, got "${value}"`);
  }
  return port;
}

// Only the end-to-end tests may shorten the lock. A real run (any other NODE_ENV)
// always uses the full length, and an unusable test value never shortens it either.
function lockMs(env: NodeJS.ProcessEnv): number {
  const full = LOCK_MINUTES * 60_000;
  if (env.NODE_ENV !== "test" || env.AMETHYST_LOCK_SECONDS === undefined) return full;
  const seconds = Number(env.AMETHYST_LOCK_SECONDS);
  return Number.isFinite(seconds) && seconds > 0 ? seconds * 1000 : full;
}

// A comma list of host names (a port or brackets may be written, and are dropped). An entry that isn't a host name
// stops the server rather than being skipped, so a typo can't leave someone wondering why a name is refused.
function allowedHosts(value: string | undefined): string[] {
  const entries = (value ?? "").split(",").map((entry) => entry.trim()).filter((entry) => entry !== "");
  return entries.map((entry) => {
    const name = hostnameOf(entry);
    if (name === null) throw new Error(`AMETHYST_ALLOWED_HOSTS must be a comma list of host names, got "${entry}"`);
    return name;
  });
}

export function loadConfig(env: NodeJS.ProcessEnv): Config {
  return {
    port: parsePort(env.AMETHYST_PORT),
    host: env.AMETHYST_HOST || "127.0.0.1",
    dbPath: env.AMETHYST_DB || "data/amethyst.db",
    secureCookies: env.AMETHYST_SECURE_COOKIES === "1",
    // The override lets the end-to-end tests (NODE_ENV=test, so the lock can be short) serve the built app too.
    webDist: env.AMETHYST_WEB_DIST || (env.NODE_ENV === "production" ? "dist/web" : null),
    lockMs: lockMs(env),
    allowedHosts: allowedHosts(env.AMETHYST_ALLOWED_HOSTS),
  };
}
