import { type KeyboardEvent, type ReactNode, useRef } from "react";
import styles from "./Segmented.module.css";
import { cx } from "./cx";

export type SegmentedOption<T extends string> = { value: T; label: ReactNode };

export type SegmentedProps<T extends string> = {
  options: ReadonlyArray<SegmentedOption<T>>;
  /** The chosen option, or null while none is (the first option is then the Tab stop). */
  value: T | null;
  onChange: (value: T) => void;
  /** What is being chosen ("Appearance"), for screen readers. */
  label: string;
  disabled?: boolean;
  /**
   * Greyed and inert, yet still reachable so a tooltip can say why (a `disabled` option gets neither hover nor focus):
   * the options carry aria-disabled, press and arrow keys change nothing. Point `aria-describedby` at the reason; the
   * group and each option are described by it.
   */
  unavailable?: boolean;
  "aria-describedby"?: string;
  className?: string;
};

/**
 * One choice out of a few, side by side (overview-v3's difficulty .seg). A radio group: only the chosen option
 * is a Tab stop, and the arrow keys (plus Home / End) move the choice.
 */
export function Segmented<T extends string>({
  options,
  value,
  onChange,
  label,
  disabled,
  unavailable,
  "aria-describedby": describedBy,
  className,
}: SegmentedProps<T>) {
  const buttons = useRef<Array<HTMLButtonElement | null>>([]);
  const chosen = options.findIndex((option) => option.value === value);
  const tabStop = chosen === -1 ? 0 : chosen;

  function choose(index: number) {
    onChange(options[index].value);
    buttons.current[index]?.focus();
  }

  function onKeyDown(event: KeyboardEvent, index: number) {
    if (unavailable) return;
    const count = options.length;
    let next: number;
    switch (event.key) {
      case "ArrowRight":
      case "ArrowDown":
        next = (index + 1) % count;
        break;
      case "ArrowLeft":
      case "ArrowUp":
        next = (index - 1 + count) % count;
        break;
      case "Home":
        next = 0;
        break;
      case "End":
        next = count - 1;
        break;
      default:
        return;
    }
    event.preventDefault();
    choose(next);
  }

  return (
    <div
      role="radiogroup"
      aria-label={label}
      aria-describedby={describedBy}
      aria-disabled={disabled || unavailable || undefined}
      className={cx(styles.group, className)}
    >
      {options.map((option, index) => (
        <button
          key={option.value}
          ref={(button) => {
            buttons.current[index] = button;
          }}
          type="button"
          role="radio"
          aria-checked={index === chosen}
          aria-disabled={unavailable || undefined}
          // Some screen readers skip a group's description once focus is on an option, so an unavailable option carries it too.
          aria-describedby={unavailable ? describedBy : undefined}
          tabIndex={index === tabStop ? 0 : -1}
          disabled={disabled}
          className={styles.option}
          onClick={() => {
            if (!unavailable) onChange(option.value);
          }}
          onKeyDown={(event) => onKeyDown(event, index)}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}
