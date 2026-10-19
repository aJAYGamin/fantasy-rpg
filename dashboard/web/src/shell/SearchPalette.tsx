import { Dialog, Input } from "../components";
import styles from "./SearchPalette.module.css";
import { SEARCH_PLACEHOLDER } from "./TopBar";

export type SearchPaletteProps = { open: boolean; onClose: () => void };

// Stand-in until search arrives (Task 9 replaces this file); the top-bar box and ⌘K / Ctrl+K already open it.
export function SearchPalette({ open, onClose }: SearchPaletteProps) {
  return (
    <Dialog open={open} onClose={onClose} title="Search">
      <Input aria-label="Search" placeholder={SEARCH_PLACEHOLDER} autoComplete="off" spellCheck={false} />
      <p className={styles.note}>Results will show here.</p>
    </Dialog>
  );
}
