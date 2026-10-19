import { useCallback, useEffect, useRef, useState } from "react";
import { Outlet } from "react-router";
import styles from "./AppShell.module.css";
import { SearchPalette } from "./SearchPalette";
import { Sidebar } from "./Sidebar";
import { TopBar } from "./TopBar";
import { useSidebarMode } from "./useSidebarMode";

function onAMac(): boolean {
  const hints = navigator as Navigator & { userAgentData?: { platform?: string } };
  return /mac/i.test(hints.userAgentData?.platform || navigator.platform || "");
}

function isEditable(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  return (
    target instanceof HTMLInputElement ||
    target instanceof HTMLTextAreaElement ||
    target.isContentEditable ||
    target.closest('[contenteditable=""], [contenteditable="true"]') !== null
  );
}

/**
 * ⌘K, or Ctrl+K, opens search from anywhere on the page, even inside a text field. Not while another dialog is up
 * (it has the floor), and on a Mac Ctrl+K inside a text field is left alone: there it deletes to the end of the line.
 */
function useSearchShortcut(open: () => void): void {
  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      // The modifiers first: Chrome's autofill sends keydown events that carry no key at all.
      if (!(event.metaKey || event.ctrlKey) || event.altKey || event.shiftKey) return;
      if (event.key?.toLowerCase() !== "k") return;
      if (document.querySelector('[role="dialog"][aria-modal="true"]') !== null) return;
      if (event.ctrlKey && !event.metaKey && onAMac() && isEditable(event.target)) return;
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
