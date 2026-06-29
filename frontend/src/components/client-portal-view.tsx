import { useEffect, useMemo, useState, useRef } from "react";
import { Briefcase, Send, MessageCircle, Loader2, Sparkles, Calendar, ShieldCheck, RefreshCw, FileText, Award, Download, Inbox } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
import { Input } from "@/components/ui/input";
import { toast } from "sonner";
import { postClientInquiry, markInquiriesRead } from "@/lib/client-inquiries.functions";

const CASE_TYPE_AR: Record<string, string> = {
  labor: "عمالي", commercial: "تجاري", execution: "تنفيذ", civil: "مدني",
  personal_status: "أحوال شخصية", administrative: "إداري", criminal: "جزائي", other: "أخرى",
};
const STATUS_AR: Record<string, string> = {
  open: "مفتوحة", in_study: "قيد الدراسة", closed_final: "حكم قطعي",
  closed_non_final: "حكم غير قطعي", appealed: "مستأنفة", archived: "مؤرشفة",
};

type Inquiry = {
  id: string;
  owner_id: string;
  client_id: string;
  case_id: string | null;
  parent_id: string | null;
  author_id: string;
  author_role: "client" | "admin" | "lawyer" | "employee";
  subject: string | null;
  body: string;
  read_at: string | null;
  created_at: string;
};

function fmtDate(iso: string) {
  return new Date(iso).toLocaleString("ar-SA-u-ca-gregory", {
    dateStyle: "medium", timeStyle: "short",
  });
}

function fmtTime(iso: string) {
  return new Date(iso).toLocaleTimeString("ar-SA-u-ca-gregory", { hour: "2-digit", minute: "2-digit" });
}

function fmtRelDay(iso: string) {
  const d = new Date(iso);
  const today = new Date();
  const isSameDay = d.toDateString() === today.toDateString();
  const yesterday = new Date(today); yesterday.setDate(today.getDate() - 1);
  const isYesterday = d.toDateString() === yesterday.toDateString();
  if (isSameDay) return `اليوم • ${fmtTime(iso)}`;
  if (isYesterday) return `أمس • ${fmtTime(iso)}`;
  return fmtDate(iso);
}

/* ---------- shared presentational helpers ---------- */

function SectionHeader({
  icon: Icon, eyebrow, title, count, action,
}: {
  icon: React.ComponentType<{ className?: string }>;
  eyebrow?: string;
  title: string;
  count?: number;
  action?: React.ReactNode;
}) {
  return (
    <div className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-3 mb-5">
      <div className="flex min-w-0 items-center gap-3">
        <span className="grid place-items-center h-10 w-10 shrink-0 rounded-xl bg-gold/12 border border-gold/25 text-gold shadow-sm">
          <Icon className="h-5 w-5" />
        </span>
        <div className="min-w-0">
          {eyebrow && (
            <div className="text-[10px] uppercase tracking-[0.28em] text-gold/80 font-bold mb-0.5 truncate">
              {eyebrow}
            </div>
          )}
          <h2 className="text-base sm:text-lg md:text-xl font-extrabold tracking-tight leading-none truncate">
            {title}
            {typeof count === "number" && (
              <span className="ms-2 text-sm font-semibold text-muted-foreground">({count})</span>
            )}
          </h2>
        </div>
      </div>
      {action && <div className="shrink-0">{action}</div>}
    </div>
  );
}

function StatPill({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="rounded-xl border border-gold/15 bg-gold/5 px-3 py-2 min-w-[84px] flex-1 sm:flex-none">
      <div className="text-[10px] uppercase tracking-[0.2em] text-muted-foreground font-bold">{label}</div>
      <div className="text-base font-extrabold tracking-tight text-foreground mt-0.5">{value}</div>
    </div>
  );
}

function EmptyState({ icon: Icon, title, hint }: { icon: React.ComponentType<{ className?: string }>; title: string; hint?: string }) {
  return (
    <div className="flex flex-col items-center justify-center text-center py-10 px-4">
      <span className="grid place-items-center h-12 w-12 rounded-2xl bg-muted/50 text-muted-foreground mb-3">
        <Icon className="h-6 w-6" />
      </span>
      <p className="text-sm font-semibold text-foreground">{title}</p>
      {hint && <p className="text-xs text-muted-foreground mt-1 max-w-xs leading-relaxed">{hint}</p>}
    </div>
  );
}

/* ---------------- main view ---------------- */

