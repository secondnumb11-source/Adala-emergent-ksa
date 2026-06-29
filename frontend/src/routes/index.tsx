import { createFileRoute, Link } from "@tanstack/react-router";
import { lazy, Suspense } from "react";
import {
  Scale, Bot, MessageSquare, FileText, Calculator, ShieldCheck, Sparkles,
  Workflow, Building2, BadgeCheck, Zap, Lock, Globe, CheckCircle2, XCircle,
  ArrowLeft, Phone, Mail, User, MessageCircle, Briefcase, FileSignature,
  Receipt, Library, Network, Crown, ChevronDown,
} from "lucide-react";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";
import { Tilt3D } from "@/components/tilt-3d";
import { Luxury3DText } from "@/components/luxury-3d-text";
import { HeroSpotlight } from "@/components/hero-spotlight";
import { ReducedMotionIndicator } from "@/components/reduced-motion-indicator";

// Lazy-load the heaviest below-the-fold module (~414 lines of UI) so the
// initial landing payload stays light. SSR still renders the section via
// streaming Suspense; the client hydrates the chunk on demand.
const FeatureStations = lazy(() =>
  import("@/components/feature-stations").then((m) => ({ default: m.FeatureStations })),
);


const FAQ_ITEMS = [
  { q: "كيف يتم تأمين الربط والمزامنة التلقائية مع حسابات ناجز ووكالات وزارة العدل؟", a: "نستخدم أداة سحب آمنة عبر extension متصفح بصلاحيات محدودة. لا نخزن بيانات الدخول؛ الجلسة مشفرة محلياً وكل عملية مزامنة مسجّلة في سجل التدقيق." },
  { q: "هل يدعم النظام ضريبة القيمة المضافة وفواتير هيئة الزكاة والضريبة؟", a: "نعم — نحن متطابقون 100% مع ZATCA Phase 2 (الفوترة الإلكترونية المرحلة الثانية) مع توليد QR وإرسال الفواتير لمنصة فاتورة تلقائياً." },
  { q: "كيف تعمل ميزة الإشعار بالواتساب وهل تحتاج لرسائل إضافية مأجورة؟", a: "نستخدم WhatsApp Business API الرسمي. حزمة الرسائل مشمولة بالاشتراك، ويمكن ترقيتها حسب حجم الإرسال." },
  { q: "هل بياناتي محفوظة داخل المملكة؟", a: "نعم — جميع البيانات مستضافة في خوادم سعودية معتمدة من NCA، ولا تغادر المملكة." },
];

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "منصة العدالة — المنظومة القانونية والذكاء القضائي المتكامل" },
      { name: "description", content: "حل تقني متكامل لمكاتب المحاماة بالمملكة: ربط ناجز، صياغة بالذكاء الاصطناعي، فواتير ZATCA، إشعارات واتساب — جرّب مجاناً." },
      { property: "og:title", content: "منصة العدالة — المنظومة القضائية الأقوى بالمملكة" },
      { property: "og:description", content: "ربط مباشر ببوابة ناجز، صياغة لوائح بالذكاء الاصطناعي، فواتير ZATCA، وإشعارات واتساب — أنجز قضاياك بضغطة زر." },
      { property: "og:url", content: "https://start-up-joy.lovable.app/" },
    ],
    links: [{ rel: "canonical", href: "https://start-up-joy.lovable.app/" }],
    scripts: [
      {
        type: "application/ld+json",
        children: JSON.stringify({
          "@context": "https://schema.org",
          "@type": "FAQPage",
          mainEntity: FAQ_ITEMS.map((it) => ({
            "@type": "Question",
            name: it.q,
            acceptedAnswer: { "@type": "Answer", text: it.a },
          })),
        }),
      },
    ],
  }),
  component: LandingPage,
});

function LandingPage() {
  return (
    <div className="min-h-screen overflow-x-hidden">
      <Header />
      <Hero />
      <ReducedMotionIndicator />
      <Stats />
      <Features />
      <Suspense fallback={<div className="py-20" aria-hidden />}>
        <FeatureStations />
      </Suspense>
      <AIShowcase />
      <Comparison />
      <Calculator2 />
      <WhatsAppDemo />
      <Security />
      <ClientPortal />
      <EmployeePortal />
      <FAQ />
      <Contact />
      <Footer />
    </div>
  );
}

