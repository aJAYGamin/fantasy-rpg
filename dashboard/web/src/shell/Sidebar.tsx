import { useId, useState } from "react";
import { NavLink } from "react-router";
import { PRODUCT_NAME } from "../../../shared/src/constants";
import { Tooltip } from "../components";
import { cx } from "../components/cx";
import styles from "./Sidebar.module.css";
import { NAV, type NavGroup, type NavItem } from "./nav";

/** The groups and pages whose label contains `query` (any capitals); groups left empty drop out. */
function matching(query: string): NavGroup[] {
  const wanted = query.trim().toLocaleLowerCase();
  return NAV.map((group) => ({
    ...group,
    items: group.items.filter((item) => item.label.toLocaleLowerCase().includes(wanted)),
  })).filter((group) => group.items.length > 0);
}

/**
 * The deep-plum sidebar: brand, a filter that narrows the pages, and the page groups. Folded (`collapsed`), it is
 * a 72 px rail of icons, each named for screen readers and labelled by a tooltip.
 */
export function Sidebar({ collapsed }: { collapsed: boolean }) {
  const [filter, setFilter] = useState("");
  const groups = matching(collapsed ? "" : filter);
  const id = useId();

  return (
    <nav aria-label="Main" className={cx(styles.sidebar, collapsed && styles.collapsed)}>
      <div className={styles.brand}>
        <span className={styles.gem} aria-hidden="true" />
        <span className={collapsed ? "visually-hidden" : styles.name}>{PRODUCT_NAME}</span>
        {!collapsed && <small className={styles.dev}>dev</small>}
      </div>

      {!collapsed && (
        <div className={styles.filterRow}>
          <input
            className={styles.filter}
            type="text"
            placeholder="Filter"
            aria-label="Filter pages"
            autoComplete="off"
            spellCheck={false}
            value={filter}
            onChange={(event) => setFilter(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Escape" && filter !== "") {
                event.preventDefault();
                setFilter("");
              }
            }}
          />
        </div>
      )}

      {groups.map((group) => (
        <div key={group.group} className={styles.group}>
          <p id={`${id}-${group.group}`} className={collapsed ? "visually-hidden" : styles.groupLabel}>
            {group.group}
          </p>
          <ul className={styles.list} aria-labelledby={`${id}-${group.group}`}>
            {group.items.map((item) => (
              <li key={item.path}>
                <SidebarLink item={item} collapsed={collapsed} />
              </li>
            ))}
          </ul>
        </div>
      ))}

      {/* Always present, so screen readers hear it when the filter empties the list. */}
      <p role="status" className={styles.empty}>
        {groups.length === 0 ? "No pages match" : ""}
      </p>
    </nav>
  );
}

function SidebarLink({ item, collapsed }: { item: NavItem; collapsed: boolean }) {
  const badgeId = useId();
  const Icon = item.icon;
  const link = (
    <NavLink
      to={item.path}
      end={item.path === "/"}
      // The badge describes the page rather than naming it, so the link is "Admin" folded or not.
      aria-describedby={item.badge ? badgeId : undefined}
      className={({ isActive }) => cx(styles.item, isActive && styles.active)}
    >
      <Icon className={styles.icon} />
      <span className={collapsed ? "visually-hidden" : styles.label}>{item.label}</span>
      {item.badge && (
        <span id={badgeId} className={styles.badge} aria-hidden="true" hidden={collapsed}>
          {item.badge}
        </span>
      )}
    </NavLink>
  );
  if (!collapsed) return link;
  const tip = item.badge ? `${item.label} · ${item.badge}` : item.label;
  return (
    <Tooltip text={tip} side="right" className={styles.tipAnchor}>
      {link}
    </Tooltip>
  );
}
