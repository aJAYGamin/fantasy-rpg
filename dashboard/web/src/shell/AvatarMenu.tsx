import { LogOut, Settings, User as UserIcon } from "lucide-react";
import type { User } from "../../../shared/src/api";
import { useAuthState, useSignOut } from "../api/hooks";
import { MenuItem, MenuLink, MenuSeparator, Popover, Tooltip } from "../components";
import { Avatar } from "./Avatar";
import styles from "./AvatarMenu.module.css";

/**
 * The menu's rows. They mount each time the menu opens, so a sign-out error from last time doesn't linger. Sign out
 * keeps the menu open until the server agrees: on success useSignOut goes to the sign-in page, on failure the menu
 * says so and it can be tried again. (If the menu is dismissed meanwhile, useSignOut still finishes the job, and
 * the shell's SignOutNotice reports a failure.)
 */
function AccountMenuItems({ user, close }: { user: User; close: () => void }) {
  const signOut = useSignOut();
  return (
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
      <MenuItem icon={<LogOut />} disabled={signOut.isPending} onClick={() => signOut.mutate()}>
        Sign out
      </MenuItem>
      {signOut.isError && (
        <p role="alert" className={styles.error}>
          Couldn't sign out. Try again.
        </p>
      )}
    </>
  );
}

/** The avatar at the end of the top bar and its menu: who is signed in, Profile, Settings, Sign out. */
export function AvatarMenu() {
  const user = useAuthState().data?.user;
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
      {(close) => <AccountMenuItems user={user} close={close} />}
    </Popover>
  );
}
