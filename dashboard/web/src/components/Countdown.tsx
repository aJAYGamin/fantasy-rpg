import { useEffect, useLayoutEffect, useRef, useState } from "react";

const secondsUntil = (end: number) => Math.ceil(Math.max(0, end - Date.now()) / 1000);

/**
 * Whole seconds left until `until`, ticking exactly when the shown second changes so it never lags or skips.
 * Reaches 0 and stays there. It reads the clock afresh each tick, and again whenever the page becomes visible:
 * timers in a hidden tab run late (or stop while the computer sleeps), and the number must be right the moment
 * someone looks.
 */
export function useSecondsLeft(until: Date): number {
  const end = until.getTime();
  const [seconds, setSeconds] = useState(() => secondsUntil(end));
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    function tick() {
      clearTimeout(timer);
      const remaining = Math.max(0, end - Date.now());
      setSeconds(Math.ceil(remaining / 1000));
      if (remaining > 0) timer = setTimeout(tick, remaining % 1000 || 1000);
    }
    function onVisibilityChange() {
      if (document.visibilityState === "visible") tick();
    }
    tick();
    document.addEventListener("visibilitychange", onVisibilityChange);
    return () => {
      clearTimeout(timer);
      document.removeEventListener("visibilitychange", onVisibilityChange);
    };
  }, [end]);
  return seconds;
}

/** Whole seconds as m:ss ("4:06"); minutes keep counting past 59. */
function minutesAndSeconds(totalSeconds: number): string {
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}

export type CountdownProps = {
  until: Date;
  /** Called once when the time is reached (straight away if it already has). */
  onDone?: () => void;
  className?: string;
};

/** The time left until `until`, as m:ss, ticking each second (the lock screen's timer). */
export function Countdown({ until, onDone, className }: CountdownProps) {
  const seconds = useSecondsLeft(until);
  const end = until.getTime();
  const onDoneRef = useRef(onDone);
  const doneFor = useRef<number | null>(null);

  useLayoutEffect(() => {
    onDoneRef.current = onDone;
  });

  useEffect(() => {
    if (seconds === 0 && doneFor.current !== end) {
      doneFor.current = end;
      onDoneRef.current?.();
    }
  }, [seconds, end]);

  return (
    <span role="timer" className={className}>
      {minutesAndSeconds(seconds)}
    </span>
  );
}
