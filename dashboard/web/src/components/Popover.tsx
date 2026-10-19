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
  /** A menu opens from the arrow keys too: Down to its first item, Up to its last. */
  onKeyDown: (event: KeyboardEvent) => void;
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
  /**
   * "dialog" (default): a panel of ordinary controls, reached with Tab. "menu": a list of MenuItem / MenuLink
   * rows, reached with the arrow keys, Home and End, as menus are.
   */
  role?: "dialog" | "menu";
  className?: string;
};

const MENU_ITEMS = '[role="menuitem"], [role="menuitemradio"], [role="menuitemcheckbox"]';

function menuItemsIn(panel: HTMLElement): HTMLElement[] {
  return [...panel.querySelectorAll<HTMLElement>(MENU_ITEMS)];
}

/**
 * A panel that drops down from its button (the top bar's menus). It takes focus when it opens (a menu: its first
 * item), and closes on Escape, on a click outside it, or when Tab leaves it. Escape and `close` put focus back on
 * the button.
 */
export function Popover({ trigger, children, label, align = "end", role = "dialog", className }: PopoverProps) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const panelRef = useRef<HTMLDivElement>(null);
  // Which menu item takes the focus when the menu opens: the last one when it was opened with the Up arrow.
  const startAtLast = useRef(false);
  const panelId = useId();

  const close = useCallback(() => {
    setOpen(false);
    triggerRef.current?.focus();
  }, []);

  useEffect(() => {
    if (!open) return;
    const panel = panelRef.current;
    if (panel) {
      const items = role === "menu" ? menuItemsIn(panel) : tabbablesIn(panel);
      ((startAtLast.current ? items.at(-1) : items[0]) ?? panel).focus();
    }

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
  }, [open, role]);

  function onKeyDown(event: KeyboardEvent) {
    if (open && event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      close();
      return;
    }
    const panel = panelRef.current;
    if (role === "menu" && open && panel?.contains(event.target as Node)) moveInMenu(event, panel);
  }

  // The keys a menu answers to while the focus is on one of its items.
  function moveInMenu(event: KeyboardEvent, panel: HTMLElement) {
    const items = menuItemsIn(panel);
    const at = items.indexOf(document.activeElement as HTMLElement);
    let next: HTMLElement | undefined;
    if (event.key === "ArrowDown") next = items[(at + 1) % items.length];
    else if (event.key === "ArrowUp") next = at <= 0 ? items.at(-1) : items[at - 1];
    else if (event.key === "Home") next = items[0];
    else if (event.key === "End") next = items.at(-1);
    else if (event.key === " " && event.target instanceof HTMLAnchorElement) {
      // Space picks a menu item; a button does that by itself, a link only answers Enter.
      event.preventDefault();
      event.target.click();
      return;
    } else return;
    event.preventDefault();
    next?.focus();
  }

  function onTriggerKeyDown(event: KeyboardEvent) {
    if (role !== "menu" || (event.key !== "ArrowDown" && event.key !== "ArrowUp")) return;
    event.preventDefault();
    startAtLast.current = event.key === "ArrowUp";
    const panel = panelRef.current;
    if (open && panel) {
      const items = menuItemsIn(panel);
      (startAtLast.current ? items.at(-1) : items[0])?.focus();
    } else {
      setOpen(true);
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
        onClick: () => {
          startAtLast.current = false;
          setOpen((now) => !now);
        },
        onKeyDown: onTriggerKeyDown,
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
