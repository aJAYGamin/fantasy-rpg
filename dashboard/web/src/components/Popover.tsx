import {
  type FocusEvent,
  type KeyboardEvent,
  type ReactNode,
  type RefObject,
  useCallback,
  useEffect,
  useId,
  useRef,
  useState,
} from "react";
import styles from "./Popover.module.css";
import { cx } from "./cx";
import { tabbablesIn } from "./focusable";

export type PopoverTriggerProps = {
  ref: RefObject<HTMLButtonElement | null>;
  onClick: () => void;
  "aria-expanded": boolean;
  "aria-controls": string | undefined;
  "aria-haspopup": "dialog" | "menu";
};

export type PopoverProps = {
  /** Draws the button that opens it; spread the props onto that button (Button and IconButton take them). */
  trigger: (props: PopoverTriggerProps) => ReactNode;
  /** The panel's contents; as a function it gets `close`, for an item that should shut the panel when picked. */
  children: ReactNode | ((close: () => void) => ReactNode);
  /** What the panel is, for screen readers ("Notifications"). */
  label: string;
  /** Which edge of the button the panel lines up with. */
  align?: "start" | "end";
  role?: "dialog" | "menu";
  className?: string;
};

/**
 * A panel that drops down from its button (the top bar's menus). It takes focus when it opens, and closes on
 * Escape, on a click outside it, or when Tab leaves it. Escape and `close` put focus back on the button.
 */
export function Popover({ trigger, children, label, align = "end", role = "dialog", className }: PopoverProps) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const panelRef = useRef<HTMLDivElement>(null);
  const panelId = useId();

  const close = useCallback(() => {
    setOpen(false);
    triggerRef.current?.focus();
  }, []);

  useEffect(() => {
    if (!open) return;
    const panel = panelRef.current;
    if (panel) (tabbablesIn(panel)[0] ?? panel).focus();

    function onPointerDown(event: PointerEvent) {
      const root = rootRef.current;
      if (!root || root.contains(event.target as Node)) return;
      // The click outside takes focus where it landed; only if focus was in the panel does it go back to the
      // button, so it isn't lost when the panel disappears.
      const focusWasInside = root.contains(document.activeElement);
      setOpen(false);
      if (focusWasInside) triggerRef.current?.focus();
    }
    document.addEventListener("pointerdown", onPointerDown);
    return () => document.removeEventListener("pointerdown", onPointerDown);
  }, [open]);

  function onKeyDown(event: KeyboardEvent) {
    if (open && event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      close();
    }
  }

  function onBlur(event: FocusEvent) {
    const next = event.relatedTarget as Node | null;
    // Focus leaving the window entirely (switching apps) is not leaving the panel.
    if (next === null && !document.hasFocus()) return;
    if (open && !rootRef.current?.contains(next)) setOpen(false);
  }

  return (
    <div ref={rootRef} className={styles.root} onKeyDown={onKeyDown} onBlur={onBlur}>
      {trigger({
        ref: triggerRef,
        onClick: () => setOpen((now) => !now),
        "aria-expanded": open,
        "aria-controls": open ? panelId : undefined,
        "aria-haspopup": role,
      })}
      {open && (
        <div
          ref={panelRef}
          id={panelId}
          role={role}
          aria-label={label}
          tabIndex={-1}
          className={cx(styles.panel, styles[align], className)}
        >
          {typeof children === "function" ? children(close) : children}
        </div>
      )}
    </div>
  );
}
