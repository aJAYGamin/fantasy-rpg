import { QueryClient, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef } from "react";
import { useNavigate } from "react-router";
import type {
  AuthState,
  ChangeAnswersRequest,
  ChangePasswordRequest,
  ForgotRequest,
  GameStatus,
  NotificationKind,
  NotificationList,
  Settings,
  SettingsPatch,
  SetupRequest,
  SigninRequest,
  UpdateAccountRequest,
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

// Small notes kept in the query cache, so they live as long as the app does and each test starts without them.
// The first one's "auth" prefix keeps it through sign-out's clean-up of everything else.
const SIGNED_OUT_BY_CHOICE = ["auth", "signed-out-by-choice"] as const;
// Whether a sign-out failed after the menu that started it was gone.
const SIGN_OUT_FAILED = ["notice", "sign-out-failed"] as const;
// How many times the profile picture has changed in this visit (see usePictureVersion).
const PICTURE_VERSION = ["account", "picture-version"] as const;

function useNote<T>(key: readonly string[], none: T): T {
  const { data } = useQuery({
    queryKey: key,
    queryFn: () => none,
    initialData: none,
    staleTime: Number.POSITIVE_INFINITY,
    gcTime: Number.POSITIVE_INFINITY,
  });
  return data ?? none;
}

// A new sign-in starts with a clean slate: nothing left over from the last session may decide where it goes (the
// "signed out on purpose" note drops its way back) or show a message about it (a sign-out that had failed).
function forgetSignOut(queryClient: QueryClient): void {
  queryClient.setQueryData(SIGNED_OUT_BY_CHOICE, false);
  queryClient.setQueryData(SIGN_OUT_FAILED, false);
}

/** Signs in; on success the cached auth state becomes signed in, and the guards move on to the page asked for. */
export function useSignIn() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (request: SigninRequest) => api<User>("POST", "/api/auth/signin", request),
    onSuccess: (user) => {
      forgetSignOut(queryClient);
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
      forgetSignOut(queryClient);
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

/**
 * Whether the person has just signed out on purpose, as opposed to a session that ended on its own. The guards send
 * the second kind to sign-in with a way back (`next`); the first goes to plain /signin.
 */
export function useSignedOutByChoice(): boolean {
  return useNote<boolean>(SIGNED_OUT_BY_CHOICE, false);
}

/**
 * While someone is signed in, "signed out on purpose" is old news. Forget it, so that a session which later ends on
 * its own (or a sign-in made in another tab) doesn't find the note still there and lose the way back (`next`).
 */
export function useForgetSignOutWhileSignedIn(signedIn: boolean): void {
  const queryClient = useQueryClient();
  useEffect(() => {
    if (signedIn) queryClient.setQueryData(SIGNED_OUT_BY_CHOICE, false);
  }, [signedIn, queryClient]);
}

/**
 * What the app does once the server has ended this session at the person's request: forgets everything cached for
 * it and becomes signed out (the guards take it from there).
 */
export function finishSignOut(queryClient: QueryClient): void {
  queryClient.removeQueries({ predicate: (query) => query.queryKey[0] !== queryKeys.auth[0] });
  // Before the auth state changes, so the guard that notices it already knows why.
  queryClient.setQueryData(SIGNED_OUT_BY_CHOICE, true);
  queryClient.setQueryData<AuthState>(queryKeys.auth, { setupRequired: false, user: null });
}

/**
 * Signs out, then goes to the sign-in page. The navigation and the failure handling are the mutation's own, so they
 * still happen if the menu that sent it was dismissed while the request was on its way. A failure shows where the
 * sender is still on screen (its `isError`); once it is gone the shell's notice (useSignOutFailed) does.
 */
export function useSignOut() {
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const senderIsHere = useRef(true);
  useEffect(() => {
    senderIsHere.current = true;
    return () => {
      senderIsHere.current = false;
    };
  }, []);
  return useMutation({
    mutationFn: () => api("POST", "/api/auth/signout"),
    onMutate: () => {
      queryClient.setQueryData(SIGN_OUT_FAILED, false);
    },
    onSuccess: () => {
      finishSignOut(queryClient);
      navigate("/signin", { replace: true });
    },
    onError: () => {
      if (!senderIsHere.current) queryClient.setQueryData(SIGN_OUT_FAILED, true);
    },
  });
}

/** Whether to tell the person a sign-out failed after its menu was gone, and how to put that notice away. */
export function useSignOutFailed() {
  const queryClient = useQueryClient();
  const failed = useNote<boolean>(SIGN_OUT_FAILED, false);
  return { failed, dismiss: () => queryClient.setQueryData(SIGN_OUT_FAILED, false) };
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
      // That snapshot also undoes any change made while this one was on its way; the server's copy puts those back.
      void queryClient.invalidateQueries({ queryKey: queryKeys.settings });
    },
    onSuccess: (settings) => {
      // With a newer change still on its way, this answer is already out of date; that one's answer will land.
      if (queryClient.isMutating({ mutationKey: SETTINGS_UPDATE }) === 1) {
        queryClient.setQueryData<Settings>(queryKeys.settings, settings);
      }
    },
  });
}

