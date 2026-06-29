import { createFileRoute, Link } from "@tanstack/react-router";
import {
  Sparkles, Bot, ScrollText, FileSignature, Receipt, Calculator,
  Clock, ShieldCheck, ArrowLeft,
} from "lucide-react";
import { PageHeader } from "@/components/section-shell";
import { Card } from "@/components/ui/card";

export const Route = createFileRoute("/_authenticated/app/ai/")({
  component: AiHub,
});

const SECTIONS = [
  {
    to: "/app/ai/consultant",
    title: "المستشار والمحلل الذكي",
    desc: "استشارات قانونية فورية، تحليل القضايا والمواقف، وتلخيص المستندات وفق الأنظمة السعودية.",
    icon: Bot,
    gradient: "from-indigo-500 via-blue-500 to-cyan-400",
    glow: "shadow-[0_20px_60px_-12px_rgba(99,102,241,0.45)]",
  },
  {
    to: "/app/ai/memos",
    title: "صياغة اللوائح والمذكرات",
    desc: "صحف الدعاوى، المذكرات الجوابية، لوائح الاستئناف والاعتراض، الإشعارات والإنذارات.",
    icon: ScrollText,
    gradient: "from-amber-500 via-gold to-yellow-400",
    glow: "shadow-[0_20px_60px_-12px_rgba(245,158,11,0.45)]",
  },
  {
    to: "/app/ai/contracts",
    title: "صياغة العقود",
    desc: "عقود العمل، الشراكة، الاستثمار، التوريد، الامتياز، المقاولات، وعقود أتعاب المكتب.",
    icon: FileSignature,
    gradient: "from-emerald-500 via-teal-500 to-green-400",
    glow: "shadow-[0_20px_60px_-12px_rgba(16,185,129,0.45)]",
  },
  {
    to: "/app/ai/invoices",
    title: "إصدار الفواتير",
    desc: "فواتير الأتعاب الضريبية، بوابات الدفع الإلكتروني، سندات القبض والصرف.",
    icon: Receipt,
    gradient: "from-rose-500 via-pink-500 to-fuchsia-400",
    glow: "shadow-[0_20px_60px_-12px_rgba(244,63,94,0.45)]",
  },
  {
    to: "/app/ai/calculator",
    title: "الحاسبة القضائية",
    desc: "متابعة المقبوضات والمصروفات، احتساب ضريبة القيمة المضافة 15% وفق ZATCA، وحساب الأتعاب.",
    icon: Calculator,
    gradient: "from-violet-500 via-purple-500 to-indigo-400",
    glow: "shadow-[0_20px_60px_-12px_rgba(139,92,246,0.45)]",
  },
  {
    to: "/app/ai/deadlines",
    title: "حاسبة المدد النظامية",
    desc: "حساب تلقائي لمدد الاستئناف والاعتراض والنقض وطلبات التنفيذ مع عداد تنازلي.",
    icon: Clock,
    gradient: "from-orange-500 via-amber-500 to-yellow-400",
    glow: "shadow-[0_20px_60px_-12px_rgba(249,115,22,0.45)]",
  },
  {
    to: "/app/ai/zatca",
    title: "الفواتير المعتمد ZATCA",
    desc: "مزامنة وإصدار الفواتير المعتمدة مع منصة فاتورة (المرحلة الثانية) وإدارة المدفوعات.",
    icon: ShieldCheck,
    gradient: "from-sky-500 via-blue-500 to-indigo-500",
    glow: "shadow-[0_20px_60px_-12px_rgba(14,165,233,0.45)]",
  },
];

function AiHub() {
  return (
    <>
      <PageHeader
        icon={Sparkles}
        title="المساعد الذكي وأدوات الذكاء الاصطناعي"
        subtitle="منظومة متكاملة من أدوات الذكاء الاصطناعي لخدمة المحامي والمكتب القانوني"
      />

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {SECTIONS.map((s, i) => (
          <Link key={s.to} to={s.to} className="group block focus:outline-none">
            <Card
              className={`card-3d border-none p-0 overflow-hidden h-full ${s.glow} transition-all duration-500`}
              style={{ animationDelay: `${i * 60}ms` }}
            >
              <div className={`relative h-28 bg-gradient-to-br ${s.gradient} overflow-hidden`}>
                <div className="absolute inset-0 bg-[radial-gradient(circle_at_30%_20%,rgba(255,255,255,0.4),transparent_60%)]" />
                <div className="absolute -bottom-6 -left-6 h-32 w-32 rounded-full bg-white/10 blur-2xl" />
                <div className="relative h-full flex items-center justify-between p-6">
                  <div className="grid h-16 w-16 place-items-center rounded-2xl bg-white/25 backdrop-blur-md border border-white/40 text-white shadow-2xl transform-gpu transition-transform duration-500 group-hover:scale-110 group-hover:-rotate-6">
                    <s.icon className="h-8 w-8" strokeWidth={2.2} />
                  </div>
                  <ArrowLeft className="h-5 w-5 text-white/70 transition-transform duration-500 group-hover:-translate-x-2 group-hover:text-white" />
                </div>
              </div>
              <div className="p-5">
                <h3 className="font-extrabold text-base mb-2 group-hover:text-gold transition-colors">
                  {s.title}
                </h3>
                <p className="text-xs text-muted-foreground leading-relaxed">{s.desc}</p>
              </div>
            </Card>
          </Link>
        ))}
      </div>
    </>
  );
}
