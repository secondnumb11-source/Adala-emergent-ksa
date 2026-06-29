import { useEffect, useMemo, useState } from "react";
import { Briefcase, CheckCircle2, ListChecks, MessageSquare, CalendarDays, UserCog, Loader2, ChevronDown, Upload, FileText, Send, BarChart3, Clock, AlertTriangle } from "lucide-react";
import { Link } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { toast } from "sonner";

const TASK_STATUS_AR: Record<string, string> = {
  todo: "للتنفيذ", in_progress: "جارية", done: "منجزة", overdue: "متأخرة",
};

type Employee = { id: string; full_name: string | null; job_title: string | null; owner_id: string };
type Task = { id: string; title: string; status: string; due_date: string | null; case_id: string | null; description?: string | null; priority?: string | null; employee_id?: string | null; owner_id?: string };
type Session = { id: string; session_date: string; court: string | null; case_id: string | null; notes: string | null };

export function EmployeePortalView({ userId }: { userId: string }) {
  const [loading, setLoading] = useState(true);
  const [emp, setEmp] = useState<Employee | null>(null);
  const [tasks, setTasks] = useState<Task[]>([]);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [unreadChat, setUnreadChat] = useState(0);
  const [expanded, setExpanded] = useState<string | null>(null);

  const load = async (uid: string) => {
    const { data: e } = await supabase
      .from("employees")
      .select("id, full_name, job_title, owner_id, assigned_cases")
      .eq("user_id", uid)
      .maybeSingle();
    setEmp(e as Employee | null);
    if (!e) { setLoading(false); return; }
    const assigned = Array.isArray((e as any).assigned_cases) ? (e as any).assigned_cases as string[] : [];
    const [t, m] = await Promise.all([
      supabase.from("tasks").select("id, title, status, due_date, case_id, description, priority, employee_id, owner_id").eq("employee_id", e.id).order("due_date", { ascending: true }),
      supabase.from("employee_messages").select("id", { count: "exact", head: true }).eq("recipient_id", uid).eq("is_read", false),
    ]);
    let sessionsRows: Session[] = [];
    if (assigned.length) {
      const { data: s } = await supabase.from("sessions")
        .select("id, session_date, court, case_id, notes")
        .in("case_id", assigned)
        .gte("session_date", new Date().toISOString().slice(0, 10))
        .order("session_date", { ascending: true })
        .limit(8);
      sessionsRows = (s ?? []) as Session[];
    }
    setTasks((t.data ?? []) as Task[]);
    setSessions(sessionsRows);
    setUnreadChat(m.count ?? 0);
    setLoading(false);
  };

  useEffect(() => {
    let alive = true;
    void (async () => { if (alive) await load(userId); })();
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userId]);

  // Realtime: instant sync when the manager edits any of MY tasks (or assigns new ones)
  useEffect(() => {
    if (!emp) return;
    const ch = supabase
      .channel(`rt:emp-tasks:${emp.id}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "tasks", filter: `employee_id=eq.${emp.id}` },
        () => { void load(userId); },
      )
      .subscribe();
    return () => { supabase.removeChannel(ch); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [emp?.id, userId]);

  const pendingTasks = useMemo(() => tasks.filter((t) => t.status !== "done"), [tasks]);
  const doneTasks = useMemo(() => tasks.filter((t) => t.status === "done"), [tasks]);
  const overdueTasks = useMemo(() => tasks.filter((t) => {
    if (t.status === "done") return false;
    if (t.status === "overdue") return true;
    return !!t.due_date && new Date(t.due_date) < new Date();
  }), [tasks]);
  const completionRate = tasks.length ? Math.round((doneTasks.length / tasks.length) * 100) : 0;

  const updateStatus = async (taskId: string, status: string) => {
    const { error } = await supabase.from("tasks").update({ status: status as any }).eq("id", taskId);
    if (error) { toast.error("تعذّر تحديث الحالة"); return; }
    setTasks((prev) => prev.map((t) => t.id === taskId ? { ...t, status } : t));
    toast.success("تم تحديث حالة المهمة — أُخطر المدير");
  };

  const uploadTaskDoc = async (task: Task, file: File) => {
    if (!emp) return;
    const path = `${emp.owner_id}/tasks/${task.id}/${Date.now()}-${file.name}`;
    const up = await supabase.storage.from("case-documents").upload(path, file, { upsert: false, contentType: file.type });
    if (up.error) { toast.error("فشل رفع الملف"); return; }
    const { error: insErr } = await supabase.from("documents").insert({
      owner_id: emp.owner_id,
      case_id: task.case_id,
      title: `[مهمة] ${task.title} — ${file.name}`,
      doc_type: "task_attachment" as any,
      storage_path: path,
    } as any);
    if (insErr) { toast.error("رُفع الملف لكن تعذّر فهرسته"); return; }
    toast.success("تم رفع المستند ومزامنته مع المدير");
  };

  if (loading) {
    return (
      <div className="grid place-items-center p-20" dir="rtl">
        <Loader2 className="h-8 w-8 animate-spin text-gold" />
      </div>
    );
  }

  if (!emp) {
    return (
      <div className="card-luxe p-12 text-center" dir="rtl">
        <UserCog className="h-12 w-12 text-gold mx-auto mb-4" />
        <h2 className="text-xl font-extrabold text-white">لم يتم ربط حسابك ببيانات موظف بعد</h2>
        <p className="text-white/70 mt-2">تواصل مع إدارة المكتب لتفعيل بوابة الموظف الخاصة بك.</p>
      </div>
    );
  }

  return (
    <div className="space-y-6" dir="rtl">
      <section className="card-night relative overflow-hidden p-7">
        <div className="flex items-center gap-4">
          <div className="grid h-14 w-14 place-items-center rounded-2xl bg-gradient-to-br from-gold to-gold/60 text-primary shadow-lg">
            <UserCog className="h-7 w-7" />
          </div>
          <div>
            <div className="text-xs uppercase tracking-[0.25em] text-gold/80">بوابة الموظف</div>
            <h1 className="text-2xl md:text-3xl font-extrabold text-white mt-1">أهلاً، {emp.full_name || "—"}</h1>
            <p className="text-white/70 text-sm mt-0.5">{emp.job_title || "موظف"}</p>
          </div>
        </div>
      </section>

      {/* Personal KPIs (only this employee's data) */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
        <Stat icon={ListChecks} label="مهامي قيد التنفيذ" value={pendingTasks.length} />
        <Stat icon={CheckCircle2} label="مهامي المنجزة" value={doneTasks.length} />
        <Stat icon={AlertTriangle} label="مهامي المتأخرة" value={overdueTasks.length} highlight={overdueTasks.length > 0} />
        <Stat icon={BarChart3} label="نسبة الإنجاز" value={completionRate} suffix="%" />
        <Stat icon={MessageSquare} label="رسائل غير مقروءة" value={unreadChat} highlight={unreadChat > 0} />
      </div>
      <p className="text-[11px] text-muted-foreground -mt-2">هذه المؤشرات تخصّك أنت فقط — لا تشمل بيانات بقية الفريق.</p>

      <Card className="p-5" dir="rtl">
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-lg font-extrabold flex items-center gap-2"><ListChecks className="h-5 w-5 text-gold" /> مهامي المُسندة</h2>
          <Link to="/app/tasks" className="text-xs text-gold hover:underline">عرض كل المهام</Link>
        </div>
        {pendingTasks.length === 0 ? (
          <p className="text-center text-muted-foreground py-6">لا توجد مهام مستحقة. أحسنت!</p>
        ) : (
          <ul className="divide-y divide-border">
            {pendingTasks.slice(0, 12).map((t) => {
              const open = expanded === t.id;
              return (
                <li key={t.id} className="py-3">
                  <button
                    onClick={() => setExpanded(open ? null : t.id)}
                    className="w-full flex items-center justify-between gap-3 text-right"
                  >
                    <div className="min-w-0 flex-1">
                      <div className="font-semibold truncate">{t.title}</div>
                      {t.due_date && <div className="text-[11px] text-muted-foreground mt-0.5 flex items-center gap-1"><Clock className="h-3 w-3" /> الاستحقاق: {t.due_date}</div>}
                    </div>
                    <Badge variant="outline" className="shrink-0">{TASK_STATUS_AR[t.status] || t.status}</Badge>
                    <ChevronDown className={`h-4 w-4 text-muted-foreground transition-transform ${open ? "rotate-180" : ""}`} />
                  </button>
                  {open && (
                    <div className="mt-3 rounded-xl border border-gold/30 bg-gold/5 p-3 space-y-3">
                      {t.description && (
                        <div>
                          <div className="text-[11px] font-bold text-gold mb-1">تفاصيل المهمة والمطلوب</div>
                          <p className="text-sm whitespace-pre-wrap leading-relaxed">{t.description}</p>
                        </div>
                      )}
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="text-[11px] font-bold">تحديث الحالة:</span>
                        {(["todo", "in_progress", "done"] as const).map((s) => (
                          <button
                            key={s}
                            onClick={() => updateStatus(t.id, s)}
                            className={`text-[11px] px-2.5 py-1 rounded-full border font-bold transition ${
                              t.status === s
                                ? "border-gold bg-gold text-primary"
                                : "border-border bg-card hover:bg-muted"
                            }`}
                          >
                            {TASK_STATUS_AR[s]}
                          </button>
                        ))}
                      </div>
                      <div className="flex flex-wrap items-center gap-2 pt-1 border-t border-gold/20">
                        <label className="inline-flex items-center gap-1.5 cursor-pointer text-[11px] font-bold rounded-lg border border-gold/40 bg-gold/10 px-3 py-1.5 hover:bg-gold/20">
                          <Upload className="h-3.5 w-3.5" /> رفع مستند للمهمة
                          <input
                            type="file"
                            className="hidden"
                            onChange={(e) => { const f = e.target.files?.[0]; if (f) void uploadTaskDoc(t, f); e.currentTarget.value = ""; }}
                          />
                        </label>
                        <Link to="/app/team-chat" search={{ peer: undefined }} className="inline-flex items-center gap-1.5 text-[11px] font-bold rounded-lg border border-border bg-card px-3 py-1.5 hover:bg-muted">
                          <Send className="h-3.5 w-3.5" /> فتح محادثة مع المدير
                        </Link>
                        {t.case_id && (
                          <Link to="/app/archive" className="inline-flex items-center gap-1.5 text-[11px] font-bold rounded-lg border border-border bg-card px-3 py-1.5 hover:bg-muted">
                            <FileText className="h-3.5 w-3.5" /> مستندات القضية
                          </Link>
                        )}
                      </div>
                      <p className="text-[10px] text-muted-foreground">
                        أي تعديل تجريه يُزامَن مباشرة مع لوحة مدير المكتب لمتابعة الإنجاز.
                      </p>
                    </div>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </Card>

      <Card className="p-5" dir="rtl">
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-lg font-extrabold flex items-center gap-2"><CalendarDays className="h-5 w-5 text-gold" /> الجلسات القادمة</h2>
          <Link to="/app/sessions" className="text-xs text-gold hover:underline">عرض كل الجلسات</Link>
        </div>
        {sessions.length === 0 ? (
          <p className="text-center text-muted-foreground py-6">لا توجد جلسات قادمة مرتبطة بقضاياك.</p>
        ) : (
          <ul className="divide-y divide-border">
            {sessions.map((s) => (
              <li key={s.id} className="py-3 flex items-center justify-between gap-3">
                <div className="min-w-0">
                  <div className="font-semibold truncate">{s.notes || "جلسة"}</div>
                  <div className="text-[11px] text-muted-foreground mt-0.5">{s.session_date} • {s.court || "—"}</div>
                </div>
                <Briefcase className="h-4 w-4 text-muted-foreground shrink-0" />
              </li>
            ))}
          </ul>
        )}
      </Card>
    </div>
  );
}

function Stat({ icon: Icon, label, value, highlight, suffix }: { icon: any; label: string; value: number; highlight?: boolean; suffix?: string }) {
  return (
    <Card className={`p-4 flex items-center gap-3 ${highlight ? "border-red-600 border-2" : ""}`} dir="rtl">
      <div className={`grid h-12 w-12 place-items-center rounded-xl ${highlight ? "bg-red-600 text-white animate-pulse" : "bg-gold/15 text-gold"}`}>
        <Icon className="h-6 w-6" />
      </div>
      <div className="min-w-0">
        <div className="text-xs text-muted-foreground">{label}</div>
        <div className="text-2xl font-extrabold">{value}{suffix || ""}</div>
      </div>
    </Card>
  );
}