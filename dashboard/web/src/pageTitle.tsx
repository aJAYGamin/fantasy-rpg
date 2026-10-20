import { type ReactNode, createContext, useCallback, useContext, useEffect, useRef, useState } from "react";
import { PRODUCT_NAME } from "../../shared/src/constants";

// Inside the shell, hears each title a page sets so it can be read out (see PageAnnouncer).
const TitleListener = createContext<((title: string) => void) | null>(null);

/**
 * Titles the browser tab "<page> · Amethyst Dashboard", e.g. "Party" or "Account · Settings". Null while a page is
 * only passed through on its way to another (a redirect), so nothing is set or read out for it.
 */
export function usePageTitle(page: string | null): void {
  const heard = useContext(TitleListener);
  useEffect(() => {
    if (page === null) return;
    const title = `${page} · ${PRODUCT_NAME}`;
    document.title = title;
    heard?.(title);
  }, [page, heard]);
}

/**
 * The shell's one live region. A browser reads a page's title as it loads, but not when the app moves to another
 * page by itself, so this reads the new title out, politely and without moving the focus. The shell's first page isn't
 * read: that is the one the person has just arrived at.
 */
export function PageAnnouncer({ children }: { children: ReactNode }) {
  const [announcement, setAnnouncement] = useState("");
  const last = useRef<string | null>(null);
  const heard = useCallback((title: string) => {
    // A title set again unchanged (a page drawn twice) is no news.
    if (last.current !== null && title !== last.current) setAnnouncement(title);
    last.current = title;
  }, []);
  return (
    <TitleListener.Provider value={heard}>
      {children}
      {/* Always there, even empty: a screen reader only reads a change inside a live region that already exists. */}
      <div role="status" className="visually-hidden" data-testid="page-announcer">
        {announcement}
      </div>
    </TitleListener.Provider>
  );
}
