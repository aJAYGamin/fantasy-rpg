import { expect, test } from "vitest";
import { COLOR_THEMES } from "../../shared/src/colorThemes";
import colorThemesCss from "../src/theme/colorThemes.css?raw";
import { PALETTES } from "../src/theme/palettes";
import {
  DARK_SELECTOR,
  LIGHT_SELECTOR,
  buildColorThemesCss,
  luminanceOf,
  themeSelector,
  tokenBlock,
} from "../src/theme/themeTokens";
import tokensCss from "../src/theme/tokens.css?raw";

const theme = (name: (typeof COLOR_THEMES)[number], mode: "light" | "dark") =>
  tokenBlock(colorThemesCss, themeSelector(name, mode));

test("the color themes stylesheet is exactly what the cursor palettes produce (run npm run color-themes after a change)", () => {
  expect(colorThemesCss).toBe(buildColorThemesCss(tokensCss));
});

test("Amethyst is the dashboard's own look, so it has no block of its own; the other nineteen have one per mode", () => {
  expect(colorThemesCss).not.toContain('[data-color="amethyst"]');
  for (const name of COLOR_THEMES.filter((name) => name !== "amethyst")) {
    expect(theme(name, "light").size, `${name} light`).toBeGreaterThan(20);
    expect(theme(name, "dark").size, `${name} dark`).toBeGreaterThan(20);
  }
});

test("buttons are the cursor color itself: white text where it reads, dark text on the bright ones", () => {
  expect(theme("garnet", "light").get("--am-fill")).toBe("#a8213f");
  expect(theme("garnet", "light").get("--on-am")).toBe("#ffffff");
  expect(theme("storm", "light").get("--am-fill")).toBe("#f2cc2a");
  expect(luminanceOf(theme("storm", "light").get("--on-am") as string)).toBeLessThan(0.05);
});

test("in dark mode Void's and Obsidian's buttons are brightened to their glowing rim colors", () => {
  expect(theme("void", "dark").get("--am-fill")).toBe(PALETTES.void.rim.toLowerCase());
  expect(theme("obsidian", "dark").get("--am-fill")).toBe(PALETTES.obsidian.rim.toLowerCase());
  expect(theme("void", "light").get("--am-fill")).not.toBe(PALETTES.void.rim.toLowerCase());
});

test("a fill too pale to stand out on white gets a deeper edge; a strong one keeps none", () => {
  expect(theme("storm", "light").get("--am-edge")).not.toBe("transparent");
  expect(theme("garnet", "light").get("--am-edge")).toBe("transparent");
});

test("the grays and the sidebar take each theme's hue at Amethyst's own brightness, so they read the same", () => {
  for (const [mode, selector] of [
    ["light", LIGHT_SELECTOR],
    ["dark", DARK_SELECTOR],
  ] as const) {
    const base = tokenBlock(tokensCss, selector);
    for (const name of COLOR_THEMES.filter((name) => name !== "amethyst")) {
      for (const token of ["--bg", "--text", "--dim", "--line", "--side", "--side-text", "--side-head"]) {
        const ours = luminanceOf(theme(name, mode).get(token) as string);
        const amethyst = luminanceOf(base.get(token) as string);
        // Within the 2.5% each one leans so that rounding can't cost contrast (near black, one sRGB step is more).
        expect(Math.abs(ours - amethyst), `${name} ${mode} ${token}`).toBeLessThan(Math.max(0.05 * amethyst, 0.0015));
      }
    }
  }
});

test("the sidebar is a deep shade of the theme's own color", () => {
  // Garnet's sidebar is red-dominant and Tidal's blue-dominant, both dark.
  const [r, g, b] = [1, 3, 5].map((i) => Number.parseInt((theme("garnet", "light").get("--side") as string).slice(i, i + 2), 16));
  expect(r).toBeGreaterThan(g);
  expect(r).toBeGreaterThan(b);
  const tidal = theme("tidal", "light").get("--side") as string;
  expect(Number.parseInt(tidal.slice(5, 7), 16)).toBeGreaterThan(Number.parseInt(tidal.slice(1, 3), 16));
  expect(luminanceOf(tidal)).toBeLessThan(0.05);
});
