const plural = (count: number, word: string) => `${count} ${word}${count === 1 ? "" : "s"}`;

/** A time in words for a screen reader: "4 minutes 6 seconds", "5 minutes", "59 seconds". */
export function spokenDuration(totalSeconds: number): string {
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  if (minutes === 0) return plural(seconds, "second");
  if (seconds === 0) return plural(minutes, "minute");
  return `${plural(minutes, "minute")} ${plural(seconds, "second")}`;
}
