import { LayoutDashboard, type LucideIcon, MapPin, Shield, ShoppingBag, Sword, Users } from "lucide-react";

export type NavItem = {
  label: string;
  path: string;
  icon: LucideIcon;
  /** A small tag after the label, e.g. "In development". */
  badge?: string;
};

export type NavGroup = { group: "OVERVIEW" | "DEBUG" | "ADMIN"; items: NavItem[] };

/** The sidebar's pages, in order. Settings is reached from the top bar and the account menu instead. */
export const NAV: NavGroup[] = [
  { group: "OVERVIEW", items: [{ label: "Overview", path: "/", icon: LayoutDashboard }] },
  {
    group: "DEBUG",
    items: [
      { label: "Party", path: "/party", icon: Users },
      { label: "Inventory", path: "/inventory", icon: ShoppingBag },
      { label: "Gear", path: "/gear", icon: Sword },
      { label: "Location", path: "/location", icon: MapPin },
    ],
  },
  { group: "ADMIN", items: [{ label: "Admin", path: "/admin", icon: Shield, badge: "In development" }] },
];
