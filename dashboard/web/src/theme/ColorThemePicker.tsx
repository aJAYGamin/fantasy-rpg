import { Check } from "lucide-react";
import { type KeyboardEvent, useRef } from "react";
import { COLOR_THEMES, type ColorTheme, colorThemeName } from "../../../shared/src/colorThemes";
import { cx } from "../components/cx";
import styles from "./ColorThemePicker.module.css";
import { gemOf } from "./palettes";

const COLUMNS = 5;

export type ColorThemePickerProps = {
  value: ColorTheme;
  onChange: (theme: ColorTheme) => void;
  className?: string;
};

/**
 * The twenty color themes as gems, five to a row in the cursor wheel's order (the top bar's palette and Settings both
 * show it). A radio group: only the chosen gem is a Tab stop, the arrow keys move the choice across a row and up and
 * down a column (wrapping round), and Home / End go to the first and last. Choosing applies at once.
 */
export function ColorThemePicker({ value, onChange, className }: ColorThemePickerProps) {
  const buttons = useRef<Array<HTMLButtonElement | null>>([]);
  const chosen = Math.max(0, COLOR_THEMES.indexOf(value));
  const count = COLOR_THEMES.length;

  function choose(index: number) {
    if (COLOR_THEMES[index] !== value) onChange(COLOR_THEMES[index]);
    buttons.current[index]?.focus();
  }

  function onKeyDown(event: KeyboardEvent, index: number) {
    const moves: Record<string, number> = {
      ArrowRight: (index + 1) % count,
      ArrowLeft: (index - 1 + count) % count,
      ArrowDown: (index + COLUMNS) % count,
      ArrowUp: (index - COLUMNS + count) % count,
      Home: 0,
      End: count - 1,
    };
    if (!(event.key in moves)) return;
    event.preventDefault();
    choose(moves[event.key]);
  }

  return (
    <div role="radiogroup" aria-label="Color theme" className={cx(styles.grid, className)}>
      {COLOR_THEMES.map((theme, index) => (
        <button
          key={theme}
          ref={(button) => {
            buttons.current[index] = button;
          }}
          type="button"
          role="radio"
          aria-checked={index === chosen}
          tabIndex={index === chosen ? 0 : -1}
          className={styles.choice}
          onClick={() => {
            if (theme !== value) onChange(theme);
          }}
          onKeyDown={(event) => onKeyDown(event, index)}
        >
          <span className={styles.gem} style={{ background: gemOf(theme) }} aria-hidden="true">
            {index === chosen && <Check className={styles.check} strokeWidth={3} />}
          </span>
          <span className={styles.name}>{colorThemeName(theme)}</span>
        </button>
      ))}
    </div>
  );
}
