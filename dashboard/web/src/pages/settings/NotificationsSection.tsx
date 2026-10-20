import type { NotificationKind, Settings } from "../../../../shared/src/api";
import { SectionCard } from "./SectionCard";
import { ToggleRow } from "./SettingRow";
import styles from "./NotificationsSection.module.css";
import { useSettingsSaver } from "./useSettingsSaver";

const KINDS: ReadonlyArray<{ kind: NotificationKind; label: string; hint: string }> = [
  { kind: "security", label: "Account security", hint: "Failed sign-ins, pauses, and changes to your password or answers." },
  { kind: "game", label: "Game connection", hint: "The game connecting and disconnecting." },
  { kind: "changes", label: "Changes", hint: "Debug changes applied, waiting or failed." },
];

/** Which kinds of notification count toward the bell's unread number. */
export function NotificationsSection({ settings }: { settings: Settings }) {
  const { saved, problem, save } = useSettingsSaver();
  return (
    <SectionCard title="Notifications" saved={saved} problem={problem}>
      <p className={styles.lead}>Choose which kinds of notification count toward the bell's unread number.</p>
      {KINDS.map(({ kind, label, hint }) => (
        <ToggleRow
          key={kind}
          label={label}
          hint={hint}
          checked={settings.notify[kind]}
          onChange={(on) => save({ notify: { [kind]: on } })}
        />
      ))}
    </SectionCard>
  );
}