/* ============ Header ============ */
function Header() {
  const [open, setOpen] = useState(false);
  return (
    <header className="sticky top-0 z-50 border-b border-border/50 bg-background/80 backdrop-blur-xl">
      <div className="container mx-auto flex h-16 items-center justify-between px-4">
        <Link
          to="/"
          aria-label="منصة العدالة لإدارة مكاتب المحاماة — الصفحة الرئيسية"
          className="brand-title group gap-3 rounded-lg outline-none focus-visible:ring-2 focus-visible:ring-gold focus-visible:ring-offset-2 focus-visible:ring-offset-background"
        >
          <div className="brand-mark grid h-11 w-11 place-items-center rounded-xl bg-gradient-to-br from-primary to-primary/70 text-gold shadow-md ring-1 ring-gold/30" aria-hidden="true">
            <Scale className="h-5 w-5 drop-shadow" />
          </div>
          <div className="font-extrabold text-lg leading-tight tracking-tight" aria-hidden="true">
            <span className="brand-title-text">منصة </span>
            <span className="brand-title-accent" data-text="العدالة">العدالة</span>
            <span className="brand-title-text"> - لإدارة مكاتب المحاماة</span>
          </div>
        </Link>

        <nav aria-label="التنقّل الرئيسي" className="hidden md:flex items-center gap-7 text-sm font-medium text-muted-foreground">
          <a href="#features" className="rounded-md px-1 py-0.5 hover:text-primary transition-colors outline-none focus-visible:ring-2 focus-visible:ring-gold">المميزات</a>
          <a href="#ai" className="rounded-md px-1 py-0.5 hover:text-primary transition-colors outline-none focus-visible:ring-2 focus-visible:ring-gold">الذكاء الاصطناعي</a>
          <a href="#comparison" className="rounded-md px-1 py-0.5 hover:text-primary transition-colors outline-none focus-visible:ring-2 focus-visible:ring-gold">المقارنة</a>
          <a href="#security" className="rounded-md px-1 py-0.5 hover:text-primary transition-colors outline-none focus-visible:ring-2 focus-visible:ring-gold">الأمان</a>
          <a href="#faq" className="rounded-md px-1 py-0.5 hover:text-primary transition-colors outline-none focus-visible:ring-2 focus-visible:ring-gold">الأسئلة الشائعة</a>
        </nav>
        <div className="flex items-center gap-2">
          <Link
            to="/auth"
            className="hidden sm:inline-flex items-center rounded-lg px-3 py-1.5 text-sm font-medium hover:bg-accent outline-none focus-visible:ring-2 focus-visible:ring-gold focus-visible:ring-offset-2 focus-visible:ring-offset-background"
          >
            دخول
          </Link>
          <Link
            to="/auth"
            search={{ mode: "signup" } as never}
            aria-label="ابدأ تجربة مجانية لمدة 48 ساعة"
            className="btn-gold btn-gold-3d inline-flex items-center gap-1 px-4 py-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-gold focus-visible:ring-offset-2 focus-visible:ring-offset-background"
          >
            تجربة لمدة 48 ساعة مجاناً
            <ArrowLeft className="h-4 w-4" aria-hidden="true" />
          </Link>
        </div>
      </div>
    </header>
  );
}

