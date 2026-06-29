import { createFileRoute, Link } from "@tanstack/react-router";
import { useState, useEffect } from "react";
import { Clock, ArrowRight, AlertTriangle, CheckCircle, Calendar, Plus } from "lucide-react";
import { PageHeader } from "@/components/section-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { useList } from "@/lib/data-hooks";

export const Route = createFileRoute("/_authenticated/app/ai/deadlines")({
  component: DeadlinesPage,
});

type DeadlineType =
  | "appeal"
  | "appeal_urgent"
  | "objection"
  | "cassation"
  | "cassation_urgent"
  | "reconsideration"
  | "execution"
  | "judgment_receipt";

/**
 * المدد النظامية وفق نظام المرافعات الشرعية السعودي:
 * - المادة (178): مدة الاعتراض بالاستئناف ثلاثون يوماً، وفي الأحكام المستعجلة عشرة أيام.
 * - المادة (193): مدة طلب التمييز (النقض) أمام المحكمة العليا ثلاثون يوماً، وعشرة أيام في المستعجلة.
 * - المادة (200): مدة التماس إعادة النظر ثلاثون يوماً.
 * يسقط الحق في الاعتراض بانقضاء المدة (المادة 179).
 */
const DEADLINE_DAYS: Record<DeadlineType, { days: number; label: string; ref: string }> = {
  appeal: { days: 30, label: "استئناف حكم عادي", ref: "م.178 مرافعات" },
  appeal_urgent: { days: 10, label: "استئناف حكم مستعجل", ref: "م.178 مرافعات" },
  objection: { days: 30, label: "اعتراض على حكم غيابي", ref: "م.178 مرافعات" },
  cassation: { days: 30, label: "نقض (المحكمة العليا)", ref: "م.193 مرافعات" },
  cassation_urgent: { days: 10, label: "نقض حكم مستعجل", ref: "م.193 مرافعات" },
  reconsideration: { days: 30, label: "التماس إعادة النظر", ref: "م.200 مرافعات" },
  execution: { days: 60, label: "تقديم طلب تنفيذ", ref: "نظام التنفيذ" },
  judgment_receipt: { days: 7, label: "استلام صك الحكم", ref: "م.166 مرافعات" },
};

type Deadline = {
  id: string;
  caseTitle: string;
  type: DeadlineType;
  startDate: string;
  receivedJudgment: boolean;
};

function DeadlinesPage() {
  const cases = useList<{ id: string; title?: string; case_number?: string }>("cases");
  const [deadlines, setDeadlines] = useState<Deadline[]>(() => {
    if (typeof window === "undefined") return [];
    const stored = localStorage.getItem("adala_deadlines");
    return stored ? JSON.parse(stored) : [];
  });

  useEffect(() => {
    if (typeof window !== "undefined") {
      localStorage.setItem("adala_deadlines", JSON.stringify(deadlines));
    }
  }, [deadlines]);

  const [newCase, setNewCase] = useState("");
  const [newType, setNewType] = useState<DeadlineType>("appeal");
  const [newDate, setNewDate] = useState(new Date().toISOString().slice(0, 10));

  const add = () => {
    if (!newCase) return;
    setDeadlines((d) => [...d, {
      id: crypto.randomUUID(),
      caseTitle: newCase,
      type: newType,
      startDate: newDate,
      receivedJudgment: false,
    }]);
    setNewCase("");
  };

  const toggleReceived = (id: string) => {
    setDeadlines((d) => d.map((x) => x.id === id ? { ...x, receivedJudgment: !x.receivedJudgment, startDate: !x.receivedJudgment ? new Date().toISOString().slice(0, 10) : x.startDate } : x));
  };

  const remove = (id: string) => setDeadlines((d) => d.filter((x) => x.id !== id));

  return (
    <>
      <PageHeader
        icon={Clock}
        title="حاسبة المدد النظامية"
        subtitle="حساب تلقائي لمدد الاستئناف والاعتراض والنقض وطلبات التنفيذ وفق الأنظمة السعودية"
        action={
          <Button asChild variant="outline" size="sm">
            <Link to="/app/ai"><ArrowRight className="h-4 w-4 ml-1" /> العودة</Link>
          </Button>
        }
      />

      <Card className="card-3d border-none p-6 mb-6">
        <h3 className="font-bold mb-4 flex items-center gap-2"><Plus className="h-5 w-5 text-gold" /> إضافة قضية لمتابعة المدة</h3>
        <div className="grid md:grid-cols-4 gap-3">
          <select value={newCase} onChange={(e) => setNewCase(e.target.value)} className="h-10 rounded-lg border bg-background px-3 text-sm">
            <option value="">— اختر قضية —</option>
            {cases.data?.map((c) => <option key={c.id} value={c.title ?? c.case_number ?? c.id}>{c.title ?? c.case_number}</option>)}
          </select>
          <select value={newType} onChange={(e) => setNewType(e.target.value as DeadlineType)} className="h-10 rounded-lg border bg-background px-3 text-sm">
            {Object.entries(DEADLINE_DAYS).map(([k, v]) => <option key={k} value={k}>{v.label} ({v.days} يوم)</option>)}
          </select>
          <Input type="date" value={newDate} onChange={(e) => setNewDate(e.target.value)} className="h-10" />
          <Button onClick={add} disabled={!newCase} className="btn-gold h-10">إضافة للمتابعة</Button>
        </div>
      </Card>

      {deadlines.length === 0 ? (
        <Card className="card-3d border-none p-10 text-center">
          <Clock className="h-12 w-12 mx-auto text-muted-foreground/40 mb-3" />
          <p className="text-muted-foreground">لا توجد مدد قيد المتابعة — أضف قضية للبدء</p>
        </Card>
      ) : (
        <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-4 mb-8">
          {deadlines.map((d) => <DeadlineCard key={d.id} d={d} onToggle={() => toggleReceived(d.id)} onDelete={() => remove(d.id)} />)}
        </div>
      )}

      <Card className="card-3d border-none p-6">
        <h3 className="font-bold mb-4">المدد النظامية المرجعية وفق الأنظمة السعودية</h3>
        <div className="grid md:grid-cols-2 gap-3 text-sm">
          {[
            ["الاستئناف على الأحكام (العادية)", "30 يوماً من تاريخ تسلّم صك الحكم — م.178"],
            ["الاستئناف على الأحكام المستعجلة", "10 أيام من تاريخ التسلّم — م.178"],
            ["الاعتراض على الأحكام الغيابية", "30 يوماً من تاريخ التبليغ — م.178"],
            ["النقض أمام المحكمة العليا (عادية)", "30 يوماً من تاريخ التسلّم — م.193"],
            ["النقض على الأحكام المستعجلة", "10 أيام من تاريخ التسلّم — م.193"],
            ["التماس إعادة النظر", "30 يوماً من زوال/اكتشاف السبب — م.200"],
            ["استلام صك الحكم بعد النطق", "خلال أسبوع (7 أيام) — م.166"],
            ["تقديم طلب التنفيذ", "وفق نظام التنفيذ"],
            ["الدعوى العمالية - المطالبة", "12 شهراً من انتهاء الخدمة — نظام العمل"],
          ].map(([title, days]) => (
            <div key={title} className="flex justify-between items-center p-3 rounded-lg bg-muted/30 border">
              <span className="font-medium">{title}</span>
              <span className="text-gold font-bold text-xs">{days}</span>
            </div>
          ))}
        </div>
        <p className="mt-4 text-xs text-muted-foreground leading-relaxed">
          ملاحظة: تبدأ مدة الاعتراض من اليوم التالي لتاريخ تسلّم صك الحكم، ويسقط الحق في الاعتراض بانقضاء المدة (م.179 من نظام المرافعات الشرعية). تُحتسب أيام جلسات الاستئناف وتقديم الطلبات وفق هذه المدد.
        </p>
      </Card>
    </>
  );
}

