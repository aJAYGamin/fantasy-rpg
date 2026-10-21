import { ChevronDown } from "lucide-react";
import { Fragment, type ReactNode, useId } from "react";
import { Link } from "react-router";
import { useGameConnected } from "../api/hooks";
import { Button, Card, Pill, Ring, type RingColor, Segmented, Tooltip } from "../components";
import { usePageTitle } from "../pageTitle";
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

const GAUGES: ReadonlyArray<{ label: string; color: RingColor }> = [
  { label: "Party HP", color: "am" },
  { label: "Party MP", color: "aria" },
  { label: "Moves unlocked", color: "am2" },
  { label: "Items carried", color: "gold" },
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

/** The one-click buttons at the top of Quick Actions, in order. */
const ONE_CLICK: ReadonlyArray<{ label: string; variant?: "primary" }> = [
  { label: "Heal party + full resonance", variant: "primary" },
  { label: "Unlock all moves" },
  { label: "Max out gold" },
  { label: "Save the game now" },
];

/**
 * The Quick Actions. While the game isn't running every control is shown but unavailable: it stays focusable and says
 * why on hover and on keyboard focus (aria-disabled rather than disabled), and a press does nothing. Once the game is
 * connected they are plain controls; stage 2 gives each its action.
 */
function QuickActions({ connected }: { connected: boolean }) {
  const reasonId = useId();
  const waiting = !connected;
  const unavailable = waiting ? ({ unavailable: true, "aria-describedby": reasonId } as const) : {};
  // The wrapper puts the tooltip on a waiting control; the control sits in the same box either way.
  const gate = (children: ReactNode, { className, align }: { className?: string; align?: "end" } = {}) =>
    waiting ? (
      <Tooltip text={WHY_UNAVAILABLE} className={className} align={align}>
        {children}
      </Tooltip>
    ) : (
      <span className={className}>{children}</span>
    );

  return (
    <Card title="Quick Actions" actions={<Pill tone="am">Applies right away</Pill>}>
      {/* The tooltip is drawn only; this is what a screen reader hears for each control that points here. */}
      {waiting && (
        <span id={reasonId} className="visually-hidden">
          {WHY_UNAVAILABLE}
        </span>
      )}
      <div className={styles.actions}>
        {ONE_CLICK.map(({ label, variant }) => (
          <Fragment key={label}>
            {gate(
              <Button variant={variant} className={styles.fill} {...unavailable}>
                {label}
              </Button>,
              { className: styles.cell },
            )}
          </Fragment>
        ))}
      </div>

      <div className={styles.teleport}>
        {gate(
          // A select that can't open yet: stage 2 lists the saved spots.
          <button
            type="button"
            role="combobox"
            aria-label="Teleport to…"
            aria-haspopup="listbox"
            aria-expanded={false}
            aria-disabled={waiting || undefined}
            aria-describedby={waiting ? reasonId : undefined}
            className={styles.select}
          >
            <span>Teleport to…</span>
            <ChevronDown aria-hidden="true" />
          </button>,
          { className: styles.cell },
        )}
        {gate(
          <Button className={styles.go} {...unavailable}>
            Go
          </Button>,
          // At the card's right edge: the bubble lines up with the button's right side instead of overflowing the page.
          { align: "end" },
        )}
      </div>

      <div className={styles.difficulty}>
        <span className={styles.difficultyLabel}>Difficulty</span>
        {gate(
          <Segmented
            label="Difficulty"
            options={DIFFICULTIES}
            value={null}
            // Nothing is chosen yet: stage 2 reads the game's difficulty and changes it.
            onChange={() => {}}
            unavailable={waiting}
            aria-describedby={waiting ? reasonId : undefined}
            className={styles.segmented}
          />,
          { className: styles.cell },
        )}
      </div>

      {gate(
        <Button variant="danger" className={styles.fill} {...unavailable}>
          Reset to before debugging
        </Button>,
        { className: styles.reset },
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
  usePageTitle("Overview");
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
        <QuickActions connected={connected} />
      </div>

      <Card flush>
        <div className={styles.strip}>
          {GAUGES.map(({ label, color }) => (
            <div key={label} className={styles.gauge}>
              <Ring percent={0} label="—" color={color} aria-label={label} valueText="No data yet" />
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
