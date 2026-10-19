import { useEffect, useRef } from "react";
import { Link } from "react-router";
import { LOCK_MINUTES, MAX_WRONG_PASSWORDS } from "../../../shared/src/constants";
import { Button, Countdown, Ring, useSecondsLeft } from "../components";
import { cx } from "../components/cx";
import { AuthLayout } from "./AuthLayout";
import form from "./AuthForm.module.css";
import styles from "./LockedPanel.module.css";
import { useSignInTo } from "./links";
import { spokenDuration } from "./spokenDuration";

export type LockedPanelProps = {
  /** What is paused: signing in (too many wrong passwords) or resetting the password (a wrong answer). */
  kind: "signin" | "reset";
  /** When the pause ends, on this computer's clock. */
  until: Date;
  /**
   * Whether the attempt that was just made is the one that caused the pause. Then the lead says what went wrong;
   * otherwise (a pause that was already there) it only says the pause is on, because the page can't know why.
   */
  justLocked: boolean;
  /** Pressed once the time is up; the page brings its form back. */
  onTryAgain: () => void;
  /** Set on the sign-in page itself: "Back to sign in" there just closes this panel. */
  onBack?: () => void;
};

const TITLES = { signin: "Sign-in is paused", reset: "Password reset is locked" } as const;

const CAUSES = {
  signin: `That was ${MAX_WRONG_PASSWORDS} wrong passwords in a row. You can try again when the timer runs out.`,
  reset: "One of the answers didn't match. You can try again when the timer runs out.",
} as const;

const EARLIER = "Too many tries recently. You can try again when the timer runs out.";

/** signin-v1's fourth screen: a ring counting down to the end of the pause, and a Try again that wakes when it does. */
export function LockedPanel({ kind, until, justLocked, onTryAgain, onBack }: LockedPanelProps) {
  const secondsLeft = useSecondsLeft(until);
  const timeIsUp = secondsLeft === 0;
  const heading = useRef<HTMLHeadingElement>(null);
  const signInTo = useSignInTo();

  // The form that was here is gone, so the cursor would be nowhere. Putting it on the heading makes a screen
  // reader start with what changed.
  useEffect(() => heading.current?.focus(), []);

  return (
    <AuthLayout tagline="Taking a short pause." tagsub="This stops anyone from guessing over and over.">
      <div className={styles.lock}>
        <h1 ref={heading} tabIndex={-1} className={cx(form.title, form.focusTarget)}>
          {TITLES[kind]}
        </h1>
        <p className={form.lead}>{justLocked ? CAUSES[kind] : EARLIER}</p>
        <Ring
          size="lg"
          className={styles.ring}
          // The ring shows the time left out of a whole pause.
          percent={(secondsLeft / (LOCK_MINUTES * 60)) * 100}
          aria-label="Time until you can try again"
          valueText={spokenDuration(secondsLeft)}
          label={<Countdown until={until} />}
        />
        {/* Swapped when the time is up, so a screen reader hears that the wait is over. */}
        <p role="status" className={styles.note}>
          {timeIsUp ? "You can try again now." : "The page unlocks on its own. No need to refresh."}
        </p>
        <Button variant="primary" disabled={!timeIsUp} onClick={onTryAgain} className={styles.tryAgain}>
          Try again
        </Button>
        <div className={cx(form.row, form.rowCentered)}>
          <Link to={signInTo} onClick={onBack}>
            <span aria-hidden="true">←</span> Back to sign in
          </Link>
        </div>
      </div>
    </AuthLayout>
  );
}
