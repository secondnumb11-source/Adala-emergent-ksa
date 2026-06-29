import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useMemo, useRef, useState } from "react";
import {
  Settings as SettingsIcon, Library, Save, RotateCcw, ExternalLink,
  Building2, Palette, LayoutDashboard, Tag, KeyRound, CalendarSync,
  CloudUpload, Plug, Plus, Trash2, Eye, EyeOff, Copy, ChevronUp,
  ChevronDown, Upload, Download, Image as ImageIcon, RefreshCw, Sparkles,
  Bell, Activity, ScrollText, ShieldCheck,
} from "lucide-react";
import { Link } from "@tanstack/react-router";

import { NotificationPrefsSection } from "@/components/notification-prefs-section";
import { toast } from "sonner";
import { PageHeader } from "@/components/section-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { Slider } from "@/components/ui/slider";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from "@/components/ui/select";
import { LAWS, loadLibraryUrls, saveLibraryUrls, type LawId } from "@/lib/legal-library";
import {
  loadSettings, patchSettings, resetSettings, saveSettings,
  THEME_PRESETS, type AppSettings, type ThemePreset, type ColorMode,
} from "@/lib/app-settings";
import { useUserPreferences } from "@/hooks/use-user-preferences";

export const Route = createFileRoute("/_authenticated/app/settings")({
  component: SettingsPage,
});

/* The dashboard card catalog — used for show/hide & reordering controls */
const DASHBOARD_CARDS: { id: string; label: string }[] = [
  { id: "kpis",         label: "بطاقات المؤشرات الرئيسية" },
  { id: "timeline",     label: "الخط الزمني للقضايا" },
  { id: "sessions",     label: "الجلسات القادمة" },
  { id: "tasks",        label: "المهام النشطة" },
  { id: "alerts",       label: "تنبيهات المهل" },
  { id: "ai",           label: "أدوات الذكاء الاصطناعي" },
  { id: "najiz",        label: "حالة ربط ناجز" },
  { id: "documents",    label: "المستندات الحديثة" },
  { id: "clients",      label: "نشاط العملاء" },
  { id: "employees",    label: "حضور الموظفين" },
  { id: "logs",         label: "سجل العمليات" },
  { id: "library",      label: "المكتبة القانونية المختصرة" },
];

function SettingsPage() {
  const [settings, setSettings] = useState<AppSettings>(() => loadSettings());

  useEffect(() => {
    const onChange = () => setSettings(loadSettings());
    window.addEventListener("lex:settings-changed", onChange);
    return () => window.removeEventListener("lex:settings-changed", onChange);
  }, []);

  const update = <K extends keyof AppSettings>(section: K, patch: Partial<AppSettings[K]>) => {
    setSettings(patchSettings(section, patch));
  };

  return (
    <>
      <PageHeader icon={SettingsIcon} title="الإعدادات" subtitle="تخصيص كامل لمنصة العدالة" />

      {/* Cards removed: "قائمة التعديلات" / "تشخيص النظام" / "سجل التدقيق" (per request). */}

      <Tabs defaultValue="office" className="mt-6">
        <TabsList className="flex flex-wrap gap-1 h-auto p-1">
          <TabsTrigger value="office" className="gap-2"><Building2 className="h-4 w-4" />الهوية والترويسة</TabsTrigger>
          <TabsTrigger value="appearance" className="gap-2"><Palette className="h-4 w-4" />المظهر والثيمات</TabsTrigger>
          <TabsTrigger value="dashboard" className="gap-2"><LayoutDashboard className="h-4 w-4" />لوحة البيانات</TabsTrigger>
          <TabsTrigger value="labels" className="gap-2"><Tag className="h-4 w-4" />المسميات والوظائف</TabsTrigger>
          <TabsTrigger value="integrations" className="gap-2"><Plug className="h-4 w-4" />التكاملات</TabsTrigger>
          <TabsTrigger value="calendar" className="gap-2"><CalendarSync className="h-4 w-4" />تقويم خارجي</TabsTrigger>
          <TabsTrigger value="backup" className="gap-2"><CloudUpload className="h-4 w-4" />نسخ احتياطي</TabsTrigger>
          <TabsTrigger value="library" className="gap-2"><Library className="h-4 w-4" />روابط المكتبة</TabsTrigger>
          <TabsTrigger value="notifications" className="gap-2"><Bell className="h-4 w-4" />تفضيلات الإشعارات</TabsTrigger>
          <TabsTrigger value="system-check" className="gap-2"><ShieldCheck className="h-4 w-4" />فحص جاهزية النظام</TabsTrigger>
        </TabsList>

        <TabsContent value="office" className="mt-6"><OfficeSection s={settings.office} onChange={(p) => update("office", p)} /></TabsContent>
        <TabsContent value="appearance" className="mt-6"><AppearanceSection s={settings.appearance} onChange={(p) => update("appearance", p)} /></TabsContent>
        <TabsContent value="dashboard" className="mt-6"><DashboardSection s={settings.dashboard} onChange={(p) => update("dashboard", p)} /></TabsContent>
        <TabsContent value="labels" className="mt-6"><LabelsSection s={settings.labels} onChange={(p) => update("labels", p)} /></TabsContent>
        <TabsContent value="integrations" className="mt-6"><IntegrationsSection s={settings.integrations} onChange={(p) => update("integrations", p)} /></TabsContent>
        <TabsContent value="calendar" className="mt-6"><CalendarSection s={settings.calendar} onChange={(p) => update("calendar", p)} /></TabsContent>
        <TabsContent value="backup" className="mt-6"><BackupSection s={settings.backup} onChange={(p) => update("backup", p)} full={settings} setFull={setSettings} /></TabsContent>
        <TabsContent value="library" className="mt-6"><LibraryUrlsSection /></TabsContent>
        <TabsContent value="notifications" className="mt-6"><NotificationPrefsSection /></TabsContent>
        <TabsContent value="system-check" className="mt-6">
          <Card className="p-6 text-center">
            <ShieldCheck className="h-10 w-10 mx-auto text-emerald-600" />
            <p className="mt-3 font-bold text-lg">فحص جاهزية النظام</p>
            <p className="text-sm text-muted-foreground mt-1">انتقل إلى صفحة الفحص الشاملة للتحقق من جميع المكونات.</p>
            <Button asChild className="mt-4">
              <Link to="/app/system-check">فتح صفحة الفحص</Link>
            </Button>
          </Card>
        </TabsContent>
      </Tabs>

      <div className="mt-8 flex justify-end">
        <Button
          variant="outline"
          onClick={() => {
            if (confirm("إعادة تعيين جميع الإعدادات إلى الافتراضي؟")) {
              setSettings(resetSettings());
              toast.success("تمت إعادة الإعدادات للافتراضي");
            }
          }}
          className="gap-2"
        >
          <RotateCcw className="h-4 w-4" /> إعادة تعيين جميع الإعدادات
        </Button>
      </div>
    </>
  );
}

