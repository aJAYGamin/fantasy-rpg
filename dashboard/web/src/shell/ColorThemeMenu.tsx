import { Palette } from "lucide-react";
import { IconButton, MenuItem, Popover, Tooltip } from "../components";
import styles from "./ColorThemeMenu.module.css";

/** The color theme picker. Amethyst is the only theme for now; the menu says more are coming. */
export function ColorThemeMenu() {
  return (
    <Popover
      role="menu"
      label="Color theme"
      className={styles.menu}
      trigger={(props) => (
        <Tooltip text="Color theme">
          <IconButton {...props} label="Color theme" bordered={false}>
            <Palette />
          </IconButton>
        </Tooltip>
      )}
    >
      {(close) => (
        <>
          <MenuItem checked icon={<span className={styles.swatch} />} onClick={close}>
            Amethyst
          </MenuItem>
          <MenuItem disabled inset className={styles.note}>
            More themes coming later
          </MenuItem>
        </>
      )}
    </Popover>
  );
}
