import { Card, Pill } from "../components";
import { cx } from "../components/cx";
import styles from "./WaitingForGame.module.css";

/**
 * "○ Waiting for the game", for a page header or the Overview's Game Status card. The ○ is decoration, so it is hidden
 * from screen readers.
 */
export function WaitingPill() {
  return (
    <Pill tone="warn">
      <span aria-hidden="true">○</span> Waiting for the game
    </Pill>
  );
}

export type WaitingForGameProps = {
  /**
   * True (the default): a card of its own, for a Debug page. False: just the message, for a place inside a card that
   * is already there (the Overview's Game Status), where its heading sits one level lower.
   */
  framed?: boolean;
};

/** What a page shows while the game isn't running. The page decides when (it is the one that polls the status). */
export function WaitingForGame({ framed = true }: WaitingForGameProps) {
  const Heading = framed ? "h2" : "h3";
  const message = (
    <div className={cx(styles.message, !framed && styles.inCard)}>
      <span className={styles.gem} aria-hidden="true" />
      <Heading className={styles.heading}>
        <span className={styles.star} aria-hidden="true">
          ✦
        </span>{" "}
        The game isn't running{" "}
        <span className={styles.star} aria-hidden="true">
          ✦
        </span>
      </Heading>
      <p className={styles.text}>Start it from Godot and this page will connect on its own.</p>
      <p className={styles.status}>Waiting for the game · checking every few seconds</p>
    </div>
  );

  return framed ? (
    <Card flush className={styles.card}>
      {message}
    </Card>
  ) : (
    message
  );
}
