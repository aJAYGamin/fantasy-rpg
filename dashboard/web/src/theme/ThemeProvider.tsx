import { type ReactNode, createContext, useContext, useLayoutEffect, useMemo, useSyncExternalStore } from "react";
import type { Settings } from "../../../shared/src/api";
import { type ColorTheme, DEFAULT_COLOR_THEME, isColorTheme } from "../../../shared/src/colorThemes";

export type Appearance = Settings["appearance"];
export type ResolvedTheme = "light" | "dark";

// index.html's inline script reads these two keys before React loads, so the first paint is already right.
export const THEME_KEY = "amethyst-theme";
export const APPEARANCE_KEY = "amethyst-appearance";
export const COLOR_KEY = "amethyst-color";

const DARK_QUERY = "(prefers-color-scheme: dark)";

const ThemeContext = createContext<{ resolved: ResolvedTheme } | null>(null);

function subscribeToMac(onChange: () => void): () => void {
  const query = window.matchMedia(DARK_QUERY);
  query.addEventListener("change", onChange);
  return () => query.removeEventListener("change", onChange);
}

const macIsDark = () => window.matchMedia(DARK_QUERY).matches;
const neverSubscribe = () => () => {};
const notDark = () => false;

/** Whether the Mac is in dark mode, followed live; only listens while `follow` is on. */
function useMacIsDark(follow: boolean): boolean {
  return useSyncExternalStore(follow ? subscribeToMac : neverSubscribe, follow ? macIsDark : notDark);
}

function remember(key: string, value: string): void {
  try {
    localStorage.setItem(key, value);
  } catch {
    // Storage can be off (private windows); the theme still applies, it just isn't remembered.
  }
}

/** The appearance saved on this browser by the last visit, for pages shown before settings load (sign-in). */
export function storedAppearance(): Appearance {
  try {
    const appearance = localStorage.getItem(APPEARANCE_KEY);
    if (appearance === "light" || appearance === "dark" || appearance === "system") return appearance;
    const theme = localStorage.getItem(THEME_KEY);
    if (theme === "light" || theme === "dark") return theme;
  } catch {
    // Unreadable storage: fall through to the default.
  }
  return "light";
}

/** The color theme this browser last showed, for pages shown before settings load (sign-in). */
export function storedColorTheme(): ColorTheme {
  try {
    const color = localStorage.getItem(COLOR_KEY);
    if (isColorTheme(color)) return color;
  } catch {
    // Unreadable storage: fall through to the default.
  }
  return DEFAULT_COLOR_THEME;
}

/**
 * Applies the theme to the whole page (data-theme and data-color on <html>) and remembers both for the next load.
 * "system" follows the Mac's light/dark setting live.
 */
export function ThemeProvider({
  appearance,
  colorTheme = DEFAULT_COLOR_THEME,
  children,
}: {
  appearance: Appearance;
  colorTheme?: ColorTheme;
  children?: ReactNode;
}) {
  const macIsDarkNow = useMacIsDark(appearance === "system");
  const resolved: ResolvedTheme = appearance === "system" ? (macIsDarkNow ? "dark" : "light") : appearance;

  // Before paint, so a change of setting never shows a frame of the old theme.
  useLayoutEffect(() => {
    document.documentElement.dataset.theme = resolved;
    remember(THEME_KEY, resolved);
    remember(APPEARANCE_KEY, appearance);
  }, [appearance, resolved]);

  useLayoutEffect(() => {
    document.documentElement.dataset.color = colorTheme;
    remember(COLOR_KEY, colorTheme);
  }, [colorTheme]);

  const value = useMemo(() => ({ resolved }), [resolved]);
  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme(): { resolved: ResolvedTheme } {
  const theme = useContext(ThemeContext);
  if (theme === null) throw new Error("useTheme needs a ThemeProvider above it");
  return theme;
}