function DeadlineCard({ d, onToggle, onDelete }: { d: Deadline; onToggle: () => void; onDelete: () => void }) {
  const meta = DEADLINE_DAYS[d.type];
  const start = new Date(d.startDate);
  const end = new Date(start.getTime() + meta.days * 86400000);
  const [now, setNow] = useState(Date.now());

  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 60000);
    return () => clearInterval(t);
  }, []);

  const ms = end.getTime() - now;
  const days = Math.floor(ms / 86400000);
  const hours = Math.floor((ms % 86400000) / 3600000);
  const expired = ms <= 0;
  const urgent = days < 7;

  return (
    <Card className={`card-3d border-none p-0 overflow-hidden ${expired ? "ring-2 ring-destructive/60" : urgent ? "ring-2 ring-amber-500/60" : ""}`}>
      <div className={`h-2 ${expired ? "bg-destructive" : urgent ? "bg-amber-500" : "bg-emerald-500"}`} />
      <div className="p-5">
        <div className="flex items-start justify-between mb-3">
          <div className="flex-1">
            <div className="font-extrabold text-sm mb-1">{d.caseTitle}</div>
            <div className="text-xs text-muted-foreground flex items-center gap-1">
              <Calendar className="h-3 w-3" /> {meta.label} — {meta.days} يوم
            </div>
          </div>
          <button onClick={onDelete} className="text-muted-foreground hover:text-destructive text-xs">حذف</button>
        </div>

        <div className={`rounded-xl p-4 ${expired ? "bg-destructive/10" : urgent ? "bg-amber-500/10" : "bg-emerald-500/10"}`}>
          {expired ? (
            <div className="flex items-center gap-2 text-destructive">
              <AlertTriangle className="h-5 w-5" />
              <span className="font-bold">انتهت المدة النظامية</span>
            </div>
          ) : (
            <div>
              <div className="text-[10px] text-muted-foreground mb-1">المتبقي</div>
              <div className="flex items-end gap-2">
                <div className="text-3xl font-extrabold tabular-nums">{days}</div>
                <div className="text-sm text-muted-foreground mb-1">يوم</div>
                <div className="text-lg font-bold tabular-nums mr-2">{hours}</div>
                <div className="text-sm text-muted-foreground mb-1">ساعة</div>
              </div>
              <div className="text-[10px] text-muted-foreground mt-2">ينتهي في: {end.toLocaleDateString("ar-SA")}</div>
            </div>
          )}
        </div>

        <button
          onClick={onToggle}
          className={`mt-3 w-full flex items-center justify-center gap-2 rounded-lg py-2 text-xs font-bold transition-colors ${
            d.receivedJudgment ? "bg-emerald-500/20 text-emerald-700 dark:text-emerald-400" : "bg-muted hover:bg-muted/80"
          }`}
        >
          <CheckCircle className="h-3.5 w-3.5" />
          {d.receivedJudgment ? "تم استلام الحكم" : "تأكيد استلام الحكم"}
        </button>
      </div>
    </Card>
  );
}
