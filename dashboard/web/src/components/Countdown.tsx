import { useEffect, useLayoutEffect, useRef, useState } from "react";

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
  const end = until.getTime();
  const [left, setLeft] = useState(() => Math.max(0, end - Date.now()));
  const onDoneRef = useRef(onDone);
  const doneFor = useRef<number | null>(null);

  useLayoutEffect(() => {
    onDoneRef.current = onDone;
  });

  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    function tick() {
      const remaining = Math.max(0, end - Date.now());
      setLeft(remaining);
      if (remaining === 0) {
        if (doneFor.current !== end) {
          doneFor.current = end;
          onDoneRef.current?.();
        }
        return;
      }
      // Wake exactly when the shown second changes, so the display never lags or skips.
      timer = setTimeout(tick, remaining % 1000 || 1000);
    }
    tick();
    return () => clearTimeout(timer);
  }, [end]);

  return (
    <span role="timer" className={className}>
      {minutesAndSeconds(Math.ceil(left / 1000))}
    </span>
  );
}
