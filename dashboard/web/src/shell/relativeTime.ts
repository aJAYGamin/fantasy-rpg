import { useEffect, useState } from "react";

const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

/**
 * "Just now", "2 min ago", "3 hr ago", "1 day ago", and past a week a short date (with the year once it isn't this
 * one). `now` is the browser's clock; a time just ahead of it (the two clocks differ a little) reads as just now.
 */
export function relativeTime(iso: string, now: number): string {
  const then = Date.parse(iso);
  if (Number.isNaN(then)) return "";
  const elapsed = now - then;
  if (elapsed < MINUTE) return "Just now";
  if (elapsed < HOUR) return `${Math.floor(elapsed / MINUTE)} min ago`;
  if (elapsed < DAY) return `${Math.floor(elapsed / HOUR)} hr ago`;
  if (elapsed < 7 * DAY) {
    const days = Math.floor(elapsed / DAY);
    return days === 1 ? "1 day ago" : `${days} days ago`;
  }
  const date = new Date(then);
  const thisYear = date.getFullYear() === new Date(now).getFullYear();
  return date.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    ...(thisYear ? {} : { year: "numeric" }),
  });
}

/** The browser's clock, refreshed every `period` ms while the component is on screen, so times keep counting. */
export function useNow(period = 30_000): number {
  const [now, setNow] = useState(Date.now);
  useEffect(() => {
    // The clock may have moved on between the first render and now (and, on a laptop that slept, long since).
    setNow(Date.now());
    const timer = setInterval(() => setNow(Date.now()), period);
    return () => clearInterval(timer);
  }, [period]);
  return now;
}
