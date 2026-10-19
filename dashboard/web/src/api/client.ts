import type { ApiError } from "../../../shared/src/api";
import { REQUEST_HEADER } from "../../../shared/src/constants";

export type Method = "GET" | "POST" | "PATCH" | "PUT" | "DELETE";

/** A request the server refused (or never answered). Branch on `body.error`, never on `status` alone. */
export class ApiFailure extends Error {
  readonly status: number;
  readonly body: ApiError;

  constructor(status: number, body: ApiError) {
    super(body.message);
    this.name = "ApiFailure";
    this.status = status;
    this.body = body;
  }
}

const UNREACHABLE: ApiError = {
  error: "network_error",
  message: "Can't reach the dashboard's server. Check that it's running.",
};
const UNREADABLE: ApiError = { error: "server_error", message: "Something went wrong on the server." };

// Any route can answer signed_out (the session expired, or was ended elsewhere); whoever listens sends the
// person back to sign in.
const signedOutListeners = new Set<() => void>();

/** Calls `listener` whenever any request is refused with signed_out. Returns a function that stops it. */
export function onSignedOut(listener: () => void): () => void {
  signedOutListeners.add(listener);
  return () => signedOutListeners.delete(listener);
}

function isApiError(value: unknown): value is ApiError {
  return (
    typeof value === "object" &&
    value !== null &&
    typeof (value as ApiError).error === "string" &&
    typeof (value as ApiError).message === "string"
  );
}

async function errorBodyOf(response: Response): Promise<ApiError> {
  try {
    const body: unknown = await response.json();
    return isApiError(body) ? body : UNREADABLE;
  } catch {
    return UNREADABLE;
  }
}

/**
 * Calls the dashboard's own server. State-changing requests carry the request header the server insists on,
 * and always send a JSON body (`{}` when there's nothing to send): the server refuses a JSON request with an
 * empty body. Resolves with the parsed JSON answer, or undefined for an empty one; rejects with ApiFailure.
 */
export async function api<T = void>(method: Method, path: string, body?: unknown): Promise<T> {
  const headers: Record<string, string> = { Accept: "application/json" };
  let payload: string | undefined;
  if (method !== "GET") {
    headers[REQUEST_HEADER] = "1";
    headers["Content-Type"] = "application/json";
    payload = JSON.stringify(body ?? {});
  }

  let response: Response;
  try {
    response = await fetch(path, { method, headers, body: payload, credentials: "same-origin" });
  } catch {
    throw new ApiFailure(0, UNREACHABLE);
  }

  if (!response.ok) {
    const error = await errorBodyOf(response);
    if (error.error === "signed_out") for (const listener of [...signedOutListeners]) listener();
    throw new ApiFailure(response.status, error);
  }

  const text = await response.text();
  if (text === "") return undefined as T;
  try {
    return JSON.parse(text) as T;
  } catch {
    throw new ApiFailure(response.status, UNREADABLE);
  }
}
