import {
  Bell,
  CornerDownLeft,
  KeyRound,
  type LucideIcon,
  Palette,
  Plug,
  SearchIcon,
  SearchX,
  Settings,
  User,
} from "lucide-react";
import {
  type KeyboardEvent,
  type ReactNode,
  useEffect,
  useId,
  useMemo,
  useRef,
  useState,
} from "react";
import { useNavigate } from "react-router";
import { Dialog } from "../components";
import { cx } from "../components/cx";
import { NAV } from "./nav";
import styles from "./SearchPalette.module.css";
import { type SearchEntry, buildIndex, groupResults, search } from "./searchIndex";
import { SEARCH_PLACEHOLDER } from "./TopBar";

export type SearchPaletteProps = { open: boolean; onClose: () => void };

const PAGE_ICONS = new Map<string, LucideIcon>([
  ...NAV.flatMap((group) => group.items).map((item): [string, LucideIcon] => [item.path, item.icon]),
  ["/settings", Settings],
]);

const SETTINGS_ICONS: Record<string, LucideIcon> = {
  "settings-appearance": Palette,
  "settings-account": User,
  "settings-sign-in": KeyRound,
  "settings-game-connection": Plug,
  "settings-notifications": Bell,
};

/** A page or settings section gets the icon it has in the sidebar and menus; a hero, a dot in their own colour. */
function Mark({ entry }: { entry: SearchEntry }) {
  if (entry.group === "Heroes") return <span className={styles.hero} data-hero={entry.id.replace("hero-", "")} />;
  const Icon = (entry.group === "Pages" ? PAGE_ICONS.get(entry.path) : SETTINGS_ICONS[entry.id]) ?? Settings;
  return <Icon />;
}

/** The label with the part that matched in bold (only when it is the label that matched, not a hidden keyword). */
function Label({ label, query }: { label: string; query: string }): ReactNode {
  const needle = query.trim().toLowerCase();
  const lower = label.toLowerCase();
  const at = needle === "" || lower.length !== label.length ? -1 : lower.indexOf(needle);
  if (at === -1) return label;
  return (
    <>
      {label.slice(0, at)}
      <b className={styles.match}>{label.slice(at, at + needle.length)}</b>
      {label.slice(at + needle.length)}
    </>
  );
}

/**
 * ⌘K search over the pages, heroes and settings. A modal dialog holding a combobox and its listbox: the focus stays
 * in the field, and the arrow keys move a highlight (aria-activedescendant) that Enter opens. It starts empty each
 * time.
 */
export function SearchPalette({ open, onClose }: SearchPaletteProps) {
  return (
    <Dialog open={open} onClose={onClose} title="Search" variant="palette">
      <PaletteBody onClose={onClose} />
    </Dialog>
  );
}

function PaletteBody({ onClose }: { onClose: () => void }) {
  const navigate = useNavigate();
  const id = useId();
  const listId = `${id}-results`;
  const index = useMemo(buildIndex, []);
  const [query, setQuery] = useState("");
  // The highlighted result's id; none yet means the first one, so a typed query can be opened with Enter at once.
  const [highlightedId, setHighlightedId] = useState<string | null>(null);
  const scrollToHighlight = useRef(false);

  const groups = useMemo(() => groupResults(search(index, query)), [index, query]);
  // The arrow keys walk the results in the order they are drawn, which is by group.
  const flat = useMemo(() => groups.flatMap((group) => group.entries), [groups]);
  const highlighted = flat.find((entry) => entry.id === highlightedId) ?? flat[0];
  const optionId = (entry: SearchEntry) => `${id}-${entry.id}`;

  // Only the keyboard scrolls the highlight into view; the pointer is already looking at what it highlights.
  useEffect(() => {
    if (!scrollToHighlight.current || !highlighted) return;
    scrollToHighlight.current = false;
    document.getElementById(`${id}-${highlighted.id}`)?.scrollIntoView?.({ block: "nearest" });
  }, [highlighted, id]);

  function choose(entry: SearchEntry) {
    navigate(entry.path);
    onClose();
  }

  function onKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    // The Enter that ends an input method's composition (Japanese, Chinese, Korean) belongs to the composition.
    if (event.nativeEvent.isComposing) return;
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      if (flat.length === 0) return;
      const at = highlighted ? flat.indexOf(highlighted) : 0;
      const next = event.key === "ArrowDown" ? (at + 1) % flat.length : (at - 1 + flat.length) % flat.length;
      scrollToHighlight.current = true;
      setHighlightedId(flat[next].id);
    } else if (event.key === "Enter") {
      event.preventDefault();
      if (highlighted) choose(highlighted);
    }
  }

  const found = flat.length > 0;
  return (
    <>
      <div className={styles.field}>
        <SearchIcon className={styles.fieldIcon} />
        <input
          type="text"
          role="combobox"
          aria-label="Search"
          aria-autocomplete="list"
          aria-expanded={found}
          aria-controls={found ? listId : undefined}
          aria-activedescendant={highlighted ? optionId(highlighted) : undefined}
          className={styles.input}
          placeholder={SEARCH_PLACEHOLDER}
          value={query}
          onChange={(event) => {
            setQuery(event.target.value);
            setHighlightedId(null);
          }}
          onKeyDown={onKeyDown}
          autoComplete="off"
          autoCorrect="off"
          autoCapitalize="off"
          spellCheck={false}
        />
      </div>

      {/* Said aloud as the person types; the nothing-found message below is drawn, not live. */}
      <div role="status" className="visually-hidden">
        {query.trim() === "" ? "" : found ? `${flat.length} ${flat.length === 1 ? "result" : "results"}` : "No results"}
      </div>

      {found ? (
        // Pointer presses keep the focus in the field: the list is for choosing, not for typing into.
        <div
          id={listId}
          role="listbox"
          aria-label="Results"
          className={styles.results}
          onMouseDown={(event) => event.preventDefault()}
        >
          {groups.map(({ group, entries }) => (
            <div key={group} role="group" aria-labelledby={`${id}-group-${group}`} className={styles.group}>
              <div id={`${id}-group-${group}`} role="presentation" className={styles.groupLabel}>
                {group}
              </div>
              {entries.map((entry) => {
                const current = entry === highlighted;
                return (
                  // Not focusable and no key handler of its own: the field above is the keyboard's way to choose.
                  <div
                    key={entry.id}
                    id={optionId(entry)}
                    role="option"
                    aria-selected={current}
                    className={cx(styles.option, current && styles.current)}
                    onMouseMove={() => !current && setHighlightedId(entry.id)}
                    onClick={() => choose(entry)}
                  >
                    <span className={styles.mark} aria-hidden="true">
                      <Mark entry={entry} />
                    </span>
                    <span className={styles.label}>
                      <Label label={entry.label} query={query} />
                    </span>
                    {current && <CornerDownLeft className={styles.enter} aria-hidden="true" />}
                  </div>
                );
              })}
            </div>
          ))}
        </div>
      ) : (
        <div className={styles.empty}>
          <span className={styles.emptyIcon} aria-hidden="true">
            <SearchX />
          </span>
          <p>Nothing found. Items, gear and maps appear here once the game is connected.</p>
        </div>
      )}

      <div className={styles.hints} aria-hidden="true">
        <span>
          <kbd className={styles.key}>↑</kbd> <kbd className={styles.key}>↓</kbd> to move
        </span>
        <span>
          <kbd className={styles.key}>↵</kbd> to open
        </span>
        <span>
          <kbd className={styles.key}>esc</kbd> to close
        </span>
      </div>
    </>
  );
}
