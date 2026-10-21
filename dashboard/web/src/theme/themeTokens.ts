import { COLOR_THEMES, type ColorTheme } from "../../../shared/src/colorThemes";
import { PALETTES } from "./palettes";

/*
 * Works out every color theme's tokens from its cursor palette. The output is colorThemes.css (written by
 * `npm run color-themes`, checked by color-themes.test.ts), so a theme is plain CSS by the time the page loads:
 * index.html sets data-color before the first paint and nothing flashes.
 *
 * Two kinds of token:
 *  - The grays, the sidebar and the sign-in panel are Amethyst's own values turned to the theme's hue at the same
 *    brightness (WCAG luminance). Every contrast Amethyst's tokens already meet among themselves holds unchanged.
 *  - The accent comes straight from the palette: each token takes the shade nearest the one Amethyst uses that meets
 *    its contrast needs against those surfaces. Bright colors keep their bright buttons with dark text, and get a
 *    deeper --am-edge where the fill alone would not stand out on white.
 * theme.test.tsx checks every pair the components use, in every theme and both modes.
 */

export type Mode = "light" | "dark";
type Rgb = readonly [number, number, number];

export const LIGHT_SELECTOR = ':root,\n[data-theme="light"]';
export const DARK_SELECTOR = '[data-theme="dark"]';

/** Where a theme's block applies; light also covers a page whose data-theme isn't set yet. */
export function themeSelector(theme: ColorTheme, mode: Mode): string {
  return mode === "light" ? `[data-color="${theme}"]:not([data-theme="dark"])` : `[data-color="${theme}"][data-theme="dark"]`;
}

/** The custom properties declared in the CSS block whose selector is exactly `selector`. */
export function tokenBlock(css: string, selector: string): Map<string, string> {
  const start = css.indexOf(`${selector} {`);
  if (start === -1) throw new Error(`no "${selector} {" block`);
  const block = css.slice(start, css.indexOf("}", start));
  return new Map([...block.matchAll(/(--[\w-]+):\s*([^;]+);/g)].map(([, name, value]) => [name, value.trim()]));
}

// ---- color arithmetic (sRGB, WCAG luminance, OKLab) ----

const WHITE: Rgb = [255, 255, 255];
const BLACK: Rgb = [0, 0, 0];

function parse(hex: string): Rgb {
  const match = /^#([0-9a-f]{6})$/i.exec(hex);
  if (!match) throw new Error(`not a #rrggbb color: ${hex}`);
  return [0, 2, 4].map((i) => Number.parseInt(match[1].slice(i, i + 2), 16)) as unknown as Rgb;
}

function format(color: Rgb): string {
  return `#${color.map((v) => Math.round(Math.min(255, Math.max(0, v))).toString(16).padStart(2, "0")).join("")}`;
}

/** `b` laid over `a` at `amount` (0 → a, 1 → b). */
function mix(a: Rgb, b: Rgb, amount: number): Rgb {
  return a.map((v, i) => v + (b[i] - v) * amount) as unknown as Rgb;
}

const toLinear = (v: number) => {
  const c = v / 255;
  return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
};
const fromLinear = (c: number) => 255 * (c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055);

