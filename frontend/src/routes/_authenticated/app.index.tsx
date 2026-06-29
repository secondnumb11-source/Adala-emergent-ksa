import { createFileRoute, Link } from "@tanstack/react-router";
import { useEffect, useMemo, useRef, useState } from "react";
import {
  LayoutDashboard, Briefcase, Users2, CheckCircle2, AlertTriangle,
  Clock, Sparkles, Bot, FileSignature, Receipt, Calculator,
  CalendarClock, Gavel, BookOpen, TrendingUp, Timer, Layers3, Flame,
  ShieldCheck, ChevronLeft, Crown, Download, Filter, Bell, Radio,
  Pencil, Check, X as XIcon,
} from "lucide-react";
import {
  ResponsiveContainer, LineChart, Line, BarChart, Bar, PieChart, Pie, Cell,
  AreaChart, Area, XAxis, YAxis, Tooltip, CartesianGrid, Legend,
} from "recharts";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import type { Database } from "@/integrations/supabase/types";
import { DashboardLayout, DashboardCard } from "@/components/dashboard-layout";
import { Tilt3D } from "@/components/tilt-3d";
import { ClientPortalView } from "@/components/client-portal-view";
import { EmployeePortalView } from "@/components/employee-portal-view";

export const Route = createFileRoute("/_authenticated/app/")({
  component: Dashboard,
});

type CaseRow = Database["public"]["Tables"]["cases"]["Row"];
type SessionRow = Database["public"]["Tables"]["sessions"]["Row"];
type TaskRow = Database["public"]["Tables"]["tasks"]["Row"];
type DocRow = Database["public"]["Tables"]["documents"]["Row"];
type EmployeeRow = Database["public"]["Tables"]["employees"]["Row"];
type ClientRow = Database["public"]["Tables"]["clients"]["Row"];
type AppRole = Database["public"]["Enums"]["app_role"];

const CASE_TYPE_AR: Record<string, string> = {
  labor: "عمالي", commercial: "تجاري", execution: "تنفيذ", civil: "مدني",
  personal_status: "أحوال شخصية", administrative: "إداري", criminal: "جزائي", other: "أخرى",
};
const STATUS_AR: Record<string, string> = {
  open: "مفتوحة", in_study: "قيد الدراسة", closed_final: "حكم قطعي",
  closed_non_final: "حكم غير قطعي", appealed: "مستأنفة", archived: "مؤرشفة",
};
const TASK_STATUS_AR: Record<string, string> = {
  todo: "للتنفيذ", in_progress: "جارية", done: "منجزة", overdue: "متأخرة",
};
const ROLE_AR: Record<AppRole, string> = {
  admin: "مدير النظام", lawyer: "محامٍ", employee: "موظف", client: "عميل",
};

function greeting(): string {
  const h = new Date().getHours();
  if (h < 5) return "ليلة موفقة";
  if (h < 12) return "صباح الخير";
  if (h < 17) return "مساء الخير";
  return "أمسية مباركة";
}

function todayArabic(): string {
  return new Intl.DateTimeFormat("ar-SA-u-ca-gregory", {
    weekday: "long", day: "numeric", month: "long", year: "numeric",
  }).format(new Date());
}

function daysBetween(target: string | Date): number {
  const t = new Date(target).getTime();
  const now = new Date(); now.setHours(0, 0, 0, 0);
  return Math.ceil((t - now.getTime()) / 86_400_000);
}

function hoursUntil(target: string | Date): number {
  return (new Date(target).getTime() - Date.now()) / 3_600_000;
}

const NOTIFIED_KEY = "lex:notified_sessions";
function loadNotified(): Set<string> {
  try { return new Set(JSON.parse(localStorage.getItem(NOTIFIED_KEY) || "[]")); }
  catch { return new Set(); }
}
function saveNotified(s: Set<string>) {
  try { localStorage.setItem(NOTIFIED_KEY, JSON.stringify(Array.from(s).slice(-200))); } catch {}
}

