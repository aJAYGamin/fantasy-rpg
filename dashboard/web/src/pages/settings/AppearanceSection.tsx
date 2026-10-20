import type { Settings } from "../../../../shared/src/api";
import { Segmented } from "../../components";
import { SectionCard } from "./SectionCard";
import { SettingRow } from "./SettingRow";
import styles from "./AppearanceSection.module.css";
import { useSettingsSaver } from "./useSettingsSaver";

const MODES = [
  { value: "light", label: "Light" },
  { value: "dark", label: "Dark" },
  { value: "system", label: "Follow my Mac" },
] as const;

const SIDEBARS = [
  { value: "expanded", label: "Expanded" },
  { value: "icons", label: "Icons only" },
] as const;

// Amethyst is the only colour theme for now, so the only choice there is is the one in use.
const COLOUR_THEMES = [
  {
    value: "amethyst",
    label: (
      <>
        <span className={styles.swatch} aria-hidden="true" />
        Amethyst
      </>
    ),
  },
] as const;

/** Light, dark or the Mac's own setting; the colour theme; and whether the sidebar is folded to icons. */
export function AppearanceSection({ settings }: { settings: Settings }) {
  const { saved, problem, save } = useSettingsSaver();
  return (
    <SectionCard title="Appearance" saved={saved} problem={problem}>
      <SettingRow title="Mode" hint="Follow my Mac switches with your Mac's light and dark setting.">
        <Segmented
          label="Mode"
          options={MODES}
          value={settings.appearance}
          // Choosing what is already chosen changes nothing, so there is nothing to save (and no "Saved").
          onChange={(appearance) => appearance !== settings.appearance && save({ appearance })}
        />
      </SettingRow>
      <SettingRow title="Colour theme" hint="More themes coming later">
        <Segmented
          label="Colour theme"
          options={COLOUR_THEMES}
          value={settings.colourTheme}
          // Amethyst is the only theme, so choosing it again can only change nothing.
          onChange={() => {}}
        />
      </SettingRow>
      <SettingRow title="Sidebar" hint="Icons only folds the sidebar to a narrow rail.">
        <Segmented
          label="Sidebar"
          options={SIDEBARS}
          value={settings.sidebar}
          onChange={(sidebar) => sidebar !== settings.sidebar && save({ sidebar })}
        />
      </SettingRow>
    </SectionCard>
  );
}
