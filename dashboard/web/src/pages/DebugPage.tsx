import { useGameConnected } from "../api/hooks";
import { usePageTitle } from "../pageTitle";
import { PageHeader } from "../shell/PageHeader";
import styles from "./DebugPage.module.css";
import { WaitingForGame, WaitingPill } from "./WaitingForGame";

/** The note under every Debug page's header (party-v4's .info): what applied changes do and where Reset is. */
function ReminderStrip() {
  return (
    <p className={styles.reminder}>
      Changes you apply here stay if you save the game. <b>Reset to before debugging</b> on the Overview rewinds
      everything to before your first Apply.
    </p>
  );
}

/**
 * A Debug page: its header (with the game's status at the right), the reminder, then the page's tools. Stage 1 has no
 * game to edit, so there are no tools yet, only the waiting message; stage 2 shows each page's own once the game is
 * connected, in place of it. The page is the one place that polls the game's status.
 */
export function DebugPage({ title }: { title: string }) {
  const connected = useGameConnected();
  usePageTitle(title);
  return (
    <>
      <PageHeader title={title} crumbs={["Debug", title]} right={connected ? undefined : <WaitingPill />} />
      <ReminderStrip />
      {!connected && <WaitingForGame />}
    </>
  );
}
