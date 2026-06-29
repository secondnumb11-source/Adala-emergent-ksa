import { createFileRoute } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { CheckCircle2, Circle, ClipboardCheck, ListChecks, Filter, ScanLine, AlertTriangle } from "lucide-react";
import { PageHeader } from "@/components/section-shell";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";



export const Route = createFileRoute("/_authenticated/app/changes")({
  component: ChangesPage,
});

type Status = "done" | "pending";
type Item = { id: string; text: string; status: Status; note?: string };
type Section = { id: string; title: string; items: Item[] };

const SECTIONS: Section[] = [
  {
    id: "welcome",
    title: "المربع الترحيبي في لوحة البيانات الرئيسية",
    items: [
      { id: "w1", text: "حذف مربع (بث مباشر) من يسار المربع الترحيبي", status: "done" },
      { id: "w2", text: "إضافة زر (تخصيص اللوحة) في يسار المربع الترحيبي يسمح بإعادة ترتيب وتحجيم الكروت بطريقة احترافية", status: "done", note: "السحب والإفلات + مقابض تغيير الحجم عبر DashboardLayout" },
    ],
  },
  {
    id: "session",
    title: "زر إنهاء الجلسة",
    items: [
      { id: "s1", text: "زر صغير منحني (إنهاء الجلسة) أعلى يسار جميع الصفحات يقوم بتسجيل الخروج", status: "done" },
      { id: "s2", text: "ثبات الزر في جميع أقسام النظام", status: "done", note: "موجود في الهيدر العام داخل layout app.tsx" },
      { id: "s3", text: "نافذة تأكيد قبل تسجيل الخروج", status: "done" },
    ],
  },
  {
    id: "cards",
    title: "كروت البيانات (القضايا، العملاء، البوابة، الوكالات، التنفيذ، الموظفين)",
    items: [
      { id: "c1", text: "توسيع حجم مربعات البيانات لعرض كامل المحتوى بوضوح", status: "done" },
      { id: "c2", text: "تحويل النمط من داكن إلى مضيء فاخر وأنيق", status: "done", note: "تعريف card-luxe الجديد بخلفية عاجية وحدود ذهبية" },
      { id: "c3", text: "تصميم ثلاثي الأبعاد 3D مع ظلال ولمعان", status: "done" },
      { id: "c4", text: "تأثيرات حركية تفاعلية عند تمرير الماوس (hover)", status: "done" },
      { id: "c5", text: "زيادة تباين النصوص للقراءة الواضحة", status: "done", note: "ألوان #1f1810 / #4a3d28 + override للنصوص البيضاء" },
    ],
  },
  {
    id: "sidebar-structure",
    title: "إعادة ترتيب الشريط الجانبي بالتصنيفات",
    items: [
      { id: "g1", text: "تصنيف: المنظومة القضائية وإدارة العمل (5 أقسام)", status: "done" },
      { id: "g2", text: "تصنيف: إدارة شؤون العملاء (4 أقسام)", status: "done" },
      { id: "g3", text: "تصنيف: فريق العمل (4 أقسام)", status: "done" },
      { id: "g4", text: "تصنيف: المساعد الذكي وأدوات الذكاء الاصطناعي", status: "done" },
      { id: "g5", text: "تصنيف: خدمات المساندة والتحقق الذكي (3 أقسام)", status: "done" },
      { id: "g6", text: "تكامل ناجز ثم الإعدادات في النهاية", status: "done" },
    ],
  },
  {
    id: "sidebar-design",
    title: "تصميم الشريط الجانبي",
    items: [
      { id: "d1", text: "تثبيت الشريط الجانبي وعدم اختفاء بياناته عند التمرير", status: "done", note: "lg:sticky lg:top-0 lg:h-screen" },
      { id: "d2", text: "تصميم احترافي وأنيق وعصري", status: "done" },
      { id: "d3", text: "تعريض النصوص وزيادة التباين", status: "done" },
      { id: "d4", text: "تأثيرات حركية تفاعلية احترافية على hover", status: "done", note: "nav-3d مع translateX/translateZ/rotateY" },
      { id: "d5", text: "تصميم ثلاثي الأبعاد 3D للوحة الجانبية", status: "done", note: "sidebar-3d-bg + perspective" },
      { id: "d6", text: "تأثيرات 3D عند تمييز القسم المحدد", status: "done" },
      { id: "d7", text: "قائمة منسدلة لأدوات الذكاء الاصطناعي مع علامة فتح ChevronDown", status: "done" },
      { id: "d8", text: "شارة AI متوهجة باللون الذهبي بجانب قسم AI", status: "done" },
      { id: "d9", text: "توهج وتمييز الرموز بجانب كل قسم", status: "done", note: "nav-icon-glow" },
      { id: "d10", text: "تنسيق الساعة HH:MM AM/PM بلون أخضر فسفوري", status: "done" },
      { id: "d11", text: "تغيير (نسخة تجريبية) إلى (لإدارة مكاتب المحاماة) مع تأثيرات 3D", status: "done" },
      { id: "d12", text: "نقل تشخيص النظام وسجل التدقيق إلى صفحة الإعدادات", status: "done" },
    ],
  },
  {
    id: "mobile",
    title: "تحسينات الموبايل وتجربة الشاشات الصغيرة",
    items: [
      { id: "m1", text: "تصفح التصنيفات قابلًا للتمرير داخل الشريط الجانبي على الموبايل", status: "done" },
      { id: "m2", text: "الهيدر الثابت لا يخفي المحتوى أثناء التمرير", status: "done" },
      { id: "m3", text: "كروت متجاوبة (عمود واحد على الموبايل)", status: "done" },
    ],
  },
];

