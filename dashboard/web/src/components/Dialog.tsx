import { X } from "lucide-react";
import { type KeyboardEvent, type MouseEvent, type PointerEvent, type ReactNode, useEffect, useId, useRef } from "react";
import { createPortal } from "react-dom";
import styles from "./Dialog.module.css";
import { IconButton } from "./IconButton";
import { tabbablesIn } from "./focusable";

export type DialogProps = {
  open: boolean;
  onClose: () => void;
  title: ReactNode;
  children: ReactNode;
  /** The buttons along the bottom, e.g. Cancel and the action. */
  footer?: ReactNode;
};

/**
 * A modal dialog over a dimmed page. Focus moves in when it opens (to the first control after the close
 * button), Tab and Shift+Tab stay inside, the app behind it (#root) is inert, Escape or a click on the dimmed
 * page closes it, and focus goes back to whatever had it before.
 */
export function Dialog({ open, ...rest }: DialogProps) {
  if (!open) return null;
  return createPortal(<OpenDialog {...rest} />, document.body);
}

function OpenDialog({ onClose, title, children, footer }: Omit<DialogProps, "open">) {
  const panelRef = useRef<HTMLDivElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);
  const pressedOverlay = useRef(false);
  const titleId = useId();

  useEffect(() => {
    const before = document.activeElement instanceof HTMLElement ? document.activeElement : null;
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
      before?.focus();
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
    <div className={styles.overlay} onPointerDown={onOverlayDown} onClick={onOverlayClick}>
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        tabIndex={-1}
        className={styles.panel}
        onKeyDown={onKeyDown}
      >
        <header className={styles.header}>
          <h2 id={titleId} className={styles.title}>
            {title}
          </h2>
          <IconButton label="Close" bordered={false} onClick={onClose}>
            <X />
          </IconButton>
        </header>
        <div ref={contentRef} className={styles.content}>
          <div className={styles.body}>{children}</div>
          {footer !== undefined && <footer className={styles.footer}>{footer}</footer>}
        </div>
      </div>
    </div>
  );
}
