import { createFileRoute } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { useMutation } from "@tanstack/react-query";
import {
  BarChart3, Users, CheckCircle2, AlertTriangle, Clock, Target, Sparkles, Download, FileText,
  Loader2,
} from "lucide-react";
import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, Legend,
  PieChart, Pie, Cell,
  RadarChart, PolarGrid, PolarAngleAxis, PolarRadiusAxis, Radar,
  LineChart, Line,
} from "recharts";
import { PageHeader } from "@/components/section-shell";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { useList } from "@/lib/data-hooks";
import { useRealtimeTable } from "@/lib/realtime";
import { analyzePerformance } from "@/lib/performance.functions";
import { exportRecordPdf } from "@/lib/pdf-export";
import { RequireRole } from "@/components/require-role";
import { toast } from "sonner";

export const Route = createFileRoute("/_authenticated/app/performance")({
  component: GuardedPerformancePage,
});

function GuardedPerformancePage() {
  return (
    <RequireRole allowed={["lawyer", "admin"]}>
      <PerformancePage />
    </RequireRole>
  );
}

type EmpStat = {
  id: string;
  user_id: string | null;
  employee_name: string;
  total: number;
  done: number;
  in_progress: number;
  todo: number;
  overdue: number;
  on_time_done: number;
  avg_completion_days: number | null;
  efficiency_score: number; // 0-100
  speed_score: number;
  accuracy_score: number;
  volume_score: number;
  discipline_score: number;
  cases_count: number;
};

const PALETTE = ["#d4af37", "#0c1426", "#3b82f6", "#10b981", "#ef4444", "#f59e0b", "#8b5cf6", "#06b6d4"];

function isOverdue(t: any) {
  if (!t.due_date || t.status === "done") return false;
  return new Date(t.due_date + "T23:59:59").getTime() < Date.now();
}

