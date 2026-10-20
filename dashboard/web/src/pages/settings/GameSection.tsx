import type { Settings } from "../../../../shared/src/api";
import { DEFAULT_GAME_PORT, GAME_PORT_MAX, GAME_PORT_MIN, INVALID_GAME_PORT_MESSAGE } from "../../../../shared/src/constants";
import { CommitField } from "./CommitField";
import { SectionCard } from "./SectionCard";
import { ToggleRow } from "./SettingRow";
import styles from "./GameSection.module.css";
import { problemWithSetting, useSettingsSaver } from "./useSettingsSaver";

function checkPort(typed: string): string | undefined {
  // Digits only: Number() would also take "1e4", "0x400" and " ".
  const port = /^\d+$/.test(typed) ? Number(typed) : Number.NaN;
  return port >= GAME_PORT_MIN && port <= GAME_PORT_MAX ? undefined : INVALID_GAME_PORT_MESSAGE;
}

/** The port the game is reached on, and whether to reconnect by itself. The link itself arrives in stage 2. */
export function GameSection({ settings }: { settings: Settings }) {
  const { saved, problem, save, commit } = useSettingsSaver();
  return (
    <SectionCard title="Game connection" saved={saved} problem={problem}>
      <div className={styles.port}>
        <CommitField
          label="Port"
          hint={`Default: ${DEFAULT_GAME_PORT}`}
          saved={String(settings.gamePort)}
          check={checkPort}
          save={(typed) => commit({ gamePort: Number(typed) })}
          problemOf={problemWithSetting}
          inputMode="numeric"
          autoComplete="off"
          spellCheck={false}
          className={styles.field}
        />
      </div>
      <ToggleRow
        label="Reconnect automatically when the game restarts"
        checked={settings.autoReconnect}
        onChange={(autoReconnect) => save({ autoReconnect })}
      />
      <p className={styles.note}>The game connection arrives in the next stage.</p>
    </SectionCard>
  );
}
