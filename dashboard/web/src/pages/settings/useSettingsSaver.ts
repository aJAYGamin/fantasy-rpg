import { useState } from "react";
import type { SettingsPatch } from "../../../../shared/src/api";
import { INVALID_GAME_PORT_MESSAGE } from "../../../../shared/src/constants";
import { useUpdateSettings } from "../../api/hooks";
import { refusalOf } from "../../auth/refusal";
import { useSavedNotice } from "./useSavedNotice";

const COULDNT_SAVE = "That setting couldn't be saved.";

// invalid_setting names the setting in its own `setting` field; this says what was wrong with it, in words (R32). A
// Map, so a name such as "constructor" finds nothing rather than something every object has.
const SETTING_SENTENCES = new Map<string, string>([["gamePort", INVALID_GAME_PORT_MESSAGE]]);

/**
 * The sentence for a settings change the server refused, or nothing when there is nothing to say: a session that has
 * ended is already on its way to the sign-in page.
 */
export function problemWithSetting(error: unknown): string | undefined {
  const refusal = refusalOf(error);
  if (refusal === null) return COULDNT_SAVE;
  if (refusal.body.error === "signed_out") return undefined;
  if (refusal.body.error === "invalid_setting") {
    return SETTING_SENTENCES.get(refusal.body.setting ?? "") ?? COULDNT_SAVE;
  }
  return refusal.body.message;
}

/**
 * Saving for one section of Settings. A change is saved the moment it is made: `save` for a choice or switch (the
 * section shows "Saved", or `problem` when the server says no, and the change is undone), `commit` for a typed value
 * (the field shows its own problems; the promise is how it hears).
 */
export function useSettingsSaver() {
  const { saved, flash } = useSavedNotice();
  const update = useUpdateSettings();
  const [problem, setProblem] = useState<string>();

  // Awaited one by one rather than with mutate's callbacks: those only run for the latest change, so a refusal that
  // came back after another change was made would say nothing.
  function save(patch: SettingsPatch): void {
    setProblem(undefined);
    void (async () => {
      try {
        await update.mutateAsync(patch);
        flash();
      } catch (error) {
        setProblem(problemWithSetting(error));
      }
    })();
  }

  async function commit(patch: SettingsPatch): Promise<void> {
    await update.mutateAsync(patch);
    flash();
  }

  return { saved, problem, save, commit };
}
