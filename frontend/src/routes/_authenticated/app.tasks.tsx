import { createFileRoute } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { ListChecks, AlertTriangle, CheckCircle2, Clock, ArrowRightLeft } from "lucide-react";
import { PageHeader } from "@/components/section-shell";
import { CrudDialog, AddButton, type Field } from "@/components/crud-dialog";
import { DataTable } from "@/components/data-table";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useList, useUpsert, useDelete } from "@/lib/data-hooks";
import { useRealtimeTable } from "@/lib/realtime";
import { ContactEmployeeButton } from "@/components/contact-employee-button";

export const Route = createFileRoute("/_authenticated/app/tasks")({
  component: TasksPage,
});

const STATUS_LABEL: Record<string, string> = {
  todo: "قيد الإسناد",
  in_progress: "جارٍ التنفيذ",
  done: "مكتمل",
  overdue: "متأخر",
};

const PRIORITY_LABEL: Record<string, string> = {
  low: "منخفض",
  medium: "متوسط",
  high: "مرتفع",
  urgent: "عاجل",
};

const PRIORITY_TONE: Record<string, string> = {
  low: "bg-muted text-foreground/70",
  medium: "bg-sky-500/15 text-sky-600 dark:text-sky-300",
  high: "bg-amber-500/15 text-amber-600 dark:text-amber-300",
  urgent: "bg-destructive/15 text-destructive",
};

function isOverdue(t: any) {
  if (!t.due_date || t.status === "done") return false;
  const due = new Date(t.due_date + "T23:59:59");
  return due.getTime() < Date.now();
}

