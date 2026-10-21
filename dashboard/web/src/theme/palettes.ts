import type { ColorTheme } from "../../../shared/src/colorThemes";

/**
 * The game's twenty cursor colors, copied from the cursor art reference
 * (.claude/docs/superpowers/specs/2026-10-17-themed-cursor-art.html, the .c-<color> classes): eight shades from
 * light to dark (--s0 … --s7) and the light rim each cursor is drawn with. Every color theme is worked out from
 * these alone (themeTokens.ts).
 */
export type Palette = {
  shades: readonly [string, string, string, string, string, string, string, string];
  rim: string;
};

export const PALETTES: Record<ColorTheme, Palette> = {
  amethyst: { shades: ["#E2D0FF", "#C9A8FF", "#B48CFF", "#9C6BF5", "#7E4FE0", "#6A3BC9", "#4B2A99", "#3A2860"], rim: "#EBDBFF" },
  arcane: { shades: ["#FBE0FF", "#F2BFFF", "#E394FA", "#D06BF0", "#B84FDB", "#9A36BF", "#6A1F8A", "#48145E"], rim: "#FBE6FF" },
  rose: { shades: ["#FFF0F8", "#FFE0F2", "#FFC2E8", "#FF9AD2", "#F078B8", "#E0559E", "#A3295F", "#6E1C40"], rim: "#FFE8F5" },
  garnet: { shades: ["#FFD6DE", "#F5A3B4", "#E36A84", "#C93A5A", "#A8213F", "#87132E", "#5C0A1E", "#3D0613"], rim: "#FFDCE3" },
  ember: { shades: ["#FFE6E6", "#FFD0D0", "#FFA8A8", "#FF7A7A", "#EB5555", "#D93A3A", "#9E1F1F", "#6E1515"], rim: "#FFE6E6" },
  blaze: { shades: ["#FFF0E3", "#FFD9B8", "#FFBC85", "#FF9A4D", "#F57F26", "#E0650F", "#A84400", "#702E00"], rim: "#FFEFE0" },
  gilded: { shades: ["#FFF6D6", "#FFE7A3", "#F9D36B", "#EDB938", "#D49A1C", "#B07A0E", "#74500A", "#4D3506"], rim: "#FFF3CC" },
  storm: { shades: ["#FFFDE6", "#FFF8C8", "#FFEE8A", "#FFE45C", "#F2CC2A", "#E6B800", "#A37A00", "#6E5300"], rim: "#FFFBE0" },
  terra: { shades: ["#FFF4E6", "#F7DDB5", "#EEC48E", "#E0A868", "#CC8F50", "#B9783A", "#7A4A1E", "#55331A"], rim: "#FFF1DC" },
  venom: { shades: ["#F6FFDB", "#E6FFA8", "#D2FA6E", "#BDF23A", "#A2DB1F", "#84BF0F", "#557F05", "#385503"], rim: "#F4FFD6" },
  gale: { shades: ["#EFFFEA", "#DFFFD6", "#C2F7B0", "#A6F28F", "#80DE6A", "#5FCC48", "#34912A", "#23631C"], rim: "#EFFFEA" },
  grove: { shades: ["#D9FFE8", "#A8F0C6", "#6FDB9E", "#3CC27A", "#22A35E", "#158448", "#0B5C30", "#063D20"], rim: "#DFFFEC" },
  spirit: { shades: ["#ECFFF9", "#D6FFF2", "#B0F8E2", "#8FF2D3", "#66DDBA", "#3FC9A3", "#1F8F75", "#156250"], rim: "#E6FFF8" },
  frost: { shades: ["#F7FEFF", "#E0FBFF", "#C2F4FF", "#A8EEFF", "#7FDDF2", "#5CCFEA", "#2A8FB0", "#1E6A82"], rim: "#F0FDFF" },
  tidal: { shades: ["#E3F1FF", "#CDE6FF", "#A6D2FF", "#7DBBFF", "#4DA0F0", "#3C8AE6", "#1F5BB0", "#15406F"], rim: "#E6F2FF" },
  abyss: { shades: ["#C9D3FF", "#9DABF5", "#7184E6", "#4E62CF", "#3747AD", "#26338A", "#172160", "#0E1540"], rim: "#C9D3FF" },
  void: { shades: ["#6B55A0", "#5B4385", "#4A3570", "#3A2860", "#2E2050", "#24183F", "#120D1F", "#0B0814"], rim: "#B48CFF" },
  obsidian: { shades: ["#8C8C99", "#6E6E7A", "#55555F", "#3E3E47", "#2E2E36", "#222228", "#141418", "#0A0A0D"], rim: "#D9D9E6" },
  steel: { shades: ["#E3E8EF", "#C9D2DE", "#AEB9C8", "#93A1B3", "#788799", "#5F6E80", "#3F4A57", "#2B333D"], rim: "#EEF2F7" },
  lunar: { shades: ["#FFFFFF", "#F7F8FC", "#E6E9F2", "#D3D8E6", "#B9C0D4", "#9CA5BF", "#6E7894", "#4D556B"], rim: "#FFFFFF" },
};

/** The theme's gem, as the cursor wheel's swatches draw it: lit from the top left. */
export function gemOf(theme: ColorTheme): string {
  const { shades } = PALETTES[theme];
  return `radial-gradient(circle at 35% 30%, ${shades[1]}, ${shades[4]} 60%, ${shades[6]})`;
}
