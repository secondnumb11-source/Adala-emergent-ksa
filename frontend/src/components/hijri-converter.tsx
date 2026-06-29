import { useEffect, useMemo, useRef, useState } from "react";
import { CalendarRange, X, ArrowLeftRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { toast } from "sonner";
import {
  formatGregorianAr,
  formatHijriAr,
  getArabicWeekday,
  gregorianToHijri,
  hijriToGregorian,
  HIJRI_MONTHS_AR,
  GREGORIAN_MONTHS_AR,
} from "@/lib/hijri";

type Mode = "g2h" | "h2g";

export function HijriConverter() {
  const [open, setOpen] = useState(false);
  const [mode, setMode] = useState<Mode>("g2h");
  const panelRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const firstFieldRef = useRef<HTMLInputElement>(null);

  const today = useMemo(() => new Date(), []);
  const todayHijri = useMemo(() => gregorianToHijri(today), [today]);

  const [gy, setGy] = useState(today.getFullYear());
  const [gm, setGm] = useState(today.getMonth() + 1);
  const [gd, setGd] = useState(today.getDate());

  const [hy, setHy] = useState(todayHijri.y);
  const [hm, setHm] = useState(todayHijri.m);
  const [hd, setHd] = useState(todayHijri.d);

  const result = useMemo(() => {
    try {
      if (mode === "g2h") {
        const d = new Date(Date.UTC(gy, gm - 1, gd));
        if (isNaN(d.getTime())) return null;
        const h = gregorianToHijri(d);
        return {
          weekday: getArabicWeekday(d),
          primary: formatHijriAr(h),
          secondary: formatGregorianAr(d),
        };
      } else {
        const d = hijriToGregorian(hy, hm, hd);
        const h = gregorianToHijri(d);
        return {
          weekday: getArabicWeekday(d),
          primary: formatGregorianAr(d),
          secondary: formatHijriAr(h),
        };
      }
    } catch {
      return null;
    }
  }, [mode, gy, gm, gd, hy, hm, hd]);

  const swap = () => setMode((m) => (m === "g2h" ? "h2g" : "g2h"));

  const copyResult = async () => {
    if (!result) return;
    try {
      await navigator.clipboard.writeText(`${result.weekday} — ${result.primary}`);
      toast.success("تم نسخ التاريخ");
    } catch {
      toast.error("تعذر النسخ");
    }
  };

  // Focus management + Escape to close + focus trap
  useEffect(() => {
    if (!open) return;
    const prev = document.activeElement as HTMLElement | null;
    firstFieldRef.current?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.stopPropagation();
        setOpen(false);
        triggerRef.current?.focus();
      } else if (e.key === "Tab" && panelRef.current) {
        const focusables = panelRef.current.querySelectorAll<HTMLElement>(
          'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])',
        );
        if (focusables.length === 0) return;
        const first = focusables[0];
        const last = focusables[focusables.length - 1];
        const active = document.activeElement as HTMLElement | null;
        if (e.shiftKey && active === first) { e.preventDefault(); last.focus(); }
        else if (!e.shiftKey && active === last) { e.preventDefault(); first.focus(); }
      }
    };
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("keydown", onKey);
      prev?.focus?.();
    };
  }, [open]);

  return (
    <>
      <button
        ref={triggerRef}
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-label="محول التاريخ الهجري والميلادي"
        aria-expanded={open}
        aria-haspopup="dialog"
        title="محول التاريخ الهجري ↔ الميلادي"
        className="fixed bottom-6 left-24 z-40 grid h-11 w-11 place-items-center rounded-full bg-gradient-to-br from-emerald-500 to-emerald-700 text-white shadow-2xl shadow-emerald-500/30 ring-2 ring-emerald-300/50 transition-all hover:scale-110 hover:shadow-emerald-500/50 active:scale-95"
      >
        <CalendarRange className="h-5 w-5" />
      </button>

      {open && (
        <div
          ref={panelRef}
          role="dialog"
          aria-modal="false"
          aria-label="نافذة محول التاريخ الهجري والميلادي"
          className="fixed bottom-20 left-6 z-40 w-[min(360px,92vw)] overflow-hidden rounded-2xl border border-border bg-card shadow-2xl animate-fade-in"
          dir="rtl"
        >
          <div className="flex items-center justify-between gap-2 border-b border-border bg-gradient-to-l from-emerald-600/15 to-transparent px-4 py-3">
            <div className="flex items-center gap-2">
              <CalendarRange className="h-4 w-4 text-emerald-600" />
              <span className="text-sm font-bold">محول التاريخ</span>
            </div>
            <button
              onClick={() => { setOpen(false); triggerRef.current?.focus(); }}
              aria-label="إغلاق محول التاريخ"
              className="rounded p-1 text-muted-foreground hover:bg-accent focus:outline-none focus:ring-2 focus:ring-emerald-500"
            >
              <X className="h-4 w-4" />
            </button>
          </div>

          <div className="space-y-3 p-4">
            <div className="flex items-center justify-center gap-2">
              <span className={`text-xs font-semibold ${mode === "g2h" ? "text-emerald-600" : "text-muted-foreground"}`}>ميلادي</span>
              <Button type="button" size="icon" variant="outline" onClick={swap} className="h-8 w-8 rounded-full" title="عكس الاتجاه">
                <ArrowLeftRight className="h-4 w-4" />
              </Button>
              <span className={`text-xs font-semibold ${mode === "h2g" ? "text-emerald-600" : "text-muted-foreground"}`}>هجري</span>
            </div>

            {mode === "g2h" ? (
              <div className="grid grid-cols-3 gap-2">
                <Field label="اليوم">
                  <Input ref={firstFieldRef} type="number" min={1} max={31} value={gd} onChange={(e) => setGd(parseInt(e.target.value || "0", 10))} />
                </Field>
                <Field label="الشهر">
                  <select className="h-9 w-full rounded-md border border-input bg-background px-2 text-sm" value={gm} onChange={(e) => setGm(parseInt(e.target.value, 10))}>
                    {GREGORIAN_MONTHS_AR.map((n, i) => (
                      <option key={i} value={i + 1}>{n}</option>
                    ))}
                  </select>
                </Field>
                <Field label="السنة">
                  <Input type="number" min={1900} max={2200} value={gy} onChange={(e) => setGy(parseInt(e.target.value || "0", 10))} />
                </Field>
              </div>
            ) : (
              <div className="grid grid-cols-3 gap-2">
                <Field label="اليوم">
                  <Input ref={firstFieldRef} type="number" min={1} max={30} value={hd} onChange={(e) => setHd(parseInt(e.target.value || "0", 10))} />
                </Field>
                <Field label="الشهر">
                  <select className="h-9 w-full rounded-md border border-input bg-background px-2 text-sm" value={hm} onChange={(e) => setHm(parseInt(e.target.value, 10))}>
                    {HIJRI_MONTHS_AR.map((n, i) => (
                      <option key={i} value={i + 1}>{n}</option>
                    ))}
                  </select>
                </Field>
                <Field label="السنة">
                  <Input type="number" min={1300} max={1600} value={hy} onChange={(e) => setHy(parseInt(e.target.value || "0", 10))} />
                </Field>
              </div>
            )}

            <div className="rounded-xl border border-emerald-500/20 bg-gradient-to-br from-emerald-50/60 to-transparent p-3 text-center dark:from-emerald-950/30">
              {result ? (
                <>
                  <div className="text-[11px] font-semibold text-muted-foreground">{result.weekday}</div>
                  <div className="mt-1 text-base font-extrabold text-emerald-700 dark:text-emerald-400">{result.primary}</div>
                  <div className="mt-0.5 text-[11px] text-muted-foreground">{result.secondary}</div>
                </>
              ) : (
                <div className="text-xs text-muted-foreground">أدخل تاريخاً صحيحاً</div>
              )}
            </div>

            <div className="flex items-center justify-between gap-2">
              <Button
                type="button" variant="outline" size="sm" onClick={copyResult}
                onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); copyResult(); } }}
                aria-label="نسخ التاريخ المحوّل"
                className="flex-1"
              >نسخ</Button>
              <Button
                type="button"
                variant="ghost"
                size="sm"
                onClick={() => {
                  const d = new Date();
                  setGy(d.getFullYear()); setGm(d.getMonth() + 1); setGd(d.getDate());
                  const h = gregorianToHijri(d);
                  setHy(h.y); setHm(h.m); setHd(h.d);
                }}
                className="flex-1"
              >
                اليوم
              </Button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1 block text-[11px] font-semibold text-muted-foreground">{label}</span>
      {children}
    </label>
  );
}