/* ============ Hero ============ */
function Hero() {
  return (
    <section
      aria-labelledby="hero-heading"
      className="relative overflow-hidden py-24 lg:py-32"
    >
      {/* Layered premium background */}
      <div className="absolute inset-0 -z-10 hero-grid-bg" aria-hidden="true" />
      <HeroSpotlight />
      <div className="absolute inset-0 -z-10 pointer-events-none" aria-hidden="true">
        <div className="absolute top-10 right-1/5 h-96 w-96 rounded-full bg-gold/25 blur-[110px] orb-drift" />
        <div className="absolute bottom-0 left-1/5 h-96 w-96 rounded-full bg-primary/30 blur-[110px] orb-drift" style={{ animationDelay: "3s" }} />
        <div className="absolute top-1/2 left-1/2 h-64 w-64 -translate-x-1/2 -translate-y-1/2 rounded-full bg-gold/10 blur-3xl" />
      </div>

      <div className="container mx-auto grid items-center gap-14 px-4 lg:grid-cols-2">
        <div className="text-center lg:text-right">
          <div className="inline-flex items-center gap-2 rounded-full border-2 border-gold/40 bg-gradient-to-l from-gold/15 to-transparent px-5 py-2 text-xs font-bold text-primary shadow-[0_4px_20px_-4px] shadow-gold/30 backdrop-blur-sm">
            <Crown className="h-4 w-4 text-gold" aria-hidden="true" />
            المنظومة القضائية والذكاء الاصطناعي الأقوى بالمملكة
          </div>

          <h1
            id="hero-heading"
            className="mt-7 text-4xl sm:text-5xl lg:text-7xl font-black leading-[1.08] lg:leading-[1.05] tracking-tight"
            aria-label="منصة العدالة لإدارة مكاتب المحاماة"
          >
            <Luxury3DText intensity={9} className="block">
              <span className="text-3d-royal inline-block">منصة</span>{" "}
              <span className="text-3d-gold inline-block">العدالة</span>
            </Luxury3DText>
            <span aria-hidden="true" className="mt-3 flex items-center justify-center lg:justify-end gap-3 text-2xl sm:text-3xl lg:text-5xl font-extrabold text-3d-royal">
              <span aria-hidden className="hidden sm:inline-block h-px w-10 bg-gradient-to-l from-gold to-transparent" />
              لإدارة مكاتب المحاماة
            </span>
          </h1>

          <p className="mt-7 text-lg lg:text-xl text-foreground/85 leading-relaxed font-medium">
            الحل التقني المتكامل لإدارة مكاتب المحاماة. نربطك مباشرة بـ
            {" "}<strong className="text-primary font-extrabold">بوابة ناجز</strong>{" "}
            لمزامنة الجلسات، ونوفر صياغة اللوائح بالذكاء الاصطناعي، فواتير
            {" "}<strong className="text-primary font-extrabold">ZATCA</strong>{" "}
            وإشعارات{" "}<strong className="text-primary font-extrabold">واتساب</strong>{" "}
            متكاملة — لتنجز القضايا بضغطة زر.
          </p>

          <div className="mt-9 flex flex-wrap items-center justify-center gap-4 lg:justify-end">
            <Link
              to="/auth"
              search={{ mode: "signup" } as never}
              aria-label="احصل على النسخة التجريبية المجانية لمدة 48 ساعة"
              className="btn-gold btn-gold-3d inline-flex items-center gap-2 px-8 py-4 text-base shine font-extrabold tracking-wide outline-none focus-visible:ring-2 focus-visible:ring-gold focus-visible:ring-offset-2 focus-visible:ring-offset-background"
            >
              <span aria-hidden="true">🔥</span> احصل على النسخة التجريبية المجانية
              <ArrowLeft className="h-5 w-5" aria-hidden="true" />
            </Link>
            <a
              href="#features"
              aria-label="استكشف مميزات المنصة"
              className="btn-outline-3d px-7 py-4 text-base outline-none focus-visible:ring-2 focus-visible:ring-gold focus-visible:ring-offset-2 focus-visible:ring-offset-background"
            >
              استكشف المميزات
            </a>
          </div>
          <p className="mt-5 text-sm font-medium text-foreground/65">
            بدون التزام بنكي · شاشات تفاعلية كاملة · جميع المميزات
          </p>
        </div>

        {/* Right column: interactive 3D card */}
        <div className="relative">
          <Tilt3D max={14} className="rounded-3xl">
            <div className="card-3d relative p-1.5 rounded-3xl">
              <div className="rounded-[1.4rem] bg-gradient-to-br from-primary via-primary to-[oklch(0.32_0.1_270)] p-7 text-primary-foreground relative overflow-hidden">
                {/* Inner glow */}
                <div className="pointer-events-none absolute -top-20 -right-20 h-56 w-56 rounded-full bg-gold/30 blur-3xl" />

                <div className="relative flex items-center justify-between border-b border-white/15 pb-4 pop-z">
                  <div className="flex items-center gap-2">
                    <div className="grid h-9 w-9 place-items-center rounded-xl bg-gold/20 ring-1 ring-gold/40">
                      <Bot className="h-5 w-5 text-gold" />
                    </div>
                    <span className="text-base font-bold">مساعد العدالة الذكي</span>
                  </div>
                  <span className="text-[11px] font-bold rounded-full bg-success/25 px-3 py-1 text-success ring-1 ring-success/40">
                    ● مفعّل
                  </span>
                </div>

                <div className="relative mt-5 space-y-3 text-sm pop-z">
                  <div className="rounded-xl bg-white/8 p-4 ring-1 ring-white/10 shadow-inner">
                    <div className="text-gold text-xs font-bold mb-1.5">🧑‍⚖️ المستخدم</div>
                    <p className="leading-relaxed">صغ لي لائحة اعتراضية على حكم في نزاع توريد تجاري...</p>
                  </div>
                  <div className="rounded-xl bg-gradient-to-bl from-gold/20 to-gold/10 p-4 border border-gold/40 shadow-[0_8px_24px_-8px] shadow-gold/40">
                    <div className="text-gold text-xs font-bold mb-1.5">🤖 الذكاء الاصطناعي</div>
                    <p className="leading-relaxed">✓ تم تشخيص الحكم ومطابقته بمواد نظام المحاكم التجارية السعودي.</p>
                    <p className="mt-2 leading-relaxed">
                      🚀 <strong className="text-gold">الدفع المقترح:</strong> عدم مطابقة الخدمة للمادة السابعة من العقد.
                    </p>
                  </div>
                  <div className="flex items-center gap-2 text-xs text-white/80 font-medium">
                    <Sparkles className="h-3.5 w-3.5 text-gold animate-pulse" />
                    جاري الصياغة الكاملة...
                  </div>
                </div>
              </div>
            </div>
          </Tilt3D>

          {/* Floating badges with their own tilt */}
          <div className="absolute -bottom-5 -left-5 hidden md:block">
            <Tilt3D max={20}>
              <div className="card-3d p-3.5 bg-card flex items-center gap-2 rounded-2xl">
                <div className="grid h-9 w-9 place-items-center rounded-xl bg-success/15 ring-1 ring-success/30">
                  <BadgeCheck className="h-5 w-5 text-success" />
                </div>
                <div>
                  <div className="text-xs font-extrabold text-foreground">معتمد ZATCA</div>
                  <div className="text-[10px] text-foreground/65 font-medium">Phase 2</div>
                </div>
              </div>
            </Tilt3D>
          </div>

          <div className="absolute -top-5 -right-5 hidden md:block">
            <Tilt3D max={20}>
              <div className="card-3d p-3.5 bg-card flex items-center gap-2 rounded-2xl">
                <div className="grid h-9 w-9 place-items-center rounded-xl bg-gold/15 ring-1 ring-gold/40">
                  <Sparkles className="h-5 w-5 text-gold" />
                </div>
                <div>
                  <div className="text-xs font-extrabold text-foreground">ذكاء سعودي</div>
                  <div className="text-[10px] text-foreground/65 font-medium">GPT-Legal AR</div>
                </div>
              </div>
            </Tilt3D>
          </div>
        </div>
      </div>
    </section>
  );
}


