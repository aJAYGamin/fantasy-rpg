import { Navigate, Outlet, type RouteObject, useLocation } from "react-router";
import { useAuthState } from "./api/hooks";
import { ForgotPage } from "./auth/ForgotPage";
import { SetupPage } from "./auth/SetupPage";
import { SignInPage } from "./auth/SignInPage";
import { AdminPage } from "./pages/AdminPage";
import { GearPage } from "./pages/GearPage";
import { InventoryPage } from "./pages/InventoryPage";
import { LocationPage } from "./pages/LocationPage";
import { OverviewPage } from "./pages/OverviewPage";
import { PartyPage } from "./pages/PartyPage";
import { SettingsPage } from "./pages/SettingsPage";
import { AppShell } from "./shell/AppShell";
import { RouteError } from "./shell/RouteError";
import { ServerUnreachable } from "./shell/ServerUnreachable";

const SIGNED_OUT_PAGES = new Set(["/setup", "/signin", "/forgot"]);

const leavesTheSite = (path: string) => path.startsWith("//") || path.startsWith("/\\");

/**
 * Where to go after signing in: the `next` the sign-in page was given, if it is a page of this app, else the
 * Overview. Anything that could leave the site (another origin, "//host", "/\host", a scheme) is ignored, and so
 * are the signed-out pages themselves. The path is checked again after parsing, because dot-segments collapse
 * ("/.//host" and "/a/..//host" both become "//host").
 */
function nextPath(search: string): string {
  const next = new URLSearchParams(search).get("next");
  if (next === null || !next.startsWith("/") || leavesTheSite(next)) return "/";
  const base = "http://app.invalid";
  let url: URL;
  try {
    url = new URL(next, base);
  } catch {
    return "/";
  }
  if (url.origin !== base || SIGNED_OUT_PAGES.has(url.pathname)) return "/";
  const path = url.pathname + url.search + url.hash;
  return leavesTheSite(path) ? "/" : path;
}

function signInPathFor(path: string): string {
  return path === "/" ? "/signin" : `/signin?next=${encodeURIComponent(path)}`;
}

/** Shown for the moment before the first auth answer: just the page background, so nothing flashes. */
function Pending() {
  return null;
}

// Both guards read the same auth state; while it loads they show nothing, and if the server can't be reached
// they say so. Refetches keep showing the last answer.
function useGuardState() {
  const auth = useAuthState();
  if (auth.data) return { kind: "ready", ...auth.data } as const;
  if (auth.isError) return { kind: "unreachable", retry: () => void auth.refetch() } as const;
  return { kind: "pending" } as const;
}

/** The signed-in pages: nobody gets here without an account and a session. */
function RequireSignedIn() {
  const state = useGuardState();
  const location = useLocation();
  if (state.kind === "pending") return <Pending />;
  if (state.kind === "unreachable") return <ServerUnreachable onRetry={state.retry} />;
  if (state.setupRequired) return <Navigate to="/setup" replace />;
  if (state.user === null) return <Navigate to={signInPathFor(location.pathname + location.search)} replace />;
  return <Outlet />;
}

/** First run, sign-in and forgot password: only while signed out, and only first run until an account exists. */
function RequireSignedOut() {
  const state = useGuardState();
  const location = useLocation();
  if (state.kind === "pending") return <Pending />;
  if (state.kind === "unreachable") return <ServerUnreachable onRetry={state.retry} />;
  const onSetup = location.pathname === "/setup";
  if (state.setupRequired) return onSetup ? <Outlet /> : <Navigate to="/setup" replace />;
  if (state.user !== null) return <Navigate to={nextPath(location.search)} replace />;
  if (onSetup) return <Navigate to="/signin" replace />;
  return <Outlet />;
}

// One root route so any page that throws shows the app's own error page, not the router's raw one.
export const routes: RouteObject[] = [
  {
    errorElement: <RouteError />,
    children: [
      {
        element: <RequireSignedOut />,
        children: [
          { path: "/setup", element: <SetupPage /> },
          { path: "/signin", element: <SignInPage /> },
          { path: "/forgot", element: <ForgotPage /> },
        ],
      },
      {
        element: <RequireSignedIn />,
        children: [
          {
            element: <AppShell />,
            children: [
              { index: true, element: <OverviewPage /> },
              { path: "/party", element: <PartyPage /> },
              { path: "/inventory", element: <InventoryPage /> },
              { path: "/gear", element: <GearPage /> },
              { path: "/location", element: <LocationPage /> },
              { path: "/admin", element: <AdminPage /> },
              { path: "/settings", element: <SettingsPage /> },
              { path: "/settings/:section", element: <SettingsPage /> },
              { path: "*", element: <Navigate to="/" replace /> },
            ],
          },
        ],
      },
    ],
  },
];
