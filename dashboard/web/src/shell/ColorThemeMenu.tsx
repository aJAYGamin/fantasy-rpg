import { Palette } from "lucide-react";
import { DEFAULT_COLOR_THEME } from "../../../shared/src/colorThemes";
import { useSettings, useUpdateSettings } from "../api/hooks";
import { IconButton, Popover, Tooltip } from "../components";
import { ColorThemePicker } from "../theme/ColorThemePicker";
import styles from "./ColorThemeMenu.module.css";

/**
 * The top bar's palette: the twenty color themes in a small panel. A pick recolors the dashboard at once and is
 * saved as the account's setting, as the light/dark button beside it is; the panel stays open so another can be tried.
 */
export function ColorThemeMenu() {
  const settings = useSettings();
  const update = useUpdateSettings();
  const value = settings.data?.colorTheme ?? DEFAULT_COLOR_THEME;
  return (
    <Popover
      label="Color theme"
      className={styles.panel}
      trigger={(props) => (
        <Tooltip text="Color theme">
          <IconButton {...props} label="Color theme" bordered={false}>
            <Palette />
          </IconButton>
        </Tooltip>
      )}
    >
      <p className={styles.title} aria-hidden="true">
        Color theme
      </p>
      <ColorThemePicker value={value} onChange={(colorTheme) => update.mutate({ colorTheme })} />
    </Popover>
  );
}
