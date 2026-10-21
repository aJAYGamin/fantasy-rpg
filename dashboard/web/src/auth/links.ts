import { type To, useLocation } from "react-router";

// Sign-in is reached with ?next=<page asked for>; the pages that lead out of it and back carry that along, so
// resetting a password does not forget where the person was going.

/** The sign-in page, keeping the page that was asked for. */
export function useSignInTo(): To {
  return { pathname: "/signin", search: useLocation().search };
}

/** The reset page, keeping the page that was asked for. */
export function useForgotTo(): To {
  return { pathname: "/forgot", search: useLocation().search };
}

/** What the reset page tells the sign-in page when a password has just been changed. */
export type SignInArrival = { passwordChanged: true; username: string };

/** The arrival note in a location's state, if it really is one (state can hold anything, and survives a reload). */
export function readArrival(state: unknown): SignInArrival | null {
  if (typeof state !== "object" || state === null) return null;
  const { passwordChanged, username } = state as Partial<SignInArrival>;
  return passwordChanged === true && typeof username === "string" ? { passwordChanged, username } : null;
}
