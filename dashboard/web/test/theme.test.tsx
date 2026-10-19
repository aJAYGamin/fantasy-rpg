import { act, render, screen, waitFor } from "@testing-library/react";
import { expect, test } from "vitest";
import globalCss from "../src/theme/global.css?raw";
import tokensCss from "../src/theme/tokens.css?raw";
import { ThemeProvider, useTheme } from "../src/theme/ThemeProvider";
import { mockMatchMedia, renderAt, runIndexHtmlThemeScript, settled } from "./helpers";
import { SIGNED_OUT, mockAuthState, mockSettings } from "./msw";

const theme = () => document.documentElement.dataset.theme;

test("follow my Mac switches live", () => {
  // Review Focus 5
  const mq = mockMatchMedia(false);
  render(<ThemeProvider appearance="system" />);
  expect(theme()).toBe("light");
  act(() => mq.setMatches(true));
  expect(theme()).toBe("dark");
});

test("the saved theme is applied before React renders", () => {
  // Review Focus 5
  localStorage.setItem("amethyst-theme", "dark");
  runIndexHtmlThemeScript();
  expect(theme()).toBe("dark");
});

test("before React renders, Follow my Mac reads the Mac's setting now, not the last one saved", () => {
  localStorage.setItem("amethyst-theme", "light");
  localStorage.setItem("amethyst-appearance", "system");
  mockMatchMedia(true);
  runIndexHtmlThemeScript();
  expect(theme()).toBe("dark");
});

test("with nothing saved the first load is light", () => {
  runIndexHtmlThemeScript();
  expect(theme()).toBe("light");
});

test("a chosen theme is applied and remembered for the next load", () => {
  render(<ThemeProvider appearance="dark" />);
  expect(theme()).toBe("dark");
  expect(localStorage.getItem("amethyst-theme")).toBe("dark");
  expect(localStorage.getItem("amethyst-appearance")).toBe("dark");
});

test("useTheme tells components which theme is showing", () => {
  function Shown() {
    return <p>{useTheme().resolved}</p>;
  }
  const mq = mockMatchMedia(true);
  render(
    <ThemeProvider appearance="system">
      <Shown />
    </ThemeProvider>,
  );
  expect(screen.getByText("dark")).toBeInTheDocument();
  act(() => mq.setMatches(false));
  expect(screen.getByText("light")).toBeInTheDocument();
});

test("signed out, the sign-in page keeps the last theme instead of flashing back to light", async () => {
  localStorage.setItem("amethyst-theme", "dark");
  localStorage.setItem("amethyst-appearance", "dark");
  runIndexHtmlThemeScript();
  mockAuthState(SIGNED_OUT);
  const { queryClient } = renderAt("/signin");
  expect(theme()).toBe("dark");
  await screen.findByRole("button", { name: "Sign in" });
  await settled(queryClient);
  expect(theme()).toBe("dark");
});

test("signed in, the saved appearance setting decides the theme", async () => {
  mockSettings({ appearance: "dark" });
  const { queryClient } = renderAt("/");
  await waitFor(() => expect(theme()).toBe("dark"));
  await settled(queryClient);
  expect(localStorage.getItem("amethyst-appearance")).toBe("dark");
});

// The approved mockups' palette (Task 6's token table): [token, light, dark].
const MOCKUP_PALETTE = [
  ["--side", "#1E1230", "#0D0817"],
  ["--side2", "#281A3F", "#1E1433"],
  ["--side-text", "#B9A9D6", "#B3A3D3"],
  ["--side-head", "#7E6AA3", "#6E5B94"],
  ["--bg", "#F5F3F9", "#120D1F"],
  ["--card", "#FFFFFF", "#1A1329"],
  ["--line", "#E7E2F0", "#2C2242"],
  ["--text", "#2A2238", "#ECE4FA"],
  // Light --dim is the one table value moved for contrast (R17): #7A7090 read 4.19:1 on --bg.
  ["--dim", "#716785", "#9C8FB8"],
  ["--am", "#7E4FE0", "#9C6BF5"],
  ["--am2", "#9C6BF5", "#B48CFF"],
  ["--am-soft", "#EFE7FF", "#2A1D47"],
  ["--gold", "#C9962B", "#E2B54B"],
  ["--warn", "#D9822B", "#E6A04F"],
  ["--ok", "#2E9E5B", "#4CC27E"],
  ["--ok-soft", "#E3F5EA", "#17301F"],
  ["--bad", "#C6455E", "#EE6F86"],
  ["--bad-soft", "#FBE9ED", "#3A1A24"],
  ["--aria", "#3D8FE0", "#5AA7F5"],
  ["--kael", "#D84545", "#F06A6A"],
  ["--lyra", "#4CAF50", "#6CCF6E"],
] as const;

function tokensIn(selector: string): Map<string, string> {
  const start = tokensCss.indexOf(`${selector} {`);
  if (start === -1) throw new Error(`tokens.css has no "${selector} {" block`);
  const block = tokensCss.slice(start, tokensCss.indexOf("}", start));
  return new Map([...block.matchAll(/(--[\w-]+):\s*([^;]+);/g)].map(([, name, value]) => [name, value.trim()]));
}

test("the colour tokens are the mockups' palette, in light and in dark", () => {
  const light = tokensIn(':root,\n[data-theme="light"]');
  const dark = tokensIn('[data-theme="dark"]');
  for (const [token, lightValue, darkValue] of MOCKUP_PALETTE) {
    expect(light.get(token)?.toUpperCase(), `light ${token}`).toBe(lightValue);
    expect(dark.get(token)?.toUpperCase(), `dark ${token}`).toBe(darkValue);
  }
  // Every colour the light theme defines, the dark theme redefines, so nothing falls back to a light value.
  expect([...light.keys()].filter((token) => !dark.has(token))).toEqual([]);
});

