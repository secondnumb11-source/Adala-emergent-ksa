import {
  Bot, Workflow, Network, Receipt, ShieldCheck, MessageSquare,
  CheckCircle2, ArrowLeftRight, Sparkles, Lock,
} from "lucide-react";
import { useState, type ReactNode } from "react";
import { Tilt3D } from "@/components/tilt-3d";

/**
 * "محطات الميزات" — Deep-dive interactive showcase of the 6 flagship
 * capabilities (AI Drafting, Najiz Sync, Tasks, ZATCA Finance, Vault,
 * WhatsApp). Each station carries the same 4-part luxury breakdown:
 *   1) الفوائد الإستراتيجية
 *   2) تحليل النقلة (traditional vs. Al-Adalah)
 *   3) منفعة العدالة الحصرية + عيوب المنافسين
 *   4) لوحة محاكاة مرئية فاخرة (Mockup panel)
 */

type Station = {
  id: string;
  icon: typeof Bot;
  badge: string;
  title: string;
  subtitle: string;
  description: string;
  benefits: string[];
  traditional: string;
  adalah: string;
  exclusive: string;
  competitors: string;
  mock: () => ReactNode;
  gradient: string;
};

const STATIONS: Station[] = [
  {
    id: "ai",
    icon: Bot,
    badge: "AI-DRAFTING-STATION-SECURE",
    title: "مساعد الصياغة والتحليل الفوري بالذكاء الاصطناعي",
    subtitle: "أتمتة كتابة اللوائح ومذكرات الدفاع بدقة متناهية مطابقة للأنظمة التجارية والعمالية",
    description:
      "محرك صياغة مدمج يغنيك عن البدء من الصفر. يحلل وثائق الدعاوى تلقائياً، يستخرج الثغرات النظامية، ويصوغ مذكرات الرد والاعتراض واللوائح الاستئنافية بلغة رصينة مطابقة لمعايير المحاكم التجارية والعامة بموجب الأنظمة السعودية السارية.",
    benefits: [
      "توفير 90% من الوقت في البحث القضائي وصياغة الدفوع وصحف الدعاوى.",
      "دقة لغوية ونظامية فائقة وفق المبادئ القضائية المقررة بالمملكة.",
      "استخراج ذكي لملخصات ملفات الدعوى الضخمة (آلاف الصفحات في دقيقة واحدة).",
    ],
    traditional:
      "البدء يدوياً من الصفر مع هدر ساعات في مراجعة الكتب والأنظمة والنسخ واللصق.",
    adalah:
      "صياغة المذكرة الجوابية والبحث القضائي الفوري بضغطة زر بسرعة خارقة من مكان واحد آمن.",
    exclusive:
      "توليد فوري ذكي يعتمد على وقائع ملف الدعوى مباشرة ويربطها بالمواد القانونية المحددة.",
    competitors:
      "قوالب جامدة معدة مسبقاً غير متزامنة مع ملابسات وظروف قضيتك الحقيقية.",
    gradient: "from-indigo-500 via-blue-500 to-cyan-400",
    mock: () => (
      <div className="space-y-3 text-sm">
        <div className="rounded-xl bg-white/8 p-4 ring-1 ring-white/10">
          <div className="text-gold text-xs font-bold mb-1.5">🤖 المساعد العدلي</div>
          <p className="leading-relaxed">"قم بصياغة لائحة اعتراضية على حكم في نزاع توريد تجاري..."</p>
        </div>
        <div className="rounded-xl bg-gradient-to-bl from-gold/20 to-gold/10 p-4 border border-gold/40">
          <div className="text-gold text-xs font-bold mb-1.5">✓ التشخيص</div>
          <p className="leading-relaxed">مطابقة الحكم بمواد نظام المحاكم التجارية السعودي.</p>
          <p className="mt-2 leading-relaxed text-xs opacity-90">
            🚀 <strong className="text-gold">الدفع المقترح:</strong> عدم مطابقة الخدمة للمادة السابعة من العقد.
          </p>
        </div>
      </div>
    ),
  },
  {
    id: "najiz",
    icon: Workflow,
    badge: "NAJIZ-SYNC-STATION-SECURE",
    title: "مزامنة وسحب بيانات ناجز والوكالات آلياً",
    subtitle: "مزامنة بضغطة زر لسحب قضايا القانون التجاري والعام ومواعيد الجلسات",
    description:
      "وداعاً للدخول اليدوي اليومي لبوابات ناجز. تسحب العدالة كافة تفاصيل القضايا والوكالات وجدول السجلات والقرارات فور صدورها، لتنظيمها وعرضها في لوحة معلومات موحدة متوافقة مع متطلبات وزارة العدل.",
    benefits: [
      "رصد وتحديث بيانات القضايا في أقل من 3 ثوان وتفادي ضياع الجلسات أو انتهاء المهل.",
      "تحديث ذاتي يعزز دقة وسلامة الأجندة القضائية للمستشارين بأمان.",
      "جدولة ومزامنة تواريخ القضايا مع تذكيرات تقويم تفاعلية بالفروع.",
    ],
    traditional:
      "تعاطٍ يدوي مرهق ويومي مع بوابات العدالة المتعددة مع احتمالية عالية لفوات موعد جلسة.",
    adalah:
      "تزامن رقمي آمن وحافظة واحدة موحدة تُظهر مواعيد الجلسات والدوائر آلياً ولحظياً.",
    exclusive:
      "مزامنة مشفرة وآمنة بنسبة 100% تسحب أطراف الدعوى وملخصاتها ومواعيدها في ثوانٍ معدودة.",
    competitors:
      "فتح موقع ناجز مئات المرات وتحديث الملفات بالنسخ واللصق المعرض للخطأ البشري.",
    gradient: "from-emerald-500 via-teal-500 to-green-400",
    mock: () => (
      <div className="space-y-3 text-sm">
        <div className="flex items-center justify-between rounded-xl bg-white/8 p-3 ring-1 ring-white/10">
          <span className="text-xs">بوابة ناجز — وزارة العدل</span>
          <span className="text-[10px] font-bold text-success">● متصل</span>
        </div>
        <div className="rounded-xl bg-gradient-to-bl from-gold/20 to-gold/10 p-4 border border-gold/40">
          <div className="text-gold text-xs font-bold mb-1.5">🔍 دعوى جديدة (437194619)</div>
          <p className="text-xs leading-relaxed">المدعي: شركة المشروبات العامة</p>
          <p className="text-xs mt-1">الجلسة: 15 يونيو 2026 — 10:00 ص</p>
          <div className="mt-2 text-[10px] opacity-80">✓ مزامنة مستمرة لأجندة المكتب</div>
        </div>
      </div>
    ),
  },
  {
    id: "tasks",
    icon: Network,
    badge: "TASK-MANAGEMENT-STATION-SECURE",
    title: "إسناد وحوكمة المهام بالسحب والإفلات التفاعلي",
    subtitle: "توزيع ملفات القضايا، ومتابعة مذكرات الردود، والتحكم بالإنتاجية",
    description:
      "لوحة تخطيط تفاعلية تتيح حوكمة وإنتاجية مكاتب الاستشارات. توزّع صياغة المذكرات، ومراجعة العقود، وحضور الجلسات بين المستشارين، وتتابع سير الإجراءات بالسحب والإفلات بسلاسة.",
    benefits: [
      "رقابة فورية على إنتاجية المستشارين بالفروع بمخطط زمني واضح للمعاملات.",
      "تسريع إنجاز الملفات بنسبة 60% عبر تحديد المسؤوليات والأهداف للمساعدين.",
      "حفظ تاريخ العمل والتعليقات والملفات المتبادلة لكل دعوى بمكان واحد قابل للجرد.",
    ],
    traditional:
      "متابعة شفهية أو رسائل مبعثرة ومهام تائهة بين محادثات الواتساب والتطبيقات.",
    adalah:
      "عوالم إلكترونية مرئية تُظهر المكلَّف والتاريخ الفعلي ومستند الدعوى المتصل بجلاء.",
    exclusive:
      "ارتباط مباشر وبنيوي بين بطاقة المهمة وملف الدعوى وسندات قبض ورصيد أتعاب العميل.",
    competitors:
      "تطبيقات مهام منفصلة تزيد تشتت الفريق ولا ترتبط بالمالية أو الدعاوى.",
    gradient: "from-amber-500 via-gold to-yellow-400",
    mock: () => (
      <div className="space-y-2 text-sm">
        {[
          { t: "صياغة مذكرة — قضية 45829", s: "warning", d: "اليوم 14:00" },
          { t: "حضور جلسة — العمالية", s: "primary", d: "غداً 09:00" },
          { t: "رفع استئناف — قضية 41203", s: "destructive", d: "متأخر يومين" },
        ].map((m) => (
          <div
            key={m.t}
            className={`rounded-xl border-r-4 p-3 bg-white/8 ${
              m.s === "destructive" ? "border-destructive" :
              m.s === "warning" ? "border-warning" : "border-gold"
            }`}
          >
            <div className="font-semibold text-xs">{m.t}</div>
            <div className="text-[10px] opacity-70 mt-0.5">⏰ {m.d}</div>
          </div>
        ))}
      </div>
    ),
  },
  {
    id: "zatca",
    icon: Receipt,
    badge: "FINANCE-ZATCA-STATION-SECURE",
    title: "نظام الإثبات المالي المعتمد للزكاة (المرحلة الثانية)",
    subtitle: "حساب أتعاب المرافعة، المصاريف، سندات الصرف والقبض وفق المعايير السعودية",
    description:
      "منظومة محاسبة وعلاقات مالية شاملة. تحسب عقود الأتعاب على دفعات ميسرة أو ساعات استشارية للشركات، وتولد فواتير ضريبية مشفرة متوافقة كلياً مع نظام الفوترة الإلكتروني (المرحلة الثانية — فاتورة).",
    benefits: [
      "امتثال كامل 100% مع هيئة الزكاة والضريبة والجمارك.",
      "تسريع تحصيل الأتعاب بمعدل الضعف عبر فواتير تُرسل للعميل عبر واتساب.",
      "تقارير أرباح وخسائر ومصاريف محاكم مفصلة لكل دعوى وعميل ونسب الشركاء.",
    ],
    traditional:
      "حسابات يدوية مبعثرة وفواتير Word لا تحوي تشفير QR الضريبي المعتمد.",
    adalah:
      "دورة فوترة آلية ترسل سندات القبض المتوافقة فوراً للعميل بضغطة زر.",
    exclusive:
      "توليد تلقائي للفواتير المشفرة مع تحصيل الأتعاب بروابط دفع ذكية.",
    competitors:
      "برامج فوترة عامة مستوردة مجهدة في الإعفاء الضريبي وغير مرتبطة بنظام القضايا.",
    gradient: "from-rose-500 via-pink-500 to-fuchsia-400",
    mock: () => (
      <div className="space-y-3 text-sm">
        <div className="rounded-xl bg-white/8 p-4 ring-1 ring-white/10">
          <div className="flex justify-between text-xs">
            <span>سند قبض ضريبي #FT-1029</span>
            <span className="text-gold font-bold">QR</span>
          </div>
          <div className="mt-3 text-xs opacity-90">العميل: شركة سدافكو للتنمية</div>
          <div className="mt-1 text-xs opacity-90">الإجمالي (شامل ض.ق.م):</div>
          <div className="text-2xl font-extrabold text-gold mt-1">42,000 ر.س</div>
        </div>
        <div className="text-[10px] opacity-80">✓ متطابق ZATCA Phase 2</div>
      </div>
    ),
  },
  {
    id: "vault",
    icon: ShieldCheck,
    badge: "VAULT-SECURITY-STATION-SECURE",
    title: "خزنة الوثائق الحصينة والعلامات المائية الرقمية",
    subtitle: "حفظ المذكرات والتعميلات ومستندات الخصوم وتتبع هوية المحمّل آلياً",
    description:
      "حماية مطلقة لأسرار وعقود منشأتك وعملائك. منصة سحابية مشفرة بـ AES-256 لحفظ وصيانة ملفات القضايا، مع تطبيق ذكي للعلامات المائية الرقمية التي تطبع اسم وهوية وتوقيت الموظف الذي حمّل أي مستند تتبعاً لأي تسريب.",
    benefits: [
      "حماية أسرار العملاء بختم مائي يحمل تفاصيل مشغل الملف لمنع التسريب.",
      "سجل تتبع لكل إجراء (من فتح؟ من عدّل؟ من نزّل؟ ومتى؟).",
      "تشفير فائق للملفات يضمن الوصول للمصرَّح لهم بملف الدعوى فقط.",
    ],
    traditional:
      "ملفات مخزنة بأجهزة متعددة أو خوادم خارجية بدون حماية أو ختم مائي.",
    adalah:
      "أرشيف مركزي مشفر وصلاحيات صارمة توضح جرد ونشاط الفريق بدقة بنكية.",
    exclusive:
      "خزانة مشفرة تتبع سياسات الهيئة الوطنية للأمن السيبراني لحفظ الخصوصية.",
    competitors:
      "تخزين بملفات خارجية مكشوفة تعرض أسرار الخصوم للخطر بدون مسؤولية مائية.",
    gradient: "from-sky-500 via-indigo-500 to-violet-500",
    mock: () => (
      <div className="space-y-3 text-sm">
        <div className="rounded-xl bg-white/8 p-4 ring-1 ring-white/10">
          <div className="flex items-center gap-2 text-xs">
            <Lock className="h-4 w-4 text-gold" />
            <span>وثيقة_تعميل_سري.pdf</span>
          </div>
          <div className="mt-2 text-[10px] opacity-80">4.2 MB • AES-256</div>
        </div>
        <div className="rounded-xl bg-gradient-to-bl from-gold/15 to-transparent p-3 border border-gold/30 text-[11px] leading-relaxed">
          ⚠️ محمي بعلامة مائية رقمية تمنع تسريب التفاصيل خارج المعتمدين.
        </div>
      </div>
    ),
  },
  {
    id: "whatsapp",
    icon: MessageSquare,
    badge: "WHATSAPP-ALERTS-STATION-SECURE",
    title: "بث إشعارات وتحديثات الواتساب التلقائية",
    subtitle: "إشعار العملاء بقرارات الدوائر وتواريخ الجلسات ومواعيد سداد الأتعاب تلقائياً",
    description:
      "بوابة بث ذكية تربط مكتبك بهواتف العملاء مباشرة. بفضل محرك الأتمتة، تُبثّ رسائل تذكير مخصصة باسم العميل قبل الجلسات بـ 24 ساعة، ويُشعَر بصدور الأحكام واستلام الدفعات بسندات QR.",
    benefits: [
      "توطيد الثقة مع العملاء عبر تحديثهم لحظياً على تطبيقهم المفضل.",
      "تخفيض اتصالات المراجعات اليدوية بنسبة تتجاوز 85%.",
      "تنبيه آلي للعميل وفريق العمل لمنع فوات أي مدد نظامية.",
    ],
    traditional:
      "اتصالات يدوية متكررة أو رسائل SMS ناقصة وجافة بلا متابعة.",
    adalah:
      "متابعة آلية على مدار الساعة — العميل يعلم بكل تحديث وسداد فوراً عبر واتساب.",
    exclusive:
      "ربط متكامل مع نظام تذكير دوري ذكي يعمل في الخلفية 24/7.",
    competitors:
      "رسائل SMS باهظة محدودة الحروف تفتقر للجاذبية والمهنية.",
    gradient: "from-green-500 via-emerald-500 to-teal-400",
    mock: () => (
      <div className="rounded-xl bg-gradient-to-b from-[#075E54] to-[#128C7E] text-white p-3 text-sm">
        <div className="text-[10px] opacity-80 mb-2">10:30 ص — Twilio WhatsApp</div>
        <div className="rounded-2xl rounded-tl-sm bg-white/15 p-3 text-xs leading-relaxed">
          ⚖️ <strong>تذكير قضائي</strong>: المحترم أحمد بكر، نحيطكم علماً باقتراب جلسة قضيتكم رقم 43194 صباح غدٍ بعد أقل من 24 ساعة...
        </div>
        <div className="text-[10px] opacity-70 mt-2 text-left">✓✓ تم التوصيل</div>
      </div>
    ),
  },
];

