import type { Settings } from "../../../../shared/src/api";
import { Segmented } from "../../components";
import { ColorThemePicker } from "../../theme/ColorThemePicker";
import { SectionCard } from "./SectionCard";
import { SettingRow } from "./SettingRow";
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

/** Light, dark or the Mac's own setting; the color theme; and whether the sidebar is folded to icons. */
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
      <SettingRow title="Color theme" hint="The game's twenty cursor colors. Each one recolors the accent and the sidebar.">
        <ColorThemePicker value={settings.colorTheme} onChange={(colorTheme) => save({ colorTheme })} />
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
