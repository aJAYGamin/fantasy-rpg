const TABBABLE = [
  "a[href]",
  "button:not([disabled])",
  'input:not([disabled]):not([type="hidden"])',
  "select:not([disabled])",
  "textarea:not([disabled])",
  "[tabindex]",
]
  .map((selector) => `${selector}:not([tabindex="-1"])`)
  .join(", ");

/** The elements inside `root` that Tab stops on, in order. */
export function tabbablesIn(root: HTMLElement): HTMLElement[] {
  return [...root.querySelectorAll<HTMLElement>(TABBABLE)];
}
