import { useEffect, useState, useCallback, useRef } from "react";
import { supabase } from "@/integrations/supabase/client";

export type DashboardCardPref = { id: string; visible: boolean };

export interface UserPreferences {
  sidebar_width: number;
  sidebar_collapsed: boolean;
  dashboard_cards: DashboardCardPref[];
}

export const DEFAULT_PREFERENCES: UserPreferences = {
  sidebar_width: 288,
  sidebar_collapsed: false,
  dashboard_cards: [],
};

const LS_KEY = "lex:user-prefs:v1";

function readLocal(): Partial<UserPreferences> {
  if (typeof window === "undefined") return {};
  try {
    const raw = window.localStorage.getItem(LS_KEY);
    return raw ? JSON.parse(raw) : {};
  } catch { return {}; }
}

function writeLocal(p: UserPreferences) {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(LS_KEY, JSON.stringify({
      sidebar_width: p.sidebar_width,
      sidebar_collapsed: p.sidebar_collapsed,
    }));
  } catch { /* noop */ }
}

export function useUserPreferences() {
  const [prefs, setPrefs] = useState<UserPreferences>(() => ({ ...DEFAULT_PREFERENCES, ...readLocal() }));
  const [loaded, setLoaded] = useState(false);
  const userIdRef = useRef<string | null>(null);
  const saveTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const reload = useCallback(async () => {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) { setLoaded(true); return; }
    userIdRef.current = user.id;
    const { data } = await supabase
      .from("user_preferences")
      .select("sidebar_width, sidebar_collapsed, dashboard_cards")
      .eq("user_id", user.id)
      .maybeSingle();
    if (data) {
      const merged: UserPreferences = {
        sidebar_width: data.sidebar_width ?? DEFAULT_PREFERENCES.sidebar_width,
        sidebar_collapsed: data.sidebar_collapsed ?? false,
        dashboard_cards: (data.dashboard_cards as DashboardCardPref[]) ?? [],
      };
      setPrefs(merged);
      writeLocal(merged);
    } else {
      setPrefs((prev) => ({ ...DEFAULT_PREFERENCES, ...readLocal(), dashboard_cards: prev.dashboard_cards }));
    }
    setLoaded(true);
  }, []);

  useEffect(() => { void reload(); }, [reload]);

  const persist = useCallback((next: UserPreferences, immediate = false) => {
    writeLocal(next);
    const uid = userIdRef.current;
    if (!uid) return;
    if (saveTimer.current) clearTimeout(saveTimer.current);
    const run = () =>
      supabase.from("user_preferences").upsert({
        user_id: uid,
        sidebar_width: next.sidebar_width,
        sidebar_collapsed: next.sidebar_collapsed,
        dashboard_cards: next.dashboard_cards as never,
      }, { onConflict: "user_id" }).then(() => {});
    if (immediate) run();
    else saveTimer.current = setTimeout(run, 400);
  }, []);

  const update = useCallback((patch: Partial<UserPreferences>) => {
    setPrefs((prev) => {
      const next = { ...prev, ...patch };
      persist(next);
      return next;
    });
  }, [persist]);

  const replaceAll = useCallback((next: UserPreferences) => {
    setPrefs(next);
    persist(next, true);
  }, [persist]);

  const resetDefaults = useCallback(() => {
    replaceAll(DEFAULT_PREFERENCES);
  }, [replaceAll]);

  return { prefs, update, replaceAll, resetDefaults, reload, loaded };
}
