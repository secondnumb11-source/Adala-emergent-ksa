import { createFileRoute } from "@tanstack/react-router";
import { Landmark, ExternalLink, Search } from "lucide-react";
import { useMemo, useState } from "react";
import { PageHeader } from "@/components/section-shell";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";

export const Route = createFileRoute("/_authenticated/app/gov")({
  component: GovPortal,
});

type Platform = {
  name: string;
  desc: string;
  url: string;
  domain: string;
  initials: string;
  gradient: string;
  category: string;
};

// Logo.dev public token — safe for client; serves favicons by domain.
const LOGO_TOKEN = "pk_X-1ZO13GSgeOoUrIuJ6GMQ";
const logoSrc = (domain: string) =>
  `https://img.logo.dev/${domain}?token=${LOGO_TOKEN}&size=128&format=png`;

const PLATFORMS: Platform[] = [
  { name: "ناجز", desc: "خدمات وزارة العدل القضائية", url: "https://najiz.sa", domain: "najiz.sa", initials: "نج", gradient: "from-emerald-500 to-emerald-800", category: "قضائي" },
  { name: "بوابة المحامين", desc: "خدمات المحامين المرخصين", url: "https://lawyers.moj.gov.sa", domain: "moj.gov.sa", initials: "مح", gradient: "from-amber-500 to-amber-800", category: "قضائي" },
  { name: "نظام إنفاذ", desc: "محاكم التنفيذ والمطالبات", url: "https://enforcement.moj.gov.sa", domain: "moj.gov.sa", initials: "إن", gradient: "from-rose-500 to-rose-800", category: "قضائي" },
  { name: "أبشر أفراد", desc: "الخدمات الحكومية للأفراد", url: "https://www.absher.sa", domain: "absher.sa", initials: "أب", gradient: "from-sky-500 to-sky-800", category: "أحوال" },
  { name: "أبشر أعمال", desc: "خدمات منشآت القطاع الخاص", url: "https://business.absher.sa", domain: "absher.sa", initials: "أع", gradient: "from-cyan-500 to-cyan-800", category: "أعمال" },
  { name: "قوى", desc: "وزارة الموارد البشرية", url: "https://www.qiwa.sa", domain: "qiwa.sa", initials: "قو", gradient: "from-indigo-500 to-indigo-800", category: "عمل" },
  { name: "مدد", desc: "حماية الأجور وعقود العمل", url: "https://www.mudad.com.sa", domain: "mudad.com.sa", initials: "مد", gradient: "from-violet-500 to-violet-800", category: "عمل" },
  { name: "مقيم", desc: "خدمات المقيمين والكفلاء", url: "https://muqeem.sa", domain: "muqeem.sa", initials: "مق", gradient: "from-teal-500 to-teal-800", category: "أحوال" },
  { name: "هيئة الزكاة والضريبة والجمارك", desc: "ZATCA — الإقرارات والفواتير", url: "https://zatca.gov.sa", domain: "zatca.gov.sa", initials: "زك", gradient: "from-lime-500 to-lime-800", category: "مالي" },
  { name: "وزارة التجارة", desc: "السجلات التجارية والعلامات", url: "https://mc.gov.sa", domain: "mc.gov.sa", initials: "تج", gradient: "from-orange-500 to-orange-800", category: "أعمال" },
  { name: "المركز السعودي للتحكيم التجاري", desc: "SCCA — التحكيم والوساطة", url: "https://www.sadr.org", domain: "sadr.org", initials: "تح", gradient: "from-fuchsia-500 to-fuchsia-800", category: "قضائي" },
  { name: "هيئة السوق المالية", desc: "CMA — الشركات المدرجة والمستثمرين", url: "https://cma.org.sa", domain: "cma.org.sa", initials: "سم", gradient: "from-blue-500 to-blue-800", category: "مالي" },
  { name: "مركز الأعمال السعودي", desc: "تأسيس وتراخيص المنشآت", url: "https://business.sa", domain: "business.sa", initials: "أع", gradient: "from-yellow-500 to-yellow-800", category: "أعمال" },
  { name: "بلدي", desc: "الخدمات البلدية والرخص", url: "https://balady.gov.sa", domain: "balady.gov.sa", initials: "بل", gradient: "from-green-500 to-green-800", category: "أعمال" },
  { name: "إيجار", desc: "العقود الإيجارية الموثقة", url: "https://eservices.ejar.sa", domain: "ejar.sa", initials: "إج", gradient: "from-pink-500 to-pink-800", category: "عقاري" },
  { name: "وزارة الإسكان", desc: "خدمات السكن والتمويل", url: "https://housing.sa", domain: "housing.sa", initials: "إس", gradient: "from-red-500 to-red-800", category: "عقاري" },
  { name: "الهيئة العامة للعقار", desc: "REGA — الصكوك والوسطاء", url: "https://rega.gov.sa", domain: "rega.gov.sa", initials: "عق", gradient: "from-purple-500 to-purple-800", category: "عقاري" },
  { name: "الديوان الملكي", desc: "البلاغات والقضايا السامية", url: "https://www.royalcourt.gov.sa", domain: "royalcourt.gov.sa", initials: "ملك", gradient: "from-amber-600 to-amber-900", category: "حكومي" },
];

