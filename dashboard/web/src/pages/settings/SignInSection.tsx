import type { Settings } from "../../../../shared/src/api";
import { KEEP_SIGNED_IN_DAY_CHOICES } from "../../../../shared/src/constants";
import { Segmented } from "../../components";
import { SectionCard } from "./SectionCard";
import { SettingRow } from "./SettingRow";
import { useSettingsSaver } from "./useSettingsSaver";

const CHOICES = KEEP_SIGNED_IN_DAY_CHOICES.map((days) => ({ value: String(days), label: `${days} days` }));

/** How long "Keep me signed in" lasts. */
export function SignInSection({ settings }: { settings: Settings }) {
  const { saved, problem, save } = useSettingsSaver();
  return (
    <SectionCard title="Sign-in" saved={saved} problem={problem}>
      <SettingRow
        title="Keep me signed in lasts"
        hint="Used the next time you sign in with Keep me signed in ticked."
      >
        <Segmented
          label="Keep me signed in lasts"
          options={CHOICES}
          value={String(settings.keepSignedInDays)}
          onChange={(days) =>
            days !== String(settings.keepSignedInDays) &&
            save({ keepSignedInDays: Number(days) as Settings["keepSignedInDays"] })
          }
        />
      </SettingRow>
    </SectionCard>
  );
}