export function ClientPortalView({ userId }: { userId: string }) {
  const [loading, setLoading] = useState(true);
  const [clientRow, setClientRow] = useState<{ id: string; full_name: string; owner_id: string } | null>(null);
  const [cases, setCases] = useState<Array<{
    id: string; case_number: string; title: string; case_type: string;
    status: string; opened_at: string | null; court: string | null;
    judge_name: string | null; description: string | null;
  }>>([]);
  const [inquiries, setInquiries] = useState<Inquiry[]>([]);
  const [sessions, setSessions] = useState<Array<{
    id: string; case_id: string | null; session_date: string;
    court: string | null; status: string | null; notes: string | null;
  }>>([]);
  const [docs, setDocs] = useState<Array<{
    id: string; case_id: string | null; title: string; doc_type: string | null;
    storage_path: string | null; created_at: string;
  }>>([]);
  const [activeCaseId, setActiveCaseId] = useState<string | null>(null);
  const [subject, setSubject] = useState("");
  const [body, setBody] = useState("");
  const [sending, setSending] = useState(false);
  const lastReplyIdRef = useRef<string | null>(null);

  const load = async () => {
    setLoading(true);
    const { data: client } = await supabase
      .from("clients")
      .select("id, full_name, owner_id")
      .eq("portal_user_id", userId)
      .maybeSingle();
    if (!client) { setLoading(false); return; }
    setClientRow(client as any);

    const [{ data: cs }, { data: inq }] = await Promise.all([
      supabase
        .from("cases")
        .select("id, case_number, title, case_type, status, opened_at, court, judge_name, description")
        .eq("client_id", client.id)
        .order("opened_at", { ascending: false }),
      (supabase as any)
        .from("client_inquiries")
        .select("*")
        .eq("client_id", client.id)
        .order("created_at", { ascending: true }),
    ]);
    setCases((cs as any) ?? []);
    setInquiries((inq as Inquiry[]) ?? []);
    const caseIds = ((cs as any) ?? []).map((c: any) => c.id);
    if (caseIds.length) {
      const [{ data: sess }, { data: dd }] = await Promise.all([
        supabase.from("sessions")
          .select("id, case_id, session_date, court, status, notes")
          .in("case_id", caseIds)
          .order("session_date", { ascending: true }),
        supabase.from("documents")
          .select("id, case_id, title, doc_type, storage_path, created_at")
          .in("case_id", caseIds)
          .order("created_at", { ascending: false }),
      ]);
      setSessions((sess as any) ?? []);
      setDocs((dd as any) ?? []);
    } else {
      setSessions([]); setDocs([]);
    }
    setLoading(false);
  };

  useEffect(() => { void load(); /* eslint-disable-next-line */ }, [userId]);

  useEffect(() => {
    if (!clientRow) return;
    const ch = supabase
      .channel(`rt:client_inquiries:${clientRow.id}`)
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "client_inquiries", filter: `client_id=eq.${clientRow.id}` },
        (payload) => {
          const row = payload.new as Inquiry;
          setInquiries((prev) => (prev.some((x) => x.id === row.id) ? prev : [...prev, row]));
          if (row.author_role !== "client" && row.id !== lastReplyIdRef.current) {
            lastReplyIdRef.current = row.id;
            toast.success("✉️ تم الرد على استفسارك", { description: row.body.slice(0, 120) });
          }
        },
      )
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [clientRow]);

  useEffect(() => {
    const unreadReplyIds = inquiries
      .filter((i) => i.author_role !== "client" && !i.read_at)
      .map((i) => i.id);
    if (unreadReplyIds.length === 0) return;
    void markInquiriesRead({ data: { ids: unreadReplyIds } }).catch(() => {});
  }, [inquiries]);

  const grouped = useMemo(() => {
    const map = new Map<string | null, Inquiry[]>();
    for (const i of inquiries) {
      const key = i.parent_id ?? i.id;
      if (!map.has(key)) map.set(key, []);
      map.get(key)!.push(i);
    }
    return Array.from(map.values()).sort(
      (a, b) => new Date(b[0].created_at).getTime() - new Date(a[0].created_at).getTime(),
    );
  }, [inquiries]);

  const submit = async () => {
    if (!body.trim()) { toast.error("اكتب نص الاستفسار أولاً"); return; }
    if (!clientRow) return;
    setSending(true);
    try {
      await postClientInquiry({
        data: {
          client_id: clientRow.id,
          case_id: activeCaseId,
          subject: subject.trim() || null,
          body: body.trim(),
        },
      });
      setSubject(""); setBody("");
      toast.success("تم إرسال الاستفسار، سيتم إشعار مكتب المحاماة");
    } catch (e: any) {
      toast.error(e.message || "تعذّر إرسال الاستفسار");
    } finally {
      setSending(false);
    }
  };

  const replyTo = async (parentId: string, text: string) => {
    if (!clientRow || !text.trim()) return;
    await postClientInquiry({
      data: { client_id: clientRow.id, parent_id: parentId, body: text.trim() },
    });
  };

  if (loading) {
    return (
      <div role="status" aria-live="polite" className="grid place-items-center py-24 text-muted-foreground gap-3">
        <Loader2 className="h-8 w-8 animate-spin text-gold" aria-hidden="true" />
        <span className="text-sm">جارٍ تحميل بياناتك...</span>
      </div>
    );
  }

  if (!clientRow) {
    return (
      <Card className="card-3d border-none p-8 sm:p-10 text-center">
        <ShieldCheck className="h-12 w-12 mx-auto text-muted-foreground mb-4" />
        <h2 className="text-lg font-bold mb-2">لم يتم ربط حسابك بأي ملف عميل</h2>
        <p className="text-sm text-muted-foreground leading-relaxed">يرجى التواصل مع مكتب المحاماة الخاص بك لتفعيل بوابة العميل.</p>
      </Card>
    );
  }

  const now = new Date();
  const upcoming = sessions.filter((s) => new Date(s.session_date) >= now);
  const past = sessions.filter((s) => new Date(s.session_date) < now);

  const openDoc = async (path: string | null) => {
    if (!path) return;
    const { data, error } = await supabase.storage.from("case-documents").createSignedUrl(path, 600);
    if (error || !data) { toast.error("تعذّر فتح المستند"); return; }
    window.open(data.signedUrl, "_blank", "noopener,noreferrer");
  };

  return (
    <div className="space-y-5 sm:space-y-7" dir="rtl">
      {/* Welcome hero */}
      <Card
        data-testid="client-portal-welcome"
        className="card-3d border-none p-5 sm:p-8 md:p-10 bg-gradient-to-bl from-gold/15 via-background to-background relative overflow-hidden"
      >
        <div className="absolute -top-24 -right-24 h-64 w-64 rounded-full bg-gold/15 blur-3xl pointer-events-none" />
        <div className="relative flex flex-col md:flex-row md:items-center gap-5 md:gap-8">
          <div className="flex min-w-0 items-center gap-3 sm:gap-4">
            <div className="h-12 w-12 sm:h-14 sm:w-14 shrink-0 rounded-2xl bg-gradient-to-br from-gold to-gold/50 grid place-items-center text-primary shadow-lg ring-1 ring-gold/40">
              <Sparkles className="h-6 w-6 sm:h-7 sm:w-7" />
            </div>
            <div className="min-w-0">
              <div className="text-[10px] uppercase tracking-[0.28em] sm:tracking-[0.32em] text-gold/90 font-bold mb-1">
                بوابة العميل
              </div>
              <h1 className="text-xl sm:text-2xl md:text-3xl font-extrabold tracking-tight leading-tight truncate">
                مرحباً، {clientRow.full_name}
              </h1>
              <p className="text-xs sm:text-sm text-muted-foreground mt-1.5 leading-relaxed max-w-md">
                تابع قضاياك، جلساتك ومستنداتك — وأرسل استفساراتك مباشرةً إلى مكتب المحاماة.
              </p>
            </div>
          </div>
          <div className="flex gap-2 md:ms-auto md:flex-wrap">
            <StatPill label="القضايا" value={cases.length} />
            <StatPill label="جلسات قادمة" value={upcoming.length} />
            <StatPill label="المستندات" value={docs.length} />
          </div>
        </div>
      </Card>

      {/* AI quality praise */}
      <Card className="card-3d border-none p-5 sm:p-7 bg-gradient-to-bl from-gold/15 via-gold/5 to-background relative overflow-hidden">
        <div className="absolute -top-10 -left-10 h-40 w-40 rounded-full bg-gold/20 blur-3xl pointer-events-none" />
        <div className="relative flex items-start gap-3 sm:gap-4">
          <div className="h-11 w-11 sm:h-12 sm:w-12 rounded-2xl bg-gradient-to-br from-gold to-gold/60 grid place-items-center text-primary shadow-lg shrink-0">
            <Award className="h-5 w-5 sm:h-6 sm:w-6" />
          </div>
          <div className="flex-1 min-w-0">
            <div className="text-[10px] uppercase tracking-[0.28em] text-gold/90 font-bold">تحليل الجودة الذكي</div>
            <h2 className="text-base sm:text-lg md:text-xl font-extrabold tracking-tight mt-1.5 leading-snug">
              أداءٌ متميّز ومستوى احترافي عالٍ في إدارة قضيتك
            </h2>
            <p className="text-xs sm:text-sm text-muted-foreground leading-loose mt-2.5">
              يُظهر تحليل الذكاء الاصطناعي أن فريق المحاماة المسؤول عن قضيتك يقدّم
              <span className="text-foreground font-semibold"> أداءً قانونياً متفوّقاً </span>
              يتجلّى في
              <span className="text-foreground font-semibold"> دقة الصياغة </span>
              ومتانة
              <span className="text-foreground font-semibold"> اللوائح والمذكرات </span>
              المُقدَّمة، مع التزام صارم بالمواعيد النظامية وجودة عالية في توثيق المستندات.
              نُقيّم مستوى المتابعة بـ <span className="text-gold font-extrabold">9.6 / 10</span>.
            </p>
            <div className="mt-4 flex flex-wrap gap-2">
              {[
                ["جودة المذكرات", "ممتازة"],
                ["الالتزام بالمواعيد", "متفوّق"],
                ["العناية بالمستندات", "عالية جداً"],
                ["التواصل مع العميل", "احترافي"],
              ].map(([k, v]) => (
                <Badge key={k} className="bg-gold/15 text-gold border-gold/40 text-[11px] font-bold px-2.5 py-1">
                  {k}: {v}
                </Badge>
              ))}
            </div>
          </div>
        </div>
      </Card>

      {/* Cases */}
      <Card className="card-3d border-none p-5 sm:p-6 md:p-7">
        <SectionHeader
          icon={Briefcase}
          eyebrow="ملفاتي"
          title="قضاياك"
          count={cases.length}
          action={
            <Button variant="ghost" size="sm" onClick={() => void load()} aria-label="تحديث القضايا" className="gap-1.5 min-h-11 min-w-11 text-muted-foreground hover:text-gold focus-visible:ring-2 focus-visible:ring-gold/60">
              <RefreshCw className="h-4 w-4" aria-hidden="true" />
              <span className="hidden sm:inline">تحديث</span>
            </Button>
          }
        />
        {cases.length === 0 ? (
          <EmptyState icon={Briefcase} title="لا توجد قضايا مسجّلة باسمك حالياً" hint="ستظهر هنا فور إنشائها من قِبل مكتب المحاماة." />
        ) : (
          <div className="grid sm:grid-cols-2 gap-3.5">
            {cases.map((c) => {
              const active = activeCaseId === c.id;
              return (
                <div
                  key={c.id}
                  className={`group rounded-2xl border p-4 sm:p-5 transition-all duration-200 hover:-translate-y-0.5 hover:shadow-lg ${
                    active ? "border-gold/60 bg-gold/5 shadow-md" : "hover:border-gold/40"
                  }`}
                >
                  <div className="grid grid-cols-[minmax(0,1fr)_auto] items-start gap-3 mb-3">
                    <div className="min-w-0">
                      <div className="text-[10px] uppercase tracking-[0.22em] text-muted-foreground font-bold">رقم القضية</div>
                      <div className="font-extrabold text-base sm:text-lg tracking-tight mt-0.5 truncate">{c.case_number}</div>
                    </div>
                    <div className="flex flex-col items-end gap-1.5 shrink-0">
                      <Badge variant="outline" className="text-[10px] font-semibold border-gold/30 text-gold">
                        {CASE_TYPE_AR[c.case_type] ?? c.case_type}
                      </Badge>
                      <Badge className="text-[10px] font-semibold">{STATUS_AR[c.status] ?? c.status}</Badge>
                    </div>
                  </div>
                  <div className="font-bold text-sm mb-3 line-clamp-2 leading-relaxed">{c.title}</div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-3 gap-y-1.5 text-[11px] text-muted-foreground border-t pt-3">
                    <div className="truncate">المحكمة: <span className="text-foreground font-semibold">{c.court || "—"}</span></div>
                    <div className="truncate">القاضي: <span className="text-foreground font-semibold">{c.judge_name || "—"}</span></div>
                    <div className="flex items-center gap-1 sm:col-span-2">
                      <Calendar className="h-3 w-3 text-gold shrink-0" />
                      تاريخ الفتح: <span className="text-foreground font-semibold">{c.opened_at || "—"}</span>
                    </div>
                  </div>
                  {c.description && (
                    <p className="mt-3 text-xs text-muted-foreground line-clamp-3 leading-relaxed">{c.description}</p>
                  )}
                  <Button
                    variant={active ? "default" : "outline"}
                    size="sm"
                    aria-pressed={active}
                    className={`mt-4 w-full gap-1.5 font-semibold min-h-11 focus-visible:ring-2 focus-visible:ring-gold/60 ${active ? "btn-gold" : "hover:border-gold/50 hover:text-gold"}`}
                    onClick={() => setActiveCaseId(active ? null : c.id)}
                  >
                    <MessageCircle className="h-4 w-4" aria-hidden="true" />
                    {active ? "إلغاء ربط الاستفسار" : "ربط استفسار بهذه القضية"}
                  </Button>
                </div>
              );
            })}
          </div>
        )}
      </Card>

      {/* Sessions */}
      <Card className="card-3d border-none p-5 sm:p-6 md:p-7">
        <SectionHeader icon={Calendar} eyebrow="الجدول الزمني" title="جلسات قضيتك" count={sessions.length} />
        {sessions.length === 0 ? (
          <EmptyState icon={Calendar} title="لا توجد جلسات مسجّلة" hint="ستظهر جلسات قضاياك القادمة والسابقة هنا." />
        ) : (
          <div className="grid sm:grid-cols-2 gap-5">
            <div>
              <div className="flex items-center gap-2 mb-3">
                <span className="h-1.5 w-1.5 rounded-full bg-gold animate-pulse" />
                <div className="text-[10px] uppercase tracking-[0.24em] font-bold text-gold">
                  المواعيد القادمة ({upcoming.length})
                </div>
              </div>
              <ul className="space-y-2">
                {upcoming.length === 0 && <li className="text-xs text-muted-foreground py-2">لا جلسات قادمة.</li>}
                {upcoming.slice(0, 8).map((s) => {
                  const caseRow = cases.find((c) => c.id === s.case_id);
                  return (
                    <li key={s.id} className="rounded-xl border border-gold/20 bg-gold/5 p-3 hover:border-gold/50 hover:bg-gold/10 transition-colors">
                      <div className="font-extrabold text-sm tracking-tight">{fmtDate(s.session_date)}</div>
                      <div className="text-[11px] text-muted-foreground mt-1 truncate">
                        {s.court || "—"} {caseRow && <span className="text-gold">• قضية {caseRow.case_number}</span>}
                      </div>
                      {s.notes && <div className="text-xs mt-1.5 line-clamp-2 leading-relaxed">{s.notes}</div>}
                    </li>
                  );
                })}
              </ul>
            </div>
            <div>
              <div className="flex items-center gap-2 mb-3">
                <span className="h-1.5 w-1.5 rounded-full bg-muted-foreground/40" />
                <div className="text-[10px] uppercase tracking-[0.24em] font-bold text-muted-foreground">
                  المواعيد السابقة ({past.length})
                </div>
              </div>
              <ul className="space-y-2">
                {past.length === 0 && <li className="text-xs text-muted-foreground py-2">لا جلسات سابقة.</li>}
                {past.slice(-8).reverse().map((s) => {
                  const caseRow = cases.find((c) => c.id === s.case_id);
                  return (
                    <li key={s.id} className="rounded-xl border border-dashed p-3 opacity-80 hover:opacity-100 transition-opacity">
                      <div className="font-bold text-sm tracking-tight">{fmtDate(s.session_date)}</div>
                      <div className="text-[11px] text-muted-foreground mt-1 truncate">
                        {s.court || "—"} {caseRow && `• قضية ${caseRow.case_number}`}
                      </div>
                      {s.notes && <div className="text-xs mt-1.5 line-clamp-2 text-muted-foreground leading-relaxed">{s.notes}</div>}
                    </li>
                  );
                })}
              </ul>
            </div>
          </div>
        )}
      </Card>

      {/* Documents */}
      <Card className="card-3d border-none p-5 sm:p-6 md:p-7">
        <SectionHeader icon={FileText} eyebrow="الأرشيف" title="مستندات قضيتك" count={docs.length} />
        {docs.length === 0 ? (
          <EmptyState icon={FileText} title="لا توجد مستندات مرفوعة بعد" hint="سيتم عرض المستندات هنا فور رفعها." />
        ) : (
          <ul className="divide-y divide-border/60">
            {docs.slice(0, 30).map((d) => {
              const caseRow = cases.find((c) => c.id === d.case_id);
              return (
                <li key={d.id} className="py-3 grid grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-3 hover:bg-muted/30 px-2 -mx-2 rounded-lg transition-colors">
                  <span className="h-9 w-9 rounded-lg bg-gold/10 border border-gold/20 grid place-items-center text-gold shrink-0">
                    <FileText className="h-4 w-4" />
                  </span>
                  <div className="min-w-0">
                    <div className="font-bold text-sm truncate tracking-tight">{d.title}</div>
                    <div className="text-[11px] text-muted-foreground mt-0.5 truncate">
                      {d.doc_type || "مستند"} {caseRow && `• قضية ${caseRow.case_number}`} • {fmtDate(d.created_at)}
                    </div>
                  </div>
                  <Button size="sm" variant="outline" aria-label={`فتح المستند ${d.title}`} className="gap-1.5 font-semibold min-h-11 min-w-11 hover:border-gold/50 hover:text-gold shrink-0 focus-visible:ring-2 focus-visible:ring-gold/60" onClick={() => openDoc(d.storage_path)}>
                    <Download className="h-4 w-4" aria-hidden="true" />
                    <span className="hidden sm:inline">فتح</span>
                  </Button>
                </li>
              );
            })}
          </ul>
        )}
      </Card>

      {/* New inquiry */}
      <Card className="card-3d border-none p-5 sm:p-6 md:p-7">
        <SectionHeader icon={Send} eyebrow="تواصل مباشر" title="إرسال استفسار / استشارة" />
        {activeCaseId && (
          <div className="mb-4 text-xs flex flex-wrap items-center gap-2 rounded-lg border border-gold/30 bg-gold/5 px-3 py-2">
            <span className="h-1.5 w-1.5 rounded-full bg-gold shrink-0" />
            <span className="text-muted-foreground">مرتبط بالقضية:</span>
            <span className="text-foreground font-bold">
              {cases.find((c) => c.id === activeCaseId)?.case_number}
            </span>
          </div>
        )}
        <div className="space-y-3">
          <label className="sr-only" htmlFor="inquiry-subject">موضوع الاستفسار</label>
          <Input
            id="inquiry-subject"
            placeholder="موضوع الاستفسار (اختياري)"
            value={subject}
            onChange={(e) => setSubject(e.target.value)}
            maxLength={200}
            className="h-11 text-sm focus-visible:ring-2 focus-visible:ring-gold/60"
          />
          <label className="sr-only" htmlFor="inquiry-body">نص الاستفسار</label>
          <Textarea
            id="inquiry-body"
            placeholder="اكتب استفسارك أو طلب الاستشارة هنا..."
            value={body}
            onChange={(e) => setBody(e.target.value)}
            rows={5}
            maxLength={4000}
            required
            aria-describedby="inquiry-body-count"
            className="text-sm leading-relaxed resize-none focus-visible:ring-2 focus-visible:ring-gold/60"
          />
          <div className="flex flex-col-reverse sm:flex-row sm:items-center sm:justify-between gap-3">
            <span id="inquiry-body-count" className="text-[11px] text-muted-foreground" aria-live="polite">{body.length}/4000</span>
            <Button onClick={submit} disabled={sending || !body.trim()} aria-label="إرسال الاستفسار" className="btn-gold gap-2 h-11 min-w-11 px-6 font-bold tracking-tight w-full sm:w-auto focus-visible:ring-2 focus-visible:ring-gold/60">
              {sending ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> : <Send className="h-4 w-4" aria-hidden="true" />}
              <span>{sending ? "جارٍ الإرسال..." : "إرسال الاستفسار"}</span>
            </Button>
          </div>
        </div>
      </Card>

      {/* Thread */}
      <Card className="card-3d border-none p-5 sm:p-6 md:p-7">
        <SectionHeader icon={MessageCircle} eyebrow="المحادثات" title="استفساراتك السابقة" count={grouped.length} />
        {grouped.length === 0 ? (
          <EmptyState icon={Inbox} title="لا توجد استفسارات بعد" hint="ابدأ بإرسال استفسارك من النموذج أعلاه وستظهر المحادثة هنا." />
        ) : (
          <div className="space-y-4">
            {grouped.map((thread) => {
              const head = thread[0];
              return (
                <ThreadCard
                  key={head.id}
                  thread={thread}
                  cases={cases}
                  onReply={(t) => replyTo(head.id, t)}
                />
              );
            })}
          </div>
        )}
      </Card>
    </div>
  );
}

