import { NavLink, Navigate, useParams } from "react-router";
import { Card } from "../components";
import { cx } from "../components/cx";
import { PageHeader } from "../shell/PageHeader";
import styles from "./SettingsPage.module.css";
import { AccountSection } from "./settings/AccountSection";
import { AppearanceSection } from "./settings/AppearanceSection";
import { GameSection } from "./settings/GameSection";
import { NotificationsSection } from "./settings/NotificationsSection";
import { SettingsGate } from "./settings/SettingsGate";
import { SignInSection } from "./settings/SignInSection";
import { DEFAULT_SECTION, SECTIONS, type SectionSlug } from "./settings/sections";

function SectionBody({ slug }: { slug: SectionSlug }) {
  switch (slug) {
    case "appearance":
      return <SettingsGate>{(settings) => <AppearanceSection settings={settings} />}</SettingsGate>;
    case "account":
      return <AccountSection />;
    case "sign-in":
      return <SettingsGate>{(settings) => <SignInSection settings={settings} />}</SettingsGate>;
    case "game-connection":
      return <SettingsGate>{(settings) => <GameSection settings={settings} />}</SettingsGate>;
    case "notifications":
      return <SettingsGate>{(settings) => <NotificationsSection settings={settings} />}</SettingsGate>;
  }
}

/**
 * Settings: the list of sections at the left and the open one at the right. /settings, and a section that doesn't
 * exist, go to the first section (R31). Each change is saved as it is made; the password and the security answers
 * have buttons of their own.
 */
export function SettingsPage() {
  const { section } = useParams();
  const current = SECTIONS.find((candidate) => candidate.slug === section);
  if (!current) return <Navigate to={`/settings/${DEFAULT_SECTION}`} replace />;

  return (
    <>
      <PageHeader title="Settings" crumbs={["Settings"]} />
      <div className={styles.layout}>
        <Card flush className={styles.list}>
          <nav aria-label="Settings sections" className={styles.nav}>
            {SECTIONS.map(({ slug, label, icon: Icon }) => (
              <NavLink
                key={slug}
                to={`/settings/${slug}`}
                className={({ isActive }) => cx(styles.link, isActive && styles.open)}
              >
                <Icon aria-hidden="true" />
                {label}
              </NavLink>
            ))}
          </nav>
        </Card>
        <div className={styles.content}>
          <SectionBody slug={current.slug} />
        </div>
      </div>
    </>
  );
}