/* ============================================================
   1) Office Identity & Header
   ============================================================ */
function OfficeSection({ s, onChange }: { s: AppSettings["office"]; onChange: (p: Partial<AppSettings["office"]>) => void }) {
  const fileRef = useRef<HTMLInputElement>(null);

  const onLogo = (file: File | undefined) => {
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      onChange({ logoDataUrl: String(reader.result) });
      toast.success("تم تحديث الشعار");
    };
    reader.readAsDataURL(file);
  };

  return (
    <Card className="card-3d border-none p-6 space-y-6">
      <Header icon={Building2} title="هوية المكتب وترويسة المستندات" subtitle="تُستخدم على جميع الفواتير والتقارير والسندات الصادرة" />

      <div className="grid md:grid-cols-[200px_1fr] gap-6">
        <div className="space-y-3">
          <Label>شعار المكتب</Label>
          <div className="aspect-square rounded-2xl border bg-muted/30 grid place-items-center overflow-hidden">
            {s.logoDataUrl ? (
              <img src={s.logoDataUrl} alt="logo" className="object-contain w-full h-full" />
            ) : (
              <ImageIcon className="h-10 w-10 text-muted-foreground" />
            )}
          </div>
          <div className="flex gap-2">
            <Button size="sm" variant="outline" onClick={() => fileRef.current?.click()} className="flex-1 gap-2"><Upload className="h-3.5 w-3.5" />رفع</Button>
            {s.logoDataUrl && (
              <Button size="sm" variant="outline" onClick={() => onChange({ logoDataUrl: "" })}><Trash2 className="h-3.5 w-3.5" /></Button>
            )}
          </div>
          <input ref={fileRef} type="file" accept="image/*" hidden onChange={(e) => onLogo(e.target.files?.[0])} />
        </div>

        <div className="grid sm:grid-cols-2 gap-4">
          <Field label="اسم المكتب (عربي)" value={s.arabicName} onChange={(v) => onChange({ arabicName: v })} />
          <Field label="Office name (English)" value={s.officeName} onChange={(v) => onChange({ officeName: v })} ltr />
          <Field label="الرقم الضريبي (VAT)" value={s.taxNumber} onChange={(v) => onChange({ taxNumber: v })} ltr />
          <Field label="رقم السجل التجاري" value={s.crNumber} onChange={(v) => onChange({ crNumber: v })} ltr />
          <Field label="رقم الهاتف" value={s.phone} onChange={(v) => onChange({ phone: v })} ltr />
          <Field label="البريد الإلكتروني" value={s.email} onChange={(v) => onChange({ email: v })} ltr />
          <Field label="الموقع الإلكتروني" value={s.website} onChange={(v) => onChange({ website: v })} ltr />
          <Field label="نص الترخيص" value={s.licenseText} onChange={(v) => onChange({ licenseText: v })} placeholder="ترخيص ممارسة المهنة رقم..." />
          <div className="sm:col-span-2">
            <Label className="text-xs">العنوان الكامل</Label>
            <Textarea value={s.address} onChange={(e) => onChange({ address: e.target.value })} rows={2} className="mt-1" />
          </div>
        </div>
      </div>

      <div className="grid md:grid-cols-2 gap-4">
        <div>
          <Label className="text-xs">HTML ترويسة مخصصة (اختياري)</Label>
          <Textarea dir="ltr" value={s.headerHtml} onChange={(e) => onChange({ headerHtml: e.target.value })} rows={4} className="mt-1 font-mono text-[11px]" placeholder="<header>…</header>" />
        </div>
        <div>
          <Label className="text-xs">HTML تذييل مخصص (اختياري)</Label>
          <Textarea dir="ltr" value={s.footerHtml} onChange={(e) => onChange({ footerHtml: e.target.value })} rows={4} className="mt-1 font-mono text-[11px]" placeholder="<footer>…</footer>" />
        </div>
      </div>

      <label className="flex items-start gap-3 rounded-xl border bg-muted/30 p-3 cursor-pointer">
        <input
          type="checkbox"
          className="mt-1 h-4 w-4 accent-gold"
          checked={!!s.printHighContrast}
          onChange={(e) => onChange({ printHighContrast: e.target.checked })}
          aria-describedby="print-hc-desc"
        />
        <div className="flex-1">
          <div className="text-sm font-bold">تباين مرتفع عند الطباعة</div>
          <div id="print-hc-desc" className="text-[11px] text-muted-foreground mt-0.5 leading-relaxed">
            يرفع حدّة تباين النصوص والخطوط والجداول في طباعة الفواتير وسندات القبض والصرف لضمان وضوح أقصى عند الطباعة الورقية أو حفظ PDF.
          </div>
        </div>
      </label>

      <DocPreview s={s} />
    </Card>
  );
}

