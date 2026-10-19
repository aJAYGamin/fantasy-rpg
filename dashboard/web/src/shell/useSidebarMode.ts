import { useEffect } from "react";
import type { Settings } from "../../../shared/src/api";
import { useSettings, useUpdateSettings } from "../api/hooks";

type SidebarMode = Settings["sidebar"];

// The last mode this browser saw, so a folded sidebar doesn't open and snap shut while the settings load.
const SIDEBAR_KEY = "amethyst-sidebar";

function storedMode(): SidebarMode {
  try {
    return localStorage.getItem(SIDEBAR_KEY) === "icons" ? "icons" : "expanded";
  } catch {
    return "expanded";
  }
}

/** Whether the sidebar is folded to icons (the account's `sidebar` setting), and a toggle that saves the change. */
export function useSidebarMode(): { collapsed: boolean; toggle: () => void } {
  const saved = useSettings().data?.sidebar;
  const update = useUpdateSettings();

  useEffect(() => {
    if (!saved) return;
    try {
      localStorage.setItem(SIDEBAR_KEY, saved);
    } catch {
      // Storage can be off (private windows); the setting itself is saved on the server.
    }
  }, [saved]);

  const mode = saved ?? storedMode();
  return {
    collapsed: mode === "icons",
    toggle: () => update.mutate({ sidebar: mode === "icons" ? "expanded" : "icons" }),
  };
}
