import { Bell, Gamepad2, KeyRound, type LucideIcon, Palette, UserRound } from "lucide-react";

export type SectionSlug = "appearance" | "account" | "sign-in" | "game-connection" | "notifications";

export type Section = { slug: SectionSlug; label: string; icon: LucideIcon };

/** The Settings sections, in the order the list shows them. The slugs are the page's addresses (ruling R2). */
export const SECTIONS: readonly Section[] = [
  { slug: "appearance", label: "Appearance", icon: Palette },
  { slug: "account", label: "Account", icon: UserRound },
  { slug: "sign-in", label: "Sign-in", icon: KeyRound },
  { slug: "game-connection", label: "Game connection", icon: Gamepad2 },
  { slug: "notifications", label: "Notifications", icon: Bell },
];

export const DEFAULT_SECTION: SectionSlug = "appearance";
