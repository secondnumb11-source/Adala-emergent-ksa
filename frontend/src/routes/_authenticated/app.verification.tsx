import { createFileRoute } from "@tanstack/react-router";
import { BadgeCheck, Scale, Building2, UserSearch, Gavel, ArrowLeft, MailCheck, Loader2 } from "lucide-react";
import { type LucideIcon } from "lucide-react";
import { useEffect, useState } from "react";
import { PageHeader } from "@/components/section-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

export const Route = createFileRoute("/_authenticated/app/verification")({
  component: VerificationServices,
});

type Tool = {
  title: string;
  short: string;
  description: string;
  icon: LucideIcon;
  url: string;
  gradient: string;
  tag: string;
};

const TOOLS: Tool[] = [
  {
    title: "حاسبة التركات والمواريث الشرعية",
    short: "الفرض والتعصيب وأنصبة الورثة",
    description:
      "أداة دقيقة لحساب الموزعات الشرعية والأنصبة وفقاً لأحكام الفرض والتعصيب بمختلف حالات الورثة.",
    icon: Scale,
    url: "https://najiz.sa/applications/inheritance/",
    gradient: "from-amber-400 via-amber-600 to-amber-900",
    tag: "حسابات شرعية",
  },
  {
    title: "تحديث الصكوك العقارية الرقمية",
    short: "تحويل الصكوك الورقية إلى رقمية",
    description:
      "خدمة وزارة العدل لتحديث الصكوك العقارية الورقية القديمة وتحويلها إلى صكوك رقمية نشطة موثوقة.",
    icon: Building2,
    url: "https://najiz.sa/applications/landing/service/2010202",
    gradient: "from-emerald-400 via-emerald-600 to-emerald-900",
    tag: "عقاري",
  },
  {
    title: "استعلام شؤون الأجانب والحدود",
    short: "تأشيرات العمل والترحيل والحدود",
    description:
      "التحقق من تأشيرات العمل، حالات الترحيل، وحدود الإقامة لشركاء العمل والكفلاء عبر منصة أبشر الرسمية.",
    icon: UserSearch,
    url: "https://www.absher.sa",
    gradient: "from-sky-400 via-sky-600 to-sky-900",
    tag: "أحوال وحدود",
  },
  {
    title: "استعلام تنفيذ الأحكام القضائية",
    short: "أوامر التنفيذ — المادة 34/46",
    description:
      "رصد أوامر التنفيذ القضائية والمطالبات المالية المترتبة عليها، مع متابعة سندات التنفيذ النشطة.",
    icon: Gavel,
    url: "https://enforcement.moj.gov.sa",
    gradient: "from-rose-400 via-rose-600 to-rose-900",
    tag: "تنفيذ",
  },
];

function VerificationServices() {
  return (
    <>
      <PageHeader
        icon={BadgeCheck}
        title="خدمات المساندة والتحقق"
        subtitle="الأدوات المعتمدة للتحقق والمساندة القضائية الذكية"
      />

      <Card className="card-night mb-8 p-6 md:p-8 text-center">
        <p className="text-sm md:text-base text-sidebar-foreground/90 max-w-3xl mx-auto leading-relaxed">
          مجموعة من الأدوات المتطورة لحساب المواريث الشرعية، تحديث الصكوك العقارية الرقمية،
          التحقق والاستعلام عن الحدود، ومتابعة سندات التنفيذ — في واجهة واحدة موحدة.
        </p>
        <div className="gold-divider mt-5 max-w-xs mx-auto" />
      </Card>

      <ResendActivationCard />

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {TOOLS.map((t) => (
          <a key={t.title} href={t.url} target="_blank" rel="noreferrer" className="group block">
            <Card className="card-3d shine border-none p-6 h-full flex flex-col gap-4 cursor-pointer relative overflow-hidden">
              {/* decorative gradient orb */}
              <div
                className={`absolute -top-16 -left-16 h-40 w-40 rounded-full bg-gradient-to-br ${t.gradient} opacity-20 blur-2xl group-hover:opacity-40 transition-opacity`}
              />

              <div className="flex items-start gap-4 relative">
                <div
                  className={`grid h-20 w-20 shrink-0 place-items-center rounded-2xl bg-gradient-to-br ${t.gradient} text-white shadow-xl`}
                  style={{
                    boxShadow:
                      "inset 0 2px 0 rgba(255,255,255,0.35), inset 0 -3px 0 rgba(0,0,0,0.2), 0 14px 30px -10px rgba(0,0,0,0.4)",
                  }}
                >
                  <t.icon className="h-9 w-9" strokeWidth={2.2} />
                </div>
                <div className="flex-1 min-w-0">
                  <span className="inline-block text-[10px] font-bold uppercase tracking-wider text-gold bg-gold/10 px-2 py-0.5 rounded">
                    {t.tag}
                  </span>
                  <h3 className="mt-1.5 font-extrabold text-lg leading-tight">{t.title}</h3>
                  <p className="mt-1 text-xs text-muted-foreground font-medium">{t.short}</p>
                </div>
              </div>

              <p className="text-sm text-foreground/80 leading-relaxed relative">
                {t.description}
              </p>

              <div className="mt-auto flex items-center justify-between border-t border-border/60 pt-4 relative">
                <span className="text-xs text-muted-foreground">معتمد رسمياً</span>
                <span className="inline-flex items-center gap-2 text-sm font-bold text-primary group-hover:text-gold group-hover:gap-3 transition-all">
                  فتح الأداة
                  <ArrowLeft className="h-4 w-4" />
                </span>
              </div>
            </Card>
          </a>
        ))}
      </div>
    </>
  );
}

function ResendActivationCard() {
  const [email, setEmail] = useState<string | null>(null);
  const [confirmed, setConfirmed] = useState<boolean>(true);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => {
      const u = data.user;
      setEmail(u?.email ?? null);
      setConfirmed(!!u?.email_confirmed_at);
    });
  }, []);

  async function resend() {
    if (!email) return;
    setLoading(true);
    const redirectTo = `${window.location.origin}/auth`;
    const { error } = await supabase.auth.resend({ type: "signup", email, options: { emailRedirectTo: redirectTo } });
    setLoading(false);
    if (error) {
      toast.error(`فشل إعادة الإرسال: ${error.message}`);
      return;
    }
    toast.success(`تم إرسال رسالة التفعيل إلى ${email}`);
  }

  return (
    <Card className="mb-8 p-5 md:p-6 flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
      <div className="flex items-start gap-3">
        <div className="grid h-12 w-12 place-items-center rounded-xl bg-primary/10 text-primary">
          <MailCheck className="h-6 w-6" />
        </div>
        <div>
          <h3 className="font-bold text-base">رسالة تفعيل الحساب</h3>
          <p className="text-xs text-muted-foreground mt-1">
            {email
              ? confirmed
                ? `الحساب ${email} مفعَّل بالفعل.`
                : `إرسال رسالة تفعيل جديدة إلى ${email}.`
              : "جارٍ قراءة بيانات المستخدم…"}
          </p>
        </div>
      </div>
      <Button onClick={resend} disabled={!email || confirmed || loading} className="gap-2">
        {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <MailCheck className="h-4 w-4" />}
        إعادة إرسال رسالة التفعيل
      </Button>
    </Card>
  );
}
