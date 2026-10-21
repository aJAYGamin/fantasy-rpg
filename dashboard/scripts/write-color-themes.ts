// Writes web/src/theme/colorThemes.css from tokens.css and the cursor palettes (npm run color-themes).
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { buildColorThemesCss } from "../web/src/theme/themeTokens";

const themeDir = fileURLToPath(new URL("../web/src/theme/", import.meta.url));
const css = buildColorThemesCss(readFileSync(`${themeDir}tokens.css`, "utf8"));
writeFileSync(`${themeDir}colorThemes.css`, css);
console.log(`wrote colorThemes.css (${css.split("\n").length} lines)`);