/** Replaces the signed-in account in the cached auth state, so the top bar and the menus follow at once. */
function changeUser(queryClient: QueryClient, change: (user: User) => User): void {
  queryClient.setQueryData<AuthState>(queryKeys.auth, (state) =>
    state?.user ? { ...state, user: change(state.user) } : state,
  );
}

/** Renames the signed-in account. The server's answer is the account as saved. */
export function useUpdateDisplayName() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (request: UpdateAccountRequest) => api<User>("PATCH", "/api/account", request),
    onSuccess: (saved) => changeUser(queryClient, () => saved),
  });
}

/** Changes the password. Every other sign-in ends; this one stays. Nothing is cached (R23). */
export function useChangePassword() {
  return useMutation({
    mutationFn: (request: ChangePasswordRequest) => api("POST", "/api/account/password", request),
  });
}

/** Changes the three security answers. Nothing is cached (R23). */
export function useChangeAnswers() {
  return useMutation({
    mutationFn: (request: ChangeAnswersRequest) => api("POST", "/api/account/answers", request),
  });
}

// After the picture changes, the cached account says whether there is one, and the picture's version moves on:
// every <img> of it asks for it again (its address changes) and starts afresh (it is keyed by the version), even one
// that had failed to load.
function pictureChanged(queryClient: QueryClient, hasAvatar: boolean): void {
  changeUser(queryClient, (user) => ({ ...user, hasAvatar }));
  queryClient.setQueryData<number>(PICTURE_VERSION, (version) => (version ?? 0) + 1);
}

/** Sets the profile picture from a file the person chose (the server checks the type and size again). */
export function useUploadAvatar() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (file: File) => {
      const form = new FormData();
      form.append("file", file);
      return api("PUT", "/api/account/avatar", form);
    },
    onSuccess: () => pictureChanged(queryClient, true),
  });
}

/** Removes the profile picture; the initials show instead. */
export function useRemoveAvatar() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: () => api("DELETE", "/api/account/avatar"),
    onSuccess: () => pictureChanged(queryClient, false),
  });
}

/** How many times the picture has changed in this visit: 0 until it does. */
export function usePictureVersion(): number {
  return useNote<number>(PICTURE_VERSION, 0);
}

export function useNotifications() {
  return useQuery({
    queryKey: queryKeys.notifications,
    queryFn: () => api<NotificationList>("GET", "/api/notifications"),
    refetchInterval: 30_000,
  });
}

const MARK_READ = ["notifications", "mark-read"] as const;

type Counts = (kind: NotificationKind) => boolean;

// Marking read shows at once and is undone if the server refuses; either way the list is fetched again once the last
// change has been answered, so what stays is what the server holds.
function useMarkRead<Variables>(
  request: (variables: Variables) => Promise<void>,
  apply: (list: NotificationList, variables: Variables, counts: Counts) => NotificationList,
) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationKey: MARK_READ,
    mutationFn: request,
    onMutate: async (variables) => {
      await queryClient.cancelQueries({ queryKey: queryKeys.notifications });
      const before = queryClient.getQueryData<NotificationList>(queryKeys.notifications);
      // `unread` leaves out the kinds switched off in the settings, so opening one of those must not lower it.
      const notify = queryClient.getQueryData<Settings>(queryKeys.settings)?.notify;
      const counts: Counts = (kind) => notify?.[kind] ?? true;
      if (before) queryClient.setQueryData<NotificationList>(queryKeys.notifications, apply(before, variables, counts));
      return { before };
    },
    onError: (_error, _variables, saved) => {
      if (saved?.before) queryClient.setQueryData<NotificationList>(queryKeys.notifications, saved.before);
    },
    onSettled: () => {
      if (queryClient.isMutating({ mutationKey: MARK_READ }) === 1) {
        void queryClient.invalidateQueries({ queryKey: queryKeys.notifications });
      }
    },
  });
}

/** Marks one notification read (by its id). */
export function useMarkNotificationRead() {
  return useMarkRead<number>(
    (id) => api("POST", `/api/notifications/${id}/read`),
    (list, id, counts) => {
      const item = list.items.find((candidate) => candidate.id === id);
      if (!item || item.read) return list;
      return {
        items: list.items.map((candidate) => (candidate === item ? { ...candidate, read: true } : candidate)),
        unread: counts(item.kind) ? Math.max(0, list.unread - 1) : list.unread,
      };
    },
  );
}

/** Marks every notification read, including any older than the ones listed. */
export function useMarkAllNotificationsRead() {
  return useMarkRead<void>(
    () => api("POST", "/api/notifications/read-all"),
    (list) => ({ items: list.items.map((item) => (item.read ? item : { ...item, read: true })), unread: 0 }),
  );
}

/** In stage 1 always { connected: false, state: "waiting" }; checked every 3 s so pages wake when the game starts. */
export function useGameStatus() {
  return useQuery({
    queryKey: queryKeys.game,
    queryFn: () => api<GameStatus>("GET", "/api/game/status"),
    refetchInterval: 3_000,
  });
}

/**
 * Whether the game is running and linked right now. Anything short of a clear, current "connected" counts as waiting:
 * not asked yet, or the latest ask failed (React Query keeps the last good answer when a refetch fails, so the
 * failure is checked on its own), so a page shows its waiting state until the game itself says otherwise.
 */
export function useGameConnected(): boolean {
  const { data, isError } = useGameStatus();
  return !isError && Boolean(data?.connected);
}
