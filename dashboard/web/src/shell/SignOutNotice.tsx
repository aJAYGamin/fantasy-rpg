import { CircleAlert, X } from "lucide-react";
import { useSignOutFailed } from "../api/hooks";
import { IconButton } from "../components";
import styles from "./SignOutNotice.module.css";

/**
 * Tells the person a sign-out didn't happen, when the account menu that asked for it is already gone (while it is
 * open, the menu says so itself). Stays until put away or until Sign out is tried again.
 */
export function SignOutNotice() {
  const { failed, dismiss } = useSignOutFailed();
  if (!failed) return null;
  return (
    <div role="alert" className={styles.notice}>
      <CircleAlert className={styles.icon} />
      <p className={styles.text}>Couldn't sign out. Try again.</p>
      <IconButton label="Dismiss" bordered={false} onClick={dismiss}>
        <X />
      </IconButton>
    </div>
  );
}
