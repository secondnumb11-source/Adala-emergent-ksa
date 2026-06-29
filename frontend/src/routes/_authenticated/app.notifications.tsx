import { createFileRoute } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import {
  Bell, Send, Clock3, MessageCircle, Pencil, Trash2, CalendarClock,
  ShieldCheck, FileText, Sparkles, Plus, AlertTriangle,
} from "lucide-react";
import { PageHeader } from "@/components/section-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { useList, useUpsert, useDelete } from "@/lib/data-hooks";
import { toast } from "sonner";
import { CalendarModeToggle } from "@/components/calendar-mode-toggle";
import { useCalendarMode, formatDateByMode } from "@/hooks/use-calendar-mode";

export const Route = createFileRoute("/_authenticated/app/notifications")({
  component: NotificationsPage,
});

type ClientRow = { id: string; full_name: string; phone?: string | null };
type CaseRow = { id: string; title: string; case_number: string; client_id?: string | null };
type SessionRow = { id: string; case_id: string; session_date: string; court?: string | null };
type NotifRow = {
  id: string; client_id?: string | null; case_id?: string | null;
  template?: string | null; message: string;
  channel: "whatsapp" | "sms" | "email";
  status: "draft" | "scheduled" | "sent" | "failed" | "cancelled";
  scheduled_at?: string | null; sent_at?: string | null; created_at: string;
};

const TEMPLATES: { id: string; label: string; body: string }[] = [
  { id: "welcome", label: "ترحيب بعميل جديد",
    body: "مرحباً {client_name}،\nنشكر ثقتكم بمكتب «عدالة» لخدمات المحاماة والاستشارات القانونية. تم تسجيلكم في نظامنا، وسنوافيكم بتحديثات قضاياكم أولاً بأول.\nللتواصل: في أي وقت." },
  { id: "session_reminder", label: "تذكير بموعد جلسة",
    body: "تذكير: لديكم جلسة في القضية رقم {case_number} ({case_title}) بتاريخ {session_date} في {court}.\nنرجو الحضور قبل الموعد بـ 15 دقيقة.\nمكتب عدالة." },
  { id: "session_postponed", label: "تأجيل جلسة",
    body: "إشعار تأجيل: تم تأجيل جلسة القضية رقم {case_number} إلى {session_date}.\nمكتب عدالة." },
  { id: "case_update", label: "تحديث على القضية",
    body: "تحديث على القضية رقم {case_number} ({case_title}):\n[يُكتب هنا التحديث]\nللاستفسار، نحن في خدمتكم.\nمكتب عدالة." },
  { id: "invoice_due", label: "مطالبة بسداد رسوم",
    body: "السلام عليكم {client_name}،\nنود تذكيركم بالرسوم المستحقة على القضية رقم {case_number}.\nنرجو التكرم بالسداد، ولأي استفسار يسعدنا تواصلكم.\nمكتب عدالة." },
  { id: "fees_due", label: "تذكير بدفعة أتعاب",
    body: "إشعار: استحقاق دفعة أتعاب على القضية رقم {case_number}. نشكر التزامكم وحسن تعاونكم.\nمكتب عدالة." },
  { id: "case_won", label: "شكر عند إتمام الدعوى",
    body: "نهنئكم بصدور الحكم في القضية رقم {case_number} ({case_title}). كان شرفاً تمثيلكم، ونتطلع لخدمتكم مجدداً.\nمكتب عدالة." },
];

function fillTemplate(body: string, ctx: Record<string, string | undefined | null>) {
  return body.replace(/\{(\w+)\}/g, (_, k) => (ctx[k] ?? `{${k}}`) as string);
}
function normalizePhone(p?: string | null) {
  if (!p) return "";
  const digits = p.replace(/\D/g, "");
  if (digits.startsWith("00")) return digits.slice(2);
  if (digits.startsWith("0")) return "966" + digits.slice(1);
  if (digits.startsWith("966")) return digits;
  return digits;
}
function waLink(phone: string, message: string) {
  return `https://wa.me/${normalizePhone(phone)}?text=${encodeURIComponent(message)}`;
}

