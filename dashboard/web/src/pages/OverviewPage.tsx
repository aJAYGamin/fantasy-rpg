import { ChevronDown } from "lucide-react";
import { type ReactNode, useId } from "react";
import { Link } from "react-router";
import { useGameConnected } from "../api/hooks";
import { Button, Card, Pill, Ring, type RingColour, Segmented, Tooltip } from "../components";
import { PageHeader } from "../shell/PageHeader";
import styles from "./OverviewPage.module.css";
import { WaitingForGame, WaitingPill } from "./WaitingForGame";

/** Why a quick action can't be used yet; shown in a tooltip, and read out as the button's description. */
const WHY_UNAVAILABLE = "Available once the game is running";

const DIFFICULTIES = [
  { value: "easy", label: "Easy" },
  { value: "normal", label: "Normal" },
  { value: "hard", label: "Hard" },
] as const;

const GAUGES: ReadonlyArray<{ label: string; colour: RingColour }> = [
  { label: "Party HP", colour: "am" },
  { label: "Party MP", colour: "aria" },
  { label: "Moves unlocked", colour: "am2" },
  { label: "Items carried", colour: "gold" },
];

/** A dash where a number will go, read as "no data yet" rather than as punctuation. */
function Dash() {
  return (
    <>
      <span aria-hidden="true">—</span>
      <span className="visually-hidden">No data yet</span>
    </>
  );
}

function MiniStat({ label }: { label: string }) {
  return (
    <div>
      <dt>{label}</dt>
      <dd>
        <Dash />
      </dd>
    </div>
  );
}

function NoData() {
  return <p className={styles.empty}>No data yet</p>;
}

/**
 * The Quick Actions, all shown but unavailable until the game runs. They stay focusable and say why on hover and on
 * keyboard focus (aria-disabled rather than disabled), and a press does nothing.
 */
function QuickActions() {
  const reasonId = useId();
  const stillWaiting = { unavailable: true, "aria-describedby": reasonId } as const;
  const withReason = (children: ReactNode, className?: string, align?: "end") => (
    <Tooltip text={WHY_UNAVAILABLE} className={className} align={align}>
      {children}
    </Tooltip>
  );

  return (
    <Card title="Quick Actions" actions={<Pill tone="am">Applies right away</Pill>}>
      {/* The tooltip is drawn only; this is what a screen reader hears for each control that points here. */}
      <span id={reasonId} className="visually-hidden">
        {WHY_UNAVAILABLE}
      </span>
      <div className={styles.actions}>
        {withReason(
          <Button variant="primary" className={styles.fill} {...stillWaiting}>
            Heal party + full resonance
          </Button>,
          styles.cell,
        )}
        {withReason(
          <Button className={styles.fill} {...stillWaiting}>
            Unlock all moves
          </Button>,
          styles.cell,
        )}
        {withReason(
          <Button className={styles.fill} {...stillWaiting}>
            Max out gold
          </Button>,
          styles.cell,
        )}
        {withReason(
          <Button className={styles.fill} {...stillWaiting}>
            Save the game now
          </Button>,
          styles.cell,
        )}
      </div>

      <div className={styles.teleport}>
        {withReason(
          // A select that can't open yet: stage 2 lists the saved spots.
          <button
            type="button"
            role="combobox"
            aria-label="Teleport to…"
            aria-haspopup="listbox"
            aria-expanded={false}
            aria-disabled="true"
            aria-describedby={reasonId}
            className={styles.select}
          >
            <span>Teleport to…</span>
            <ChevronDown aria-hidden="true" />
          </button>,
          styles.cell,
        )}
        {withReason(
          <Button className={styles.go} {...stillWaiting}>
            Go
          </Button>,
          undefined,
          // At the card's right edge: the bubble lines up with the button's right side instead of overflowing the page.
          "end",
        )}
      </div>

      <div className={styles.difficulty}>
        <span className={styles.difficultyLabel}>Difficulty</span>
        {withReason(
          <Segmented
            label="Difficulty"
            options={DIFFICULTIES}
            value={null}
            // Nothing can be chosen until the game is running.
            onChange={() => {}}
            unavailable
            aria-describedby={reasonId}
            className={styles.segmented}
          />,
          styles.cell,
        )}
      </div>

      {withReason(
        <Button variant="danger" className={styles.fill} {...stillWaiting}>
          Reset to before debugging
        </Button>,
        styles.reset,
      )}
      <p className={styles.note}>Quick actions skip the Apply step. They wait if you're in a battle or conversation.</p>
    </Card>
  );
}

/**
 * The Overview. With no game running, its numbers are dashes and its cards are empty frames (overview-v3's layout),
 * and the Game Status card says the game isn't running; the Quick Actions are shown but can't be used yet.
 */
export function OverviewPage() {
  // The one place on this page that polls the game's status; stage 2 fills the cards once it is connected.
  const connected = useGameConnected();
  return (
    <>
      <PageHeader
        title="Overview"
        crumbs={["Overview"]}
        right={
          <dl className={styles.mini}>
            <MiniStat label="Gold" />
            <MiniStat label="Party level" />
            <MiniStat label="Debug changes" />
          </dl>
        }
      />

      <div className={styles.row}>
        <Card
          title="Game Status"
          actions={connected ? undefined : <WaitingPill />}
          className={styles.status}
          bodyClassName={styles.statusBody}
          flush
        >
          {!connected && <WaitingForGame framed={false} />}
        </Card>
        <QuickActions />
      </div>

      <Card flush>
        <div className={styles.strip}>
          {GAUGES.map(({ label, colour }) => (
            <div key={label} className={styles.gauge}>
              <Ring percent={0} label="—" colour={colour} aria-label={label} valueText="No data yet" />
              <div>
                <div className={styles.gaugeLabel}>{label}</div>
                <div className={styles.gaugeValue}>No data yet</div>
              </div>
            </div>
          ))}
        </div>
      </Card>

      <div className={styles.row}>
        <Card
          title="Party"
          actions={
            <Link to="/party" className={styles.open}>
              Open Party <span aria-hidden="true">→</span>
            </Link>
          }
        >
          <NoData />
        </Card>
        <Card title="Debug Activity">
          <NoData />
        </Card>
      </div>
    </>
  );
}