function luminance(color: Rgb): number {
  const [r, g, b] = color.map((v) => Math.round(v)).map(toLinear);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

export function luminanceOf(hex: string): number {
  return luminance(parse(hex));
}

function contrast(a: Rgb, b: Rgb): number {
  const [light, dark] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (light + 0.05) / (dark + 0.05);
}

type Lch = { l: number; c: number; h: number };

function toOklch(color: Rgb): Lch {
  const [r, g, b] = color.map(toLinear);
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  const L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s;
  const A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
  const B = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s;
  return { l: L, c: Math.hypot(A, B), h: Math.atan2(B, A) };
}

/** The sRGB color for an OKLCH one, or null when it falls outside sRGB. */
function fromOklch({ l: L, c, h }: Lch): Rgb | null {
  const A = c * Math.cos(h);
  const B = c * Math.sin(h);
  const l = (L + 0.3963377774 * A + 0.2158037573 * B) ** 3;
  const m = (L - 0.1055613458 * A - 0.0638541728 * B) ** 3;
  const s = (L - 0.0894841775 * A - 1.291485548 * B) ** 3;
  const linear = [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  ];
  if (linear.some((v) => v < -1e-4 || v > 1 + 1e-4)) return null;
  return linear.map((v) => fromLinear(Math.min(1, Math.max(0, v)))) as unknown as Rgb;
}

/** At lightness `l`, the most of chroma `c` that sRGB can show at hue `h`. */
function inGamut(l: number, c: number, h: number): Rgb {
  let low = 0;
  let high = c;
  let best = fromOklch({ l, c: 0, h }) ?? (l > 0.5 ? WHITE : BLACK);
  for (let i = 0; i < 24; i++) {
    const mid = (low + high) / 2;
    const color = fromOklch({ l, c: mid, h });
    if (color) {
      best = color;
      low = mid;
    } else high = mid;
  }
  return fromOklch({ l, c: high, h }) ?? best;
}

/** Amethyst's chroma, the measure the other palettes' saturation is taken against. */
const AMETHYST_CHROMA = toOklch(parse(PALETTES.amethyst.shades[4])).c;

/** Which way a retinted token leans: a surface away from the inks on it, an ink away from its surface. */
type Lean = "lighter" | "darker";
const LEAN = 0.025;

/**
 * `hex` turned to `hue`, its chroma scaled by `scale`, at its own luminance: the same light or dark gray, in another
 * color. Luminance (not OKLab lightness) is held, because it is what the contrast rules measure; it leans 2.5% one way
 * so that landing on whole sRGB steps can only add contrast, never take a hair off a pair that sits right at 4.5:1.
 */
function retint(hex: string, hue: number, scale: number, lean: Lean): string {
  // Pure white and black have no hue to turn (and the search below would only round them a step off).
  if (/^#(?:ffffff|000000)$/i.test(hex)) return hex.toLowerCase();
  const source = parse(hex);
  const target = Math.min(1, luminance(source) * (lean === "lighter" ? 1 + LEAN : 1 - LEAN));
  const chroma = toOklch(source).c * scale;
  let low = 0;
  let high = 1;
  let color = source;
  for (let i = 0; i < 40; i++) {
    const mid = (low + high) / 2;
    color = inGamut(mid, chroma, hue);
    if (luminance(color) < target) low = mid;
    else high = mid;
  }
  return format(color);
}

// ---- the palette as a ramp, for the accent ----

type Theme = { shades: Rgb[]; rim: Rgb; dark: boolean };

// The shades from white to black: position -1 is white, 0 … 7 the palette's shades, 8 black; in between, mixed.
// Void and Obsidian are dark all the way down, so their glowing rim sits above their lightest shade.
function rampAt(theme: Theme, at: number): Rgb {
  const stops: Rgb[] = theme.dark ? [WHITE, theme.rim, ...theme.shades, BLACK] : [WHITE, ...theme.shades, BLACK];
  const offset = theme.dark ? 2 : 1; // where shade 0 sits in `stops`
  const position = Math.min(stops.length - 1, Math.max(0, at + offset));
  const index = Math.floor(position);
  if (index >= stops.length - 1) return stops[stops.length - 1];
  return mix(stops[index], stops[index + 1], position - index);
}

/** The ramp color nearest `prefer` (a shade number) that passes `ok`: searched outward in small steps. */
function pick(theme: Theme, prefer: number, ok: (color: Rgb) => boolean, what: string): Rgb {
  const low = theme.dark ? -2 : -1;
  for (let step = 0; step <= 200; step++) {
    for (const at of step === 0 ? [prefer] : [prefer + step * 0.05, prefer - step * 0.05]) {
      if (at < low || at > 8) continue;
      const color = rampAt(theme, at);
      if (ok(color)) return color;
    }
  }
  throw new Error(`no shade works for ${what}`);
}

const passes = (min: number, ...backs: Rgb[]) => (color: Rgb) => backs.every((back) => contrast(color, back) >= min);
const rgba = (color: Rgb, alpha: number) => `rgba(${color.map((v) => Math.round(v)).join(", ")}, ${alpha})`;

// Retinted: the page's surfaces and inks, the sidebar and the sign-in panel, each leaning away from what it sits
// next to. The page's surfaces are light in light mode and dark in dark mode; the sidebar and panel are dark in both.
const PAGE_SURFACES = ["--bg", "--card", "--neutral-soft", "--control-bg", "--control-hover", "--input-bg", "--row-line",
  "--track", "--line", "--disabled-bg", "--scrollbar", "--scrollbar-hover"];
const PAGE_INKS = ["--text", "--dim", "--neutral-ink", "--label", "--placeholder", "--toggle-off", "--check-border",
  "--disabled-ink"];
const DARK_SURFACES = ["--side", "--side2", "--side-hover", "--brand-from", "--brand-to"];
const LIGHT_INKS = ["--side-text", "--side-head", "--side-line", "--side-edge", "--brand-sub", "--brand-foot"];

function retinted(mode: Mode): Array<[string, Lean]> {
  const [surface, ink]: [Lean, Lean] = mode === "light" ? ["lighter", "darker"] : ["darker", "lighter"];
  return [
    ...PAGE_SURFACES.map((token): [string, Lean] => [token, surface]),
    ...PAGE_INKS.map((token): [string, Lean] => [token, ink]),
    ...DARK_SURFACES.map((token): [string, Lean] => [token, "darker"]),
    ...LIGHT_INKS.map((token): [string, Lean] => [token, "lighter"]),
  ];
}

/** The tokens a color theme sets over tokens.css in one mode. Amethyst sets none: it is tokens.css. */
export function deriveTheme(name: ColorTheme, mode: Mode, base: Map<string, string>): Map<string, string> {
  const out = new Map<string, string>();
  if (name === "amethyst") return out;
  const palette = PALETTES[name];
  const theme: Theme = {
    shades: palette.shades.map(parse),
    rim: parse(palette.rim),
    dark: name === "void" || name === "obsidian",
  };
  const s = theme.shades;
  const vivid = toOklch(s[4]);
  const scale = Math.min(1, vivid.c / AMETHYST_CHROMA);
  const baseColor = (token: string) => {
    const value = base.get(token);
    if (value === undefined) throw new Error(`tokens.css has no ${token}`);
    return value;
  };

  for (const [token, lean] of retinted(mode)) out.set(token, retint(baseColor(token), vivid.h, scale, lean));
  const got = (token: string) => parse(out.get(token) ?? baseColor(token));
  const card = got("--card");
  const bg = got("--bg");
  const input = got("--input-bg");
  const side = got("--side");
  const side2 = got("--side2");

  // Buttons and other filled shapes: the vivid shade itself. White text where it reads; otherwise dark text, as on
  // Storm's yellow. Void and Obsidian are near-black, so in dark mode they glow in their rim color instead.
  const ink = mix(s[7], BLACK, 0.6);
  let fill: Rgb;
  let onFill: Rgb;
  const whiteable = [s[4], s[5]].find((shade) => contrast(WHITE, shade) >= 4.5);
  if (theme.dark && mode === "dark") {
    fill = theme.rim;
    onFill = ink;
  } else if (whiteable) {
    fill = whiteable;
    onFill = WHITE;
  } else {
    fill = contrast(ink, s[4]) >= 4.5 ? s[4] : s[3];
    onFill = ink;
  }
  // Hovered, the fill moves away from its text: darker under white, lighter under dark ink.
  const hover = onFill === WHITE ? mix(fill, BLACK, 0.12) : mix(fill, WHITE, 0.2);
  // An edge only where the fill alone would blend into the card or the page.
  const standsOut = passes(3, card, bg);
  const edge = standsOut(fill)
    ? "transparent"
    : format(pick(theme, mode === "light" ? 5 : 2, standsOut, `${name} ${mode} edge`));

  const soft = mode === "light" ? mix(s[1], WHITE, 0.72) : mix(theme.dark ? theme.rim : s[4], card, theme.dark ? 0.85 : 0.78);
  const line = mode === "light" ? mix(s[2], WHITE, 0.55) : mix(theme.dark ? theme.rim : s[4], card, theme.dark ? 0.7 : 0.6);

  // Text-weight accents read at 4.5:1 on every surface they sit on; ring-like ones at 3:1.
  const am = pick(theme, mode === "light" ? 4 : 3, passes(4.5, card, bg, input), `${name} ${mode} --am`);
  // --am-text also marks a pressed show-password button, which can sit in a field marked wrong (--bad-soft).
  const amText = pick(theme, mode === "light" ? 4 : 1, passes(4.5, card, bg, soft, got("--bad-soft")), `${name} ${mode} --am-text`);
  const amInk = pick(theme, mode === "light" ? 6 : 1, passes(4.5, card, bg, soft), `${name} ${mode} --am-ink`);
  const am2 = pick(theme, mode === "light" ? 3 : 2, passes(3, side, side2), `${name} ${mode} --am2`);
  const focus = pick(theme, mode === "light" ? 4 : 3, passes(3, card, bg, side, side2), `${name} ${mode} --focus-line`);
  const tagInk = pick(theme, 1, passes(4.5, side, side2), `${name} ${mode} --side-tag-ink`);
  const glow = theme.dark ? theme.rim : s[3];

  out.set("--am", format(am));
  out.set("--am2", format(am2));
  out.set("--am-soft", format(soft));
  out.set("--on-am", format(onFill));
  out.set("--am-fill", format(fill));
  out.set("--am-fill-hover", format(hover));
  out.set("--am-edge", edge);
  out.set("--am-switch", format(fill));
  out.set("--am-ink", format(amInk));
  out.set("--am-text", format(amText));
  out.set("--am-line", format(line));
  out.set("--focus-line", format(focus));
  out.set("--focus-tint", rgba(focus, mode === "light" ? 0.15 : 0.25));
  out.set("--side-tag-ink", format(tagInk));
  out.set("--gem", theme.dark
    ? `radial-gradient(circle at 35% 30%, ${palette.rim}, ${palette.shades[3]} 60%, ${palette.shades[6]})`
    : `radial-gradient(circle at 35% 30%, ${palette.shades[1]}, ${palette.shades[4]} 60%, ${palette.shades[6]})`);
  out.set("--gem-glow", `0 0 0 3px ${rgba(glow, theme.dark ? 0.35 : 0.25)}`);
  out.set("--brand-glow", rgba(glow, mode === "light" ? 0.35 : 0.3));
  if (mode === "light") out.set("--overlay", rgba(side, 0.45));
  return out;
}

/** colorThemes.css: every theme but Amethyst, light then dark, worked out from tokens.css and the palettes. */
export function buildColorThemesCss(tokensCss: string): string {
  const bases = { light: tokenBlock(tokensCss, LIGHT_SELECTOR), dark: tokenBlock(tokensCss, DARK_SELECTOR) };
  const blocks = COLOR_THEMES.filter((name) => name !== "amethyst").flatMap((name) =>
    (["light", "dark"] as const).map((mode) => {
      const lines = [...deriveTheme(name, mode, bases[mode])].map(([token, value]) => `  ${token}: ${value};`);
      return `${themeSelector(name, mode)} {\n${lines.join("\n")}\n}\n`;
    }),
  );
  return [
    "/*",
    " * The dashboard's color themes, one block per theme and mode, laid over tokens.css by <html data-color>.",
    " * Generated from the game's cursor palettes by src/theme/themeTokens.ts: do not edit by hand; after changing",
    " * tokens.css, palettes.ts or themeTokens.ts, run `npm run color-themes` (a test fails until this file matches).",
    " */",
    "",
    blocks.join("\n"),
  ].join("\n");
}
