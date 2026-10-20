// What the end-to-end specs share: the invented owner, sign-in through the API, and a real picture to upload.

import { deflateSync, crc32 } from "node:zlib";
import { type APIRequestContext, type Page, expect } from "@playwright/test";
import { REQUEST_HEADER, SECURITY_QUESTIONS } from "../shared/src/constants.js";

/** An invented owner. Nothing here is anyone's real password or answer. */
export const OWNER = {
  displayName: "Test Owner",
  username: "owner",
  password: "lantern-moss-42-quill",
} as const;

/** Invented answers to the three security questions, in their order. */
export const ANSWERS: readonly [string, string, string] = ["Midwinter", "Tarnwick", "Lanterns and Lanes"];

export { SECURITY_QUESTIONS };

/** The header every state-changing request must carry; the web app adds it by itself. */
export const STATE_CHANGE = { [REQUEST_HEADER]: "1" };

/**
 * Creates the owner account, as the first-run screen would, on a server whose database is still empty. Playwright
 * starts a fresh worker after a failed test and runs beforeAll again there, so an owner made earlier is kept.
 */
export async function ensureOwner(request: APIRequestContext): Promise<void> {
  const state = await request.get("/api/auth/state");
  expect(state.ok()).toBe(true);
  if (!((await state.json()) as { setupRequired: boolean }).setupRequired) return;
  const response = await request.post("/api/auth/setup", {
    headers: STATE_CHANGE,
    data: { ...OWNER, answers: ANSWERS },
  });
  expect(response.status(), await response.text()).toBe(201);
}

/** Signs the page's browser in as the owner (the session cookie lands in its context), without the form. */
export async function signIn(page: Page, password: string = OWNER.password): Promise<void> {
  const response = await page.request.post("/api/auth/signin", {
    headers: STATE_CHANGE,
    data: { username: OWNER.username, password, keepSignedIn: false },
  });
  expect(response.ok(), await response.text()).toBe(true);
}

/** Resolves with the answer to the next settings change the page sends. */
export function nextSettingsSave(page: Page) {
  return page.waitForResponse(
    (response) => response.url().endsWith("/api/settings") && response.request().method() === "PATCH",
  );
}

function chunk(type: string, data: Buffer): Buffer {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, "latin1"), data]);
  const check = Buffer.alloc(4);
  check.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, check]);
}

/** A real PNG file: `width` × `height` pixels of one RGB colour. */
export function solidPng(width: number, height: number, [red, green, blue]: [number, number, number]): Buffer {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  // 8 bits per channel, colour type 2 (RGB), standard compression, filter and no interlacing.
  header.set([8, 2, 0, 0, 0], 8);
  // Each row starts with its filter type (0, none), then its pixels.
  const pixel = [red, green, blue];
  const row = Buffer.from([0, ...Array.from({ length: width }, () => pixel).flat()]);
  const pixels = Buffer.concat(Array.from({ length: height }, () => row));
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(pixels)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}
