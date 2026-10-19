import { NAV } from "./nav";

/** The palette draws its results in this order. */
export const GROUPS = ["Pages", "Heroes", "Settings"] as const;

export type SearchEntry = {
  id: string;
  label: string;
  group: (typeof GROUPS)[number];
  path: string;
  /** Other words that find it (not shown). */
  keywords?: string[];
};

const MAX_RESULTS = 20;

// Words that find a page besides its name. Kept short and plain: the search is a substring match, nothing fuzzier.
const PAGE_KEYWORDS: Record<string, string[]> = {
  "/": ["home", "status", "dashboard"],
  "/party": ["heroes", "characters", "team", "stats"],
  "/inventory": ["items", "bag", "gold", "potions"],
  "/gear": ["equipment", "weapons", "armour", "armor"],
  "/location": ["map", "maps", "where", "teleport", "position"],
  "/admin": ["administration"],
  "/settings": ["preferences", "options"],
};

const HEROES = [
  { slug: "aria", label: "Aria" },
  { slug: "kael", label: "Kael" },
  { slug: "lyra", label: "Lyra" },
];

// The slugs are the Settings page's routes (ruling R2).
const SETTINGS_SECTIONS = [
  {
    slug: "appearance",
    label: "Appearance",
    keywords: ["theme", "dark mode", "light mode", "colour", "color", "sidebar"],
  },
  {
    slug: "account",
    label: "Account",
    keywords: ["profile", "display name", "picture", "avatar", "password", "security answers"],
  },
  { slug: "sign-in", label: "Sign-in", keywords: ["keep me signed in", "login", "log in", "session"] },
  { slug: "game-connection", label: "Game connection", keywords: ["port", "reconnect", "link"] },
  { slug: "notifications", label: "Notifications", keywords: ["alerts", "bell", "unread"] },
];

/**
 * Everything the search can find without the game: the pages, the three heroes and the settings sections, in the
 * order the palette draws their groups. Items, gear, maps and saved spots join in stage 2, from the game.
 */
export function buildIndex(): SearchEntry[] {
  const pages = [...NAV.flatMap((group) => group.items), { label: "Settings", path: "/settings" }];
  return [
    ...pages.map(
      ({ label, path }): SearchEntry => ({
        id: `page-${label.toLowerCase()}`,
        label,
        group: "Pages",
        path,
        keywords: PAGE_KEYWORDS[path],
      }),
    ),
    ...HEROES.map(
      ({ slug, label }): SearchEntry => ({
        id: `hero-${slug}`,
        label,
        group: "Heroes",
        path: `/party?hero=${slug}`,
        keywords: ["hero", "party", "character"],
      }),
    ),
    ...SETTINGS_SECTIONS.map(
      ({ slug, label, keywords }): SearchEntry => ({
        id: `settings-${slug}`,
        label,
        group: "Settings",
        path: `/settings/${slug}`,
        keywords,
      }),
    ),
  ];
}

const byLabel = (a: SearchEntry, b: SearchEntry) => a.label.localeCompare(b.label, "en", { sensitivity: "base" });

/**
 * Entries whose label or keywords contain `query`, ignoring capitals: those whose label starts with it first, then
 * the rest, each alphabetical, at most 20. An empty query lists the index as it stands (up to 20), so the palette
 * opens on the sidebar's order rather than an alphabet.
 */
export function search(index: readonly SearchEntry[], query: string): SearchEntry[] {
  const needle = query.trim().toLowerCase();
  if (needle === "") return index.slice(0, MAX_RESULTS);
  const startsWith: SearchEntry[] = [];
  const contains: SearchEntry[] = [];
  for (const entry of index) {
    const label = entry.label.toLowerCase();
    if (label.startsWith(needle)) startsWith.push(entry);
    else if (label.includes(needle) || entry.keywords?.some((word) => word.toLowerCase().includes(needle))) {
      contains.push(entry);
    }
  }
  return [...startsWith.sort(byLabel), ...contains.sort(byLabel)].slice(0, MAX_RESULTS);
}

/** Results gathered under their group's heading, groups in the palette's order, each group keeping the ranking. */
export function groupResults(
  results: readonly SearchEntry[],
): Array<{ group: SearchEntry["group"]; entries: SearchEntry[] }> {
  return GROUPS.map((group) => ({ group, entries: results.filter((entry) => entry.group === group) })).filter(
    ({ entries }) => entries.length > 0,
  );
}
