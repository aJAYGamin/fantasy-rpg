import { useCallback, useEffect, useRef, useState } from "react";
import { Outlet } from "react-router";
import styles from "./AppShell.module.css";
import { SearchPalette } from "./SearchPalette";
import { Sidebar } from "./Sidebar";
import { TopBar } from "./TopBar";
import { useSidebarMode } from "./useSidebarMode";

/** ⌘K (Mac) or Ctrl+K, from anywhere on the page, even inside a text field. */
function useSearchShortcut(open: () => void): void {
  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key.toLowerCase() !== "k" || !(event.metaKey || event.ctrlKey) || event.altKey || event.shiftKey) {
        return;
      }
      // The browser's own ⌘K / Ctrl+K (its search bar) and the letter itself both stay out of it.
      event.preventDefault();
      open();
    }
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [open]);
}

/** The frame of every signed-in page: the sidebar, the top bar, and the page itself below the bar. */
export function AppShell() {
  const { collapsed, toggle } = useSidebarMode();
  const [searchOpen, setSearchOpen] = useState(false);
  const openSearch = useCallback(() => setSearchOpen(true), []);
  const mainRef = useRef<HTMLElement>(null);
  useSearchShortcut(openSearch);

  return (
    <div className={styles.shell}>
      {/* The first Tab stop: past the sidebar and the top bar, straight to the page. */}
      <a
        href="#content"
        className={styles.skip}
        onClick={(event) => {
          event.preventDefault();
          mainRef.current?.focus();
        }}
      >
        Skip to content
      </a>
      <Sidebar collapsed={collapsed} />
      <div className={styles.column}>
        <TopBar collapsed={collapsed} onToggleSidebar={toggle} onOpenSearch={openSearch} />
        <main ref={mainRef} id="content" tabIndex={-1} className={styles.page}>
          <Outlet />
        </main>
      </div>
      <SearchPalette open={searchOpen} onClose={() => setSearchOpen(false)} />
    </div>
  );
}
