import { useEffect, useState } from "react";

const secondsUntil = (end: number) => Math.ceil(Math.max(0, end - Date.now()) / 1000);

/**
 * Whole seconds left until `until`, ticking exactly when the second changes (the same schedule as Countdown, so the
 * ring and the number beside it agree). Reaches 0 and stays there.
 */
export function useSecondsLeft(until: Date): number {
  const end = until.getTime();
  const [seconds, setSeconds] = useState(() => secondsUntil(end));
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    function tick() {
      const remaining = Math.max(0, end - Date.now());
      setSeconds(Math.ceil(remaining / 1000));
      if (remaining > 0) timer = setTimeout(tick, remaining % 1000 || 1000);
    }
    tick();
    return () => clearTimeout(timer);
  }, [end]);
  return seconds;
}

const plural = (count: number, word: string) => `${count} ${word}${count === 1 ? "" : "s"}`;

/** A time in words for a screen reader: "4 minutes 6 seconds", "5 minutes", "59 seconds". */
export function spokenDuration(totalSeconds: number): string {
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  if (minutes === 0) return plural(seconds, "second");
  if (seconds === 0) return plural(minutes, "minute");
  return `${plural(minutes, "minute")} ${plural(seconds, "second")}`;
}