test("outside tokens.css, no stylesheet or component names a colour of its own", () => {
  const sources = {
    ...import.meta.glob<string>("../src/**/*.css", { query: "?raw", import: "default", eager: true }),
    ...import.meta.glob<string>("../src/**/*.tsx", { query: "?raw", import: "default", eager: true }),
  };
  const colourLiteral = /#[0-9a-f]{3,8}\b|\b(?:rgba?|hsla?|oklch|lab|lch)\(|:\s*(?:white|black)\b/i;
  const offenders = Object.entries(sources)
    .filter(([path]) => !path.endsWith("/theme/tokens.css"))
    .filter(([, text]) => colourLiteral.test(text.replace(/\/\*[\s\S]*?\*\//g, "")))
    .map(([path]) => path);
  expect(Object.keys(sources).length).toBeGreaterThan(20);
  expect(offenders).toEqual([]);
});

// ---- contrast (WCAG 2.x relative luminance) ----

function luminance(hex: string): number {
  const match = /^#([0-9a-f]{6})$/i.exec(hex);
  if (!match) throw new Error(`not a #rrggbb colour: ${hex}`);
  const [r, g, b] = [0, 2, 4].map((i) => {
    const channel = Number.parseInt(match[1].slice(i, i + 2), 16) / 255;
    return channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contrast(a: string, b: string): number {
  const [light, dark] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (light + 0.05) / (dark + 0.05);
}

type Pair = { fore: string; back: string; min: number; where: string };

const stylesheets = import.meta.glob<string>("../src/**/*.css", { query: "?raw", import: "default", eager: true });

/**
 * Every text colour a stylesheet sets, with the surface it sits on: the same rule's background if it sets one;
 * otherwise the amethyst fill for white-on-amethyst text, the field fills for text inside an input, and the
 * card and page for everything else. Disabled states are exempt from the contrast rule.
 */
function textPairsInStylesheets(): Pair[] {
  const pairs: Pair[] = [];
  for (const [path, css] of Object.entries(stylesheets)) {
    if (path.endsWith("/theme/tokens.css")) continue;
    for (const [, selector, body] of css.replace(/\/\*[\s\S]*?\*\//g, "").matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
      // A rule for the disabled state itself is exempt; a hover rule that merely excludes it (":not(:disabled)") isn't.
      if (selector.replace(/:not\([^)]*\)/g, "").includes("disabled")) continue;
      const fore = /(?<![\w-])color:\s*var\((--[\w-]+)\)/.exec(body)?.[1];
      if (!fore) continue;
      const ownBack = /(?<![\w-])background(?:-color)?:\s*var\((--[\w-]+)\)/.exec(body)?.[1];
      const backs = ownBack
        ? [ownBack]
        : fore === "--on-am"
          ? ["--am-fill"]
          : /\/(Input|PasswordInput)\.module\.css$/.test(path)
            ? ["--input-bg", "--bad-soft"]
            : ["--card", "--bg"];
      for (const back of backs) pairs.push({ fore, back, min: 4.5, where: `${path} ${selector.trim()}` });
    }
  }
  return pairs;
}

// Pairs no single rule shows: hover fills, typing in a field marked wrong, and the 3:1 tracks and boundaries.
const LISTED: Pair[] = [
  { fore: "--on-am", back: "--am-fill-hover", min: 4.5, where: "primary button, hovered" },
  { fore: "--text", back: "--bad-soft", min: 4.5, where: "typing in a field marked wrong" },
  { fore: "--toggle-off", back: "--card", min: 3, where: "an off switch's track on a card" },
  { fore: "--toggle-off", back: "--bg", min: 3, where: "an off switch's track on the page" },
  { fore: "--on-am", back: "--toggle-off", min: 3, where: "the knob on an off switch" },
  { fore: "--on-am", back: "--am", min: 3, where: "the knob on an on switch" },
  { fore: "--check-border", back: "--input-bg", min: 3, where: "an unticked checkbox's edge" },
  { fore: "--check-border", back: "--card", min: 3, where: "an unticked checkbox on a card" },
  { fore: "--check-border", back: "--bg", min: 3, where: "an unticked checkbox on the page" },
  { fore: "--am-fill", back: "--card", min: 3, where: "a ticked checkbox / chosen segment on a card" },
  { fore: "--am-fill", back: "--bg", min: 3, where: "a ticked checkbox / chosen segment on the page" },
];

test("every colour pair the components use meets WCAG AA in both themes", () => {
  const derived = textPairsInStylesheets();
  expect(derived.length).toBeGreaterThan(30);
  const failures: string[] = [];
  for (const [theme, tokens] of [
    ["light", tokensIn(':root,\n[data-theme="light"]')],
    ["dark", tokensIn('[data-theme="dark"]')],
  ] as const) {
    for (const { fore, back, min, where } of [...derived, ...LISTED]) {
      const [foreValue, backValue] = [tokens.get(fore), tokens.get(back)];
      if (!foreValue || !backValue) throw new Error(`${theme} has no ${foreValue ? back : fore} (${where})`);
      const ratio = contrast(foreValue, backValue);
      if (ratio < min) failures.push(`${theme}: ${fore} on ${back} is ${ratio.toFixed(2)}:1, under ${min} (${where})`);
    }
  }
  expect(failures).toEqual([]);
});

test("the focus ring survives forced-colours (high contrast) mode, where shadows are dropped", () => {
  const rule = /(?:^|\n):focus-visible\s*\{([^}]*)\}/.exec(globalCss)?.[1];
  expect(rule).toMatch(/outline:\s*3px solid transparent/);
  expect(rule).toMatch(/box-shadow:\s*var\(--focus-ring\)/);
});