export function FeatureStations() {
  const [active, setActive] = useState(STATIONS[0].id);
  const station = STATIONS.find((s) => s.id === active)!;

  return (
    <section id="stations" className="py-20 bg-gradient-to-b from-background via-primary/5 to-background">
      <div className="container mx-auto px-4">
        <div className="mx-auto max-w-3xl text-center">
          <div className="text-sm font-bold text-gold tracking-wide">
            🛠️ العرض التفصيلي الشامل
          </div>
          <h2 className="mt-3 text-3xl md:text-5xl font-extrabold text-gradient-royal leading-tight">
            محطات العدالة — الفرق الذي تشعر به
          </h2>
          <p className="mt-4 text-muted-foreground text-lg leading-relaxed">
            لماذا تشتت أعمال مكتبك بين تطبيقات منفصلة؟ انقر على أي محطة فنية أدناه لاستكشاف
            الفرق الشاسع بين منصة العدالة والأنظمة التقليدية.
          </p>
        </div>

        {/* Tabs */}
        <div className="mt-10 flex flex-wrap items-center justify-center gap-2">
          {STATIONS.map((s) => {
            const Icon = s.icon;
            const isActive = s.id === active;
            return (
              <button
                key={s.id}
                onClick={() => setActive(s.id)}
                className={`group inline-flex items-center gap-2 rounded-2xl px-4 py-2.5 text-xs md:text-sm font-bold transition-all duration-300 border-2 ${
                  isActive
                    ? "border-gold bg-gradient-to-bl from-gold/20 to-gold/5 text-primary shadow-[0_8px_24px_-8px] shadow-gold/40 -translate-y-0.5"
                    : "border-border/60 bg-card/60 text-muted-foreground hover:border-gold/40 hover:text-foreground"
                }`}
              >
                <Icon className={`h-4 w-4 ${isActive ? "text-gold" : ""}`} />
                <span className="hidden sm:inline">{s.title.split("—")[0].split("بالذكاء")[0].split("بالسحب")[0].slice(0, 28)}</span>
                <span className="sm:hidden">{s.id}</span>
              </button>
            );
          })}
        </div>

        {/* Active station */}
        <div className="mt-10 grid gap-8 lg:grid-cols-5">
          {/* Left: details */}
          <div className="lg:col-span-3">
            <Tilt3D max={5} className="rounded-3xl">
              <div className="card-3d p-8 h-full">
                <div className="flex items-center gap-4 border-b border-border pb-5">
                  <div className={`grid h-16 w-16 place-items-center rounded-2xl bg-gradient-to-br ${station.gradient} text-white shadow-lg`}>
                    <station.icon className="h-8 w-8" />
                  </div>
                  <div className="min-w-0">
                    <div className="text-[10px] font-mono tracking-wider text-gold">{station.badge}</div>
                    <h3 className="mt-1 text-xl md:text-2xl font-extrabold text-foreground leading-tight">
                      {station.title}
                    </h3>
                  </div>
                </div>

                <p className="mt-5 text-sm text-foreground/70 leading-relaxed font-medium">
                  <span className="block text-gold font-bold mb-2">{station.subtitle}</span>
                  {station.description}
                </p>

                {/* Benefits */}
                <div className="mt-6">
                  <div className="inline-flex items-center gap-2 rounded-full bg-success/10 px-3 py-1 text-xs font-bold text-success ring-1 ring-success/30">
                    <Sparkles className="h-3.5 w-3.5" /> الفوائد والمكاسب الإستراتيجية
                  </div>
                  <ul className="mt-3 space-y-2">
                    {station.benefits.map((b) => (
                      <li key={b} className="flex items-start gap-2 text-sm leading-relaxed">
                        <CheckCircle2 className="h-4 w-4 shrink-0 text-gold mt-0.5" />
                        <span>{b}</span>
                      </li>
                    ))}
                  </ul>
                </div>

                {/* Transition analysis */}
                <div className="mt-7">
                  <div className="inline-flex items-center gap-2 rounded-full bg-primary/10 px-3 py-1 text-xs font-bold text-primary ring-1 ring-primary/30">
                    <ArrowLeftRight className="h-3.5 w-3.5" /> تحليل النقلة في طبيعة العمل
                  </div>
                  <div className="mt-3 grid gap-3 sm:grid-cols-2">
                    <Row icon="🔴" tone="bad" title="الطرق التقليدية" text={station.traditional} />
                    <Row icon="🟢" tone="good" title="مع منصة العدالة" text={station.adalah} />
                  </div>
                </div>

                {/* Exclusive vs competitors */}
                <div className="mt-5 grid gap-3 sm:grid-cols-2">
                  <Row icon="⚖️" tone="gold" title="منفعة العدالة الحصرية" text={station.exclusive} />
                  <Row icon="✘" tone="bad" title="عيوب البرامج الأخرى" text={station.competitors} />
                </div>

                <div className="mt-6 inline-flex items-center gap-2 text-xs font-bold text-gold">
                  ⚡ مفعَّل بالكامل في النسخة التجريبية المجانية
                </div>
              </div>
            </Tilt3D>
          </div>

          {/* Right: mockup panel */}
          <div className="lg:col-span-2">
            <Tilt3D max={12} className="rounded-3xl sticky top-24">
              <div className="card-3d p-1.5 rounded-3xl">
                <div className={`rounded-[1.4rem] bg-gradient-to-br ${station.gradient} p-6 text-white relative overflow-hidden min-h-[420px]`}>
                  <div className="pointer-events-none absolute -top-20 -right-20 h-56 w-56 rounded-full bg-white/20 blur-3xl" />
                  <div className="pointer-events-none absolute -bottom-20 -left-20 h-56 w-56 rounded-full bg-black/20 blur-3xl" />

                  <div className="relative flex items-center justify-between border-b border-white/20 pb-3">
                    <div className="flex items-center gap-2">
                      <div className="grid h-9 w-9 place-items-center rounded-xl bg-white/20 ring-1 ring-white/30">
                        <station.icon className="h-5 w-5" />
                      </div>
                      <span className="text-sm font-bold">معاينة حية</span>
                    </div>
                    <span className="text-[10px] font-bold rounded-full bg-white/20 px-2.5 py-1 ring-1 ring-white/30">
                      ● مباشر
                    </span>
                  </div>

                  <div className="relative mt-5">{station.mock()}</div>
                </div>
              </div>
            </Tilt3D>
          </div>
        </div>
      </div>
    </section>
  );
}

function Row({
  icon, tone, title, text,
}: { icon: string; tone: "good" | "bad" | "gold"; title: string; text: string }) {
  const cls =
    tone === "good" ? "border-success/50 bg-success/5" :
    tone === "gold" ? "border-gold/50 bg-gold/5" :
    "border-destructive/40 bg-destructive/5";
  const titleCls =
    tone === "good" ? "text-success" :
    tone === "gold" ? "text-gold" :
    "text-destructive";
  return (
    <div className={`rounded-xl border-r-4 p-3 ${cls} transition-transform duration-300 hover:-translate-y-0.5`}>
      <div className={`text-xs font-bold ${titleCls}`}>{icon} {title}</div>
      <p className="mt-1 text-xs text-foreground/75 leading-relaxed">{text}</p>
    </div>
  );
}