function TasksPage() {
  // Realtime so any insert/update/delete is reflected in the employee portal instantly.
  useRealtimeTable("tasks", ["tasks"]);

  const { data: tasks = [], isLoading } = useList<any>("tasks", "due_date", true);
  const { data: employees = [] } = useList<any>("employees");
  const { data: cases = [] } = useList<any>("cases");
  const upsert = useUpsert("tasks");
  const del = useDelete("tasks");

  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<any | null>(null);
  const [search, setSearch] = useState("");
  const [filterStatus, setFilterStatus] = useState<string>("");
  const [filterEmployee, setFilterEmployee] = useState<string>("");

  const fields: Field[] = [
    { name: "title", label: "عنوان المهمة", required: true, full: true },
    { name: "description", label: "وصف المهمة", type: "textarea", full: true },
    {
      name: "employee_id", label: "الموظف المُسند إليه", type: "select",
      options: employees.map((e) => ({ value: e.id, label: e.full_name })),
    },
    {
      name: "case_id", label: "القضية المرتبطة", type: "select",
      options: cases.map((c) => ({ value: c.id, label: `#${c.case_number} — ${c.title}` })),
    },
    { name: "due_date", label: "تاريخ الاستحقاق", type: "date" },
    {
      name: "priority", label: "الأولوية", type: "select",
      options: Object.entries(PRIORITY_LABEL).map(([v, l]) => ({ value: v, label: l })),
    },
    {
      name: "status", label: "الحالة", type: "select",
      options: Object.entries(STATUS_LABEL).map(([v, l]) => ({ value: v, label: l })),
    },
  ];

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return tasks.filter((t) => {
      if (filterStatus && (filterStatus === "overdue" ? !isOverdue(t) : t.status !== filterStatus)) return false;
      if (filterEmployee && t.employee_id !== filterEmployee) return false;
      if (q && !`${t.title} ${t.description ?? ""}`.toLowerCase().includes(q)) return false;
      return true;
    });
  }, [tasks, search, filterStatus, filterEmployee]);

  const stats = useMemo(() => ({
    total: tasks.length,
    inProgress: tasks.filter((t) => t.status === "in_progress").length,
    done: tasks.filter((t) => t.status === "done").length,
    overdue: tasks.filter(isOverdue).length,
  }), [tasks]);

  const empName = (id?: string) => employees.find((e) => e.id === id)?.full_name ?? "—";
  const empUserId = (id?: string): string | null => employees.find((e) => e.id === id)?.user_id ?? null;
  const caseLabel = (id?: string) => {
    const c = cases.find((x) => x.id === id);
    return c ? `#${c.case_number}` : "—";
  };

  // Quick status change to demonstrate realtime → portal mirroring.
  const cycleStatus = async (t: any) => {
    const order = ["todo", "in_progress", "done"];
    const idx = order.indexOf(t.status);
    const next = order[(idx + 1) % order.length];
    await upsert.mutateAsync({
      id: t.id,
      status: next,
      completed_at: next === "done" ? new Date().toISOString() : null,
    });
  };

  return (
    <>
      <PageHeader
        icon={ListChecks}
        title="المهام وتوزيع الأعمال"
        subtitle="إسناد المهام للموظفين — أي تغيير يظهر فوراً في بوابة الموظف (Realtime)"
        action={<AddButton label="إضافة مهمة" onClick={() => { setEditing(null); setOpen(true); }} />}
      />

      {/* Stats cards */}
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4 mb-6">
        <StatCard icon={ListChecks} label="الإجمالي" value={stats.total} tone="from-primary/15 to-primary/5" />
        <StatCard icon={Clock} label="جارٍ التنفيذ" value={stats.inProgress} tone="from-sky-500/15 to-sky-500/5" />
        <StatCard icon={CheckCircle2} label="مكتمل" value={stats.done} tone="from-emerald-500/15 to-emerald-500/5" />
        <StatCard icon={AlertTriangle} label="متأخر" value={stats.overdue} tone="from-destructive/15 to-destructive/5" danger />
      </div>

      {/* Filters */}
      <Card className="card-3d border-none p-4 mb-4">
        <div className="grid gap-2 md:grid-cols-4">
          <Input
            placeholder="بحث في العنوان أو الوصف..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="text-right"
          />
          <select
            value={filterStatus}
            onChange={(e) => setFilterStatus(e.target.value)}
            className="h-10 rounded-lg border bg-background px-3 text-sm text-right"
          >
            <option value="">كل الحالات</option>
            {Object.entries(STATUS_LABEL).map(([v, l]) => <option key={v} value={v}>{l}</option>)}
            <option value="overdue">⏰ متأخرة فقط</option>
          </select>
          <select
            value={filterEmployee}
            onChange={(e) => setFilterEmployee(e.target.value)}
            className="h-10 rounded-lg border bg-background px-3 text-sm text-right"
          >
            <option value="">كل الموظفين</option>
            {employees.map((e) => <option key={e.id} value={e.id}>{e.full_name}</option>)}
          </select>
          <Button variant="outline" onClick={() => { setSearch(""); setFilterStatus(""); setFilterEmployee(""); }}>
            مسح الفلاتر
          </Button>
        </div>
      </Card>

      <CrudDialog
        open={open}
        onOpenChange={setOpen}
        title={editing ? "تعديل مهمة" : "مهمة جديدة"}
        fields={fields}
        initial={editing ?? { status: "todo", priority: "medium" }}
        loading={upsert.isPending}
        onSubmit={async (v) => { await upsert.mutateAsync({ ...v, id: editing?.id }); }}
      />

      {isLoading ? (
        <p className="text-center text-muted-foreground py-10">جارٍ التحميل...</p>
      ) : (
        <DataTable
          rows={filtered}
          emptyTitle={tasks.length === 0 ? "لا توجد مهام بعد" : "لا توجد نتائج مطابقة للفلاتر"}
          columns={[
            { key: "title", header: "المهمة", render: (r) => (
              <div>
                <div className="font-bold">{r.title}</div>
                {r.description && <div className="text-xs text-muted-foreground line-clamp-1">{r.description}</div>}
              </div>
            )},
            { key: "employee", header: "الموظف", render: (r) => (
              <div className="flex items-center gap-2">
                <span className="text-sm">{empName(r.employee_id)}</span>
                {r.employee_id && (
                  <ContactEmployeeButton userId={empUserId(r.employee_id)} iconOnly size="icon"
                    className="h-7 w-7 border-gold/30 bg-gold/10 text-gold hover:bg-gold/20" />
                )}
              </div>
            )},
            { key: "case", header: "القضية", render: (r) => caseLabel(r.case_id) },
            { key: "due_date", header: "الاستحقاق", render: (r) => r.due_date || "—" },
            { key: "priority", header: "الأولوية", render: (r) => (
              <Badge className={`${PRIORITY_TONE[r.priority] || ""} border-0`}>{PRIORITY_LABEL[r.priority] || r.priority}</Badge>
            )},
            { key: "status", header: "الحالة", render: (r) => {
              const over = isOverdue(r);
              return (
                <button
                  onClick={() => cycleStatus(r)}
                  className="inline-flex items-center gap-1 text-xs"
                  title="اضغط لتدوير الحالة"
                >
                  <Badge variant={over ? "destructive" : r.status === "done" ? "default" : "outline"}>
                    {over ? "متأخر" : STATUS_LABEL[r.status] || r.status}
                  </Badge>
                  <ArrowRightLeft className="h-3 w-3 text-muted-foreground" />
                </button>
              );
            }},
          ]}
          onEdit={(r) => { setEditing(r); setOpen(true); }}
          onDelete={(r) => del.mutate(r.id)}
        />
      )}
    </>
  );
}

function StatCard({
  icon: Icon, label, value, tone, danger,
}: { icon: any; label: string; value: number; tone: string; danger?: boolean }) {
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
