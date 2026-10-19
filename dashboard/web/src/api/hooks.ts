import { QueryClient, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";
import type {
  AuthState,
  ForgotRequest,
  GameStatus,
  NotificationList,
  Settings,
  SettingsPatch,
  SetupRequest,
  SigninRequest,
  User,
} from "../../../shared/src/api";
import { ApiFailure, api, onSignedOut } from "./client";

export const queryKeys = {
  auth: ["auth", "state"],
  settings: ["settings"],
  notifications: ["notifications"],
  game: ["game", "status"],
} as const;

const SETTINGS_UPDATE = ["settings", "update"] as const;

export function createQueryClient(): QueryClient {
  return new QueryClient({
    defaultOptions: {
      // A finished mutation keeps what it was sent (the typed passwords and answers) until it is collected. Collect it
      // as soon as the screen that sent it lets go, instead of five minutes later.
      mutations: { gcTime: 0 },
      queries: {
        // A refusal won't change by asking again; a dropped connection or a server error might.
        retry: (failures, error) =>
          failures < 2 && !(error instanceof ApiFailure && error.status >= 400 && error.status < 500),
      },
    },
  });
}

/** Whether an account exists yet, and who is signed in. The router's guards decide every page from this. */
export function useAuthState() {
  return useQuery({
    queryKey: queryKeys.auth,
    queryFn: () => api<AuthState>("GET", "/api/auth/state"),
    staleTime: 60_000,
  });
}

/** Signs in; on success the cached auth state becomes signed in, and the guards move on to the page asked for. */
export function useSignIn() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (request: SigninRequest) => api<User>("POST", "/api/auth/signin", request),
    onSuccess: (user) => {
      queryClient.setQueryData<AuthState>(queryKeys.auth, { setupRequired: false, user });
    },
  });
}

/** Creates the owner account (first run only); the server signs it in, so the cached auth state follows. */
export function useSetup() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (request: SetupRequest) => api<User>("POST", "/api/auth/setup", request),
    onSuccess: (user) => {
      queryClient.setQueryData<AuthState>(queryKeys.auth, { setupRequired: false, user });
    },
  });
}

/** Sets a new password after the three security answers; nobody is signed in by it, so nothing is cached. */
export function useResetPassword() {
  return useMutation({
    mutationFn: (request: ForgotRequest) => api("POST", "/api/auth/forgot", request),
  });
}

export function useSignOut() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: () => api("POST", "/api/auth/signout"),
    onSuccess: () => {
      // Everything else cached belonged to the session that just ended.
      queryClient.removeQueries({ predicate: (query) => query.queryKey[0] !== queryKeys.auth[0] });
      queryClient.setQueryData<AuthState>(queryKeys.auth, { setupRequired: false, user: null });
    },
  });
}

/**
 * When any request is refused with signed_out, asks the server for the auth state again; the guards then send
 * the person to sign in, with a way back to the page they were on.
 */
export function useSignedOutWatcher(): void {
  const queryClient = useQueryClient();
  useEffect(() => onSignedOut(() => void queryClient.invalidateQueries({ queryKey: queryKeys.auth })), [queryClient]);
}

/** The signed-in account's settings. Pass `enabled: false` while nobody is signed in. */
export function useSettings({ enabled = true }: { enabled?: boolean } = {}) {
  return useQuery({
    queryKey: queryKeys.settings,
    queryFn: () => api<Settings>("GET", "/api/settings"),
    enabled,
    staleTime: 60_000,
  });
}

function withPatch(settings: Settings, patch: SettingsPatch): Settings {
  return { ...settings, ...patch, notify: { ...settings.notify, ...patch.notify } };
}

/** Saves a settings change. It shows at once (a theme switch shouldn't wait), and is undone if the server refuses. */
export function useUpdateSettings() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationKey: SETTINGS_UPDATE,
    mutationFn: (patch: SettingsPatch) => api<Settings>("PATCH", "/api/settings", patch),
    onMutate: async (patch) => {
      await queryClient.cancelQueries({ queryKey: queryKeys.settings });
      const before = queryClient.getQueryData<Settings>(queryKeys.settings);
      if (before) queryClient.setQueryData<Settings>(queryKeys.settings, withPatch(before, patch));
      return { before };
    },
    onError: (_error, _patch, saved) => {
      if (saved?.before) queryClient.setQueryData<Settings>(queryKeys.settings, saved.before);
    },
    onSuccess: (settings) => {
      // With a newer change still on its way, this answer is already out of date; that one's answer will land.
      if (queryClient.isMutating({ mutationKey: SETTINGS_UPDATE }) === 1) {
        queryClient.setQueryData<Settings>(queryKeys.settings, settings);
      }
    },
  });
}

export function useNotifications() {
  return useQuery({
    queryKey: queryKeys.notifications,
    queryFn: () => api<NotificationList>("GET", "/api/notifications"),
    refetchInterval: 30_000,
  });
}

/** In stage 1 always { connected: false, state: "waiting" }; checked every 3 s so pages wake when the game starts. */
export function useGameStatus() {
  return useQuery({
    queryKey: queryKeys.game,
    queryFn: () => api<GameStatus>("GET", "/api/game/status"),
    refetchInterval: 3_000,
  });
}
