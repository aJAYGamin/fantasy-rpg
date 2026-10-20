import { Bell, ChevronLeft, ChevronRight, Maximize, Minimize, Moon, Settings, Sun } from "lucide-react";
import { useSyncExternalStore } from "react";
import { useNotifications, useUpdateSettings } from "../api/hooks";
import { IconButton, IconLink, Popover, Tooltip } from "../components";
import { useTheme } from "../theme/ThemeProvider";
import { AvatarMenu } from "./AvatarMenu";
import { ColourThemeMenu } from "./ColourThemeMenu";
import { NotificationsPanel } from "./NotificationsPanel";
import styles from "./TopBar.module.css";

export const SEARCH_PLACEHOLDER = "Search for anything — a hero, an item, a map…";

export type TopBarProps = {
  /** Whether the sidebar is folded to icons. */
  collapsed: boolean;
  onToggleSidebar: () => void;
  onOpenSearch: () => void;
};

/** The bar across the top of every signed-in page (overview-v3's .top): sidebar toggle, search, then the tools. */
export function TopBar({ collapsed, onToggleSidebar, onOpenSearch }: TopBarProps) {
  const toggleLabel = collapsed ? "Expand sidebar" : "Collapse sidebar";
  return (
    <header className={styles.bar}>
      <Tooltip text={toggleLabel}>
        <IconButton label={toggleLabel} onClick={onToggleSidebar}>
          {collapsed ? <ChevronRight /> : <ChevronLeft />}
        </IconButton>
      </Tooltip>

      {/* Looks like an empty search field; opens the search palette, as ⌘K / Ctrl+K do from anywhere. */}
      <button
        type="button"
        className={styles.search}
        aria-label="Search"
        aria-haspopup="dialog"
        aria-keyshortcuts="Meta+K Control+K"
        onClick={(event) => {
          // Safari and Firefox don't focus a clicked button, and the palette gives the focus back to whatever had it.
          event.currentTarget.focus();
          onOpenSearch();
        }}
      >
        <span className={styles.searchText}>{SEARCH_PLACEHOLDER}</span>
      </button>

      <div className={styles.tools}>
        <Tooltip text="Settings">
          <IconLink to="/settings" label="Settings" bordered={false}>
            <Settings />
          </IconLink>
        </Tooltip>
        <ThemeButton />
        <ColourThemeMenu />
        <FullScreenButton />
        <NotificationsBell />
        <div className={styles.avatarSlot}>
          <AvatarMenu />
        </div>
      </div>
    </header>
  );
}

/** Moon in light mode, sun in dark: switches to the other one and saves it as the account's appearance. */
function ThemeButton() {
  const { resolved } = useTheme();
  const update = useUpdateSettings();
  const next = resolved === "dark" ? "light" : "dark";
  const label = `Switch to ${next} mode`;
  return (
    <Tooltip text={label}>
      <IconButton label={label} bordered={false} onClick={() => update.mutate({ appearance: next })}>
        {resolved === "dark" ? <Sun className={styles.sun} /> : <Moon />}
      </IconButton>
    </Tooltip>
  );
}

function subscribeToFullscreen(onChange: () => void): () => void {
  document.addEventListener("fullscreenchange", onChange);
  return () => document.removeEventListener("fullscreenchange", onChange);
}

const isFullscreen = () => (document.fullscreenElement ?? null) !== null;

/** Full screen and back (the browser's Fullscreen API). Hidden where the browser has no such thing. */
function FullScreenButton() {
  const full = useSyncExternalStore(subscribeToFullscreen, isFullscreen);
  const root = document.documentElement;
  if (typeof root.requestFullscreen !== "function") return null;
  const label = full ? "Exit full screen" : "Full screen";
  // A refusal (the browser can decline) just leaves the page as it was.
  const toggle = () => void (full ? document.exitFullscreen() : root.requestFullscreen()).catch(() => {});
  return (
    <Tooltip text={label}>
      <IconButton label={label} bordered={false} onClick={toggle}>
        {full ? <Minimize /> : <Maximize />}
      </IconButton>
    </Tooltip>
  );
}

/** The bell: its badge and its name carry the unread count; it opens the notifications panel. */
function NotificationsBell() {
  const unread = useNotifications().data?.unread ?? 0;
  const label = unread > 0 ? `Notifications, ${unread} unread` : "Notifications";
  return (
    <Popover
      label="Notifications"
      bare
      className={styles.notifications}
      trigger={(props) => (
        <Tooltip text="Notifications">
          <IconButton {...props} label={label} bordered={false} className={styles.bell}>
            <Bell />
            {unread > 0 && (
              <span className={styles.badge} aria-hidden="true">
                {unread > 99 ? "99+" : unread}
              </span>
            )}
          </IconButton>
        </Tooltip>
      )}
    >
      <NotificationsPanel />
    </Popover>
  );
}