function PerformancePage() {
  // Realtime so KPI reflects task changes instantly.
  useRealtimeTable("tasks", ["tasks"]);

  const { data: employees = [], isLoading: l1 } = useList<any>("employees");
  const { data: tasks = [], isLoading: l2 } = useList<any>("tasks");
  const { data: cases = [] } = useList<any>("cases");
  const [selected, setSelected] = useState<string>("all");
  const [aiText, setAiText] = useState<string>("");

  const stats = useMemo<EmpStat[]>(() => {
    const maxVolume = Math.max(1, ...employees.map((e) =>
      tasks.filter((t) => t.employee_id === e.id).length));
    return employees.map((e) => {
      const mine = tasks.filter((t) => t.employee_id === e.id);
      const done = mine.filter((t) => t.status === "done");
      const inProg = mine.filter((t) => t.status === "in_progress");
      const todo = mine.filter((t) => t.status === "todo");
      const overdue = mine.filter(isOverdue);
      const onTime = done.filter((t) =>
        t.completed_at && t.due_date &&
        new Date(t.completed_at).getTime() <= new Date(t.due_date + "T23:59:59").getTime(),
      );
      const completionDays = done
        .filter((t) => t.completed_at && t.created_at)
        .map((t) => (new Date(t.completed_at).getTime() - new Date(t.created_at).getTime()) / 86_400_000);
      const avgDays = completionDays.length
        ? Math.round((completionDays.reduce((a, b) => a + b, 0) / completionDays.length) * 10) / 10
        : null;

      // Scoring (0-100)
      const total = mine.length;
      const accuracy = total ? Math.round((onTime.length / Math.max(1, done.length)) * 100) : 0;
      const speed = avgDays == null ? 0
        : Math.max(0, Math.min(100, Math.round(100 - Math.min(avgDays, 30) * (100 / 30))));
      const volume = Math.round((total / maxVolume) * 100);
      const discipline = total ? Math.max(0, Math.round(100 - (overdue.length / total) * 100)) : 100;
      const efficiency = Math.round((accuracy + speed + volume + discipline) / 4);

      const empCases = cases.filter((c) =>
        Array.isArray(e.assigned_cases) && e.assigned_cases.includes(c.id),
      ).length;

      return {
        id: e.id,
        user_id: e.user_id ?? null,
        employee_name: e.full_name ?? "—",
        total,
        done: done.length,
        in_progress: inProg.length,
        todo: todo.length,
        overdue: overdue.length,
        on_time_done: onTime.length,
        avg_completion_days: avgDays,
        efficiency_score: efficiency,
        speed_score: speed,
        accuracy_score: accuracy,
        volume_score: volume,
        discipline_score: discipline,
        cases_count: empCases,
      };
    });
  }, [employees, tasks, cases]);

  const view = selected === "all" ? stats : stats.filter((s) => s.id === selected);
  const focused = selected !== "all" ? stats.find((s) => s.id === selected) : null;

  const totals = useMemo(() => ({
    assigned: view.reduce((a, s) => a + s.total, 0),
    done: view.reduce((a, s) => a + s.done, 0),
    overdue: view.reduce((a, s) => a + s.overdue, 0),
    avgEfficiency: view.length ? Math.round(view.reduce((a, s) => a + s.efficiency_score, 0) / view.length) : 0,
  }), [view]);

  const aiMut = useMutation({
    mutationFn: async () => analyzePerformance({
      data: {
        stats: view.map((s) => ({
          employee_name: s.employee_name,
          total: s.total, done: s.done, in_progress: s.in_progress, todo: s.todo,
          overdue: s.overdue, on_time_done: s.on_time_done,
          avg_completion_days: s.avg_completion_days,
        })),
        focus: focused?.employee_name ?? null,
      },
    }),
    onSuccess: (r) => setAiText(r.text),
    onError: (e: any) => toast.error(e.message || "تعذّر التحليل"),
  });

  const exportCsv = () => {
    const headers = ["الموظف", "المُسنَدة", "المُنجَزة", "جارية", "قيد البدء", "متأخّرة",
      "بالموعد", "متوسط الإنجاز (يوم)", "الكفاءة %", "السرعة %", "الدقة %", "الحجم %", "الانضباط %", "القضايا"];
    const rows = view.map((s) => [
      s.employee_name, s.total, s.done, s.in_progress, s.todo, s.overdue,
      s.on_time_done, s.avg_completion_days ?? "—",
      s.efficiency_score, s.speed_score, s.accuracy_score, s.volume_score, s.discipline_score, s.cases_count,
    ]);
    const csv = "\ufeff" + [headers, ...rows].map((r) => r.join(",")).join("\n");
    const a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
    a.download = `performance-${focused?.employee_name ?? "all"}-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(a.href);
  };

  const exportPdf = async () => {
    if (!focused) {
      // Export all as one PDF: list of employees
      await exportRecordPdf({
        title: "تقرير مؤشرات الأداء — كل الموظفين",
        subtitle: `إجمالي ${view.length} موظف`,
        fields: [
          { label: "إجمالي المهام المُسنَدة", value: totals.assigned },
          { label: "إجمالي المنجزة", value: totals.done },
          { label: "إجمالي المتأخرة", value: totals.overdue },
          { label: "متوسط الكفاءة العامة", value: `${totals.avgEfficiency}%` },
          ...view.map((s) => ({
            label: s.employee_name,
            value: `كفاءة ${s.efficiency_score}% · مُنجَزة ${s.done}/${s.total} · متأخرة ${s.overdue}`,
          })),
        ],
        footer: aiText || undefined,
        fileName: `performance-all-${new Date().toISOString().slice(0, 10)}.pdf`,
      });
      return;
    }
    await exportRecordPdf({
      title: `تقرير الأداء — ${focused.employee_name}`,
      subtitle: `الكفاءة الإجمالية: ${focused.efficiency_score}%`,
      fields: [
        { label: "المهام المُسنَدة", value: focused.total },
        { label: "المُنجَزة", value: focused.done },
        { label: "جارٍ التنفيذ", value: focused.in_progress },
        { label: "قيد البدء", value: focused.todo },
        { label: "المتأخّرة", value: focused.overdue },
        { label: "المُنجَزة في الموعد", value: focused.on_time_done },
        { label: "متوسط زمن الإنجاز (يوم)", value: focused.avg_completion_days ?? "—" },
        { label: "السرعة", value: `${focused.speed_score}%` },
        { label: "الدقة", value: `${focused.accuracy_score}%` },
        { label: "الحجم", value: `${focused.volume_score}%` },
        { label: "الانضباط", value: `${focused.discipline_score}%` },
        { label: "عدد القضايا المتابَعة", value: focused.cases_count },
      ],
      footer: aiText || undefined,
      fileName: `performance-${focused.employee_name}-${new Date().toISOString().slice(0, 10)}.pdf`,
    });
  };

  const loading = l1 || l2;

  // Chart datasets
  const barData = view.map((s) => ({ name: s.employee_name, مُنجَزة: s.done, جارية: s.in_progress, متأخرة: s.overdue }));
  const radarData = focused
    ? [
        { metric: "السرعة", value: focused.speed_score },
        { metric: "الدقة", value: focused.accuracy_score },
        { metric: "الحجم", value: focused.volume_score },
        { metric: "الانضباط", value: focused.discipline_score },
        { metric: "الكفاءة", value: focused.efficiency_score },
      ]
    : [
        { metric: "السرعة", value: avg(view, "speed_score") },
        { metric: "الدقة", value: avg(view, "accuracy_score") },
        { metric: "الحجم", value: avg(view, "volume_score") },
        { metric: "الانضباط", value: avg(view, "discipline_score") },
        { metric: "الكفاءة", value: avg(view, "efficiency_score") },
      ];
  const pieData = view
    .filter((s) => s.cases_count > 0)
    .map((s) => ({ name: s.employee_name, value: s.cases_count }));

  // Line: completions over the last 30 days
  const trendData = useMemo(() => {
    const buckets: Record<string, number> = {};
    const days: string[] = [];
    for (let i = 29; i >= 0; i--) {
      const d = new Date(); d.setDate(d.getDate() - i);
      const k = d.toISOString().slice(0, 10);
      buckets[k] = 0; days.push(k);
    }
    tasks.forEach((t) => {
      if (t.status !== "done" || !t.completed_at) return;
      if (selected !== "all" && t.employee_id !== selected) return;
      const k = String(t.completed_at).slice(0, 10);
      if (k in buckets) buckets[k] += 1;
    });
    return days.map((k) => ({ day: k.slice(5), منجزة: buckets[k] }));
  }, [tasks, selected]);

  return (
    <>
      <PageHeader
        icon={BarChart3}
        title="مؤشرات الأداء KPI's"
        subtitle="تحليل أداء الموظفين بالأرقام والرسومات + تحليل بالذكاء الاصطناعي"
        action={
          <div className="flex gap-2">
            <Button variant="outline" onClick={exportCsv} disabled={loading}>
              <Download className="h-4 w-4 ml-2" /> CSV
            </Button>
            <Button variant="outline" onClick={exportPdf} disabled={loading}>
              <FileText className="h-4 w-4 ml-2" /> PDF
            </Button>
          </div>
        }
      />

      {/* Filter */}
      <Card className="card-3d border-none p-4 mb-5">
        <div className="flex flex-wrap items-center gap-3">
          <div className="text-sm font-bold">عرض:</div>
          <Select value={selected} onValueChange={setSelected}>
            <SelectTrigger className="w-[260px]">
              <SelectValue placeholder="اختر موظفاً" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">كل الموظفين (مجمّع)</SelectItem>
              {employees.map((e) => (
                <SelectItem key={e.id} value={e.id}>{e.full_name}</SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Button
            className="btn-gold mr-auto"
            onClick={() => aiMut.mutate()}
            disabled={aiMut.isPending || view.length === 0}
          >
            {aiMut.isPending
              ? <Loader2 className="h-4 w-4 ml-2 animate-spin" />
              : <Sparkles className="h-4 w-4 ml-2" />}
            تحليل بالذكاء الاصطناعي
          </Button>
        </div>
      </Card>

      {/* KPI cards */}
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4 mb-5">
        <Kpi icon={Users} label="الموظفون" value={view.length} tone="from-primary/15 to-primary/5" />
        <Kpi icon={Target} label="مهام مُسنَدة" value={totals.assigned} tone="from-sky-500/15 to-sky-500/5" />
        <Kpi icon={CheckCircle2} label="منجَزة" value={totals.done} tone="from-emerald-500/15 to-emerald-500/5" />
        <Kpi icon={AlertTriangle} label="متأخرة" value={totals.overdue} tone="from-destructive/15 to-destructive/5" danger />
      </div>

      <div className="grid gap-4 lg:grid-cols-2 mb-5">
        <Card className="card-3d border-none p-5">
          <div className="flex items-center gap-2 mb-3">
            <BarChart3 className="h-4 w-4 text-gold" />
            <h3 className="font-bold">المهام لكل موظف</h3>
          </div>
          <ResponsiveContainer width="100%" height={280}>
            <BarChart data={barData}>
              <CartesianGrid strokeDasharray="3 3" opacity={0.2} />
              <XAxis dataKey="name" fontSize={11} />
              <YAxis fontSize={11} />
              <Tooltip />
              <Legend />
              <Bar dataKey="مُنجَزة" fill="#10b981" radius={[8, 8, 0, 0]} />
              <Bar dataKey="جارية" fill="#3b82f6" radius={[8, 8, 0, 0]} />
              <Bar dataKey="متأخرة" fill="#ef4444" radius={[8, 8, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </Card>

        <Card className="card-3d border-none p-5">
          <div className="flex items-center gap-2 mb-3">
            <Target className="h-4 w-4 text-gold" />
            <h3 className="font-bold">الكفاءة متعددة الأبعاد</h3>
          </div>
          <ResponsiveContainer width="100%" height={280}>
            <RadarChart data={radarData}>
              <PolarGrid />
              <PolarAngleAxis dataKey="metric" fontSize={11} />
              <PolarRadiusAxis domain={[0, 100]} fontSize={10} />
              <Radar dataKey="value" stroke="#d4af37" fill="#d4af37" fillOpacity={0.45} />
              <Tooltip />
            </RadarChart>
          </ResponsiveContainer>
        </Card>

        <Card className="card-3d border-none p-5">
          <div className="flex items-center gap-2 mb-3">
            <Clock className="h-4 w-4 text-gold" />
            <h3 className="font-bold">الإنجاز اليومي (30 يوم)</h3>
          </div>
          <ResponsiveContainer width="100%" height={240}>
            <LineChart data={trendData}>
              <CartesianGrid strokeDasharray="3 3" opacity={0.2} />
              <XAxis dataKey="day" fontSize={10} />
              <YAxis fontSize={11} allowDecimals={false} />
              <Tooltip />
              <Line type="monotone" dataKey="منجزة" stroke="#10b981" strokeWidth={2} dot={false} />
            </LineChart>
          </ResponsiveContainer>
        </Card>

        <Card className="card-3d border-none p-5">
          <div className="flex items-center gap-2 mb-3">
            <Users className="h-4 w-4 text-gold" />
            <h3 className="font-bold">توزيع القضايا على الموظفين</h3>
          </div>
          {pieData.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-12">لم تُسنَد قضايا بعد</p>
          ) : (
            <ResponsiveContainer width="100%" height={240}>
              <PieChart>
                <Pie data={pieData} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={90} label>
                  {pieData.map((_, i) => <Cell key={i} fill={PALETTE[i % PALETTE.length]} />)}
                </Pie>
                <Tooltip />
              </PieChart>
            </ResponsiveContainer>
          )}
        </Card>
      </div>

      {/* AI text */}
      {(aiText || aiMut.isPending) && (
        <Card className="card-3d border-none p-5 mb-5">
          <div className="flex items-center gap-2 mb-2">
            <Sparkles className="h-4 w-4 text-gold" />
            <h3 className="font-bold">تحليل الذكاء الاصطناعي</h3>
          </div>
          {aiMut.isPending ? (
            <p className="text-sm text-muted-foreground"><Loader2 className="inline h-4 w-4 animate-spin ml-1" /> يحلّل البيانات...</p>
          ) : (
            <Textarea value={aiText} onChange={(e) => setAiText(e.target.value)} rows={6}
              className="text-sm leading-relaxed" />
          )}
        </Card>
      )}

      {/* Detail table */}
      <Card className="card-3d border-none p-0 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-muted/40">
              <tr>
                {["الموظف", "كفاءة", "سرعة", "دقة", "حجم", "انضباط", "مُسنَدة", "منجَزة", "متأخرة", "متوسط (يوم)", "قضايا"].map((h) =>
                  <th key={h} className="p-3 text-right text-xs font-bold">{h}</th>)}
              </tr>
            </thead>
            <tbody>
              {view.map((s) => (
                <tr key={s.id} className="border-t">
                  <td className="p-3 font-bold">{s.employee_name}</td>
                  <td className="p-3"><Badge className="bg-gold/15 text-gold border-gold/30">{s.efficiency_score}%</Badge></td>
                  <td className="p-3">{s.speed_score}%</td>
                  <td className="p-3">{s.accuracy_score}%</td>
                  <td className="p-3">{s.volume_score}%</td>
                  <td className="p-3">{s.discipline_score}%</td>
                  <td className="p-3">{s.total}</td>
                  <td className="p-3 text-emerald-600">{s.done}</td>
                  <td className="p-3 text-destructive">{s.overdue}</td>
                  <td className="p-3">{s.avg_completion_days ?? "—"}</td>
                  <td className="p-3">{s.cases_count}</td>
                </tr>
              ))}
              {view.length === 0 && (
                <tr><td colSpan={11} className="p-10 text-center text-muted-foreground">لا توجد بيانات</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </Card>
    </>
  );
}

function avg(arr: EmpStat[], key: keyof EmpStat): number {
  if (!arr.length) return 0;
  const n = arr.reduce((a, s) => a + (typeof s[key] === "number" ? (s[key] as number) : 0), 0);
  return Math.round(n / arr.length);
}

function Kpi({ icon: Icon, label, value, tone, danger }:
  { icon: any; label: string; value: number; tone: string; danger?: boolean }) {
  return (
    <Card className={`card-3d border-none p-4 bg-gradient-to-br ${tone}`}>
      <div className="flex items-center gap-3">
        <div className={`grid h-11 w-11 place-items-center rounded-xl ${danger ? "bg-destructive/20 text-destructive" : "bg-primary/15 text-primary"}`}>
          <Icon className="h-5 w-5" />
        </div>
        <div>
          <div className="text-xs text-muted-foreground">{label}</div>
          <div className="text-2xl font-extrabold">{value}</div>
        </div>
      </div>
    </Card>
  );
}