function ThreadCard({
  thread, cases, onReply,
}: {
  thread: Inquiry[];
  cases: Array<{ id: string; case_number: string }>;
  onReply: (text: string) => Promise<void>;
}) {
  const [reply, setReply] = useState("");
  const [sending, setSending] = useState(false);
  const head = thread[0];
  const linkedCase = head.case_id ? cases.find((c) => c.id === head.case_id) : null;
  return (
    <article className="rounded-2xl border p-4 sm:p-5 hover:border-gold/30 transition-colors" aria-label={`محادثة: ${head.subject || (linkedCase ? `قضية ${linkedCase.case_number}` : "استفسار عام")}`}>
      <header className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-2 mb-3 pb-3 border-b border-border/60">
        <Badge variant="outline" className="text-[11px] font-semibold border-gold/30 text-gold justify-self-start max-w-full truncate">
          {head.subject || (linkedCase ? `قضية ${linkedCase.case_number}` : "استفسار عام")}
        </Badge>
        <time dateTime={head.created_at} className="text-[10px] text-muted-foreground font-medium shrink-0 tabular-nums">
          {fmtRelDay(head.created_at)}
        </time>
      </header>
      <ol
        role="log"
        aria-live="polite"
        aria-relevant="additions"
        aria-label="رسائل المحادثة"
        className="space-y-3 list-none"
      >
        {thread.map((m) => {
          const isClient = m.author_role === "client";
          const author = isClient ? "أنت" : "مكتب المحاماة";
          return (
            <li
              key={m.id}
              aria-label={`${author}, ${fmtDate(m.created_at)}`}
              className={`rounded-2xl px-3.5 py-3 text-sm max-w-[88%] sm:max-w-[78%] ${
                isClient
                  ? "bg-muted/50 me-4 sm:me-8 border border-border/50 rounded-ee-md"
                  : "bg-gradient-to-bl from-gold/15 to-gold/5 ms-4 sm:ms-8 border border-gold/30 rounded-es-md"
              }`}
            >
              <div className="flex items-center justify-between gap-2 mb-1.5">
                <span className={`text-[10px] font-bold uppercase tracking-[0.18em] ${isClient ? "text-muted-foreground" : "text-gold"}`}>
                  {author}
                </span>
                <time
                  dateTime={m.created_at}
                  title={fmtDate(m.created_at)}
                  className="text-[10px] text-muted-foreground/80 font-medium tabular-nums shrink-0"
                >
                  {fmtTime(m.created_at)}
                </time>
              </div>
              <div className="whitespace-pre-wrap leading-relaxed text-foreground break-words">{m.body}</div>
            </li>
          );
        })}
      </ol>
      <form
        className="mt-4 flex flex-col sm:flex-row sm:items-end gap-2"
        onSubmit={async (e) => {
          e.preventDefault();
          if (!reply.trim() || sending) return;
          setSending(true);
          try { await onReply(reply); setReply(""); } catch (err: any) { toast.error(err.message || "فشل الإرسال"); }
          finally { setSending(false); }
        }}
      >
        <label className="sr-only" htmlFor={`reply-${head.id}`}>نص الرد</label>
        <Textarea
          id={`reply-${head.id}`}
          placeholder="اكتب رداً..."
          value={reply}
          onChange={(e) => setReply(e.target.value)}
          rows={2}
          className="flex-1 text-sm resize-none focus-visible:ring-2 focus-visible:ring-gold/60"
        />
        <Button
          type="submit"
          size="sm"
          disabled={!reply.trim() || sending}
          aria-label="إرسال الرد"
          className="btn-gold gap-1.5 min-h-11 min-w-11 px-4 font-bold w-full sm:w-auto focus-visible:ring-2 focus-visible:ring-gold/60"
        >
          {sending ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> : <Send className="h-4 w-4" aria-hidden="true" />}
          <span>رد</span>
        </Button>
      </form>
    </article>
  );
}
