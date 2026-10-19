import { Palette } from "lucide-react";
import { IconButton, MenuItem, Popover, Tooltip } from "../components";
import styles from "./ColourThemeMenu.module.css";

/** The colour theme picker. Amethyst is the only theme for now; the menu says more are coming. */
export function ColourThemeMenu() {
  return (
    <Popover
      role="menu"
      label="Colour theme"
      className={styles.menu}
      trigger={(props) => (
        <Tooltip text="Colour theme">
          <IconButton {...props} label="Colour theme" bordered={false}>
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