function DocPreview({ s }: { s: AppSettings["office"] }) {
  return (
    <div className="rounded-2xl border bg-white text-slate-900 p-6">
      <div className="text-xs text-muted-foreground mb-3">معاينة الترويسة</div>
      <div className="flex items-start justify-between gap-4 pb-4 border-b">
        {s.logoDataUrl ? <img src={s.logoDataUrl} alt="" className="h-16 w-16 object-contain" /> : <div className="h-16 w-16 rounded bg-slate-100" />}
        <div className="text-center flex-1">
          <h3 className="text-lg font-bold">{s.arabicName || "اسم المكتب"}</h3>
          {s.officeName && <p className="text-xs text-slate-500" dir="ltr">{s.officeName}</p>}
          {s.licenseText && <p className="text-[11px] text-slate-500 mt-1">{s.licenseText}</p>}
        </div>
        <div className="text-[11px] text-slate-600 text-left" dir="ltr">
          {s.taxNumber && <div>VAT: {s.taxNumber}</div>}
          {s.crNumber && <div>CR: {s.crNumber}</div>}
          {s.phone && <div>{s.phone}</div>}
          {s.email && <div>{s.email}</div>}
        </div>
      </div>
    </div>
  );
}

/* ============================================================
   2) Appearance & Themes
   ============================================================ */
