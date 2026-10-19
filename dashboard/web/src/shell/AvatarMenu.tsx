import { LogOut, Settings, User as UserIcon } from "lucide-react";
import { useState } from "react";
import type { User } from "../../../shared/src/api";
import { useAuthState, useSignOut } from "../api/hooks";
import { MenuItem, MenuLink, MenuSeparator, Popover, Tooltip } from "../components";
import styles from "./AvatarMenu.module.css";

/** Up to two letters from the display name: the first word's and the last word's ("Test Owner" → "TO"). */
export function initialsOf(name: string): string {
  const words = name.trim().split(/\s+/).filter(Boolean);
  const picked = words.length > 1 ? [words[0], words[words.length - 1]] : words;
  // By code point, so a name starting with an emoji keeps it whole.
  return picked.map((word) => [...word][0]).join("").toLocaleUpperCase();
}

/** The account's picture, or its initials when there is none (or it fails to load). */
function Avatar({ user }: { user: User }) {
  const [broken, setBroken] = useState(false);
  if (user.hasAvatar && !broken) {
    return <img className={styles.picture} src="/api/account/avatar" alt="" onError={() => setBroken(true)} />;
  }
  return <span className={styles.initials}>{initialsOf(user.displayName)}</span>;
}

/** The avatar at the end of the top bar and its menu: who is signed in, Profile, Settings, Sign out. */
export function AvatarMenu() {
  const user = useAuthState().data?.user;
  const signOut = useSignOut();
  if (!user) return null;

  return (
    <Popover
      role="menu"
      // The menu is named for the account, so screen readers hear whose it is (the header is drawn only).
      label={`${user.displayName} (${user.username})`}
      className={styles.menu}
      trigger={(props) => (
        <Tooltip text="Account menu" align="end">
          <button {...props} type="button" aria-label="Account menu" className={styles.avatar}>
            <Avatar user={user} />
          </button>
        </Tooltip>
      )}
    >
      {(close) => (
        <>
          <div className={styles.who} aria-hidden="true">
            <span className={styles.name}>{user.displayName}</span>
            <span className={styles.username}>{user.username}</span>
          </div>
          <MenuLink to="/settings/account" icon={<UserIcon />} onClick={close}>
            Profile
          </MenuLink>
          <MenuLink to="/settings" icon={<Settings />} onClick={close}>
            Settings
          </MenuLink>
          <MenuSeparator />
          <MenuItem
            icon={<LogOut />}
            onClick={() => {
              close();
              // On success the guard sees nobody signed in and goes to the sign-in page.
              signOut.mutate();
            }}
          >
            Sign out
          </MenuItem>
        </>
      )}
    </Popover>
  );
}