const CATEGORIES = ["الكل", "قضائي", "أعمال", "عمل", "مالي", "عقاري", "أحوال", "حكومي"];

function GovPortal() {
  const [q, setQ] = useState("");
  const [cat, setCat] = useState("الكل");
  const filtered = useMemo(
    () =>
      PLATFORMS.filter(
        (p) =>
          (cat === "الكل" || p.category === cat) &&
          (q.trim() === "" || p.name.includes(q) || p.desc.includes(q)),
      ),
    [q, cat],
  );

  return (
    <>
      <PageHeader
        icon={Landmark}
        title="بوابة الخدمات الحكومية"
        subtitle={`${PLATFORMS.length} منصة سعودية رسمية في مكان واحد`}
      />

      <div className="mb-6 flex flex-wrap items-center gap-3">
        <div className="relative flex-1 min-w-[220px] max-w-md">
          <Search className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="ابحث عن منصة..."
            value={q}
            onChange={(e) => setQ(e.target.value)}
            className="h-11 pr-10 text-right bg-muted/40 border-transparent"
          />
        </div>
        <div className="flex flex-wrap gap-2">
          {CATEGORIES.map((c) => (
            <button
              key={c}
              onClick={() => setCat(c)}
              className={`rounded-full px-4 py-1.5 text-xs font-bold transition-all ${
                cat === c
                  ? "btn-gold shadow-md scale-105"
                  : "bg-muted/60 text-muted-foreground hover:bg-muted hover:scale-105"
              }`}
            >
              {c}
            </button>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-5">
        {filtered.map((p) => (
          <a
            key={p.name}
            href={p.url}
            target="_blank"
            rel="noreferrer"
            className="group block"
          >
            <Card className="card-3d shine tilt-on-hover border-none p-5 h-full flex flex-col gap-4 cursor-pointer">
              <div className="flex items-start gap-3">
                <div
                  className={`relative grid h-16 w-16 shrink-0 place-items-center rounded-2xl bg-gradient-to-br ${p.gradient} text-white font-extrabold text-xl shadow-lg overflow-hidden`}
                  style={{
                    boxShadow:
                      "inset 0 1px 0 rgba(255,255,255,0.35), inset 0 -2px 0 rgba(0,0,0,0.18), 0 10px 24px -8px rgba(0,0,0,0.35)",
                  }}
                >
                  <img
                    src={logoSrc(p.domain)}
                    alt={p.name}
                    loading="lazy"
                    className="absolute inset-0 h-full w-full object-contain p-2 bg-white/95"
                    onError={(e) => {
                      const el = e.currentTarget;
                      el.style.display = "none";
                      const fb = el.nextElementSibling as HTMLElement | null;
                      if (fb) fb.style.display = "block";
                    }}
                  />
                  <span style={{ textShadow: "0 1px 2px rgba(0,0,0,0.35)", display: "none" }}>{p.initials}</span>
                  <span className="absolute inset-0 rounded-2xl ring-1 ring-inset ring-white/20 pointer-events-none" />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="font-bold text-sm leading-tight">{p.name}</div>
                  <div className="mt-1 text-[11px] text-muted-foreground line-clamp-2">{p.desc}</div>
                </div>
              </div>
              <div className="mt-auto flex items-center justify-between border-t border-border/60 pt-3">
                <span className="text-[10px] font-bold uppercase tracking-wider text-gold">
                  {p.category}
                </span>
                <span className="inline-flex items-center gap-1 text-[11px] font-semibold text-primary group-hover:text-gold transition-colors">
                  فتح المنصة
                  <ExternalLink className="h-3.5 w-3.5" />
                </span>
              </div>
            </Card>
          </a>
        ))}
        {filtered.length === 0 && (
          <Card className="card-3d col-span-full p-10 text-center text-muted-foreground">
            لا توجد منصات مطابقة للبحث
          </Card>
        )}
      </div>
    </>
  );
}