function NotificationsPage() {
  const { mode: calMode } = useCalendarMode();
  const { data: clients = [] } = useList<ClientRow>("clients");
  const { data: cases = [] } = useList<CaseRow>("cases");
  const { data: sessions = [] } = useList<SessionRow>("sessions", "session_date", true);
  const { data: notifs = [], refetch } = useList<NotifRow>("client_notifications", "created_at", false);
  const upsert = useUpsert("client_notifications");
  const del = useDelete("client_notifications");

  const [clientId, setClientId] = useState("");
  const [caseId, setCaseId] = useState("");
  const [templateId, setTemplateId] = useState<string>("session_reminder");
  const [message, setMessage] = useState("");
  const [scheduledAt, setScheduledAt] = useState("");
  const [editingId, setEditingId] = useState<string | null>(null);

  const filteredCases = useMemo(() => cases.filter((c) => !clientId || c.client_id === clientId), [cases, clientId]);
  const client = clients.find((c) => c.id === clientId);
  const kase = cases.find((c) => c.id === caseId);
  const nextSession = sessions.find((s) => s.case_id === caseId && new Date(s.session_date) >= new Date());

  const applyTemplate = (id: string) => {
    setTemplateId(id);
    const t = TEMPLATES.find((x) => x.id === id);
    if (!t) return;
    const ctx = {
      client_name: client?.full_name,
      case_number: kase?.case_number,
      case_title: kase?.title,
      session_date: nextSession ? new Date(nextSession.session_date).toLocaleString("ar-SA", { dateStyle: "long", timeStyle: "short" }) : "",
      court: nextSession?.court ?? "",
    };
    setMessage(fillTemplate(t.body, ctx));
  };

  const reset = () => {
    setEditingId(null); setMessage(""); setScheduledAt("");
  };

  const save = async (action: "send" | "schedule" | "draft") => {
    if (!clientId) return toast.error("اختر العميل أولاً");
    if (!message.trim()) return toast.error("صياغة الرسالة مطلوبة");
    if (action === "send" && !client?.phone) return toast.error("لا يوجد رقم جوال للعميل");
    const payload: any = {
      id: editingId ?? undefined,
      client_id: clientId,
      case_id: caseId || null,
      template: templateId,
      message: message.trim(),
      channel: "whatsapp",
      status: action === "send" ? "sent" : action === "schedule" ? "scheduled" : "draft",
      scheduled_at: action === "schedule" && scheduledAt ? new Date(scheduledAt).toISOString() : null,
      sent_at: action === "send" ? new Date().toISOString() : null,
    };
    await upsert.mutateAsync(payload);
    if (action === "send" && client?.phone) {
      window.open(waLink(client.phone, message), "_blank");
    }
    reset();
    refetch();
  };

  const loadIntoForm = (n: NotifRow) => {
    setEditingId(n.id);
    setClientId(n.client_id ?? "");
    setCaseId(n.case_id ?? "");
    setTemplateId(n.template ?? "");
    setMessage(n.message);
    setScheduledAt(n.scheduled_at ? new Date(n.scheduled_at).toISOString().slice(0, 16) : "");
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  // Upcoming sessions card – clients to remind
  const upcoming = useMemo(() => {
    const now = Date.now();
    return sessions
      .filter((s) => {
        const t = new Date(s.session_date).getTime();
        return t >= now && t <= now + 7 * 24 * 3600 * 1000;
      })
      .map((s) => {
        const c = cases.find((x) => x.id === s.case_id);
        const cl = c ? clients.find((x) => x.id === c.client_id) : undefined;
        return { s, c, cl };
      })
      .filter((x) => x.c && x.cl)
      .sort((a, b) => +new Date(a.s.session_date) - +new Date(b.s.session_date));
  }, [sessions, cases, clients]);

  const quickRemind = (clId: string, csId: string) => {
    setClientId(clId); setCaseId(csId);
    setTimeout(() => applyTemplate("session_reminder"), 0);
  };

  const scheduledList = notifs.filter((n) => n.status === "scheduled");
  const sentList = notifs.filter((n) => n.status === "sent");

  return (
    <>
      <PageHeader
        icon={Bell}
        title="إشعارات العملاء"
        subtitle="إرسال تنبيهات احترافية عبر واتساب — قوالب جاهزة وجدولة وسجل كامل"
        action={<CalendarModeToggle />}
      />

      {/* CITC compliance banner */}
      <Card className="card-3d border-none p-4 mb-6 bg-gradient-to-l from-amber-500/10 via-card to-card">
        <div className="flex items-start gap-3">
          <ShieldCheck className="h-5 w-5 text-gold mt-0.5 shrink-0" />
          <div className="text-xs leading-relaxed">
            <span className="font-bold text-foreground">متوافق مع لوائح الهيئة السعودية للاتصالات وتقنية المعلومات (CST) لرسائل تنبيه الموعد:</span>
            <span className="text-muted-foreground"> تُرسل الرسائل فقط للعملاء المسجلين الذين أبدوا موافقتهم على التواصل، وتقتصر على الإشعارات الخدمية ذات الصلة بقضاياهم (تذكير بمواعيد جلسات، تحديثات قانونية، مطالبات مالية مرتبطة بالخدمة)، دون أي محتوى تسويقي، وتتضمن هوية المرسل ووسيلة التواصل.</span>
          </div>
        </div>
      </Card>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Composer */}
        <Card className="card-3d border-none p-5 lg:col-span-2">
          <div className="flex items-center justify-between mb-4">
            <h3 className="font-bold text-gradient-royal flex items-center gap-2">
              <MessageCircle className="h-4 w-4" /> إنشاء إشعار جديد
            </h3>
            {editingId && (
              <Badge variant="outline" className="text-[10px]">وضع التعديل</Badge>
            )}
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <Label className="text-xs font-semibold mb-1.5 block">العميل *</Label>
              <select value={clientId} onChange={(e) => { setClientId(e.target.value); setCaseId(""); }}
                className="w-full h-10 rounded-lg border bg-background px-3 text-sm text-right">
                <option value="">— اختر العميل —</option>
                {clients.map((c) => <option key={c.id} value={c.id}>{c.full_name} {c.phone ? `(${c.phone})` : ""}</option>)}
              </select>
            </div>
            <div>
              <Label className="text-xs font-semibold mb-1.5 block">القضية</Label>
              <select value={caseId} onChange={(e) => setCaseId(e.target.value)}
                className="w-full h-10 rounded-lg border bg-background px-3 text-sm text-right">
                <option value="">— بدون قضية —</option>
                {filteredCases.map((c) => <option key={c.id} value={c.id}>{c.case_number} – {c.title}</option>)}
              </select>
            </div>

            <div className="md:col-span-2">
              <Label className="text-xs font-semibold mb-1.5 block flex items-center gap-1.5">
                <FileText className="h-3.5 w-3.5" /> القالب
              </Label>
              <div className="flex flex-wrap gap-1.5">
                {TEMPLATES.map((t) => (
                  <button key={t.id} type="button" onClick={() => applyTemplate(t.id)}
                    className={`text-[11px] rounded-full px-3 py-1.5 border transition ${
                      templateId === t.id
                        ? "bg-gold/20 border-gold text-gold font-bold"
                        : "border-border/60 hover:border-gold/40 hover:bg-muted/40"
                    }`}>
                    {t.label}
                  </button>
                ))}
              </div>
            </div>

            <div className="md:col-span-2">
              <Label className="text-xs font-semibold mb-1.5 block flex items-center gap-1.5">
                <Sparkles className="h-3.5 w-3.5 text-gold" /> صياغة الرسالة (يمكن التعديل)
              </Label>
              <Textarea value={message} onChange={(e) => setMessage(e.target.value)}
                rows={7} className="text-right" placeholder="اكتب رسالتك هنا أو اختر قالباً بالأعلى…" />
              <div className="mt-1 flex items-center justify-between text-[10px] text-muted-foreground">
                <span>المتغيرات المتاحة: {"{client_name} {case_number} {case_title} {session_date} {court}"}</span>
                <span>{message.length} حرفاً</span>
              </div>
            </div>

            <div>
              <Label className="text-xs font-semibold mb-1.5 block flex items-center gap-1.5">
                <CalendarClock className="h-3.5 w-3.5" /> تاريخ ووقت الإرسال (للجدولة)
              </Label>
              <Input type="datetime-local" value={scheduledAt} onChange={(e) => setScheduledAt(e.target.value)} className="text-right" />
            </div>
            <div className="flex items-end">
              <div className="rounded-lg bg-muted/40 p-2.5 text-[11px] text-muted-foreground w-full">
                القناة: <span className="font-bold text-foreground">WhatsApp</span> · سيتم فتح المحادثة برقم العميل عند الإرسال الفوري.
              </div>
            </div>
          </div>

          <div className="mt-5 flex flex-wrap gap-2 pt-4 border-t border-border/40">
            <Button onClick={() => save("send")} className="btn-gold gap-2">
              <Send className="h-4 w-4" /> إرسال فوري عبر واتساب
            </Button>
            <Button onClick={() => save("schedule")} variant="outline" className="gap-2" disabled={!scheduledAt}>
              <Clock3 className="h-4 w-4" /> جدولة الإرسال
            </Button>
            <Button onClick={() => save("draft")} variant="ghost" className="gap-2">
              <Plus className="h-4 w-4" /> حفظ كمسودة
            </Button>
            {editingId && (
              <Button onClick={reset} variant="ghost" className="text-destructive">إلغاء التعديل</Button>
            )}
          </div>
        </Card>

        {/* Upcoming sessions to remind */}
        <Card className="card-3d border-none p-5">
          <div className="flex items-center justify-between mb-3">
            <h3 className="font-bold text-gradient-royal flex items-center gap-2">
              <AlertTriangle className="h-4 w-4 text-gold" /> جلسات تقترب — يستحسن التذكير
            </h3>
            <Badge variant="outline" className="text-[10px]">{upcoming.length}</Badge>
          </div>
          {upcoming.length === 0 ? (
            <p className="text-xs text-muted-foreground">لا توجد جلسات خلال الأسبوع القادم.</p>
          ) : (
            <div className="space-y-2.5">
              {upcoming.slice(0, 8).map(({ s, c, cl }) => (
                <div key={s.id}
                  className="rounded-xl border border-border/60 p-3 bg-gradient-to-br from-card to-muted/30 hover:-translate-y-0.5 hover:shadow-xl transition-all">
                  <div className="text-[11px] text-gold font-bold">
                    {formatDateByMode(s.session_date, calMode, { withTime: true })}
                  </div>
                  <div className="text-xs font-bold mt-0.5">{c!.case_number} – {c!.title}</div>
                  <div className="text-[11px] text-muted-foreground">العميل: {cl!.full_name}</div>
                  <Button size="sm" className="btn-gold w-full mt-2 h-7 text-[11px] gap-1"
                    onClick={() => quickRemind(cl!.id, c!.id)}>
                    <Bell className="h-3 w-3" /> تجهيز رسالة تذكير
                  </Button>
                </div>
              ))}
            </div>
          )}
        </Card>
      </div>

      {/* History */}
      <Card className="card-3d border-none p-5 mt-6">
        <Tabs defaultValue="scheduled">
          <TabsList>
            <TabsTrigger value="scheduled">المجدولة ({scheduledList.length})</TabsTrigger>
            <TabsTrigger value="sent">المرسلة ({sentList.length})</TabsTrigger>
            <TabsTrigger value="all">الكل ({notifs.length})</TabsTrigger>
          </TabsList>

          <TabsContent value="scheduled" className="mt-4">
            <NotifList rows={scheduledList} clients={clients} cases={cases} onEdit={loadIntoForm} onDelete={(id) => del.mutate(id)} />
          </TabsContent>
          <TabsContent value="sent" className="mt-4">
            <NotifList rows={sentList} clients={clients} cases={cases} onEdit={loadIntoForm} onDelete={(id) => del.mutate(id)} />
          </TabsContent>
          <TabsContent value="all" className="mt-4">
            <NotifList rows={notifs} clients={clients} cases={cases} onEdit={loadIntoForm} onDelete={(id) => del.mutate(id)} />
          </TabsContent>
        </Tabs>
      </Card>
    </>
  );
}

