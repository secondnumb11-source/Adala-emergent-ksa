import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { Briefcase, LayoutGrid, List, FileText, Calendar, Gavel, AlertTriangle } from "lucide-react";
import { PageHeader } from "@/components/section-shell";
import { CrudDialog, AddButton, type Field } from "@/components/crud-dialog";
import { DataTable } from "@/components/data-table";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { useList, useUpsert, useDelete } from "@/lib/data-hooks";

export const Route = createFileRoute("/_authenticated/app/cases")({
  component: CasesPage,
});

const STATUS_LABEL: Record<string, string> = {
  open: "مفتوحة", in_study: "قيد الدراسة", closed_final: "حكم قطعي", closed_non_final: "حكم غير قطعي", appealed: "استئناف",
};

function useCaseFields(clients: any[]): Field[] {
  return [
    { name: "title", label: "عنوان القضية", required: true, full: true },
    { name: "case_number", label: "رقم القضية", required: true },
    { name: "case_type", label: "نوع القضية", type: "select", required: true, options: [
      { value: "civil", label: "مدنية" }, { value: "commercial", label: "تجارية" },
      { value: "labor", label: "عمالية" }, { value: "criminal", label: "جزائية" },
      { value: "personal_status", label: "أحوال شخصية" }, { value: "administrative", label: "إدارية" },
      { value: "execution", label: "تنفيذ" }, { value: "other", label: "أخرى" },
    ]},
    { name: "status", label: "الحالة", type: "select", options: Object.entries(STATUS_LABEL).map(([v, l]) => ({ value: v, label: l })) },
    { name: "court", label: "المحكمة" },
    { name: "circuit_number", label: "رقم الدائرة" },
    { name: "opened_at", label: "تاريخ القيد", type: "date" },
    { name: "client_id", label: "العميل", type: "select", options: clients.map((c) => ({ value: c.id, label: c.full_name })) },
    { name: "description", label: "وصف القضية", type: "textarea", full: true },
  ];
}

function CasesPage() {
  const { data: cases = [], isLoading } = useList<any>("cases");
  const { data: clients = [] } = useList<any>("clients");
  const { data: sessions = [] } = useList<any>("sessions");
  const { data: docs = [] } = useList<any>("documents");
  const upsert = useUpsert("cases");
  const del = useDelete("cases");
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<any | null>(null);
  const [view, setView] = useState<"grid" | "list">("grid");

  const fields = useCaseFields(clients);
  const startAdd = () => { setEditing(null); setOpen(true); };
  const startEdit = (row: any) => { setEditing(row); setOpen(true); };

  // counts per case
  const countFor = (caseId: string, type: "session" | "memo" | "judgment") => {
    if (type === "session") return sessions.filter((s) => s.case_id === caseId).length;
    if (type === "memo") return docs.filter((d) => d.case_id === caseId && d.doc_type === "memorandum").length;
    return docs.filter((d) => d.case_id === caseId && (d.doc_type === "judgment_final" || d.doc_type === "judgment_non_final")).length;
  };

  const isAppealDue = (c: any) => c.appeal_deadline && new Date(c.appeal_deadline) > new Date()
    && (new Date(c.appeal_deadline).getTime() - Date.now()) < 1000 * 60 * 60 * 24 * 30;

  return (
    <>
      <PageHeader icon={Briefcase} title="إدارة القضايا" subtitle={`${cases.length} قضية`}
        action={
          <div className="flex gap-2">
            <div className="flex rounded-lg border bg-card p-1">
              <Button size="sm" variant={view === "grid" ? "default" : "ghost"} onClick={() => setView("grid")} className="h-8 px-3 gap-1">
                <LayoutGrid className="h-4 w-4" /> مربعات
              </Button>
              <Button size="sm" variant={view === "list" ? "default" : "ghost"} onClick={() => setView("list")} className="h-8 px-3 gap-1">
                <List className="h-4 w-4" /> قائمة
              </Button>
            </div>
            <AddButton label="إضافة قضية" onClick={startAdd} />
          </div>
        }
      />

      <CrudDialog open={open} onOpenChange={setOpen} title={editing ? "تعديل قضية" : "قضية جديدة"}
        fields={fields} initial={editing ?? { status: "open", case_type: "civil" }}
        loading={upsert.isPending}
        onSubmit={async (v) => { await upsert.mutateAsync({ ...v, id: editing?.id }); }} />

      {isLoading ? <p className="text-center text-muted-foreground py-10">جارٍ التحميل...</p> : view === "list" ? (
        <DataTable rows={cases} columns={[
          { key: "case_number", header: "رقم القضية" },
          { key: "title", header: "العنوان" },
          { key: "court", header: "المحكمة" },
          { key: "status", header: "الحالة", render: (r) => <Badge variant="outline">{STATUS_LABEL[r.status] || r.status}</Badge> },
          { key: "sessions", header: "جلسات", render: (r) => countFor(r.id, "session") },
          { key: "memos", header: "مذكرات", render: (r) => countFor(r.id, "memo") },
          { key: "judgments", header: "أحكام", render: (r) => countFor(r.id, "judgment") },
        ]} onEdit={startEdit} onDelete={(r) => del.mutate(r.id)} />
      ) : (
        cases.length === 0 ? (
          <Card className="card-luxe border-none p-10 text-center">
            <p className="text-sm">لا توجد قضايا — ابدأ بإضافة قضية جديدة</p>
          </Card>
        ) : (
          <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
            {cases.map((c) => (
              <Card key={c.id} className="card-luxe border-none p-6 cursor-pointer" onClick={() => startEdit(c)}>
                <div className="flex justify-between items-start mb-3">
                  <Badge variant="outline" className="bg-gold/15 text-gold-foreground border-gold/40 font-bold">{STATUS_LABEL[c.status] || c.status}</Badge>
                  {isAppealDue(c) && <Badge variant="destructive" className="gap-1"><AlertTriangle className="h-3 w-3" />مهلة استئناف</Badge>}
                </div>
                <div className="text-xs font-bold text-[#8a6a1a] mb-1">#{c.case_number}</div>
                <h3 className="font-extrabold text-lg mb-2 leading-snug text-[#1f1810]">{c.title}</h3>
                <p className="text-sm font-medium text-[#4a3d28] mb-5">{c.court || "—"}</p>
                <div className="grid grid-cols-3 gap-3 pt-4 border-t-2 border-gold/20">
                  <Stat icon={Calendar} label="جلسات" value={countFor(c.id, "session")} />
                  <Stat icon={FileText} label="مذكرات" value={countFor(c.id, "memo")} />
                  <Stat icon={Gavel} label="أحكام" value={countFor(c.id, "judgment")} />
                </div>
              </Card>
            ))}
          </div>

        )
      )}
    </>
  );
}

function Stat({ icon: Icon, label, value }: any) {
  return (
    <div className="text-center">
      <Icon className="h-3.5 w-3.5 mx-auto text-gold mb-1" />
      <div className="text-base font-bold">{value}</div>
      <div className="text-[10px] text-muted-foreground">{label}</div>
    </div>
  );
}
