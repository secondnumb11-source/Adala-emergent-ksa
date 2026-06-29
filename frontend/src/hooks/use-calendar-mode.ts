import { useEffect, useState, useCallback } from "react";
import {
  gregorianToHijri,
  formatHijriAr,
  formatGregorianAr,
  getArabicWeekday,
  HIJRI_MONTHS_AR,
} from "@/lib/hijri";

export type CalendarMode = "gregorian" | "hijri";
const KEY = "lovable.calendar-mode.v1";
const EVT = "lovable:calendar-mode-change";

function read(): CalendarMode {
  if (typeof window === "undefined") return "gregorian";
  return (window.localStorage.getItem(KEY) as CalendarMode) || "gregorian";
}

export function useCalendarMode() {
  const [mode, setMode] = useState<CalendarMode>("gregorian");

  useEffect(() => {
    setMode(read());
    const handler = (e: Event) => {
      const m = (e as CustomEvent<CalendarMode>).detail;
      if (m) setMode(m);
    };
    window.addEventListener(EVT, handler);
    return () => window.removeEventListener(EVT, handler);
  }, []);

  const toggle = useCallback(() => {
    const next: CalendarMode = mode === "gregorian" ? "hijri" : "gregorian";
    window.localStorage.setItem(KEY, next);
    window.dispatchEvent(new CustomEvent(EVT, { detail: next }));
    setMode(next);
  }, [mode]);

  return { mode, toggle, setMode };
}

const timeFmt = new Intl.DateTimeFormat("ar-SA-u-nu-latn", { hour: "2-digit", minute: "2-digit", hour12: false });

export function formatDateByMode(input: string | Date | null | undefined, mode: CalendarMode, opts?: { withTime?: boolean; withWeekday?: boolean }): string {
  if (!input) return "—";
  const d = typeof input === "string" ? new Date(input) : input;
  if (isNaN(d.getTime())) return "—";
  const time = opts?.withTime ? ` · ${timeFmt.format(d)}` : "";
  const wd = opts?.withWeekday ? `${getArabicWeekday(d)} ` : "";
  if (mode === "hijri") {
    const h = gregorianToHijri(d);
    return `${wd}${h.d} ${HIJRI_MONTHS_AR[h.m - 1]} ${h.y}هـ${time}`;
  }
  return `${wd}${formatGregorianAr(d)}${time}`;
}
