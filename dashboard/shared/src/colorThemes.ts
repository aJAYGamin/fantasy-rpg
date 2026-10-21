// The dashboard's color themes: the game's twenty cursor colors, in the order the game's cursor wheel steps through
// them. Amethyst is the default and the dashboard's own look; the others recolor its accent and sidebar.

export const COLOR_THEMES = [
  "amethyst",
  "arcane",
  "rose",
  "garnet",
  "ember",
  "blaze",
  "gilded",
  "storm",
  "terra",
  "venom",
  "gale",
  "grove",
  "spirit",
  "frost",
  "tidal",
  "abyss",
  "void",
  "obsidian",
  "steel",
  "lunar",
] as const;

export type ColorTheme = (typeof COLOR_THEMES)[number];

export const DEFAULT_COLOR_THEME: ColorTheme = "amethyst";

export function isColorTheme(value: unknown): value is ColorTheme {
  return typeof value === "string" && (COLOR_THEMES as readonly string[]).includes(value);
}

/** The theme's name as the game shows it ("garnet" → "Garnet"). */
export function colorThemeName(theme: ColorTheme): string {
  return theme[0].toUpperCase() + theme.slice(1);
}