function AppearanceSection({ s, onChange }: { s: AppSettings["appearance"]; onChange: (p: Partial<AppSettings["appearance"]>) => void }) {
  return (
    <div className="space-y-6">
      <Card className="card-3d border-none p-6 space-y-6">
        <Header icon={Palette} title="نمط الألوان والثيم" subtitle="اختر نمطاً جاهزاً أو خصّص الألوان يدوياً" />

        <div>
          <Label className="text-xs mb-2 block">الوضع</Label>
          <div className="flex gap-2">
            {(["light", "dark", "system"] as ColorMode[]).map((m) => (
              <Button key={m} size="sm" variant={s.mode === m ? "default" : "outline"} onClick={() => onChange({ mode: m })}>
                {m === "light" ? "فاتح" : m === "dark" ? "داكن" : "حسب النظام"}
              </Button>
            ))}
          </div>
        </div>

        <div>
          <Label className="text-xs mb-2 block">النمط المسبق</Label>
          <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
            {(Object.keys(THEME_PRESETS) as ThemePreset[]).map((p) => {
              const pr = THEME_PRESETS[p];
              const active = s.preset === p;
              return (
                <button
                  key={p}
                  onClick={() => onChange({ preset: p, customAccent: pr.accent, sidebarTint: pr.sidebar })}
                  className={`rounded-xl border p-3 text-right transition ${active ? "ring-2 ring-[var(--app-accent)]" : "hover:bg-accent/40"}`}
                >
                  <div className="flex items-center gap-2 mb-2">
                    <span className="h-6 w-6 rounded-full border" style={{ background: pr.sidebar }} />
                    <span className="h-6 w-6 rounded-full border" style={{ background: pr.accent }} />
                  </div>
                  <div className="text-sm font-bold">{pr.label}</div>
                </button>
              );
            })}
          </div>
        </div>

        <div className="grid sm:grid-cols-2 gap-4">
          <ColorPicker label="لون التمييز المخصص" value={s.customAccent} onChange={(v) => onChange({ customAccent: v })} />
          <ColorPicker label="لون الشريط الجانبي" value={s.sidebarTint} onChange={(v) => onChange({ sidebarTint: v })} />
        </div>
      </Card>

      <Card className="card-3d border-none p-6 space-y-6">
        <Header icon={Sparkles} title="الكروت والظلال والحركة" />
        <SliderRow label="زاوية انحراف الكروت (Radius)" min={0.25} max={2} step={0.05} value={s.radiusRem} unit="rem" onChange={(v) => onChange({ radiusRem: v })} />
        <SliderRow label="عمق وارتفاع الظلال" min={0} max={1.5} step={0.05} value={s.shadowDepth} onChange={(v) => onChange({ shadowDepth: v })} />
        <SliderRow label="شفافية خلفية الكروت" min={0.4} max={1} step={0.02} value={s.cardOpacity} onChange={(v) => onChange({ cardOpacity: v })} />
        <SliderRow label="حجم خط الواجهة" min={0.85} max={1.3} step={0.05} value={s.fontScale ?? 1} unit="x" onChange={(v) => onChange({ fontScale: v })} />
        <div className="flex items-center justify-between rounded-xl border p-3">
          <div>
            <div className="text-sm font-bold">التأثيرات الحركية التفاعلية</div>
            <div className="text-xs text-muted-foreground">تشغيل/إيقاف جميع الانتقالات والحركات</div>
          </div>
          <Switch checked={s.animationsEnabled} onCheckedChange={(v) => onChange({ animationsEnabled: v })} />
        </div>
        <div className="flex items-center justify-between rounded-xl border p-3">
          <div>
            <div className="text-sm font-bold">تأثيرات الـ 3D والرسوم المتقدمة</div>
            <div className="text-xs text-muted-foreground">
              كامل: كل التأثيرات • مخفف (افتراضي): يعطل 3D الثقيلة والحركات المستمرة • إيقاف: أخف وأسرع
            </div>
          </div>
          <div className="flex items-center gap-1 rounded-lg border p-1 text-xs font-bold">
            {(["full", "lite", "off"] as const).map((m) => (
              <button
                key={m}
                type="button"
                onClick={() => onChange({ effectsMode: m })}
                className={`px-3 py-1 rounded-md transition-colors ${
                  (s.effectsMode ?? "lite") === m ? "bg-gold text-background" : "hover:bg-accent"
                }`}
              >
                {m === "full" ? "كامل" : m === "lite" ? "مخفف" : "إيقاف"}
              </button>
            ))}
          </div>
        </div>
        <div className="flex items-center justify-between rounded-xl border p-3">
          <div>
            <div className="text-sm font-bold">نظام عرض ساعة الشريط الجانبي</div>
            <div className="text-xs text-muted-foreground">
              {s.clockHour12 ? "12 ساعة مع AM/PM" : "24 ساعة (00–23)"}
            </div>
          </div>
          <div className="flex items-center gap-2 text-xs font-bold">
            <span className={s.clockHour12 ? "opacity-50" : "text-gold"}>24h</span>
            <Switch checked={s.clockHour12} onCheckedChange={(v) => onChange({ clockHour12: v })} />
            <span className={s.clockHour12 ? "text-gold" : "opacity-50"}>12h</span>
          </div>
        </div>
      </Card>
    </div>
  );
}

