import { X } from "lucide-react";
import { type KeyboardEvent, type MouseEvent, type PointerEvent, type ReactNode, useEffect, useId, useRef } from "react";
import { createPortal } from "react-dom";
import styles from "./Dialog.module.css";
import { IconButton } from "./IconButton";
import { cx } from "./cx";
import { tabbablesIn } from "./focusable";

export type DialogProps = {
  open: boolean;
  onClose: () => void;
  title: ReactNode;
  children: ReactNode;
  /** The buttons along the bottom, e.g. Cancel and the action. */
  footer?: ReactNode;
  /**
   * "palette": a sheet near the top of the page whose contents are their own header (a search field, results). The
   * title is still its accessible name, but isn't drawn, and there is no close button: Escape and a click on the
   * dimmed page close it.
   */
  variant?: "dialog" | "palette";
};

/**
 * The button that opened the popover `element` sits in (the one whose aria-controls names it, or an ancestor), if any.
 * Read while that popover is still open: it says aria-controls only then.
 */
function popoverOpenerOf(element: HTMLElement | null): HTMLElement | null {
  const openers = [...document.querySelectorAll<HTMLElement>("[aria-controls]")];
  for (let node = element; node !== null; node = node.parentElement) {
    const id = node.id;
    if (id === "") continue;
    const opener = openers.find((candidate) => candidate.getAttribute("aria-controls")?.split(/\s+/).includes(id));
    if (opener) return opener;
  }
  return null;
}

/**
 * A modal dialog over a dimmed page. Focus moves in when it opens (to the first control after the close
 * button), Tab and Shift+Tab stay inside, the app behind it (#root) is inert, Escape or a click on the dimmed
 * page closes it, and focus goes back to whatever had it before. If that is gone by then (it was in a popover,
 * which closed when the focus left it, as ⌘K from an open menu does), focus goes to the popover's button instead.
 */
export function Dialog({ open, ...rest }: DialogProps) {
  if (!open) return null;
  return createPortal(<OpenDialog {...rest} />, document.body);
}

function OpenDialog({ onClose, title, children, footer, variant = "dialog" }: Omit<DialogProps, "open">) {
  const palette = variant === "palette";
  const panelRef = useRef<HTMLDivElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);
  const pressedOverlay = useRef(false);
  const titleId = useId();

  useEffect(() => {
    const before = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const fallback = popoverOpenerOf(before);
    const panel = panelRef.current;
    const content = contentRef.current;
    const first = (content && tabbablesIn(content)[0]) ?? (panel && tabbablesIn(panel)[0]) ?? panel;
    first?.focus();

    // The page behind doesn't scroll, and can't be reached by screen readers or clicks, while the dialog is up.
    const html = document.documentElement;
    const overflow = html.style.overflow;
    html.style.overflow = "hidden";
    const app = document.getElementById("root");
    const appWasInert = app?.hasAttribute("inert") ?? false;
    app?.toggleAttribute("inert", true);
    return () => {
      html.style.overflow = overflow;
      app?.toggleAttribute("inert", appWasInert);
      // After the app is live again, or the focus can't land back on it.
      const back = before?.isConnected ? before : fallback?.isConnected ? fallback : null;
      back?.focus();
    };
  }, []);

  function onKeyDown(event: KeyboardEvent) {
    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      onClose();
      return;
    }
    if (event.key !== "Tab" || !panelRef.current) return;
    const stops = tabbablesIn(panelRef.current);
    if (stops.length === 0) {
      event.preventDefault();
      return;
    }
    const first = stops[0];
    const last = stops[stops.length - 1];
    const active = document.activeElement;
    if (event.shiftKey && (active === first || active === panelRef.current)) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && active === last) {
      event.preventDefault();
      first.focus();
    }
  }

  // Only a click that both starts and ends on the dimmed page closes it, so a drag out of a text field doesn't.
  const onOverlayDown = (event: PointerEvent) => {
    pressedOverlay.current = event.target === event.currentTarget;
  };
  const onOverlayClick = (event: MouseEvent) => {
    if (pressedOverlay.current && event.target === event.currentTarget) onClose();
    pressedOverlay.current = false;
  };

  return (
    <div
      className={cx(styles.overlay, palette && styles.paletteOverlay)}
      onPointerDown={onOverlayDown}
      onClick={onOverlayClick}
    >
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        tabIndex={-1}
        className={cx(styles.panel, palette && styles.palettePanel)}
        onKeyDown={onKeyDown}
      >
        {palette ? (
          <h2 id={titleId} className="visually-hidden">
            {title}
          </h2>
        ) : (
          <header className={styles.header}>
            <h2 id={titleId} className={styles.title}>
              {title}
            </h2>
            <IconButton label="Close" bordered={false} onClick={onClose}>
              <X />
            </IconButton>
          </header>
        )}
        <div ref={contentRef} className={styles.content}>
          <div className={cx(styles.body, palette && styles.paletteBody)}>{children}</div>
          {footer !== undefined && <footer className={styles.footer}>{footer}</footer>}
        </div>
      </div>
    </div>
  );
}