function ChangesPage() {
  const [filter, setFilter] = useState<"all" | Status>("all");
  const [q, setQ] = useState("");

  const stats = useMemo(() => {
    const all = SECTIONS.flatMap((s) => s.items);
    const done = all.filter((i) => i.status === "done").length;
    return { total: all.length, done, pending: all.length - done };
  }, []);

  const visible = useMemo(() => {
    const needle = q.trim();
    return SECTIONS.map((s) => ({
      ...s,
      items: s.items.filter((i) => {
        if (filter !== "all" && i.status !== filter) return false;
        if (needle && !`${i.text} ${i.note ?? ""}`.includes(needle)) return false;
        return true;
      }),
    })).filter((s) => s.items.length > 0);
  }, [filter, q]);

  const pct = Math.round((stats.done / stats.total) * 100);

  return (
    <>
      <PageHeader
        icon={ClipboardCheck}
        title="قائمة التعديلات المطلوبة"
        subtitle="مراجعة شاملة لكل البنود التي طُلب تنفيذها وحالة كل بند"
      />

      {/* Summary */}
      <div className="mt-6 grid gap-3 sm:grid-cols-3">
        <Card className="card-luxe p-5">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-xs font-bold opacity-70">إجمالي البنود</div>
              <div className="text-3xl font-black mt-1">{stats.total}</div>
            </div>
            <ListChecks className="h-10 w-10 text-gold" />
          </div>
        </Card>
        <Card className="card-luxe p-5">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-xs font-bold opacity-70">منجزة</div>
              <div className="text-3xl font-black mt-1 text-emerald-700">{stats.done}</div>
            </div>
            <CheckCircle2 className="h-10 w-10 text-emerald-600" />
          </div>
        </Card>
        <Card className="card-luxe p-5">
          <div className="text-xs font-bold opacity-70">نسبة الإنجاز</div>
          <div className="text-3xl font-black mt-1">{pct}%</div>
          <div className="mt-3 h-2.5 rounded-full bg-gold/15 overflow-hidden">
            <div
              className="h-full bg-gradient-to-l from-emerald-500 to-emerald-400 transition-all duration-700"
              style={{ width: `${pct}%` }}
            />
          </div>
        </Card>
      </div>

      {/* Controls */}
      <div className="mt-6 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="relative flex-1 sm:max-w-md">
          <Filter className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="ابحث في البنود..."
            value={q}
            onChange={(e) => setQ(e.target.value)}
            className="pr-10 text-right"
          />
        </div>
        <div className="flex gap-2">
          {(["all", "done", "pending"] as const).map((f) => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={`px-4 py-2 rounded-xl text-xs font-bold transition border ${
                filter === f
                  ? "bg-gold text-primary border-gold shadow-md"
                  : "bg-card border-border hover:bg-muted text-muted-foreground"
              }`}
            >
              {f === "all" ? "الكل" : f === "done" ? "منجزة" : "غير مكتملة"}
            </button>
          ))}
        </div>
      </div>

      {/* Sections */}
      <div className="mt-6 space-y-5">
        {visible.length === 0 ? (
          <Card className="card-luxe p-10 text-center">لا توجد بنود مطابقة.</Card>
        ) : (
          visible.map((section) => (
            <Card key={section.id} className="card-luxe p-6">
              <div className="flex items-center justify-between mb-4 pb-3 border-b-2 border-gold/20">
                <h3 className="text-lg font-extrabold">{section.title}</h3>
                <Badge variant="outline" className="bg-gold/15 border-gold/40 font-bold">
                  {section.items.filter((i) => i.status === "done").length}/{section.items.length}
                </Badge>
              </div>
              <ul className="space-y-2.5">
                {section.items.map((item) => (
                  <li
                    key={item.id}
                    className={`flex gap-3 rounded-xl p-3 transition ${
                      item.status === "done"
                        ? "bg-emerald-50/60 border border-emerald-200"
                        : "bg-amber-50/70 border border-amber-200"
                    }`}
                  >
                    {item.status === "done" ? (
                      <CheckCircle2 className="h-5 w-5 shrink-0 text-emerald-600 mt-0.5" />
                    ) : (
                      <Circle className="h-5 w-5 shrink-0 text-amber-600 mt-0.5" />
                    )}
                    <div className="flex-1 min-w-0">
                      <div className="text-sm font-semibold leading-relaxed">{item.text}</div>
                      {item.note && (
                        <div className="text-xs opacity-70 mt-1 leading-relaxed">↳ {item.note}</div>
                      )}
                    </div>
                    <Badge
                      className={
                        item.status === "done"
                          ? "bg-emerald-600 text-white border-0"
                          : "bg-amber-500 text-white border-0"
                      }
                    >
                      {item.status === "done" ? "تم" : "غير مكتمل"}
                    </Badge>
                  </li>
                ))}
              </ul>
            </Card>
          ))
        )}
      </div>

      <SelfCheckPanel />
    </>
  );
}

