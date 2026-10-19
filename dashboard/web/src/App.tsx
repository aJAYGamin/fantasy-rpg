import { type QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { type ReactNode, useState } from "react";
import { RouterProvider, createBrowserRouter } from "react-router";
import { createQueryClient, useAuthState, useSettings, useSignedOutWatcher } from "./api/hooks";
import { routes } from "./router";
import { ThemeProvider, storedAppearance } from "./theme/ThemeProvider";

export type AppRouter = ReturnType<typeof createBrowserRouter>;

/** Signed in, the account's appearance setting decides; before that (sign-in pages), the last one this browser saw. */
function AppTheme({ children }: { children: ReactNode }) {
  const auth = useAuthState();
  const signedIn = Boolean(auth.data?.user);
  const settings = useSettings({ enabled: signedIn });
  const appearance = (signedIn ? settings.data?.appearance : undefined) ?? storedAppearance();
  return <ThemeProvider appearance={appearance}>{children}</ThemeProvider>;
}

function SignedOutWatcher() {
  useSignedOutWatcher();
  return null;
}

/** Everything the app runs inside. Tests pass their own query client and an in-memory router. */
export function AppProviders({ queryClient, router }: { queryClient: QueryClient; router: AppRouter }) {
  return (
    <QueryClientProvider client={queryClient}>
      <SignedOutWatcher />
      <AppTheme>
        <RouterProvider router={router} />
      </AppTheme>
    </QueryClientProvider>
  );
}

export function App() {
  const [queryClient] = useState(createQueryClient);
  const [router] = useState(() => createBrowserRouter(routes));
  return <AppProviders queryClient={queryClient} router={router} />;
}