function Dashboard() {
  const { user } = Route.useRouteContext();
  const [loading, setLoading] = useState(true);
  const [cases, setCases] = useState<CaseRow[]>([]);
  const [sessions, setSessions] = useState<SessionRow[]>([]);
  const [tasks, setTasks] = useState<TaskRow[]>([]);
  const [docs, setDocs] = useState<DocRow[]>([]);
  const [employees, setEmployees] = useState<EmployeeRow[]>([]);
  const [clients, setClients] = useState<ClientRow[]>([]);
  const [powers, setPowers] = useState<any[]>([]);

  const [myEmployeeId, setMyEmployeeId] = useState<string | null>(null);
  const [roles, setRoles] = useState<AppRole[]>([]);
  const [rolesLoaded, setRolesLoaded] = useState(false);
  const [dashEditing, setDashEditing] = useState(false);

  // ---- Timeline filters ----
  const [period, setPeriod] = useState<3 | 6 | 12>(8 as 3 | 6 | 12);
  const [typeFilter, setTypeFilter] = useState<string>("__all__");
  const [selectedCases, setSelectedCases] = useState<string[]>([]); // [] = all
  const [showFilters, setShowFilters] = useState(false);

  // PDF export ref
  const reportRef = useRef<HTMLDivElement>(null);
  const [exporting, setExporting] = useState(false);

  const reload = async () => {
    const [c, s, t, d, e, cl, p] = await Promise.all([
      supabase.from("cases").select("*").order("opened_at", { ascending: false }),
      supabase.from("sessions").select("*").order("session_date", { ascending: true }),
      supabase.from("tasks").select("*").order("due_date", { ascending: true }),
      supabase.from("documents").select("*"),
      supabase.from("employees").select("*"),
      supabase.from("clients").select("*"),
      supabase.from("powers_of_attorney" as any).select("*"),
    ]);
    setCases(c.data ?? []);
    setSessions(s.data ?? []);
    setTasks(t.data ?? []);
    setDocs(d.data ?? []);
    setEmployees(e.data ?? []);
    setClients(cl.data ?? []);
    setPowers((p.data as any[]) ?? []);
    setLoading(false);
  };


  // Initial load + roles
  useEffect(() => {
    let mounted = true;
    (async () => {
      const [rolesRes, empRes] = await Promise.all([
        supabase.from("user_roles").select("role").eq("user_id", user.id),
        supabase.from("employees").select("id").eq("user_id", user.id).maybeSingle(),
      ]);
      if (!mounted) return;
      const loaded = (rolesRes.data ?? []).map(r => r.role as AppRole);
      setRoles(loaded);
      setRolesLoaded(true);
      setMyEmployeeId(empRes.data?.id ?? null);
      const isClientOnly = loaded.includes("client") && !loaded.includes("admin") && !loaded.includes("lawyer");
      const isEmployeeOnly = loaded.includes("employee") && !loaded.includes("admin") && !loaded.includes("lawyer") && !loaded.includes("client");
      if (isClientOnly || isEmployeeOnly) { setLoading(false); return; }
      await reload();
    })();
    return () => { mounted = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user.id]);

  // Realtime: live refresh on any change in core tables
  useEffect(() => {
    const channel = supabase
      .channel("dashboard-live")
      .on("postgres_changes", { event: "*", schema: "public", table: "cases" }, () => reload())
      .on("postgres_changes", { event: "*", schema: "public", table: "sessions" }, (p) => {
        reload();
        if (p.eventType === "INSERT") toast.info("📅 جلسة جديدة أُضيفت");
      })
      .on("postgres_changes", { event: "*", schema: "public", table: "tasks" }, () => reload())
      .on("postgres_changes", { event: "*", schema: "public", table: "documents" }, () => reload())
      .subscribe(() => { /* live sync */ });

    return () => { supabase.removeChannel(channel); };
  }, []);

  // ---- Role-based visibility ----
  const isPrivileged = roles.includes("admin") || roles.includes("lawyer");
  const visibleCases = useMemo(() => {
    if (isPrivileged) return cases;
    if (!myEmployeeId) return cases.filter(c => c.owner_id === user.id);
    const empCases = employees.find(e => e.id === myEmployeeId)?.assigned_cases ?? [];
    const set = new Set<string>(empCases);
    return cases.filter(c => c.assigned_employee_id === myEmployeeId || set.has(c.id) || c.owner_id === user.id);
  }, [cases, employees, myEmployeeId, isPrivileged, user.id]);

  const visibleCaseIds = useMemo(() => new Set(visibleCases.map(c => c.id)), [visibleCases]);
  const visibleSessions = useMemo(
    () => sessions.filter(s => !s.case_id || visibleCaseIds.has(s.case_id)),
    [sessions, visibleCaseIds]
  );
  const visibleTasks = useMemo(() => {
    if (isPrivileged) return tasks;
    return tasks.filter(t => t.employee_id === myEmployeeId || (t.case_id && visibleCaseIds.has(t.case_id)));
  }, [tasks, myEmployeeId, isPrivileged, visibleCaseIds]);
  const visibleDocs = useMemo(
    () => docs.filter(d => !d.case_id || visibleCaseIds.has(d.case_id)),
    [docs, visibleCaseIds]
  );

  // ---- Session notifications (within 24h, not yet notified) ----
  useEffect(() => {
    if (loading) return;
    const notified = loadNotified();
    let changed = false;
    visibleSessions.forEach(s => {
      if (s.status !== "scheduled") return;
      const h = hoursUntil(s.session_date);
      if (h > 0 && h <= 24 && !notified.has(s.id)) {
        const when = new Date(s.session_date).toLocaleString("ar-SA-u-ca-gregory", { dateStyle: "medium", timeStyle: "short" });
        toast.warning(`🔔 جلسة قادمة خلال ${Math.round(h)} ساعة`, {
          description: `${s.court || "محكمة"} — ${when}`,
          duration: 8000,
        });
        notified.add(s.id);
        changed = true;
      }
    });
    if (changed) saveNotified(notified);
  }, [visibleSessions, loading]);

  const upcomingWithin24h = useMemo(
    () => visibleSessions.filter(s => s.status === "scheduled" && hoursUntil(s.session_date) > 0 && hoursUntil(s.session_date) <= 24).length,
    [visibleSessions]
  );

  const metaName = (user.user_metadata?.full_name as string | undefined) || user.email?.split("@")[0] || "محامينا";
  const metaJob = (user.user_metadata?.job_title as string | undefined) || "";
  const [userName, setUserName] = useState<string>(metaName);
  const [jobTitle, setJobTitle] = useState<string>(metaJob);
  const [editingProfile, setEditingProfile] = useState(false);
  const [draftName, setDraftName] = useState(metaName);
  const [draftJob, setDraftJob] = useState(metaJob);
  const [savingProfile, setSavingProfile] = useState(false);

  const saveProfile = async () => {
    const name = draftName.trim() || userName;
    const job = draftJob.trim();
    setSavingProfile(true);
    try {
      const { error } = await supabase.auth.updateUser({ data: { full_name: name, job_title: job } });
      if (error) throw error;
      setUserName(name);
      setJobTitle(job);
      setEditingProfile(false);
      toast.success("تم تحديث بياناتك");
    } catch (e) {
      console.error(e);
      toast.error("تعذّر حفظ التعديلات");
    } finally {
      setSavingProfile(false);
    }
  };

  // ---- KPIs (on visible data) ----
  const now = new Date();
  const openCount = visibleCases.filter(c => c.status === "open" || c.status === "in_study").length;
  const postponedCount = visibleSessions.filter(s => s.status === "postponed").length;
  const closedCount = visibleCases.filter(c => c.status === "closed_final" || c.status === "closed_non_final").length;
  const upcomingSessions = visibleSessions.filter(s => s.status === "scheduled" && new Date(s.session_date) >= now);
  const doneTasks = visibleTasks.filter(t => t.status === "done").length;
  const overdueTasks = visibleTasks.filter(t => {
    if (t.status === "done") return false;
    if (t.status === "overdue") return true;
    return t.due_date && new Date(t.due_date) < now;
  });
  const urgentTasks = visibleTasks.filter(t => t.priority === "urgent" && t.status !== "done");
  const totalTasks = visibleTasks.length || 1;
  const completionRate = Math.round((doneTasks / totalTasks) * 100);
  const appealsDue = visibleDocs
    .filter(d => d.appeal_deadline && daysBetween(d.appeal_deadline) >= 0 && daysBetween(d.appeal_deadline) <= 60)
    .sort((a, b) => new Date(a.appeal_deadline!).getTime() - new Date(b.appeal_deadline!).getTime());

  // ---- Unified deadlines & expiry alerts (المُدد والمهل) ----
  type Deadline = { key: string; primary: string; secondary: string; badge: string; tone: "danger" | "amber" | "gold"; days: number };
  const deadlines: Deadline[] = useMemo(() => {
    const out: Deadline[] = [];
    visibleSessions
      .filter(s => s.status === "scheduled" && hoursUntil(s.session_date) > 0 && daysBetween(s.session_date) <= 30)
      .forEach(s => {
        const d = daysBetween(s.session_date);
        out.push({
          key: `s-${s.id}`,
          primary: `جلسة — ${s.court || "محكمة"}`,
          secondary: new Date(s.session_date).toLocaleString("ar-SA-u-ca-gregory", { dateStyle: "medium", timeStyle: "short" }),
          badge: d === 0 ? "اليوم" : d === 1 ? "غداً" : `بعد ${d} يوم`,
          tone: d <= 1 ? "danger" : d <= 7 ? "amber" : "gold",
          days: d,
        });
      });
    appealsDue.forEach(doc => {
      const d = daysBetween(doc.appeal_deadline!);
      out.push({
        key: `a-${doc.id}`,
        primary: `مهلة استئناف — ${doc.title}`,
        secondary: `الموعد النظامي: ${new Date(doc.appeal_deadline!).toLocaleDateString("ar-SA-u-ca-gregory")}`,
        badge: `${d} يوم`,
        tone: d <= 3 ? "danger" : d <= 14 ? "amber" : "gold",
        days: d,
      });
    });
    powers.forEach((p: any) => {
      const exp = p.expiry_date || p.expires_at || p.end_date;
      if (!exp) return;
      const d = daysBetween(exp);
      if (d < 0 || d > 60) return;
      out.push({
        key: `p-${p.id}`,
        primary: `وكالة — ${p.principal_name || p.client_name || p.title || "وكالة شرعية"}`,
        secondary: `تنتهي: ${new Date(exp).toLocaleDateString("ar-SA-u-ca-gregory")}`,
        badge: d === 0 ? "تنتهي اليوم" : `${d} يوم`,
        tone: d <= 7 ? "danger" : d <= 30 ? "amber" : "gold",
        days: d,
      });
    });
    visibleTasks
      .filter(t => t.status !== "done" && t.due_date)
      .forEach(t => {
        const d = daysBetween(t.due_date!);
        if (d < -30 || d > 14) return;
        out.push({
          key: `t-${t.id}`,
          primary: `مهمة — ${t.title}`,
          secondary: d < 0 ? `متأخرة منذ ${Math.abs(d)} يوم` : `استحقاق: ${new Date(t.due_date!).toLocaleDateString("ar-SA-u-ca-gregory")}`,
          badge: d < 0 ? "متأخرة" : d <= 1 ? "عاجلة" : `${d} يوم`,
          tone: d < 0 ? "danger" : d <= 3 ? "amber" : "gold",
          days: d,
        });
      });
    return out.sort((a, b) => a.days - b.days);
  }, [visibleSessions, appealsDue, powers, visibleTasks]);


  // ---- Timeline (filtered) ----
  const filteredCases = useMemo(() => {
    return visibleCases.filter(c => {
      if (typeFilter !== "__all__" && c.case_type !== typeFilter) return false;
      if (selectedCases.length > 0 && !selectedCases.includes(c.id)) return false;
      return true;
    });
  }, [visibleCases, typeFilter, selectedCases]);

  const timelineData = useMemo(() => {
    const buckets = new Map<string, { month: string; قضايا: number; جلسات: number }>();
    const fmt = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
    const ensure = (k: string) => {
      if (!buckets.has(k)) buckets.set(k, { month: k, قضايا: 0, جلسات: 0 });
      return buckets.get(k)!;
    };
    const months = period;
    for (let i = months - 1; i >= 0; i--) {
      const dt = new Date(now.getFullYear(), now.getMonth() - i, 1);
      ensure(fmt(dt));
    }
    const idSet = new Set(filteredCases.map(c => c.id));
    filteredCases.forEach(c => {
      const k = fmt(new Date(c.opened_at)); if (buckets.has(k)) ensure(k).قضايا += 1;
    });
    visibleSessions.filter(s => s.case_id && idSet.has(s.case_id)).forEach(s => {
      const k = fmt(new Date(s.session_date)); if (buckets.has(k)) ensure(k).جلسات += 1;
    });
    return Array.from(buckets.values());
  }, [filteredCases, visibleSessions, period]);

  const statusData = useMemo(() => {
    const map = new Map<string, number>();
    visibleCases.forEach(c => map.set(c.status, (map.get(c.status) || 0) + 1));
    return Array.from(map.entries()).map(([k, v]) => ({ name: STATUS_AR[k] || k, value: v }));
  }, [visibleCases]);

  const typeData = useMemo(() => {
    const map = new Map<string, number>();
    visibleCases.forEach(c => map.set(c.case_type, (map.get(c.case_type) || 0) + 1));
    return Array.from(map.entries()).map(([k, v]) => ({ name: CASE_TYPE_AR[k] || k, value: v }));
  }, [visibleCases]);

  const teamData = useMemo(() => {
    return employees.slice(0, 8).map(e => {
      const mine = visibleTasks.filter(t => t.employee_id === e.id);
      const done = mine.filter(t => t.status === "done").length;
      const overdue = mine.filter(t => t.status === "overdue" || (t.status !== "done" && t.due_date && new Date(t.due_date) < now)).length;
      const rate = mine.length ? Math.round((done / mine.length) * 100) : 0;
      return { name: e.full_name.split(" ").slice(0, 2).join(" "), منجزة: done, متأخرة: overdue, الكفاءة: rate };
    });
  }, [employees, visibleTasks]);

  const taskMixData = useMemo(() => {
    const order: Array<keyof typeof TASK_STATUS_AR> = ["todo", "in_progress", "done", "overdue"];
    return order.map(k => ({ name: TASK_STATUS_AR[k], value: visibleTasks.filter(t => t.status === k).length }));
  }, [visibleTasks]);

  const closedCases = visibleCases.filter(c => c.closed_at);
  const avgDays = closedCases.length
    ? Math.round(closedCases.reduce((acc, c) => acc + Math.max(0, (new Date(c.closed_at!).getTime() - new Date(c.opened_at).getTime()) / 86_400_000), 0) / closedCases.length)
    : 0;
  const efficiencyScore = Math.max(0, Math.min(100, Math.round(100 - avgDays / 3)));

  const PIE_COLORS = ["#d4af37", "#1e3a5f", "#8b6b22", "#3b5f8a", "#b8941f", "#5a7ba5", "#6b5817", "#2d4a6b"];

  // ---- PDF export ----
  const exportPDF = async () => {
    if (!reportRef.current) return;
    setExporting(true);
    const id = toast.loading("جاري إنشاء التقرير…");
    try {
      const [{ default: html2canvas }, { default: jsPDF }] = await Promise.all([
        import("html2canvas"),
        import("jspdf"),
      ]);
      // wait a tick for charts to settle
      await new Promise(r => setTimeout(r, 250));
      const canvas = await html2canvas(reportRef.current, {
        scale: 1.5,
        useCORS: true,
        backgroundColor: "#ffffff",
        logging: false,
      });
      const img = canvas.toDataURL("image/jpeg", 0.92);
      const pdf = new jsPDF({ orientation: "portrait", unit: "pt", format: "a4" });
      const pageW = pdf.internal.pageSize.getWidth();
      const pageH = pdf.internal.pageSize.getHeight();
      const ratio = canvas.width / pageW;
      const imgH = canvas.height / ratio;
      let y = 0;
      while (y < imgH) {
        if (y > 0) pdf.addPage();
        pdf.addImage(img, "JPEG", 0, -y, pageW, imgH);
        y += pageH;
      }
      pdf.save(`lex-dashboard-${new Date().toISOString().slice(0, 10)}.pdf`);
      toast.success("تم إنشاء التقرير", { id });
    } catch (e) {
      console.error(e);
      toast.error("تعذّر إنشاء التقرير", { id });
    } finally {
      setExporting(false);
    }
  };

  const roleLabel = roles.length ? roles.map(r => ROLE_AR[r]).join(" • ") : "—";

  // Strict portal separation — employee takes precedence over client when both
  // roles are present, so an employee never falls into the client portal UI.
  if (rolesLoaded && roles.includes("employee") && !roles.includes("admin") && !roles.includes("lawyer")) {
    return <EmployeePortalView userId={user.id} />;
  }
  if (rolesLoaded && roles.includes("client") && !roles.includes("admin") && !roles.includes("lawyer") && !roles.includes("employee")) {
    return <ClientPortalView userId={user.id} />;
  }

  return (
    <div className="space-y-6" dir="rtl" ref={reportRef}>
      {/* ============ Welcome Hero (dark luxury) ============ */}
      <section className="card-night relative overflow-hidden p-7 md:p-10">
        <div className="pointer-events-none absolute -top-24 -left-20 h-72 w-72 rounded-full bg-gold/20 blur-3xl" />
        <div className="pointer-events-none absolute -bottom-32 -right-16 h-80 w-80 rounded-full bg-gold/10 blur-3xl" />
        <div className="relative flex flex-wrap items-center justify-between gap-6">
          <div className="flex items-center gap-5">
            <div className="grid h-16 w-16 place-items-center rounded-2xl bg-gradient-to-br from-gold to-gold/60 text-primary shadow-[0_10px_30px_-8px_rgba(212,175,55,0.6)]">
              <Crown className="h-8 w-8" />
            </div>
            <div className="min-w-0">
              <div className="text-xs uppercase tracking-[0.3em] text-gold/80">{todayArabic()}</div>
              {!editingProfile ? (
                <>
                  <h1 className="mt-1 text-2xl md:text-3xl font-extrabold flex items-center gap-2 flex-wrap">
                    <span className="shimmer-text">{greeting()}</span>
                    <span className="text-white/90">, {userName}</span>
                    <button
                      onClick={() => { setDraftName(userName); setDraftJob(jobTitle); setEditingProfile(true); }}
                      title="تعديل الاسم والمسمى الوظيفي"
                      data-html2canvas-ignore="true"
                      className="ml-1 grid h-7 w-7 place-items-center rounded-full border border-gold/40 bg-white/5 text-gold hover:bg-gold/20 transition"
                    >
                      <Pencil className="h-3.5 w-3.5" />
                    </button>
                  </h1>
                  <p className="mt-1 text-sm text-white/70">
                    منصة العدالة — لوحة الذكاء التنفيذي · <span className="text-gold">{roleLabel}</span>
                    {jobTitle && <> · <span className="text-gold/90 font-semibold">{jobTitle}</span></>}
                  </p>
                </>
              ) : (
                <div className="mt-2 grid gap-2 sm:grid-cols-2 max-w-xl" data-html2canvas-ignore="true">
                  <input
                    autoFocus
                    value={draftName}
                    onChange={(e) => setDraftName(e.target.value)}
                    placeholder="الاسم الكامل"
                    className="rounded-lg border border-gold/40 bg-white/10 text-white placeholder:text-white/40 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gold/50"
                  />
                  <input
                    value={draftJob}
                    onChange={(e) => setDraftJob(e.target.value)}
                    placeholder="المسمى الوظيفي (مثل: محامٍ أول)"
                    className="rounded-lg border border-gold/40 bg-white/10 text-white placeholder:text-white/40 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gold/50"
                  />
                  <div className="flex items-center gap-2 sm:col-span-2">
                    <button
                      onClick={saveProfile}
                      disabled={savingProfile}
                      className="inline-flex items-center gap-1.5 rounded-lg bg-gold px-4 py-2 text-xs font-bold text-primary hover:bg-gold/90 transition disabled:opacity-60"
                    >
                      <Check className="h-3.5 w-3.5" /> {savingProfile ? "جاري الحفظ…" : "حفظ"}
                    </button>
                    <button
                      onClick={() => setEditingProfile(false)}
                      className="inline-flex items-center gap-1.5 rounded-lg border border-white/20 bg-white/5 px-4 py-2 text-xs font-semibold text-white/80 hover:bg-white/10 transition"
                    >
                      <XIcon className="h-3.5 w-3.5" /> إلغاء
                    </button>
                  </div>
                </div>
              )}
            </div>
          </div>
          <div className="flex items-center gap-3 flex-wrap">
            <button
              onClick={() => setDashEditing(e => !e)}
              data-html2canvas-ignore="true"
              title="تخصيص وترتيب وتحجيم كروت لوحة البيانات"
              className={`inline-flex items-center gap-2 rounded-xl border px-4 py-2 text-sm font-bold transition shadow-lg ${
                dashEditing
                  ? "border-emerald-400/60 bg-emerald-400/15 text-emerald-200 shadow-emerald-500/30"
                  : "border-gold/50 bg-gold/10 text-gold hover:bg-gold/20 shadow-gold/20"
              }`}
            >
              {dashEditing ? <><Check className="h-4 w-4" /> إنهاء التخصيص</> : <><LayoutDashboard className="h-4 w-4" /> تخصيص اللوحة</>}
            </button>
            {upcomingWithin24h > 0 && (
              <span className="inline-flex items-center gap-1.5 rounded-lg border border-amber-400/40 bg-amber-400/10 px-3 py-2 text-xs font-bold text-amber-300">
                <Bell className="h-3.5 w-3.5" /> {upcomingWithin24h} جلسة خلال 24 ساعة
              </span>
            )}
            <button
              onClick={exportPDF}
              disabled={exporting}
              data-html2canvas-ignore="true"
              className="inline-flex items-center gap-2 rounded-lg border border-gold/40 bg-white/5 px-4 py-2 text-sm font-semibold text-white hover:bg-white/10 transition disabled:opacity-50"
            >
              <Download className="h-4 w-4 text-gold" /> {exporting ? "جاري التصدير…" : "تصدير PDF"}
            </button>
            <Link to="/app/cases" className="btn-gold inline-flex items-center gap-2 px-5 py-2.5 text-sm">
              <Briefcase className="h-4 w-4" /> القضايا
            </Link>
          </div>

        </div>

        {/* ============ Dark luxury stat tiles ============ */}
        <div className="relative mt-8 grid grid-cols-2 gap-3 md:grid-cols-4 lg:grid-cols-8">
          <StatTileDark icon={Briefcase} label="قضايا قائمة" value={openCount} accent="gold" />
          <StatTileDark icon={CalendarClock} label="مؤجلة" value={postponedCount} accent="amber" />
          <StatTileDark icon={CheckCircle2} label="منتهية" value={closedCount} accent="success" />
          <StatTileDark icon={Clock} label="جلسات قادمة" value={upcomingSessions.length} accent="gold" />
          <StatTileDark icon={Users2} label="عملاء" value={clients.length} accent="info" />
          <StatTileDark icon={CheckCircle2} label="مهام منجزة" value={doneTasks} accent="success" />
          <StatTileDark icon={AlertTriangle} label="مهام متأخرة" value={overdueTasks.length} accent="danger" />
          <StatTileDark icon={Gavel} label="استئنافات مستحقة" value={appealsDue.length} accent="amber" />
        </div>
      </section>

      <SectionHeading icon={LayoutDashboard} title="لوحة الذكاء التنفيذي" subtitle="مؤشرات أداء فورية وتحليلات ذكية لجميع عمليات المكتب" />

      {loading && (
        <div className="card-3d p-8 text-center text-muted-foreground">جاري تحميل البيانات…</div>
      )}

      <DashboardLayout
        userId={user.id}
        scope="main"
        editing={dashEditing}
        onEditingChange={setDashEditing}
        hideToolbar
        defaults={[

          { id: "timeline", span: 8 },
          { id: "ai-tools", span: 4 },
          { id: "status-pie", span: 4 },
          { id: "type-bar", span: 4 },
          { id: "task-mix", span: 4 },
          { id: "team-perf", span: 8 },
          { id: "kpis", span: 4 },
          { id: "agenda", span: 4 },
          { id: "urgent", span: 4 },
          { id: "deadlines", span: 8 },
          { id: "appeals", span: 4 },
          { id: "overdue", span: 4 },
          { id: "library", span: 4 },
          { id: "calculator", span: 4 },
        ]}
      >

        {/* Litigation Timeline */}
        <DashboardCard id="timeline" defaultSpan={8} title="التسلسل الزمني للتقاضي">
          <div className="card-3d p-6 h-full">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div className="flex items-center gap-2">
                <div className="grid h-10 w-10 place-items-center rounded-xl bg-gold/15 text-gold"><Layers3 className="h-5 w-5" /></div>
                <div>
                  <h3 className="font-bold text-lg">التسلسل الزمني للتقاضي</h3>
                  <p className="text-xs text-muted-foreground">قضايا وجلسات — قابلة للتصفية</p>
                </div>
              </div>
              <div className="flex items-center gap-2 flex-wrap" data-html2canvas-ignore="true">
                <select
                  value={period}
                  onChange={(e) => setPeriod(Number(e.target.value) as 3 | 6 | 12)}
                  className="rounded-lg border border-border bg-card px-3 py-2 text-sm shadow-soft focus:outline-none focus:ring-2 focus:ring-gold/40"
                >
                  <option value={3}>آخر 3 أشهر</option>
                  <option value={6}>آخر 6 أشهر</option>
                  <option value={8}>آخر 8 أشهر</option>
                  <option value={12}>آخر 12 شهراً</option>
                </select>
                <select
                  value={typeFilter}
                  onChange={(e) => setTypeFilter(e.target.value)}
                  className="rounded-lg border border-border bg-card px-3 py-2 text-sm shadow-soft focus:outline-none focus:ring-2 focus:ring-gold/40"
                >
                  <option value="__all__">كل الأنواع</option>
                  {Object.entries(CASE_TYPE_AR).map(([k, v]) => (
                    <option key={k} value={k}>{v}</option>
                  ))}
                </select>
                <button
                  onClick={() => setShowFilters(s => !s)}
                  className="inline-flex items-center gap-1.5 rounded-lg border border-border bg-card px-3 py-2 text-sm font-semibold hover:bg-muted transition"
                >
                  <Filter className="h-3.5 w-3.5" />
                  {selectedCases.length ? `${selectedCases.length} مختارة` : "اختيار قضايا"}
                </button>
              </div>
            </div>
            {showFilters && (
              <div className="mt-3 rounded-xl border border-border bg-muted/30 p-3 max-h-48 overflow-y-auto" data-html2canvas-ignore="true">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-xs font-bold text-muted-foreground">اختر قضايا محددة لتظهر في الرسم البياني</span>
                  <button onClick={() => setSelectedCases([])} className="text-xs font-bold text-gold hover:underline">مسح الاختيار (الكل)</button>
                </div>
                <div className="grid gap-1.5 sm:grid-cols-2 lg:grid-cols-3">
                  {filteredCases.length === 0 && <p className="text-xs text-muted-foreground">لا توجد قضايا مطابقة</p>}
                  {visibleCases.filter(c => typeFilter === "__all__" || c.case_type === typeFilter).slice(0, 80).map(c => {
                    const checked = selectedCases.includes(c.id);
                    return (
                      <label key={c.id} className={`flex items-center gap-2 cursor-pointer rounded-lg border px-2 py-1.5 text-xs transition ${checked ? "border-gold bg-gold/10" : "border-border bg-card hover:bg-muted"}`}>
                        <input
                          type="checkbox"
                          checked={checked}
                          onChange={(e) => {
                            setSelectedCases(prev => e.target.checked ? [...prev, c.id] : prev.filter(id => id !== c.id));
                          }}
                          className="accent-gold"
                        />
                        <span className="truncate"><span className="font-bold text-gold">{c.case_number}</span> — {c.title.slice(0, 30)}</span>
                      </label>
                    );
                  })}
                </div>
              </div>
            )}
            <div className="mt-5 h-72">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={timelineData}>
                  <defs>
                    <linearGradient id="gCases" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#d4af37" stopOpacity={0.55} />
                      <stop offset="95%" stopColor="#d4af37" stopOpacity={0} />
                    </linearGradient>
                    <linearGradient id="gSess" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#1e3a5f" stopOpacity={0.45} />
                      <stop offset="95%" stopColor="#1e3a5f" stopOpacity={0} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 6" stroke="currentColor" opacity={0.08} />
                  <XAxis dataKey="month" tick={{ fontSize: 11 }} />
                  <YAxis allowDecimals={false} tick={{ fontSize: 11 }} />
                  <Tooltip contentStyle={{ borderRadius: 12, border: "1px solid #d4af3766" }} />
                  <Legend />
                  <Area type="monotone" dataKey="قضايا" stroke="#d4af37" strokeWidth={2.5} fill="url(#gCases)" />
                  <Area type="monotone" dataKey="جلسات" stroke="#1e3a5f" strokeWidth={2.5} fill="url(#gSess)" />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </div>
        </DashboardCard>

        {/* AI Tools */}
        <DashboardCard id="ai-tools" defaultSpan={4} title="أدوات الذكاء الاصطناعي">
          <div className="card-3d p-6 h-full">
            <div className="flex items-center gap-2 mb-4">
              <div className="grid h-10 w-10 place-items-center rounded-xl bg-gold/15 text-gold"><Sparkles className="h-5 w-5" /></div>
              <div>
                <h3 className="font-bold text-lg">أدوات الذكاء الاصطناعي</h3>
                <p className="text-xs text-muted-foreground">دخول سريع للأدوات الذكية</p>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              {[
                { t: "المستشار", d: "تحليل ذكي", i: Bot, to: "/app/ai/consultant" },
                { t: "صياغة لوائح", d: "مذكرات ودعاوى", i: FileSignature, to: "/app/ai/memos" },
                { t: "حاسبة المدد", d: "استئناف واعتراض", i: Calculator, to: "/app/ai/calculator" },
                { t: "فواتير ZATCA", d: "فوترة معتمدة", i: Receipt, to: "/app/ai/zatca" },
              ].map(t => (
                <Link key={t.t} to={t.to} className="card-3d shine block p-4 group">
                  <div className="grid h-10 w-10 place-items-center rounded-xl bg-gradient-to-br from-gold to-gold/60 text-primary group-hover:scale-110 transition-transform">
                    <t.i className="h-5 w-5" />
                  </div>
                  <h4 className="mt-3 font-bold text-sm">{t.t}</h4>
                  <p className="mt-1 text-xs text-muted-foreground">{t.d}</p>
                </Link>
              ))}
            </div>
          </div>
        </DashboardCard>

        {/* KPI charts */}
        <DashboardCard id="status-pie" defaultSpan={4} title="حالات القضايا">
          <ChartCard icon={TrendingUp} title="حالات القضايا" subtitle="توزيع حسب الحالة">
            <ResponsiveContainer width="100%" height="100%">
              <PieChart>
                <Pie data={statusData} dataKey="value" nameKey="name" innerRadius={55} outerRadius={90} paddingAngle={3}>
                  {statusData.map((_, i) => <Cell key={i} fill={PIE_COLORS[i % PIE_COLORS.length]} />)}
                </Pie>
                <Tooltip contentStyle={{ borderRadius: 12 }} />
                <Legend />
              </PieChart>
            </ResponsiveContainer>
          </ChartCard>
        </DashboardCard>

        <DashboardCard id="type-bar" defaultSpan={4} title="توزيع القضايا">
          <ChartCard icon={Layers3} title="توزيع القضايا" subtitle="حسب نوع القضية">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={typeData}>
                <CartesianGrid strokeDasharray="3 6" opacity={0.08} />
                <XAxis dataKey="name" tick={{ fontSize: 11 }} />
                <YAxis allowDecimals={false} tick={{ fontSize: 11 }} />
                <Tooltip contentStyle={{ borderRadius: 12 }} />
                <Bar dataKey="value" fill="#d4af37" radius={[8, 8, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </ChartCard>
        </DashboardCard>

        <DashboardCard id="task-mix" defaultSpan={4} title="مزيج المهام">
          <ChartCard icon={ShieldCheck} title="مزيج المهام" subtitle="حالة المهام الحالية">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={taskMixData} layout="vertical">
                <CartesianGrid strokeDasharray="3 6" opacity={0.08} />
                <XAxis type="number" allowDecimals={false} tick={{ fontSize: 11 }} />
                <YAxis dataKey="name" type="category" tick={{ fontSize: 11 }} width={70} />
                <Tooltip contentStyle={{ borderRadius: 12 }} />
                <Bar dataKey="value" radius={[0, 8, 8, 0]}>
                  {taskMixData.map((_, i) => <Cell key={i} fill={["#3b5f8a", "#d4af37", "#16a34a", "#dc2626"][i] || "#888"} />)}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </ChartCard>
        </DashboardCard>

        {/* Team performance */}
        <DashboardCard id="team-perf" defaultSpan={8} title="تحليل أداء الفريق">
          <div className="card-3d p-6 h-full">
            <div className="flex items-center gap-2 mb-2">
              <div className="grid h-10 w-10 place-items-center rounded-xl bg-gold/15 text-gold"><Users2 className="h-5 w-5" /></div>
              <div>
                <h3 className="font-bold text-lg">تحليل أداء الفريق</h3>
                <p className="text-xs text-muted-foreground">مهام منجزة، متأخرة، ونسبة الكفاءة لكل موظف</p>
              </div>
            </div>
            <div className="mt-4 h-72">
              {teamData.length ? (
                <ResponsiveContainer width="100%" height="100%">
                  <LineChart data={teamData}>
                    <CartesianGrid strokeDasharray="3 6" opacity={0.08} />
                    <XAxis dataKey="name" tick={{ fontSize: 11 }} />
                    <YAxis tick={{ fontSize: 11 }} />
                    <Tooltip contentStyle={{ borderRadius: 12 }} />
                    <Legend />
                    <Line type="monotone" dataKey="منجزة" stroke="#16a34a" strokeWidth={2.5} dot={{ r: 4 }} />
                    <Line type="monotone" dataKey="متأخرة" stroke="#dc2626" strokeWidth={2.5} dot={{ r: 4 }} />
                    <Line type="monotone" dataKey="الكفاءة" stroke="#d4af37" strokeWidth={3} dot={{ r: 5 }} />
                  </LineChart>
                </ResponsiveContainer>
              ) : (
                <EmptyChart text="لا يوجد موظفون مسجلون بعد" />
              )}
            </div>
          </div>
        </DashboardCard>

        <DashboardCard id="kpis" defaultSpan={4} title="مؤشرات الكفاءة">
          <div className="flex flex-col gap-5 h-full">
            <KpiPanel
              icon={TrendingUp}
              title="نسبة إنجاز المهام"
              value={`${completionRate}%`}
              sub={`${doneTasks} من ${visibleTasks.length} مهمة`}
              progress={completionRate}
            />
            <KpiPanel
              icon={Timer}
              title="كفاءة العمليات القانونية"
              value={`${efficiencyScore}%`}
              sub={`متوسط مدة إنهاء القضية: ${avgDays} يوم`}
              progress={efficiencyScore}
              color="success"
            />
          </div>
        </DashboardCard>

        {/* Agenda */}
        <DashboardCard id="agenda" defaultSpan={4} title="جدول الأعمال">
          <ListCard
            icon={CalendarClock}
            title="جدول الأعمال — الجلسات القادمة"
            empty="لا توجد جلسات مجدولة"
            items={upcomingSessions.slice(0, 6).map(s => {
              const d = daysBetween(s.session_date);
              const h = hoursUntil(s.session_date);
              return {
                key: s.id,
                primary: s.court || "جلسة قضائية",
                secondary: new Date(s.session_date).toLocaleString("ar-SA-u-ca-gregory", { dateStyle: "medium", timeStyle: "short" }),
                badge: h <= 24 ? `خلال ${Math.max(1, Math.round(h))} ساعة` : d === 1 ? "غداً" : `بعد ${d} يوم`,
                tone: h <= 24 ? "danger" : d <= 7 ? "amber" : "gold",
              };
            })}
          />
        </DashboardCard>

        <DashboardCard id="urgent" defaultSpan={4} title="مهام عاجلة">
          <ListCard
            icon={Flame}
            title="مهام عاجلة"
            empty="لا توجد مهام عاجلة 🎉"
            items={urgentTasks.slice(0, 6).map(t => {
              const overdue = t.due_date ? daysBetween(t.due_date) < 0 : false;
              return {
                key: t.id,
                primary: t.title,
                secondary: t.due_date ? `استحقاق: ${new Date(t.due_date).toLocaleDateString("ar-SA-u-ca-gregory")}` : "بدون موعد",
                badge: overdue ? "متأخرة" : "عاجلة",
                tone: overdue ? "danger" : "amber",
              };
            })}
          />
        </DashboardCard>

        {/* Unified deadlines & expiry alerts */}
        <DashboardCard id="deadlines" defaultSpan={8} title="تنبيهات المُدد والمهل">
          <div className="card-3d p-6 h-full">
            <div className="flex items-center gap-2 mb-4">
              <div className="grid h-10 w-10 place-items-center rounded-xl bg-amber-500/15 text-amber-600"><Timer className="h-5 w-5" /></div>
              <div className="flex-1">
                <h3 className="font-bold text-lg">تنبيهات المُدد والمهل</h3>
                <p className="text-xs text-muted-foreground">جلسات قادمة، مواعيد استئناف، انتهاء وكالات، ومهام مستحقة — مرتّبة حسب الأولوية</p>
              </div>
              <span className="rounded-full bg-amber-500/15 text-amber-700 px-2.5 py-1 text-xs font-bold">{deadlines.length}</span>
            </div>
            {deadlines.length === 0 ? (
              <p className="text-sm text-muted-foreground text-center py-8">لا توجد مهل قريبة. كل شيء تحت السيطرة 🎉</p>
            ) : (
              <ul className="space-y-2 max-h-80 overflow-y-auto pr-1">
                {deadlines.slice(0, 12).map(d => {
                  const tone = d.tone === "danger" ? "border-rose-500/40 bg-rose-500/5" : d.tone === "amber" ? "border-amber-500/40 bg-amber-500/5" : "border-gold/30 bg-gold/5";
                  const badgeTone = d.tone === "danger" ? "bg-rose-500 text-white" : d.tone === "amber" ? "bg-amber-500 text-white" : "bg-gold text-primary";
                  return (
                    <li key={d.key} className={`flex items-center justify-between gap-3 rounded-lg border px-3 py-2 ${tone}`}>
                      <div className="min-w-0">
                        <div className="truncate text-sm font-bold">{d.primary}</div>
                        <div className="text-xs text-muted-foreground">{d.secondary}</div>
                      </div>
                      <span className={`shrink-0 rounded-full px-2.5 py-0.5 text-[11px] font-extrabold ${badgeTone}`}>{d.badge}</span>
                    </li>
                  );
                })}
              </ul>
            )}
          </div>
        </DashboardCard>

        <DashboardCard id="appeals" defaultSpan={4} title="مواعيد الاستئناف">
          <ListCard
            icon={Gavel}
            title="تذكير بمواعيد الاستئناف"
            empty="لا توجد مهل استئناف قريبة"
            items={appealsDue.slice(0, 6).map(d => {
              const days = daysBetween(d.appeal_deadline!);
              return {
                key: d.id,
                primary: d.title,
                secondary: `الموعد النظامي: ${new Date(d.appeal_deadline!).toLocaleDateString("ar-SA-u-ca-gregory")}`,
                badge: days <= 3 ? `${days} أيام` : `${days} يوم`,
                tone: days <= 3 ? "danger" : days <= 14 ? "amber" : "gold",
              };
            })}
          />
        </DashboardCard>

        <DashboardCard id="overdue" defaultSpan={4} title="المهام المتأخرة">
          <div className="card-3d relative overflow-hidden p-6 border-destructive/40 h-full">
            <div className="pointer-events-none absolute -top-12 -left-12 h-40 w-40 rounded-full bg-destructive/20 blur-2xl" />
            <div className="relative flex items-center gap-2 mb-4">
              <div className="grid h-10 w-10 place-items-center rounded-xl bg-destructive/15 text-destructive"><AlertTriangle className="h-5 w-5" /></div>
              <div>
                <h3 className="font-bold text-lg text-destructive">المهام المتأخرة</h3>
                <p className="text-xs text-muted-foreground">تحتاج تدخل فوري</p>
              </div>
            </div>
            {overdueTasks.length === 0 ? (
              <p className="text-sm text-muted-foreground">لا توجد مهام متأخرة. ممتاز!</p>
            ) : (
              <ul className="space-y-2 max-h-64 overflow-y-auto pr-1">
                {overdueTasks.slice(0, 8).map(t => (
                  <li key={t.id} className="flex items-center justify-between rounded-lg border border-destructive/30 bg-destructive/5 px-3 py-2">
                    <div className="min-w-0">
                      <div className="truncate text-sm font-semibold text-destructive">{t.title}</div>
                      <div className="text-xs text-muted-foreground">{t.due_date && `كان موعدها: ${new Date(t.due_date).toLocaleDateString("ar-SA-u-ca-gregory")}`}</div>
                    </div>
                    <span className="shrink-0 rounded-full bg-destructive px-2 py-0.5 text-[10px] font-bold text-white">متأخرة</span>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </DashboardCard>

        <DashboardCard id="library" defaultSpan={4} title="المكتبة القانونية">
          <Link to="/app/library" className="card-3d shine tilt-on-hover block p-6 group h-full">
            <div className="flex items-center gap-3">
              <div className="grid h-12 w-12 place-items-center rounded-xl bg-gradient-to-br from-gold to-gold/60 text-primary shadow-gold">
                <BookOpen className="h-6 w-6" />
              </div>
              <div>
                <h3 className="font-bold text-lg">المكتبة القانونية</h3>
                <p className="text-xs text-muted-foreground">جميع الأنظمة في المملكة العربية السعودية</p>
              </div>
            </div>
            <p className="mt-4 text-sm text-muted-foreground leading-relaxed">
              مرجع شامل للأنظمة واللوائح والتعاميم القضائية مع بحث ذكي وفهرسة موضوعية.
            </p>
            <div className="mt-5 inline-flex items-center gap-1 text-sm font-bold text-gold group-hover:gap-2 transition-all">
              تصفّح المكتبة <ChevronLeft className="h-4 w-4" />
            </div>
          </Link>
        </DashboardCard>

        <DashboardCard id="calculator" defaultSpan={4} title="الحاسبة القضائية">
          <Link to="/app/ai/calculator" className="card-3d shine tilt-on-hover block p-6 group h-full">
            <div className="flex items-center gap-3">
              <div className="grid h-12 w-12 place-items-center rounded-xl bg-gradient-to-br from-primary to-primary/70 text-gold shadow-lg">
                <Calculator className="h-6 w-6" />
              </div>
              <div>
                <h3 className="font-bold text-lg">الحاسبة القضائية</h3>
                <p className="text-xs text-muted-foreground">احتساب المدد النظامية بدقة</p>
              </div>
            </div>
            <p className="mt-4 text-sm text-muted-foreground leading-relaxed">
              حساب مدد الاستئناف، الاعتراض، والمواعيد النظامية وفق الأنظمة السعودية.
            </p>
            <div className="mt-5 inline-flex items-center gap-1 text-sm font-bold text-gold group-hover:gap-2 transition-all">
              افتح الحاسبة <ChevronLeft className="h-4 w-4" />
            </div>
          </Link>
        </DashboardCard>
      </DashboardLayout>

    </div>
  );
}

/* ============ Components ============ */

function LiveBadge({ status }: { status: "connecting" | "live" | "offline" }) {
  const map = {
    live: { txt: "بث مباشر", color: "border-emerald-400/40 bg-emerald-400/10 text-emerald-300", dot: "bg-emerald-400 animate-pulse" },
    connecting: { txt: "جارٍ الاتصال…", color: "border-amber-400/40 bg-amber-400/10 text-amber-300", dot: "bg-amber-400" },
    offline: { txt: "غير متصل", color: "border-rose-400/40 bg-rose-400/10 text-rose-300", dot: "bg-rose-400" },
  }[status];
  return (
    <span className={`inline-flex items-center gap-2 rounded-lg border px-3 py-2 text-xs font-bold ${map.color}`}>
      <span className={`inline-block h-2 w-2 rounded-full ${map.dot}`} />
      <Radio className="h-3.5 w-3.5" /> {map.txt}
    </span>
  );
}

function SectionHeading({ icon: Icon, title, subtitle }: { icon: typeof Briefcase; title: string; subtitle?: string }) {
  return (
    <div className="flex items-end justify-between gap-4">
      <div className="flex items-center gap-3">
        <div className="grid h-12 w-12 place-items-center rounded-2xl bg-gradient-to-br from-primary to-primary/70 text-gold shadow-lg">
          <Icon className="h-6 w-6" />
        </div>
        <div>
          <h2 className="text-xl md:text-2xl font-extrabold text-gradient-royal">{title}</h2>
          {subtitle && <p className="text-xs md:text-sm text-muted-foreground mt-0.5">{subtitle}</p>}
        </div>
      </div>
      <div className="gold-divider flex-1 max-w-xs hidden md:block" />
    </div>
  );
}

function StatTileDark({
  icon: Icon, label, value, accent,
}: { icon: typeof Briefcase; label: string; value: number; accent: "gold" | "amber" | "success" | "danger" | "info" }) {
  const ring: Record<typeof accent, string> = {
    gold: "from-gold/30 to-gold/0 text-gold",
    amber: "from-amber-300/30 to-amber-300/0 text-amber-300",
    success: "from-emerald-300/30 to-emerald-300/0 text-emerald-300",
    danger: "from-rose-400/30 to-rose-400/0 text-rose-300",
    info: "from-sky-300/30 to-sky-300/0 text-sky-300",
  } as const;
  return (
    <Tilt3D max={10} className="h-full">
      <div className="group relative rounded-xl border border-white/10 bg-white/5 p-3 backdrop-blur-sm transition-all duration-300 hover:-translate-y-1 hover:border-gold/40 hover:bg-white/10 hover:shadow-[0_15px_40px_-15px_rgba(212,175,55,0.5)]">
        <div className={`pointer-events-none absolute inset-0 rounded-xl bg-gradient-to-br ${ring[accent]} opacity-50`} />
        <div className="relative flex items-center justify-between">
          <Icon className={`h-5 w-5 ${ring[accent].split(" ").slice(-1)[0]}`} />
          <span className="text-2xl font-extrabold text-white">{value}</span>
        </div>
        <div className="relative mt-1 text-[11px] text-white/70">{label}</div>
      </div>
    </Tilt3D>
  );
}

function ChartCard({ icon: Icon, title, subtitle, children }: { icon: typeof Briefcase; title: string; subtitle: string; children: React.ReactNode }) {
  return (
    <div className="card-3d p-6">
      <div className="flex items-center gap-2">
        <div className="grid h-10 w-10 place-items-center rounded-xl bg-gold/15 text-gold"><Icon className="h-5 w-5" /></div>
        <div>
          <h3 className="font-bold text-lg">{title}</h3>
          <p className="text-xs text-muted-foreground">{subtitle}</p>
        </div>
      </div>
      <div className="mt-4 h-60">{children}</div>
    </div>
  );
}

function KpiPanel({
  icon: Icon, title, value, sub, progress, color = "gold",
}: { icon: typeof Briefcase; title: string; value: string; sub: string; progress: number; color?: "gold" | "success" }) {
  const bar = color === "success" ? "from-emerald-400 to-emerald-600" : "from-gold to-amber-500";
  return (
    <div className="card-3d p-5">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="grid h-10 w-10 place-items-center rounded-xl bg-gold/15 text-gold"><Icon className="h-5 w-5" /></div>
          <div>
            <h3 className="font-bold text-sm">{title}</h3>
            <p className="text-[11px] text-muted-foreground">{sub}</p>
          </div>
        </div>
        <div className="text-3xl font-extrabold text-gradient-royal">{value}</div>
      </div>
      <div className="mt-4 h-2.5 w-full overflow-hidden rounded-full bg-muted">
        <div className={`h-full bg-gradient-to-r ${bar} transition-[width] duration-700`} style={{ width: `${progress}%` }} />
      </div>
    </div>
  );
}

type ListItem = { key: string; primary: string; secondary: string; badge: string; tone: "gold" | "amber" | "danger" };

function ListCard({ icon: Icon, title, items, empty }: { icon: typeof Briefcase; title: string; items: ListItem[]; empty: string }) {
  const tones = {
    gold: "bg-gold/15 text-gold border-gold/30",
    amber: "bg-amber-500/15 text-amber-600 border-amber-500/30",
    danger: "bg-destructive/15 text-destructive border-destructive/30",
  };
  return (
    <div className="card-3d p-6">
      <div className="flex items-center gap-2 mb-4">
        <div className="grid h-10 w-10 place-items-center rounded-xl bg-gold/15 text-gold"><Icon className="h-5 w-5" /></div>
        <h3 className="font-bold text-lg">{title}</h3>
      </div>
      {items.length === 0 ? (
        <p className="text-sm text-muted-foreground py-6 text-center">{empty}</p>
      ) : (
        <ul className="space-y-2 max-h-72 overflow-y-auto pr-1">
          {items.map(it => (
            <li key={it.key} className="flex items-center justify-between rounded-lg border border-border bg-muted/30 px-3 py-2 hover:bg-muted/60 hover:border-gold/30 transition">
              <div className="min-w-0">
                <div className="truncate text-sm font-semibold">{it.primary}</div>
                <div className="text-xs text-muted-foreground">{it.secondary}</div>
              </div>
              <span className={`shrink-0 rounded-full border px-2 py-0.5 text-[10px] font-bold ${tones[it.tone]}`}>{it.badge}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function EmptyChart({ text }: { text: string }) {
  return <div className="h-full grid place-items-center text-sm text-muted-foreground border-2 border-dashed rounded-xl">{text}</div>;
}