/* ============ Stats ============ */
function Stats() {
  const stats = [
    { v: "100%", l: "فوترة الزكاة" },
    { v: "99.9%", l: "تسليم الواتساب" },
    { v: "98.4%", l: "دقة الصياغة" },
    { v: "24/7", l: "دعم فني بالرياض" },
  ];
  return (
    <section className="border-y border-border/50 bg-gradient-to-l from-primary/5 to-gold/5 py-10">
      <div className="container mx-auto grid grid-cols-2 gap-4 px-4 md:grid-cols-4">
        {stats.map((s) => (
          <div key={s.l} className="card-3d p-5 text-center">
            <div className="text-3xl md:text-4xl font-extrabold text-gradient-royal">{s.v}</div>
            <div className="mt-1 text-sm text-muted-foreground">{s.l}</div>
          </div>
        ))}
      </div>
    </section>
  );
}

/* ============ Features ============ */
const FEATURES = [
  { i: Bot, t: "المستشار الذكي القانوني", d: "صياغة اللوائح والمذكرات، تحليل القضايا، استشارات فورية وفق الأنظمة السعودية." },
  { i: Workflow, t: "مزامنة ناجز التلقائية", d: "سحب الجلسات والوكالات وطلبات التنفيذ من ناجز لحظياً دون إدخال يدوي." },
  { i: MessageSquare, t: "إشعارات واتساب رسمية", d: "تنبيه العميل قبل الجلسة بـ 24 ساعة، إرسال الفواتير والأحكام تلقائياً." },
  { i: Receipt, t: "فواتير ZATCA Phase 2", d: "إصدار الفواتير الضريبية المعتمدة بـ QR، وسندات القبض والصرف." },
  { i: FileSignature, t: "صياغة العقود الذكية", d: "عقود العمل، الشراكة، التوريد، الأتعاب — بصياغة احترافية فورية." },
  { i: Calculator, t: "حاسبة المدد النظامية", d: "حساب تلقائي لمدد الاستئناف والاعتراض والنقض وفق الأنظمة." },
  { i: ShieldCheck, t: "خزنة الوثائق الحصينة", d: "علامات مائية رقمية باسم الموظف، تشفير AES-256، خوادم سعودية." },
  { i: Users, t: "بوابة العميل وبوابة الموظف", d: "صلاحيات مخصصة، متابعة لحظية، سحب وإفلات للمهام." },
  { i: Library, t: "المكتبة القانونية الكاملة", d: "نظام المعاملات المدنية، الشركات، العمل، الاستثمار، الإثبات والتنفيذ." },
];

function Features() {
  return (
    <section id="features" className="py-20">
      <div className="container mx-auto px-4">
        <SectionHeader
          eyebrow="🛠️ العرض التفصيلي الشامل"
          title="منظومة قانونية كاملة تحت سقف واجهة واحدة"
          subtitle="لماذا تشتت أعمال مكتبك بين تطبيقات منفصلة؟ صُممت منصة العدالة لتغطي كل احتياجاتك اليومية ببساطة وأناقة."
        />
        <div className="mt-14 grid gap-6 md:grid-cols-2 lg:grid-cols-3">
          {FEATURES.map((f, i) => (
            <Tilt3D key={f.t} max={8} className="rounded-2xl">
              <div className="card-3d group p-7 h-full" style={{ animationDelay: `${i * 50}ms` }}>
                <div className="grid h-14 w-14 place-items-center rounded-2xl bg-gradient-to-br from-primary to-primary/70 text-gold shadow-md group-hover:scale-110 group-hover:rotate-6 transition-transform duration-500 pop-z">
                  <f.i className="h-7 w-7" />
                </div>
                <h3 className="mt-5 text-lg font-extrabold text-foreground">{f.t}</h3>
                <p className="mt-2 text-sm text-foreground/70 leading-relaxed font-medium">{f.d}</p>
                <div className="gold-divider mt-5 opacity-0 group-hover:opacity-100 transition-opacity" />
              </div>
            </Tilt3D>
          ))}
        </div>

      </div>
    </section>
  );
}