function NotifList({
  rows, clients, cases, onEdit, onDelete,
}: {
  rows: NotifRow[]; clients: ClientRow[]; cases: CaseRow[];
  onEdit: (n: NotifRow) => void; onDelete: (id: string) => void;
}) {
  const { mode: calMode } = useCalendarMode();
  if (rows.length === 0) {
    return <p className="text-xs text-center text-muted-foreground py-8">لا توجد عناصر.</p>;
  }
  const STATUS_BADGE: Record<string, string> = {
    scheduled: "bg-blue-500/15 text-blue-400 border-blue-500/30",
    sent: "bg-emerald-500/15 text-emerald-400 border-emerald-500/30",
    draft: "bg-muted text-muted-foreground border-border",
    failed: "bg-rose-500/15 text-rose-400 border-rose-500/30",
    cancelled: "bg-amber-500/15 text-amber-400 border-amber-500/30",
  };
  const STATUS_LABEL: Record<string, string> = {
    scheduled: "مجدولة", sent: "مرسلة", draft: "مسودة", failed: "فشل", cancelled: "ملغاة",
  };
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
      {rows.map((n) => {
        const cl = clients.find((c) => c.id === n.client_id);
        const cs = cases.find((c) => c.id === n.case_id);
        return (
          <div key={n.id}
            className="rounded-xl border border-border/60 p-3.5 bg-gradient-to-br from-card to-muted/20 hover:-translate-y-0.5 hover:shadow-xl transition-all">
            <div className="flex items-start justify-between gap-2 mb-2">
              <div>
                <div className="text-sm font-bold">{cl?.full_name ?? "—"}</div>
                {cs && <div className="text-[11px] text-muted-foreground">{cs.case_number} – {cs.title}</div>}
              </div>
              <Badge variant="outline" className={`text-[10px] ${STATUS_BADGE[n.status] || ""}`}>{STATUS_LABEL[n.status] || n.status}</Badge>
            </div>
            <p className="text-xs whitespace-pre-line line-clamp-3 text-muted-foreground border-r-2 border-gold/40 pr-2">{n.message}</p>
            <div className="mt-2 text-[10px] text-muted-foreground flex items-center gap-3 flex-wrap">
              {n.scheduled_at && <span>⏱ مجدولة: {formatDateByMode(n.scheduled_at, calMode, { withTime: true })}</span>}
              {n.sent_at && <span>✓ أُرسلت: {formatDateByMode(n.sent_at, calMode, { withTime: true })}</span>}
            </div>
            <div className="mt-2 flex gap-1 pt-2 border-t border-border/40">
              <Button size="sm" variant="ghost" className="h-7 gap-1 text-[11px]" onClick={() => onEdit(n)}>
                <Pencil className="h-3 w-3" /> تعديل
              </Button>
              <Button size="sm" variant="ghost" className="h-7 gap-1 text-[11px] text-destructive hover:text-destructive"
                onClick={() => { if (confirm("حذف الرسالة؟")) onDelete(n.id); }}>
                <Trash2 className="h-3 w-3" /> حذف
              </Button>
            </div>
          </div>
        );
      })}
    </div>
  );
}
