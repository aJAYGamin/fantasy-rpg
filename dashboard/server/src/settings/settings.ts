import { DEFAULT_SETTINGS, type Settings, type SettingsPatch } from "../../../shared/src/api.js";
import { COLOR_THEMES } from "../../../shared/src/colorThemes.js";
import { GAME_PORT_MAX, GAME_PORT_MIN, KEEP_SIGNED_IN_DAY_CHOICES } from "../../../shared/src/constants.js";
import { isObject } from "../bodies.js";
import type { Db } from "../db/database.js";

const oneOf =
  <T extends string | number>(choices: readonly T[]) =>
  (value: unknown): value is T =>
    choices.includes(value as T);
const isBoolean = (value: unknown): value is boolean => typeof value === "boolean";
const isPort = (value: unknown): value is number =>
  typeof value === "number" && Number.isInteger(value) && value >= GAME_PORT_MIN && value <= GAME_PORT_MAX;

// What each setting may be. A key that is not here is not a setting.
const CHECKS: { [K in keyof Omit<Settings, "notify">]: (value: unknown) => value is Settings[K] } = {
  appearance: oneOf(["light", "dark", "system"]),
  colorTheme: oneOf(COLOR_THEMES),
  sidebar: oneOf(["expanded", "icons"]),
  keepSignedInDays: oneOf(KEEP_SIGNED_IN_DAY_CHOICES),
  gamePort: isPort,
  autoReconnect: isBoolean,
};

type Sorted = { valid: SettingsPatch; firstBad: string | null };

// Splits the input into the settings that are fine and the first one that is not (named as "notify.game" for a
// kind inside notify). Writing a patch refuses anything bad; reading what is stored keeps what is fine.
function sortOut(input: Record<string, unknown>): Sorted {
  const valid: Record<string, unknown> = {};
  let firstBad: string | null = null;
  const reject = (key: string) => {
    firstBad ??= key;
  };

  for (const [key, value] of Object.entries(input)) {
    if (key === "notify") {
      if (!isObject(value)) {
        reject(key);
        continue;
      }
      const notify: Record<string, boolean> = {};
      for (const [kind, on] of Object.entries(value)) {
        if (Object.hasOwn(DEFAULT_SETTINGS.notify, kind) && isBoolean(on)) notify[kind] = on;
        else reject(`notify.${kind}`);
      }
      if (Object.keys(notify).length > 0) valid.notify = notify;
    } else if (Object.hasOwn(CHECKS, key) && CHECKS[key as keyof typeof CHECKS](value)) {
      valid[key] = value;
    } else {
      reject(key);
    }
  }
  return { valid, firstBad };
}

// Every key must be a known setting with an allowed value, or the whole patch is refused (naming the first bad key).
export function checkSettingsPatch(input: Record<string, unknown>): { patch: SettingsPatch } | { badKey: string } {
  const { valid, firstBad } = sortOut(input);
  return firstBad === null ? { patch: valid } : { badKey: firstBad };
}

// `later` laid over `earlier`; `notify` merges kind by kind and only appears if either side has one.
function overlay<T extends SettingsPatch>(earlier: T, later: SettingsPatch): T {
  const notify = earlier.notify || later.notify ? { ...earlier.notify, ...later.notify } : undefined;
  const merged = { ...earlier, ...later };
  if (notify === undefined) delete merged.notify;
  else merged.notify = notify;
  return merged;
}

// The choices that were made and are still valid, nothing else. Anything unusable in the saved row (no row, bad JSON,
// one bad value) is left out, so it reads as its default.
function readChosen(db: Db, accountId: number): SettingsPatch {
  const row = db.prepare<[number], { json: string }>("SELECT json FROM settings WHERE account_id = ?").get(accountId);
  let saved: unknown = null;
  try {
    saved = row ? JSON.parse(row.json) : null;
  } catch {
    saved = null;
  }
  return isObject(saved) ? sortOut(saved).valid : {};
}

// The stored choices laid over the defaults. A damaged preference must never be what stops the owner signing in.
export function readSettings(db: Db, accountId: number): Settings {
  return overlay(DEFAULT_SETTINGS, readChosen(db, accountId));
}

// Saves the patch (already checked) over the choices already made and returns the result over the defaults. Only the
// choices are stored, never the defaults, so a default that changes later changes for anyone who never chose.
export function saveSettings(db: Db, accountId: number, patch: SettingsPatch): Settings {
  const chosen = overlay(readChosen(db, accountId), patch);
  db.prepare(
    "INSERT INTO settings (account_id, json) VALUES (?, ?) ON CONFLICT (account_id) DO UPDATE SET json = excluded.json",
  ).run(accountId, JSON.stringify(chosen));
  return overlay(DEFAULT_SETTINGS, chosen);
}

// How many days "Keep me signed in" lasts for this account.
export function readKeepSignedInDays(db: Db, accountId: number): number {
  return readSettings(db, accountId).keepSignedInDays;
}