import { Users } from "lucide-react";

function SectionHeader({ eyebrow, title, subtitle }: { eyebrow: string; title: string; subtitle: string }) {
  return (
    <div className="mx-auto max-w-3xl text-center">
      <div className="text-sm font-bold text-gold tracking-wide">{eyebrow}</div>
      <h2 className="mt-3 text-3xl md:text-5xl font-extrabold text-gradient-royal leading-tight">{title}</h2>
      <p className="mt-4 text-muted-foreground text-lg leading-relaxed">{subtitle}</p>
    </div>
  );
}

/* ============ AI Showcase ============ */
function AIShowcase() {
  return (
    <section id="ai" className="py-20 bg-gradient-to-bl from-primary/5 via-background to-gold/5">
      <div className="container mx-auto px-4">
        <SectionHeader
          eyebrow="🤖 الذكاء الاصطناعي القضائي"
          title="مساعد الصياغة والتحليل الفوري"
          subtitle="أتمتة كتابة اللوائح ومذكرات الدفاع بدقة متناهية مطابقة للأنظمة التجارية والعمالية السعودية."
        />
        <div className="mt-14 grid gap-6 lg:grid-cols-2">
          <div className="card-night p-8">
            <h3 className="text-2xl font-bold text-gold">المكاسب الإستراتيجية</h3>
            <ul className="mt-5 space-y-3 text-sm">
              {[
                "توفير 90% من الوقت في البحث القضائي وصياغة الدفوع",
                "دقة لغوية ونظامية فائقة وفق المبادئ القضائية السعودية",
                "استخراج ذكي لملخصات ملفات الدعوى الضخمة في دقائق",
                "تحليل الموقف القانوني للعميل قبل اتخاذ القرار",
              ].map((t) => (
                <li key={t} className="flex items-start gap-3">
                  <CheckCircle2 className="h-5 w-5 shrink-0 text-gold" />
                  <span>{t}</span>
                </li>
              ))}
            </ul>
          </div>
          <div className="card-3d p-8">
            <h3 className="text-2xl font-bold text-primary">الفرق الواضح</h3>
            <div className="mt-5 space-y-4">
              <CompareRow type="bad" title="🔴 الطرق التقليدية" text="ساعات في مراجعة الكتب والنسخ واللصق من نماذج جامدة." />
              <CompareRow type="good" title="🟢 منصة العدالة" text="صياغة فورية مرتبطة بوقائع قضيتك ومواد الأنظمة المحددة." />
              <CompareRow type="bad" title="✘ البرامج المنافسة" text="قوالب جاهزة غير متزامنة مع ظروف قضيتك الحقيقية." />
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

function CompareRow({ type, title, text }: { type: "good" | "bad"; title: string; text: string }) {
  return (
    <div className={`rounded-xl border-r-4 p-4 ${type === "good" ? "border-success bg-success/5" : "border-destructive/60 bg-destructive/5"}`}>
      <div className="text-sm font-bold">{title}</div>
      <p className="mt-1 text-sm text-muted-foreground">{text}</p>
    </div>
  );
}

/* ============ Comparison Table ============ */
function Comparison() {
  const rows = [
    { f: "مزامنة وسحب قضايا ناجز آلياً", us: "لحظي وتلقائي بالكامل", them: "إدخال يدوي مرهق" },
    { f: "مساعد ذكاء اصطناعي قانوني سعودي", us: "خفير قضائي مدمج", them: "ملفات نصية بلا فطنة" },
    { f: "أتمتة واتساب وتنبيه قبل الجلسة 24 ساعة", us: "موصل واتساب رسمي", them: "اتصالات يدوية" },
    { f: "فواتير ZATCA Phase 2 معتمدة", us: "متطابق 100%", them: "إكسيل غير نظامي" },
    { f: "علامات مائية لمنع التسريب", us: "خزن بنكية مشفرة", them: "مستودعات مكشوفة" },
  ];
  return (
    <section id="comparison" className="py-20">
      <div className="container mx-auto px-4">
        <SectionHeader
          eyebrow="⚖️ القوة والسيادة التقنية"
          title="منصة العدالة مقابل المنافسين"
          subtitle="لماذا نتفوق على الأنظمة والخيارات التقليدية المطروحة بالسوق."
        />
        <div className="card-3d mt-14 overflow-hidden p-0">
          <div className="grid grid-cols-12 bg-gradient-to-l from-primary to-primary/80 px-6 py-4 text-primary-foreground text-sm font-bold">
            <div className="col-span-6">الميزة التقنية</div>
            <div className="col-span-3 text-center text-gold">⚖️ منصة العدالة</div>
            <div className="col-span-3 text-center">الأنظمة التقليدية</div>
          </div>
          {rows.map((r, i) => (
            <div key={r.f} className={`grid grid-cols-12 items-center gap-2 border-t border-border px-6 py-5 text-sm transition-colors hover:bg-accent/30 ${i % 2 ? "bg-muted/30" : ""}`}>
              <div className="col-span-6 font-semibold">{r.f}</div>
              <div className="col-span-3 text-center">
                <span className="inline-flex items-center gap-1.5 rounded-full bg-success/10 px-3 py-1 text-success font-bold text-xs">
                  <CheckCircle2 className="h-3.5 w-3.5" />{r.us}
                </span>
              </div>
              <div className="col-span-3 text-center text-muted-foreground text-xs">
                <span className="inline-flex items-center gap-1.5"><XCircle className="h-3.5 w-3.5 text-destructive" />{r.them}</span>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

/* ============ Calculator ============ */
function Calculator2() {
  const [cases, setCases] = useState(30);
  const [team, setTeam] = useState(5);
  const hours = Math.round(cases * 2 + team * 5);
  const value = (hours * 350).toLocaleString("ar-SA");
  return (
    <section className="py-20 bg-gradient-to-br from-primary/5 to-gold/10">
      <div className="container mx-auto px-4">
        <SectionHeader
          eyebrow="📊 حاسبة الوفورات"
          title="كم ستوفّر من ساعات وأموال شهرياً؟"
          subtitle="جرّب التقدير الفوري للوفورات التشغيلية الحقيقية لمكتبك مع منصة العدالة."
        />
        <div className="card-3d mt-12 grid gap-8 p-8 md:grid-cols-2">
          <div className="space-y-6">
            <div>
              <label className="text-sm font-semibold">عدد القضايا النشطة: <span className="text-gold font-bold">{cases}</span></label>
              <input type="range" min={5} max={200} value={cases} onChange={(e) => setCases(+e.target.value)}
                className="mt-3 w-full accent-[oklch(0.78_0.13_82)]" />
            </div>
            <div>
              <label className="text-sm font-semibold">عدد المستشارين بفريقك: <span className="text-gold font-bold">{team}</span></label>
              <input type="range" min={1} max={50} value={team} onChange={(e) => setTeam(+e.target.value)}
                className="mt-3 w-full accent-[oklch(0.78_0.13_82)]" />
            </div>
          </div>
          <div className="card-night p-6 text-center">
            <div className="text-xs text-gold">🎯 الوفورات الشهرية</div>
            <div className="mt-3 text-5xl font-extrabold text-gold">{hours} ساعة</div>
            <div className="text-sm mt-1 opacity-80">ساعات عمل مستعادة</div>
            <div className="gold-divider my-4" />
            <div className="text-3xl font-bold shimmer-text">{value} ر.س</div>
            <div className="text-sm mt-1 opacity-80">قيمة محققة للمكتب</div>
          </div>
        </div>
      </div>
    </section>
  );
}

/* ============ WhatsApp Demo ============ */
function WhatsAppDemo() {
  return (
    <section className="py-20">
      <div className="container mx-auto grid items-center gap-12 px-4 lg:grid-cols-2">
        <div>
          <div className="text-sm font-bold text-gold">📱 تكامل واتساب</div>
          <h2 className="mt-3 text-3xl md:text-4xl font-extrabold text-gradient-royal">تنبيه العملاء فوراً عبر واتساب</h2>
          <p className="mt-4 text-muted-foreground leading-relaxed">
            بمجرد اقتراب موعد جلسة أو صدور تحديث جديد، يقوم النظام آلياً بإرسال تفاصيل التحديث عبر رسالة احترافية لموكلك.
          </p>
          <ul className="mt-6 space-y-3">
            {[
              "التنبيه التلقائي قبل الجلسة بـ 24 ساعة",
              "إرسال الفواتير الإلكترونية وسندات القبض",
              "إشعار العميل بصدور الأحكام وتحديث حالتها",
            ].map((t) => (
              <li key={t} className="flex items-center gap-3 text-sm">
                <CheckCircle2 className="h-5 w-5 text-success" />{t}
              </li>
            ))}
          </ul>
        </div>
        <div className="mx-auto w-full max-w-sm">
          <div className="card-3d p-4 bg-gradient-to-b from-[#075E54] to-[#128C7E] text-white">
            <div className="flex items-center gap-3 border-b border-white/20 pb-3">
              <div className="grid h-10 w-10 place-items-center rounded-full bg-white/20"><Scale className="h-5 w-5" /></div>
              <div>
                <div className="text-sm font-bold">منصة العدالة</div>
                <div className="text-[10px] opacity-80">● متصل</div>
              </div>
            </div>
            <div className="mt-4 space-y-2">
              <div className="rounded-2xl rounded-tl-sm bg-white/15 p-3 text-sm">
                <div className="font-bold">⚖️ تذكير بموعد جلسة</div>
                <div className="mt-1 text-xs opacity-90">رقم القضية: 45829<br />الموعد: غداً 09:00 ص<br />المحكمة: العمالية - الرياض</div>
                <div className="mt-2 text-[10px] opacity-70 text-left">09:42 ✓✓</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

/* ============ Security ============ */
function Security() {
  return (
    <section id="security" className="py-20 bg-gradient-to-b from-background to-primary/5">
      <div className="container mx-auto px-4">
        <SectionHeader
          eyebrow="🇸🇦 السيادة الرقمية"
          title="حماية تامة للمستندات القضائية"
          subtitle="استضافات محلية في الرياض مطابقة لشروط الهيئة الوطنية للأمن السيبراني (NCA)."
        />
        <div className="mt-14 grid gap-6 md:grid-cols-2 lg:grid-cols-4">
          {[
            { v: "100%", l: "سيادة رقمية وطنية", i: Globe },
            { v: "AES-256", l: "تشفيرات بنكية", i: Lock },
            { v: "0%", l: "ثغرات أو تسريبات", i: ShieldCheck },
            { v: "24/7", l: "مراقبة نشطة", i: Zap },
          ].map((s) => (
            <div key={s.l} className="card-3d p-6 text-center">
              <div className="mx-auto grid h-14 w-14 place-items-center rounded-2xl bg-gradient-to-br from-gold to-gold/70 text-primary shadow-md">
                <s.i className="h-7 w-7" />
              </div>
              <div className="mt-4 text-3xl font-extrabold text-gradient-royal">{s.v}</div>
              <div className="mt-1 text-sm text-muted-foreground">{s.l}</div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

/* ============ Client Portal Section ============ */
function ClientPortal() {
  return (
    <section className="py-20">
      <div className="container mx-auto grid items-center gap-12 px-4 lg:grid-cols-2">
        <div className="card-3d p-8 order-2 lg:order-1">
          <div className="flex items-center gap-3 border-b pb-4">
            <div className="grid h-12 w-12 place-items-center rounded-xl bg-gradient-to-br from-primary to-primary/70 text-gold"><User className="h-6 w-6" /></div>
            <div>
              <div className="text-sm font-bold">بوابة العميل</div>
              <div className="text-xs text-muted-foreground">عرض كامل لتفاصيل قضيتك</div>
            </div>
          </div>
          <div className="mt-5 space-y-3 text-sm">
            <div className="rounded-lg bg-muted/40 p-3 flex justify-between"><span>رقم القضية</span><span className="font-bold">#45829</span></div>
            <div className="rounded-lg bg-muted/40 p-3 flex justify-between"><span>المحكمة</span><span className="font-bold">التجارية - الرياض</span></div>
            <div className="rounded-lg bg-success/10 border border-success/30 p-3 text-success font-semibold">✓ صدر حكم ابتدائي - يمكنك مراجعته</div>
            <button className="btn-gold w-full py-2.5 text-sm">📝 أرسل استشارة لمحاميك</button>
          </div>
        </div>
        <div className="order-1 lg:order-2">
          <div className="text-sm font-bold text-gold">👤 بوابة العميل المخصصة</div>
          <h2 className="mt-3 text-3xl md:text-4xl font-extrabold text-gradient-royal">تجربة عميل لا تُنسى</h2>
          <p className="mt-4 text-muted-foreground leading-relaxed">
            امنح موكليك بوابة احترافية يتابعون فيها قضيتهم لحظياً، يطلبون الاستشارات، ويستقبلون التحديثات — مع رابط دخول يُرسَل عبر واتساب مباشرة.
          </p>
          <ul className="mt-5 space-y-2 text-sm">
            {["عرض جميع تفاصيل القضية", "إرسال طلبات استشارة واستفسار", "استقبال ردود المكتب لحظياً", "رابط بوابة قابل للمشاركة عبر واتساب"].map((t) => (
              <li key={t} className="flex items-center gap-2"><CheckCircle2 className="h-4 w-4 text-success" />{t}</li>
            ))}
          </ul>
        </div>
      </div>
    </section>
  );
}

/* ============ Employee Portal ============ */
function EmployeePortal() {
  return (
    <section className="py-20 bg-gradient-to-l from-primary/5 to-transparent">
      <div className="container mx-auto grid items-center gap-12 px-4 lg:grid-cols-2">
        <div>
          <div className="text-sm font-bold text-gold">🧑‍💼 بوابة الموظف</div>
          <h2 className="mt-3 text-3xl md:text-4xl font-extrabold text-gradient-royal">إنجاز المهام بسلاسة احترافية</h2>
          <p className="mt-4 text-muted-foreground leading-relaxed">
            صلاحيات مخصصة لكل موظف، إسناد المهام بالسحب والإفلات، مزامنة فورية مع البوابة الرئيسية، وتنبيهات قبل انتهاء المهل.
          </p>
          <ul className="mt-5 space-y-2 text-sm">
            {["تحديد صلاحيات وأقسام كل موظف", "ربط القضايا والعملاء بكل موظف", "مزامنة المهام لحظياً مع الإدارة", "تنبيهات بالمهل المقتربة"].map((t) => (
              <li key={t} className="flex items-center gap-2"><CheckCircle2 className="h-4 w-4 text-success" />{t}</li>
            ))}
          </ul>
        </div>
        <div className="card-3d p-6">
          <div className="text-sm font-bold mb-4">مهام اليوم - أحمد المحمد</div>
          {[
            { t: "صياغة مذكرة جوابية - قضية 45829", s: "warning", d: "اليوم 14:00" },
            { t: "حضور جلسة - المحكمة العمالية", s: "primary", d: "غداً 09:00" },
            { t: "رفع لائحة استئناف - قضية 41203", s: "destructive", d: "متأخر يومين" },
          ].map((m) => (
            <div key={m.t} className={`mb-2 rounded-xl border-r-4 p-3 text-sm ${m.s === "destructive" ? "border-destructive bg-destructive/5" : m.s === "warning" ? "border-warning bg-warning/5" : "border-primary bg-primary/5"}`}>
              <div className="font-semibold">{m.t}</div>
              <div className="text-xs text-muted-foreground mt-0.5">⏰ {m.d}</div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

/* ============ FAQ ============ */
function FAQ() {
  return (
    <section id="faq" className="py-20">
      <div className="container mx-auto max-w-3xl px-4">
        <SectionHeader eyebrow="📚 الأسئلة الشائعة" title="كل ما تود معرفته" subtitle="إجابات واضحة عن الربط، الموثوقية، وتكامل واتساب." />
        <Accordion type="single" collapsible className="mt-10 space-y-3">
          {FAQ_ITEMS.map((it, i) => (
            <AccordionItem key={i} value={`i${i}`} className="card-3d border-none px-6">
              <AccordionTrigger className="text-right text-base font-bold hover:no-underline py-5">{it.q}</AccordionTrigger>
              <AccordionContent className="text-muted-foreground leading-relaxed pb-5">{it.a}</AccordionContent>
            </AccordionItem>
          ))}
        </Accordion>
      </div>
    </section>
  );
}

/* ============ Contact ============ */
function Contact() {
  return (
    <section className="py-20 bg-gradient-to-br from-primary/10 via-background to-gold/10">
      <div className="container mx-auto grid gap-10 px-4 lg:grid-cols-2">
        <div>
          <SectionHeader eyebrow="📞 تواصل معنا" title="اطلب عرضاً تفصيلياً" subtitle="يسعدنا التواصل لتقديم عرض شامل يتناسب مع إدارة مكتبكم القانوني." />
        </div>
        <form className="card-3d space-y-4 p-8">
          <Input placeholder="الاسم الكامل" className="h-12 text-right" />
          <Input placeholder="رقم الجوال" className="h-12 text-right" />
          <Input placeholder="البريد الإلكتروني" type="email" className="h-12 text-right" />
          <Textarea placeholder="تفاصيل الاستفسار" rows={4} className="text-right" />
          <Button className="btn-gold w-full h-12 text-base">إرسال الطلب</Button>
        </form>
      </div>
    </section>
  );
}

/* ============ Footer ============ */
function Footer() {
  return (
    <footer className="bg-gradient-to-b from-primary to-[oklch(0.18_0.04_260)] text-primary-foreground py-14">
      <div className="container mx-auto grid gap-10 px-4 md:grid-cols-4">
        <div className="md:col-span-2">
          <div className="flex items-center gap-2">
            <div className="grid h-10 w-10 place-items-center rounded-xl bg-gold/20 text-gold"><Scale className="h-5 w-5" /></div>
            <div className="text-lg font-bold">منصة <span className="text-gradient-gold">العدالة</span></div>
          </div>
          <p className="mt-4 text-sm opacity-80 leading-relaxed max-w-md">
            المنصة القانونية والشرعية الرقمية الأكثر تفصيلاً وسهولة لمكاتب المحاماة في الرياض وجدة وكافة مدن المملكة.
          </p>
        </div>
        <div>
          <h4 className="font-bold text-gold mb-3">المميزات</h4>
          <ul className="space-y-2 text-sm opacity-80">
            <li>✦ مزامنة ناجز والوكالات</li>
            <li>✦ المستشار الذكي AI</li>
            <li>✦ فواتير ZATCA</li>
          </ul>
        </div>
        <div>
          <h4 className="font-bold text-gold mb-3">الدعم</h4>
          <div className="text-sm opacity-80 space-y-2">
            <div className="flex items-center gap-2"><Mail className="h-4 w-4" />support@al-adalah.sa</div>
            <div className="flex items-center gap-2"><Phone className="h-4 w-4" />دعم ٢٤ ساعة - الرياض</div>
          </div>
        </div>
      </div>
      <div className="container mx-auto mt-10 border-t border-white/10 px-4 pt-6 text-xs opacity-60 text-center">
        © 2026 جميع الحقوق محفوظة لمنصة العدالة لإدارة مكاتب المحاماة.
      </div>
    </footer>
  );
}
