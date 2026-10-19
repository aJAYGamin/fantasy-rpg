import type { FastifyReply } from "fastify";
import type { ApiError } from "../../shared/src/api.js";
import { MIN_PASSWORD_LENGTH } from "../../shared/src/constants.js";

// One short sentence per error code, so every ApiError body carries both and the wording lives in one place.
const MESSAGES = {
  bad_request: "That request couldn't be read.",
  bad_request_header: "Missing request header.",
  not_found: "Not found",
  too_large: "That request is too large.",
  unsupported_media_type: "That kind of request isn't supported.",
  server_error: "Something went wrong on the server.",
  signed_out: "Please sign in.",
  already_set_up: "An account already exists.",
  too_short: `Passwords need at least ${MIN_PASSWORD_LENGTH} characters.`,
  invalid_username: "Usernames are 3 to 32 letters, digits, dots, dashes or underscores.",
  invalid_display_name: "Display names are 1 to 40 characters.",
  missing_answer: "Answer all three security questions.",
  wrong_password: "That password isn't right.",
  wrong_answer: "One or more answers didn't match.",
  locked: "Too many tries. Try again when the timer runs out.",
} as const;

export type ErrorCode = keyof typeof MESSAGES;

export function sendError(
  reply: FastifyReply,
  status: number,
  code: ErrorCode,
  extra: Pick<ApiError, "triesLeft" | "lockedUntil"> = {},
): FastifyReply {
  const body: ApiError = { error: code, message: MESSAGES[code], ...extra };
  return reply.code(status).send(body);
}