/* =========================================================
   Automated runtime self-check — probes the live DOM/CSS to
   detect missing or mis-styled elements after the redesign.
   ========================================================= */
type ProbeResult = { id: string; label: string; ok: boolean; detail: string };

function runProbes(): ProbeResult[] {
  const results: ProbeResult[] = [];

  const push = (id: string, label: string, ok: boolean, detail: string) =>
    results.push({ id, label, ok, detail });

  // Sidebar groups (5 categories + system group)
  const groupLabels = Array.from(document.querySelectorAll("aside .text-gold\\/70, aside [class*='text-gold/70']"))
    .map((n) => (n.textContent || "").trim())
    .filter(Boolean);
  const expectedGroups = [
    "المنظومة القضائية وإدارة العمل",
    "إدارة شؤون العملاء",
    "فريق العمل",
    "المساعد الذكي وأدوات الذكاء الاصطناعي",
    "خدمات المساندة والتحقق الذكي",
  ];
  const missingGroups = expectedGroups.filter((g) => !groupLabels.some((l) => l.includes(g)));
  push(
    "groups",
    "تصنيفات الشريط الجانبي الخمسة",
    missingGroups.length === 0,
    missingGroups.length === 0
      ? `تم العثور على ${groupLabels.length} تصنيف`
      : `مفقود: ${missingGroups.join(" — ")}`,
  );

  // AI dropdown trigger + AI badge
  const aiBadge = document.querySelector("aside .ai-badge");
  push("ai-badge", "شارة AI الذهبية المتوهجة", !!aiBadge, aiBadge ? "موجودة بجانب قسم AI" : "غير موجودة");

  // Sidebar nav 3D + sticky
  const aside = document.querySelector("aside");
  const sideHas3D = !!document.querySelector("aside .sidebar-3d-bg");
  push("3d", "خلفية ثلاثية الأبعاد للشريط الجانبي", sideHas3D, sideHas3D ? "sidebar-3d-bg مفعّل" : "الكلاس مفقود");

  const isSticky = (() => {
    if (!aside) return false;
    const cs = getComputedStyle(aside);
    return cs.position === "sticky" || cs.position === "fixed";
  })();
  push("sticky", "تثبيت الشريط الجانبي (sticky/fixed)", isSticky, `position=${aside ? getComputedStyle(aside).position : "—"}`);

  // Nav 3D hover utility presence
  const nav3d = document.querySelectorAll("aside .nav-3d").length;
  push("nav3d", "تأثيرات nav-3d التفاعلية", nav3d > 0, `${nav3d} عنصر مفعّل عليه nav-3d`);

  // Icon glow
  const glowed = document.querySelectorAll("aside .nav-icon-glow").length;
  push("glow", "توهج أيقونات الأقسام", glowed > 0, `${glowed} أيقونة بتوهج`);

  // Logout button
  const logoutBtn = Array.from(document.querySelectorAll("header button")).find((b) =>
    (b.textContent || "").includes("إنهاء الجلسة") || (b.getAttribute("title") || "").includes("إنهاء"),
  );
  push("logout", "زر إنهاء الجلسة في الهيدر", !!logoutBtn, logoutBtn ? "موجود وثابت" : "غير موجود");

  // Card-luxe used and is bright (not dark navy)
  const luxe = document.querySelector(".card-luxe");
  let luxeOk = false;
  let luxeDetail = "لا يوجد كارت card-luxe على هذه الصفحة";
  if (luxe) {
    const bg = getComputedStyle(luxe).backgroundColor;
    // sample bright pixel test: parse rgb
    const m = bg.match(/\d+(\.\d+)?/g);
    if (m) {
      const [r, g, b] = m.map(Number);
      const luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      luxeOk = luma > 180; // bright background
      luxeDetail = `سطوع الخلفية ≈ ${Math.round(luma)} (${luxeOk ? "مضيء فاخر" : "ليس مضيئاً — مازال داكناً"})`;
    }
  }
  push("luxe", "كروت card-luxe بنمط مضيء فاخر", luxeOk, luxeDetail);

  // Clock neon green
  const clockEl = document.querySelector("aside .font-mono") as HTMLElement | null;
  let clockOk = false;
  let clockDetail = "لم يتم العثور على عنصر الساعة";
  if (clockEl) {
    const c = getComputedStyle(clockEl).color;
    const text = (clockEl.textContent || "").trim();
    const hasAmPm = /AM|PM/.test(text);
    const greenish = /rgb\(\s*(?:[3-9]\d|1\d\d|2[0-5]\d)\s*,\s*(?:1[5-9]\d|2[0-5]\d)\s*,/.test(c);
    clockOk = hasAmPm && greenish;
    clockDetail = `لون=${c} • نص="${text.slice(0, 24)}" • AM/PM=${hasAmPm ? "نعم" : "لا"}`;
  }
  push("clock", "ساعة HH:MM AM/PM بلون أخضر فسفوري", clockOk, clockDetail);

  // Brand title text replaced
  const brand = document.querySelector("aside .brand-title");
  const brandText = brand?.textContent || "";
  const brandOk = brandText.includes("لإدارة مكاتب المحاماة") && !brandText.includes("نسخة تجريبية");
  push("brand", "تحديث عنوان (لإدارة مكاتب المحاماة)", brandOk, brandText ? brandText.trim().slice(0, 60) : "غير موجود");

  // Sidebar nav scrollable on small screens
  const navEl = document.querySelector("aside nav.sidebar-nav-scroll") as HTMLElement | null;
  const scrollOk = !!navEl && navEl.scrollHeight >= navEl.clientHeight - 1;
  push("scroll", "تمرير الشريط الجانبي يعمل بدون اختفاء", !!navEl && scrollOk, navEl ? `محتوى=${navEl.scrollHeight}px • مرئي=${navEl.clientHeight}px` : "العنصر غير موجود");

  // Sticky header
  const header = document.querySelector("header");
  const headerSticky = header ? getComputedStyle(header).position === "sticky" : false;
  push("header", "الهيدر ثابت أعلى الصفحة (sticky)", headerSticky, header ? `position=${getComputedStyle(header).position}` : "غير موجود");

  return results;
}

function SelfCheckPanel() {
  const [results, setResults] = useState<ProbeResult[] | null>(null);

  const run = () => {
    try {
      setResults(runProbes());
    } catch (e) {
      setResults([{ id: "err", label: "فشل تشغيل الفحص", ok: false, detail: String((e as Error).message) }]);
    }
  };

  const okCount = results?.filter((r) => r.ok).length ?? 0;
  const total = results?.length ?? 0;

  return (
    <Card className="card-luxe mt-8 p-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between border-b-2 border-gold/20 pb-4 mb-4">
        <div className="flex items-center gap-3">
          <div className="grid h-12 w-12 place-items-center rounded-xl bg-gold/20 text-gold">
            <ScanLine className="h-6 w-6" />
          </div>
          <div>
            <h3 className="text-lg font-extrabold">الفحص التلقائي للتغييرات</h3>
            <p className="text-xs opacity-75">يفحص الشريط الجانبي والكروت ويكشف العناصر المفقودة أو التباين غير المناسب فوراً</p>
          </div>
        </div>
        <Button onClick={run} className="bg-gold text-primary hover:bg-gold/90 font-bold">
          <ScanLine className="h-4 w-4 ml-1" />
          تشغيل الفحص الآن
        </Button>
      </div>

      {results === null ? (
        <p className="text-sm opacity-70 text-center py-6">اضغط على "تشغيل الفحص الآن" لمراجعة كل العناصر تلقائياً.</p>
      ) : (
        <>
          <div className="mb-4 flex items-center gap-3 text-sm font-bold">
            <Badge className={okCount === total ? "bg-emerald-600 text-white" : "bg-amber-500 text-white"}>
              {okCount}/{total} ناجحة
            </Badge>
            {okCount < total && (
              <span className="flex items-center gap-1 text-amber-700">
                <AlertTriangle className="h-4 w-4" />
                توجد بنود تحتاج للمراجعة
              </span>
            )}
          </div>
          <ul className="space-y-2">
            {results.map((r) => (
              <li
                key={r.id}
                className={`flex gap-3 rounded-xl p-3 border ${
                  r.ok ? "bg-emerald-50/70 border-emerald-200" : "bg-rose-50/80 border-rose-200"
                }`}
              >
                {r.ok ? (
                  <CheckCircle2 className="h-5 w-5 shrink-0 text-emerald-600 mt-0.5" />
                ) : (
                  <AlertTriangle className="h-5 w-5 shrink-0 text-rose-600 mt-0.5" />
                )}
                <div className="flex-1 min-w-0">
                  <div className="text-sm font-bold">{r.label}</div>
                  <div className="text-xs opacity-80 mt-0.5 font-mono leading-relaxed">{r.detail}</div>
                </div>
              </li>
            ))}
          </ul>
        </>
      )}
    </Card>
  );
}

