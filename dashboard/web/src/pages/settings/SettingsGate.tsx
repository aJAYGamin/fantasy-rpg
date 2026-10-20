import type { ReactNode } from "react";
import type { Settings } from "../../../../shared/src/api";
import { useSettings } from "../../api/hooks";
import { refusalOf } from "../../auth/refusal";
import { Alert } from "../../auth/Alert";
import { Button } from "../../components";
import styles from "./SettingsGate.module.css";

/** Shows its section once the account's settings are in; until then (or if they can't be had) says so. */
export function SettingsGate({ children }: { children: (settings: Settings) => ReactNode }) {
  const settings = useSettings();
  if (settings.data) return children(settings.data);
  if (settings.isError) {
    return (
      <Alert tone="bad" className={styles.failed}>
        <span>{refusalOf(settings.error)?.body.message ?? "Couldn't load your settings."}</span>
        <Button size="sm" onClick={() => void settings.refetch()}>
          Try again
        </Button>
      </Alert>
    );
  }
  return <p className={styles.loading}>Loading…</p>;
}
