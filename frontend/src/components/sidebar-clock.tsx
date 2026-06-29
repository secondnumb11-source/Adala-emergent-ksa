import { useEffect, useState } from "react";
import {
  formatGregorianAr,
  formatHijriAr,
  getArabicWeekday,
  gregorianToHijri,
} from "@/lib/hijri";
import { getClockParts } from "@/lib/clock-format";
import { loadSettings } from "@/lib/app-settings";

interface Props {
  collapsed?: boolean;
}

export function SidebarClock({ collapsed }: Props) {
  const [now, setNow] = useState<Date | null>(null);
  const [hour12, setHour12] = useState<boolean>(() => {
    try { return loadSettings().appearance.clockHour12 ?? true; } catch { return true; }
  });

  useEffect(() => {
    setNow(new Date());
    const id = setInterval(() => setNow(new Date()), 1000);
    const onChange = () => {
      try { setHour12(loadSettings().appearance.clockHour12 ?? true); } catch { /* noop */ }
    };
    window.addEventListener("lex:settings-changed", onChange);
    return () => {
      clearInterval(id);
      window.removeEventListener("lex:settings-changed", onChange);
    };
  }, []);

  if (!now) {
    return (
      <div className={`mx-2 mt-2 rounded-xl border border-sidebar-border/60 bg-gradient-to-br from-sidebar-accent/40 to-transparent ${collapsed ? "h-10" : "h-24"} animate-pulse`} />
    );
  }

  const { hh, mm, ampm } = getClockParts(now, hour12);
  const hijri = gregorianToHijri(now);

  // Phosphor / neon green
  const neon: React.CSSProperties = {
    color: "#39ff14",
    textShadow: "0 0 6px rgba(57,255,20,0.85), 0 0 14px rgba(57,255,20,0.55), 0 0 26px rgba(57,255,20,0.35)",
  };

  if (collapsed) {
    return (
      <div
        title={`${getArabicWeekday(now)} — ${formatHijriAr(hijri)} — ${formatGregorianAr(now)}`}
        className="mx-2 mt-2 grid place-items-center rounded-xl border border-gold/30 bg-black/40 py-2 font-mono text-[11px] font-bold shadow-inner"
        style={neon}
        data-testid="sidebar-clock-collapsed"
      >
        {mm}:{hh}
        {ampm && <span className="text-[8px] opacity-80">{ampm}</span>}
      </div>
    );
  }

  return (
    <div className="mx-3 mt-3 overflow-hidden rounded-2xl border border-gold/25 bg-gradient-to-br from-black/60 via-sidebar-accent/40 to-black/40 p-3 shadow-inner backdrop-blur-sm animate-fade-in">
      <div
        className="flex items-baseline justify-center gap-1 font-mono tabular-nums"
        style={neon}
        data-testid="sidebar-clock"
      >
        <span className="text-3xl font-black tracking-wider" data-testid="sidebar-clock-mm">{mm}</span>
        <span className="text-2xl font-bold animate-pulse">:</span>
        <span className="text-3xl font-black tracking-wider" data-testid="sidebar-clock-hh">{hh}</span>
        {ampm && <span className="text-sm font-bold mr-1 opacity-95">{ampm}</span>}
      </div>
      <div className="mt-1.5 text-center text-[11px] font-semibold text-sidebar-foreground/90">
        {getArabicWeekday(now)}
      </div>
      <div className="mt-1 space-y-0.5 text-center text-[10.5px] leading-tight text-sidebar-foreground/75">
        <div className="truncate">{formatHijriAr(hijri)}</div>
        <div className="truncate opacity-80">{formatGregorianAr(now)}</div>
      </div>
    </div>
  );
}
