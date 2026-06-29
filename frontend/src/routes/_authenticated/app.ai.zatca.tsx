import { createFileRoute, Link } from "@tanstack/react-router";
import { ShieldCheck, ArrowRight, CheckCircle2, ExternalLink, FileText, Database, Link2, AlertCircle } from "lucide-react";
import { PageHeader } from "@/components/section-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";

export const Route = createFileRoute("/_authenticated/app/ai/zatca")({
  component: ZatcaPage,
});

function ZatcaPage() {
  return (
    <>
      <PageHeader
        icon={ShieldCheck}
        title="الفواتير المعتمدة - ZATCA"
        subtitle="مزامنة وإصدار الفواتير الإلكترونية المعتمدة وفق متطلبات هيئة الزكاة والضريبة والجمارك (المرحلة الثانية)"
        action={
          <Button asChild variant="outline" size="sm">
            <Link to="/app/ai"><ArrowRight className="h-4 w-4 ml-1" /> العودة</Link>
          </Button>
        }
      />

      <div className="grid md:grid-cols-3 gap-4 mb-6">
        <StatusCard title="حالة الربط مع فاتورة" status="غير مرتبط" warn icon={Link2} />
        <StatusCard title="عدد الفواتير المرسلة" status="0 فاتورة" icon={FileText} />
        <StatusCard title="آخر مزامنة" status="—" icon={Database} />
      </div>

      <Card className="card-3d border-none overflow-hidden p-0 mb-6">
        <div className="bg-gradient-to-br from-sky-500 via-blue-600 to-indigo-600 p-6 text-white relative overflow-hidden">
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_20%_20%,rgba(255,255,255,0.3),transparent_60%)]" />
          <div className="relative flex items-center justify-between">
            <div>
              <div className="flex items-center gap-2 mb-2">
                <ShieldCheck className="h-6 w-6" />
                <span className="text-xs font-bold uppercase tracking-wider opacity-80">المرحلة الثانية - الربط والتكامل</span>
              </div>
              <h3 className="text-2xl font-extrabold mb-2">اربط مكتبك بمنصة فاتورة ZATCA</h3>
              <p className="text-sm opacity-90 max-w-2xl">قم بمزامنة جميع الفواتير الضريبية مع منصة فاتورة الرسمية، وأصدر فواتير معتمدة برمز QR ومعرّف فريد متوافق مع متطلبات الهيئة.</p>
            </div>
            <ShieldCheck className="h-32 w-32 opacity-20 hidden lg:block" />
          </div>
        </div>
        <div className="p-6">
          <h4 className="font-bold mb-4">خطوات التفعيل</h4>
          <ol className="space-y-3">
            {[
              { t: "تسجيل الدخول إلى بوابة فاتورة", d: "ادخل إلى fatoora.zatca.gov.sa باستخدام حساب المنشأة." },
              { t: "إنشاء OTP الربط", d: "أنشئ كلمة مرور لمرة واحدة (OTP) من بوابة فاتورة لربط النظام." },
              { t: "إدخال الشهادة في الإعدادات", d: "أدخل OTP والشهادة في صفحة الإعدادات > التكاملات > ZATCA." },
              { t: "بدء المزامنة التلقائية", d: "ستتم مزامنة جميع الفواتير الجديدة تلقائياً مع المنصة." },
            ].map((s, i) => (
              <li key={i} className="flex gap-3">
                <div className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-gradient-to-br from-sky-500 to-blue-600 text-white text-sm font-bold shadow-md">{i + 1}</div>
                <div>
                  <div className="font-bold text-sm">{s.t}</div>
                  <div className="text-xs text-muted-foreground">{s.d}</div>
                </div>
              </li>
            ))}
          </ol>

          <div className="flex gap-3 mt-6">
            <Button asChild className="btn-gold">
              <a href="https://fatoora.zatca.gov.sa/" target="_blank" rel="noreferrer">
                <ExternalLink className="h-4 w-4 ml-2" /> فتح بوابة فاتورة
              </a>
            </Button>
            <Button asChild variant="outline">
              <Link to="/app/settings">إعدادات التكامل</Link>
            </Button>
          </div>
        </div>
      </Card>

      <div className="grid md:grid-cols-2 gap-4">
        <Card className="card-3d border-none p-6">
          <h4 className="font-bold mb-3 flex items-center gap-2"><CheckCircle2 className="h-5 w-5 text-emerald-500" /> المتطلبات المتوافقة</h4>
          <ul className="space-y-2 text-sm">
            {[
              "فاتورة ضريبية معتمدة (XML + UBL 2.1)",
              "رمز الاستجابة السريع QR لكل فاتورة",
              "معرّف فريد UUID لكل مستند",
              "تشفير وتوقيع إلكتروني",
              "أرشفة 6 سنوات وفق النظام",
            ].map((x) => (
              <li key={x} className="flex items-center gap-2"><CheckCircle2 className="h-4 w-4 text-emerald-500" /> {x}</li>
            ))}
          </ul>
        </Card>

        <Card className="card-3d border-none p-6">
          <h4 className="font-bold mb-3 flex items-center gap-2"><AlertCircle className="h-5 w-5 text-amber-500" /> تنبيهات هامة</h4>
          <ul className="space-y-2 text-sm text-muted-foreground">
            <li>• الفواتير لا تُعتبر صحيحة قانونياً حتى تتم مزامنتها مع منصة فاتورة.</li>
            <li>• يجب الإفصاح عن جميع الفواتير خلال 24 ساعة من الإصدار.</li>
            <li>• الفواتير المبسطة تخضع لنموذج الإفصاح، والفواتير الشاملة لنموذج الإجازة.</li>
            <li>• تأكد من تحديث بيانات المكتب والرقم الضريبي في الإعدادات.</li>
          </ul>
        </Card>
      </div>
    </>
  );
}

function StatusCard({ title, status, warn, icon: Icon }: { title: string; status: string; warn?: boolean; icon: any }) {
  return (
    <Card className="card-3d border-none p-5">
      <div className="flex items-center justify-between mb-2">
        <span className="text-xs font-semibold text-muted-foreground">{title}</span>
        <div className={`grid h-9 w-9 place-items-center rounded-lg ${warn ? "bg-amber-500" : "bg-sky-500"} text-white shadow-lg`}>
          <Icon className="h-4 w-4" />
        </div>
      </div>
      <div className={`text-xl font-extrabold ${warn ? "text-amber-600" : ""}`}>{status}</div>
    </Card>
  );
}