function ColorPicker({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  return (
    <div>
      <Label className="text-xs">{label}</Label>
      <div className="mt-1 flex gap-2">
        <input type="color" value={value} onChange={(e) => onChange(e.target.value)} className="h-10 w-14 rounded-lg border bg-transparent cursor-pointer" />
        <Input dir="ltr" value={value} onChange={(e) => onChange(e.target.value)} className="font-mono text-xs" />
      </div>
    </div>
  );
}

function SliderRow({ label, min, max, step, value, unit, onChange }: { label: string; min: number; max: number; step: number; value: number; unit?: string; onChange: (v: number) => void }) {
  return (
    <div>
      <div className="flex items-center justify-between mb-2">
        <Label className="text-xs">{label}</Label>
        <span className="text-xs font-mono text-muted-foreground">{value.toFixed(2)}{unit ? ` ${unit}` : ""}</span>
      </div>
      <Slider min={min} max={max} step={step} value={[value]} onValueChange={([v]) => onChange(v)} />
    </div>
  );
}

/* ============================================================
   3) Dashboard module visibility + reordering
   ============================================================ */
function DashboardSection({ s, onChange }: { s: AppSettings["dashboard"]; onChange: (p: Partial<AppSettings["dashboard"]>) => void }) {
  const { prefs, update: updatePrefs } = useUserPreferences();

  const ordered = useMemo(() => {
    const known = new Set(DASHBOARD_CARDS.map((c) => c.id));
    const ord = s.cardOrder.filter((id) => known.has(id));
    const rest = DASHBOARD_CARDS.filter((c) => !ord.includes(c.id)).map((c) => c.id);
    return [...ord, ...rest];
  }, [s.cardOrder]);

  const move = (id: string, dir: -1 | 1) => {
    const idx = ordered.indexOf(id);
    if (idx < 0) return;
    const target = idx + dir;
    if (target < 0 || target >= ordered.length) return;
    const next = [...ordered];
    [next[idx], next[target]] = [next[target], next[idx]];
    onChange({ cardOrder: next });
    // mirror into cloud-synced prefs so dashboard picks it up
    updatePrefs({
      dashboard_cards: next.map((cid) => ({ id: cid, visible: !s.hiddenCards.includes(cid) })),
    });
  };

  const toggle = (id: string) => {
    const hidden = s.hiddenCards.includes(id)
      ? s.hiddenCards.filter((x) => x !== id)
      : [...s.hiddenCards, id];
    onChange({ hiddenCards: hidden });
    updatePrefs({
      dashboard_cards: ordered.map((cid) => ({ id: cid, visible: !hidden.includes(cid) })),
    });
  };

  return (
    <div className="space-y-6">
      <Card className="card-3d border-none p-6 space-y-4">
        <Header icon={Sparkles} title="الفرز والإخفاء التلقائي الذكي" subtitle="إخفاء الصناديق الفارغة من لوحة البيانات تلقائياً" />
        <div className="flex items-center justify-between rounded-xl border p-3">
          <div>
            <div className="text-sm font-bold">تفعيل التصفية الذكية</div>
            <div className="text-xs text-muted-foreground">يُخفي الوحدات التي لا تحتوي بيانات نشطة بدلاً من عرض صناديق فارغة</div>
          </div>
          <Switch checked={s.smartHideEmpty} onCheckedChange={(v) => onChange({ smartHideEmpty: v })} />
        </div>
      </Card>

      <Card className="card-3d border-none p-6 space-y-4">
        <Header icon={LayoutDashboard} title="ترتيب وإظهار كروت لوحة البيانات" subtitle="استخدم أزرار الصعود والهبوط للترتيب اليدوي، أو السحب والإفلات من لوحة التحكم" />
        <div className="space-y-2">
          {ordered.map((id, i) => {
            const card = DASHBOARD_CARDS.find((c) => c.id === id);
            if (!card) return null;
            const hidden = s.hiddenCards.includes(id);
            return (
              <div key={id} className="flex items-center gap-2 rounded-xl border bg-card p-3">
                <span className="text-xs font-mono text-muted-foreground w-6">{i + 1}</span>
                <div className="flex-1">
                  <div className="text-sm font-semibold">{card.label}</div>
                  <code className="text-[10px] text-muted-foreground">{id}</code>
                </div>
                <Button size="icon" variant="ghost" disabled={i === 0} onClick={() => move(id, -1)} title="أعلى"><ChevronUp className="h-4 w-4" /></Button>
                <Button size="icon" variant="ghost" disabled={i === ordered.length - 1} onClick={() => move(id, 1)} title="أسفل"><ChevronDown className="h-4 w-4" /></Button>
                <Button size="icon" variant="ghost" onClick={() => toggle(id)} title={hidden ? "إظهار" : "إخفاء"}>
                  {hidden ? <EyeOff className="h-4 w-4 text-muted-foreground" /> : <Eye className="h-4 w-4" />}
                </Button>
              </div>
            );
          })}
        </div>
        <p className="text-[11px] text-muted-foreground">يُحفظ الترتيب لكل مستخدم ويتزامن عبر الأجهزة (جدول user_preferences).</p>
      </Card>
    </div>
  );
}

/* ============================================================
   4) Labels / Job functions
   ============================================================ */
function LabelsSection({ s, onChange }: { s: AppSettings["labels"]; onChange: (p: Partial<AppSettings["labels"]>) => void }) {
  const [newJob, setNewJob] = useState("");

  return (
    <Card className="card-3d border-none p-6 space-y-6">
      <Header icon={Tag} title="المسميات والوظائف" subtitle="تعديل التسميات الظاهرة في جميع شاشات المنصة" />

      <div className="grid sm:grid-cols-2 gap-4">
        <Field label="مسمى الموظف (مفرد)" value={s.employeeSingular} onChange={(v) => onChange({ employeeSingular: v })} />
        <Field label="مسمى الموظفين (جمع)" value={s.employeePlural} onChange={(v) => onChange({ employeePlural: v })} />
        <Field label="مسمى العميل (مفرد)" value={s.clientSingular} onChange={(v) => onChange({ clientSingular: v })} />
        <Field label="مسمى العملاء (جمع)" value={s.clientPlural} onChange={(v) => onChange({ clientPlural: v })} />
      </div>

      <div>
        <Label className="text-xs mb-2 block">الوظائف المتاحة</Label>
        <div className="flex flex-wrap gap-2 mb-3">
          {s.jobTitles.map((j, i) => (
            <Badge key={`${j}-${i}`} variant="secondary" className="gap-2 py-1.5 px-3">
              {j}
              <button onClick={() => onChange({ jobTitles: s.jobTitles.filter((_, idx) => idx !== i) })} className="hover:text-destructive">
                <Trash2 className="h-3 w-3" />
              </button>
            </Badge>
          ))}
        </div>
        <div className="flex gap-2">
          <Input value={newJob} onChange={(e) => setNewJob(e.target.value)} placeholder="إضافة وظيفة جديدة..." />
          <Button onClick={() => { if (newJob.trim()) { onChange({ jobTitles: [...s.jobTitles, newJob.trim()] }); setNewJob(""); } }} className="gap-2">
            <Plus className="h-4 w-4" />إضافة
          </Button>
        </div>
      </div>
    </Card>
  );
}

/* ============================================================
   5) Integrations (WhatsApp, Najiz, ZATCA, SMTP, importer, per-employee)
   ============================================================ */
function IntegrationsSection({ s, onChange }: { s: AppSettings["integrations"]; onChange: (p: Partial<AppSettings["integrations"]>) => void }) {
  const [newKey, setNewKey] = useState({ employeeId: "", label: "", key: "" });

  return (
    <div className="space-y-6">
      <Card className="card-3d border-none p-6 space-y-4">
        <Header icon={Plug} title="واتساب للأعمال" />
        <div className="grid sm:grid-cols-2 gap-4">
          <SecretField label="WhatsApp API Token" value={s.whatsappToken} onChange={(v) => onChange({ whatsappToken: v })} />
          <Field label="Phone Number ID" value={s.whatsappPhoneId} onChange={(v) => onChange({ whatsappPhoneId: v })} ltr />
        </div>
      </Card>

      <Card className="card-3d border-none p-6 space-y-4">
        <Header icon={Plug} title="بوابة ناجز" />
        <div className="grid sm:grid-cols-2 gap-4">
          <SecretField label="Najiz API Key" value={s.najizApiKey} onChange={(v) => onChange({ najizApiKey: v })} />
          <Field label="Client ID" value={s.najizClientId} onChange={(v) => onChange({ najizClientId: v })} ltr />
        </div>
      </Card>

      <Card className="card-3d border-none p-6 space-y-4">
        <Header icon={Plug} title="ZATCA — الفوترة الإلكترونية" />
        <div className="grid sm:grid-cols-2 gap-4">
          <Field label="Seller ID" value={s.zatcaSellerId} onChange={(v) => onChange({ zatcaSellerId: v })} ltr />
          <SecretField label="Certificate (Base64)" value={s.zatcaCertB64} onChange={(v) => onChange({ zatcaCertB64: v })} />
        </div>
      </Card>

      <Card className="card-3d border-none p-6 space-y-4">
        <Header icon={Plug} title="خادم البريد الإلكتروني (SMTP)" />
        <div className="grid sm:grid-cols-2 gap-4">
          <Field label="SMTP Host" value={s.smtpHost} onChange={(v) => onChange({ smtpHost: v })} ltr placeholder="smtp.example.com" />
          <Field label="SMTP Port" value={String(s.smtpPort)} onChange={(v) => onChange({ smtpPort: Number(v) || 587 })} ltr />
          <Field label="Username" value={s.smtpUser} onChange={(v) => onChange({ smtpUser: v })} ltr />
          <SecretField label="Password" value={s.smtpPass} onChange={(v) => onChange({ smtpPass: v })} />
          <Field label="From Address" value={s.smtpFrom} onChange={(v) => onChange({ smtpFrom: v })} ltr placeholder="no-reply@office.com" />
        </div>
      </Card>

      <Card className="card-3d border-none p-6 space-y-4">
        <Header icon={Plug} title="مفاتيح الاستيراد وسحب البيانات الخارجي" subtitle="عند ربط المنصة مع أي أداة سحب بيانات أخرى" />
        <div className="grid sm:grid-cols-2 gap-4">
          <Field label="Base URL" value={s.importApiBaseUrl} onChange={(v) => onChange({ importApiBaseUrl: v })} ltr />
          <SecretField label="Bearer Token" value={s.importApiToken} onChange={(v) => onChange({ importApiToken: v })} />
        </div>
      </Card>

      <Card className="card-3d border-none p-6 space-y-4">
        <Header icon={KeyRound} title="مفاتيح ربط مخصصة لكل موظف" />
        <div className="grid sm:grid-cols-3 gap-2">
          <Input value={newKey.employeeId} onChange={(e) => setNewKey({ ...newKey, employeeId: e.target.value })} placeholder="معرف الموظف" dir="ltr" />
          <Input value={newKey.label} onChange={(e) => setNewKey({ ...newKey, label: e.target.value })} placeholder="الوصف" />
          <div className="flex gap-2">
            <Input value={newKey.key} onChange={(e) => setNewKey({ ...newKey, key: e.target.value })} placeholder="المفتاح" dir="ltr" />
            <Button size="icon" onClick={() => {
              if (!newKey.employeeId || !newKey.key) return;
              onChange({ employeeKeys: [...s.employeeKeys, newKey] });
              setNewKey({ employeeId: "", label: "", key: "" });
            }}><Plus className="h-4 w-4" /></Button>
          </div>
        </div>
        <div className="space-y-2">
          {s.employeeKeys.length === 0 && <p className="text-xs text-muted-foreground">لا توجد مفاتيح مضافة بعد.</p>}
          {s.employeeKeys.map((k, i) => (
            <div key={i} className="flex items-center gap-2 rounded-xl border p-3">
              <code className="text-xs flex-1" dir="ltr">{k.employeeId} · {k.label}</code>
              <code className="text-xs font-mono opacity-60" dir="ltr">{k.key.slice(0, 8)}…</code>
              <Button size="icon" variant="ghost" onClick={() => onChange({ employeeKeys: s.employeeKeys.filter((_, idx) => idx !== i) })}>
                <Trash2 className="h-4 w-4" />
              </Button>
            </div>
          ))}
        </div>
        <p className="text-[11px] text-muted-foreground">
          ⓘ المفاتيح الحساسة الإنتاجية يُفضّل تخزينها في أسرار Lovable Cloud من «الإعدادات → الأسرار». الحقول أعلاه مفيدة للاختبار وحفظ المرجع محلياً.
        </p>
      </Card>
    </div>
  );
}

/* ============================================================
   6) Calendar sync
   ============================================================ */
function CalendarSection({ s, onChange }: { s: AppSettings["calendar"]; onChange: (p: Partial<AppSettings["calendar"]>) => void }) {
  return (
    <div className="space-y-6">
      {(["google", "apple", "microsoft"] as const).map((provider) => {
        const cfg = s[provider];
        const label = provider === "google" ? "تقويم Google" : provider === "apple" ? "تقويم Apple" : "تقويم Microsoft 365";
        return (
          <Card key={provider} className="card-3d border-none p-6 space-y-4">
            <div className="flex items-center justify-between">
              <Header icon={CalendarSync} title={label} />
              <Switch checked={cfg.enabled} onCheckedChange={(v) => onChange({ [provider]: { ...cfg, enabled: v } } as any)} />
            </div>
            {provider === "apple" ? (
              <div className="grid sm:grid-cols-2 gap-4">
                <Field label="Apple ID" value={(cfg as any).appleId} onChange={(v) => onChange({ apple: { ...s.apple, appleId: v } } as any)} ltr />
                <SecretField label="App-Specific Password" value={(cfg as any).appPassword} onChange={(v) => onChange({ apple: { ...s.apple, appPassword: v } } as any)} />
              </div>
            ) : (
              <div className="grid sm:grid-cols-2 gap-4">
                {provider === "microsoft" && (
                  <Field label="Tenant ID" value={(cfg as any).tenantId} onChange={(v) => onChange({ microsoft: { ...s.microsoft, tenantId: v } } as any)} ltr />
                )}
                <Field label="Client ID" value={(cfg as any).clientId} onChange={(v) => onChange({ [provider]: { ...cfg, clientId: v } } as any)} ltr />
                <SecretField label="Refresh Token" value={(cfg as any).refreshToken} onChange={(v) => onChange({ [provider]: { ...cfg, refreshToken: v } } as any)} />
              </div>
            )}
          </Card>
        );
      })}
    </div>
  );
}

/* ============================================================
   7) Backup & cloud sync
   ============================================================ */
function BackupSection({ s, onChange, full, setFull }: { s: AppSettings["backup"]; onChange: (p: Partial<AppSettings["backup"]>) => void; full: AppSettings; setFull: (s: AppSettings) => void }) {
  const exportNow = () => {
    const blob = new Blob([JSON.stringify(full, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url; a.download = `al-adalah-settings-${new Date().toISOString().slice(0, 10)}.json`;
    a.click(); URL.revokeObjectURL(url);
    onChange({ lastBackupAt: new Date().toISOString() });
    toast.success("تم تصدير نسخة احتياطية");
  };
  const importFile = (file: File | undefined) => {
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      try {
        const next = JSON.parse(String(reader.result)) as AppSettings;
        saveSettings(next);
        setFull(loadSettings());
        toast.success("تم استيراد الإعدادات");
      } catch { toast.error("ملف غير صالح"); }
    };
    reader.readAsText(file);
  };

  return (
    <Card className="card-3d border-none p-6 space-y-6">
      <Header icon={CloudUpload} title="النسخ الاحتياطي ومزامنة السحابة" />

      <div className="flex items-center justify-between rounded-xl border p-3">
        <div>
          <div className="text-sm font-bold">نسخ احتياطي تلقائي</div>
          <div className="text-xs text-muted-foreground">يقوم بإنشاء نسخة احتياطية دورياً وحفظها لدى المزود المحدد</div>
        </div>
        <Switch checked={s.autoBackup} onCheckedChange={(v) => onChange({ autoBackup: v })} />
      </div>

      <div className="grid sm:grid-cols-2 gap-4">
        <div>
          <Label className="text-xs">دورية النسخ (أيام)</Label>
          <Input type="number" min={1} max={30} value={s.frequencyDays} onChange={(e) => onChange({ frequencyDays: Number(e.target.value) || 7 })} className="mt-1" />
        </div>
        <div>
          <Label className="text-xs">مزود السحابة</Label>
          <Select value={s.cloudProvider} onValueChange={(v) => onChange({ cloudProvider: v as AppSettings["backup"]["cloudProvider"] })}>
            <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="none">بدون (محلي فقط)</SelectItem>
              <SelectItem value="gdrive">Google Drive</SelectItem>
              <SelectItem value="onedrive">OneDrive</SelectItem>
              <SelectItem value="dropbox">Dropbox</SelectItem>
              <SelectItem value="s3">Amazon S3</SelectItem>
            </SelectContent>
          </Select>
        </div>
        {s.cloudProvider !== "none" && (
          <div className="sm:col-span-2">
            <SecretField label="رمز الوصول (Access Token)" value={s.cloudToken} onChange={(v) => onChange({ cloudToken: v })} />
          </div>
        )}
      </div>

      <div className="flex flex-wrap gap-2">
        <Button onClick={exportNow} className="gap-2"><Download className="h-4 w-4" />تصدير الآن</Button>
        <label className="inline-flex">
          <input type="file" accept="application/json" hidden onChange={(e) => importFile(e.target.files?.[0])} />
          <Button asChild variant="outline" className="gap-2"><span><Upload className="h-4 w-4" />استيراد من ملف</span></Button>
        </label>
        {s.lastBackupAt && (
          <span className="text-xs text-muted-foreground self-center">آخر نسخة: {new Date(s.lastBackupAt).toLocaleString("ar-SA")}</span>
        )}
      </div>
    </Card>
  );
}

/* ============================================================
   9) Legal library URLs (kept from previous version)
   ============================================================ */
function LibraryUrlsSection() {
  const [urls, setUrls] = useState<Record<LawId, string>>(() => loadLibraryUrls());
  const [dirty, setDirty] = useState(false);

  useEffect(() => { setUrls(loadLibraryUrls()); }, []);

  const update = (id: LawId, value: string) => { setUrls((p) => ({ ...p, [id]: value })); setDirty(true); };
  const onSave = () => { saveLibraryUrls(urls); setDirty(false); toast.success("تم حفظ روابط الأنظمة"); };
  const onReset = () => {
    const def = Object.fromEntries(LAWS.map((l) => [l.id, l.defaultUrl])) as Record<LawId, string>;
    setUrls(def); setDirty(true);
  };

  return (
    <Card className="card-3d border-none p-6">
      <div className="flex flex-wrap items-start gap-4 justify-between">
        <Header icon={Library} title="روابط أنظمة المكتبة القانونية" subtitle="الرابط الذي يُفتح عند الضغط على كل نظام" />
        <div className="flex gap-2">
          <Button variant="outline" size="sm" onClick={onReset}><RotateCcw className="h-4 w-4 ml-1" /> الافتراضي</Button>
          <Button size="sm" onClick={onSave} disabled={!dirty} className="btn-gold"><Save className="h-4 w-4 ml-1" /> حفظ</Button>
        </div>
      </div>

      <div className="mt-6 grid grid-cols-1 md:grid-cols-2 gap-4">
        {LAWS.map((law) => (
          <div key={law.id} className="rounded-2xl border bg-card p-4">
            <div className="flex items-center justify-between gap-2 mb-2">
              <div className={`inline-flex items-center gap-2 rounded-lg bg-gradient-to-br ${law.gradient} text-white px-3 py-1.5 text-xs font-bold shadow`}>
                {law.title}
              </div>
              {urls[law.id]?.trim() && (
                <a href={urls[law.id]} target="_blank" rel="noopener noreferrer" className="text-xs text-muted-foreground hover:text-gold inline-flex items-center gap-1">
                  <ExternalLink className="h-3 w-3" /> تجربة
                </a>
              )}
            </div>
            <Input dir="ltr" value={urls[law.id] ?? ""} onChange={(e) => update(law.id, e.target.value)} placeholder="https://laws.boe.gov.sa/..." className="text-xs h-10" />
          </div>
        ))}
      </div>
    </Card>
  );
}

/* ============================================================
   Shared building blocks
   ============================================================ */
function Header({ icon: Icon, title, subtitle }: { icon: any; title: string; subtitle?: string }) {
  return (
    <div className="flex items-center gap-3">
      <div className="grid h-11 w-11 place-items-center rounded-2xl bg-gradient-to-br from-indigo-600 to-blue-600 text-white shadow-lg">
        <Icon className="h-5 w-5" />
      </div>
      <div>
        <h3 className="text-base font-extrabold text-gradient-royal">{title}</h3>
        {subtitle && <p className="text-xs text-muted-foreground mt-0.5">{subtitle}</p>}
      </div>
    </div>
  );
}

function Field({ label, value, onChange, ltr, placeholder }: { label: string; value: string; onChange: (v: string) => void; ltr?: boolean; placeholder?: string }) {
  return (
    <div>
      <Label className="text-xs">{label}</Label>
      <Input dir={ltr ? "ltr" : undefined} value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder} className="mt-1" />
    </div>
  );
}

function SecretField({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  const [shown, setShown] = useState(false);
  return (
    <div>
      <Label className="text-xs">{label}</Label>
      <div className="mt-1 flex gap-1">
        <Input dir="ltr" type={shown ? "text" : "password"} value={value} onChange={(e) => onChange(e.target.value)} className="font-mono text-xs" />
        <Button size="icon" variant="outline" type="button" onClick={() => setShown((v) => !v)}>
          {shown ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
        </Button>
      </div>
    </div>
  );
}
