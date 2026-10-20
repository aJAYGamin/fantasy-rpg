import type { FastifyReply } from "fastify";
import type { ApiError } from "../../shared/src/api.js";
import {
  INVALID_DISPLAY_NAME_MESSAGE,
  INVALID_USERNAME_MESSAGE,
  TOO_SHORT_MESSAGE,
} from "../../shared/src/constants.js";

// One short sentence per error code, so every ApiError body carries both and the wording lives in one place.
const MESSAGES = {
  bad_request: "That request couldn't be read.",
  bad_request_header: "Missing request header.",
  host_not_allowed: "This dashboard doesn't answer to that host name; add it to AMETHYST_ALLOWED_HOSTS to allow it.",
  not_found: "Not found",
  too_large: "That request is too large.",
  unsupported_media_type: "That kind of request isn't supported.",
  server_error: "Something went wrong on the server.",
  signed_out: "Please sign in.",
  already_set_up: "An account already exists.",
  too_short: TOO_SHORT_MESSAGE,
  invalid_username: INVALID_USERNAME_MESSAGE,
  invalid_display_name: INVALID_DISPLAY_NAME_MESSAGE,
  invalid_setting: "That setting isn't valid.",
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
  extra: Partial<Pick<ApiError, "message" | "triesLeft" | "lockedUntil" | "setting">> = {},
): FastifyReply {
  const body: ApiError = { error: code, message: MESSAGES[code], ...extra };
  return reply.code(status).send(body);
}
