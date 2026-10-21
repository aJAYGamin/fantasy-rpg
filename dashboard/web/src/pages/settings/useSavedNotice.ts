import { useCallback, useEffect, useRef, useState } from "react";

/** How long "Saved" stays up. */
export const SAVED_MS = 2_000;

/** Whether "Saved" is showing, and `flash`, which shows it for a moment. Another flash starts the moment over. */
export function useSavedNotice(): { saved: boolean; flash: () => void } {
  const [saved, setSaved] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  // A save can finish after the section has been left; it has nothing left to tell.
  const mounted = useRef(true);

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      clearTimeout(timer.current);
    };
  }, []);

  const flash = useCallback(() => {
    if (!mounted.current) return;
    clearTimeout(timer.current);
    setSaved(true);
    timer.current = setTimeout(() => setSaved(false), SAVED_MS);
  }, []);

  return { saved, flash };
}
