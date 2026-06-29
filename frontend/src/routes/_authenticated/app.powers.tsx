import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  ScrollText, AlertTriangle, RefreshCw, Loader2, Printer,
  CalendarClock, User, ShieldCheck, FileSignature, Trash2, Pencil, Network, Plus,
} from "lucide-react";
import { PageHeader } from "@/components/section-shell";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from "@/components/ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { useList, useUpsert, useDelete } from "@/lib/data-hooks";
import { useRealtimeTable } from "@/lib/realtime";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { exportRecordPdf, exportRecordsBundle } from "@/lib/pdf-export";
import { useExpiryWarnDays, EXPIRY_WARN_OPTIONS } from "@/lib/expiry-window";

export const Route = createFileRoute("/_authenticated/app/powers")({
  component: PowersPage,
});

type ClientRow = { id: string; full_name: string };
type CaseRow = { id: string; case_number: string; title: string; client_id?: string | null };
type PowerRow = {
  id: string;
  wakalah_number: string;
  issuer_name: string | null;
  agent_name: string | null;
  issuer_id_number: string | null;
  agent_id_number: string | null;
  issue_date: string | null;
  expiry_date: string | null;
  scope: string | null;
  client_id: string | null;
  najiz_id: string | null;
  najiz_synced_at: string | null;
  status: string;
  notes: string | null;
};

const daysLeft = (d?: string | null) => {
  if (!d) return null;
  const t = new Date(d).getTime();
  const now = new Date(); now.setHours(0, 0, 0, 0);
  return Math.ceil((t - now.getTime()) / 86_400_000);
};
const makeExpiryClass = (warnDays: number) =>
  (d?: string | null): { className: string; level: "ok" | "warn" | "danger" | "expired" } => {
    const dl = daysLeft(d);
    if (dl == null) return { className: "", level: "ok" };
    if (dl < 0) return { className: "expiry-pulse", level: "expired" };
    if (dl <= warnDays) return { className: "expiry-pulse", level: "danger" };
    return { className: "", level: "ok" };
  };

function PowersPage() {
  useRealtimeTable("powers_of_attorney", ["powers_of_attorney"]);
  const qc = useQueryClient();
  const { data: rows = [], isLoading } = useList<PowerRow>("powers_of_attorney");
  const { data: clients = [] } = useList<ClientRow>("clients");
  const { data: cases = [] } = useList<CaseRow>("cases");
  const upsert = useUpsert("powers_of_attorney");
  const del = useDelete("powers_of_attorney");
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<PowerRow | null>(null);
  const [warnDays, setWarnDays] = useExpiryWarnDays();
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [bundleBusy, setBundleBusy] = useState<"" | "combined" | "zip">("");
  const expiryClass = useMemo(() => makeExpiryClass(warnDays), [warnDays]);

  const expiringCount = useMemo(
    () => rows.filter((r) => {
      const dl = daysLeft(r.expiry_date);
      return dl != null && dl >= 0 && dl <= warnDays;
    }).length,
    [rows, warnDays]
  );

  const toggleSelect = (id: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  };
  const clearSelection = () => setSelected(new Set());
  const exportSelected = async (mode: "combined" | "zip") => {
    const items = rows.filter((r) => selected.has(r.id));
    if (items.length === 0) return;
    setBundleBusy(mode);
    try {
      await exportRecordsBundle({
        mode,
        bundleName: `wakalat-${new Date().toISOString().slice(0, 10)}`,
        records: items.map((row) => {
          const clientName = clients.find((c) => c.id === row.client_id)?.full_name;
          return {
            title: `وكالة قضائية رقم ${row.wakalah_number}`,
            subtitle: clientName ? `العميل: ${clientName}` : undefined,
            fileName: `wakalah-${row.wakalah_number}.pdf`,
            fields: [
              { label: "رقم الوكالة", value: row.wakalah_number },
              { label: "اسم الموكل", value: row.issuer_name },
              { label: "رقم هوية الموكل", value: row.issuer_id_number },
              { label: "اسم الوكيل", value: row.agent_name },
              { label: "رقم هوية الوكيل", value: row.agent_id_number },
              { label: "العميل المرتبط", value: clientName },
              { label: "تاريخ الإصدار", value: row.issue_date },
              { label: "تاريخ الانتهاء", value: row.expiry_date },
              { label: "الحالة", value: row.status },
              { label: "نطاق / موضوع الوكالة", value: row.scope },
              { label: "ملاحظات", value: row.notes },
            ],
          };
        }),
      });
      toast.success(`تم تصدير ${items.length} وكالة`);
      clearSelection();
    } catch (e: any) {
      toast.error(e?.message || "فشل التصدير");
    } finally {
      setBundleBusy("");
    }
  };

  const sync = useMutation({
    mutationFn: async () => {
      // Refresh from supabase (the extension writes directly via /api/public/najiz-sync).
      // Surface latest najiz sync log for context.
      const { data: logs } = await supabase
        .from("najiz_sync_logs")
        .select("created_at, items_count, source, status")
        .like("source", "extension:powers%")
        .order("created_at", { ascending: false })
        .limit(1);
      return logs?.[0] || null;
    },
    onSuccess: (log) => {
      qc.invalidateQueries({ queryKey: ["powers_of_attorney"] });
      if (log) {
        const when = new Date(log.created_at).toLocaleString("ar-SA-u-ca-gregory", { dateStyle: "medium", timeStyle: "short" });
        toast.success(`تمت المزامنة — آخر دفعة من ناجز: ${log.items_count ?? 0} عنصر · ${when}`);
      } else {
        toast.message("تم تحديث البيانات — في انتظار أول دفعة من أداة ناجز");
      }
    },
    onError: (e: any) => toast.error(e.message || "فشل المزامنة"),
  });

  return (
    <>
      <PageHeader
        icon={ScrollText}
        title="الوكالات القضائية"
        subtitle={`${rows.length} وكالة · ${expiringCount} توشك على الانتهاء`}
        action={
          <div className="flex flex-wrap items-center gap-2">
            <label className="flex items-center gap-1.5 text-xs text-white/70">
              نافذة التنبيه:
              <select
                value={warnDays}
                onChange={(e) => setWarnDays(Number(e.target.value))}
                className="h-8 rounded-md border bg-background px-2 text-xs"
                title="عدد الأيام قبل الانتهاء التي يظهر فيها التنبيه"
              >
                {EXPIRY_WARN_OPTIONS.map((n) => <option key={n} value={n}>{n} يوم</option>)}
              </select>
            </label>
            <Button onClick={() => sync.mutate()} disabled={sync.isPending} variant="outline" className="gap-2">
              {sync.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <RefreshCw className="h-4 w-4" />}
              مزامنة مع ناجز
            </Button>
            <Button onClick={() => { setEditing(null); setOpen(true); }} className="btn-gold gap-2">
              <Plus className="h-4 w-4" /> إضافة وكالة
            </Button>
          </div>
        }
      />

      {selected.size > 0 && (
        <div className="card-luxe mb-4 flex flex-wrap items-center justify-between gap-3 p-3">
          <div className="text-sm text-white/80">{selected.size} عنصر محدد</div>
          <div className="flex flex-wrap gap-2">
            <Button size="sm" variant="outline" onClick={() => exportSelected("combined")} disabled={!!bundleBusy}>
              {bundleBusy === "combined" ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Printer className="h-3.5 w-3.5" />}
              <span className="mx-1">تصدير PDF مجمّع</span>
            </Button>
            <Button size="sm" variant="outline" onClick={() => exportSelected("zip")} disabled={!!bundleBusy}>
              {bundleBusy === "zip" ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Printer className="h-3.5 w-3.5" />}
              <span className="mx-1">تصدير ZIP</span>
            </Button>
            <Button size="sm" variant="ghost" onClick={clearSelection}>إلغاء التحديد</Button>
          </div>
        </div>
      )}

      <PowerDialog
        open={open}
        onOpenChange={setOpen}
        editing={editing}
        clients={clients}
        cases={cases}
        loading={upsert.isPending}
        onSubmit={async (payload) => {
          await upsert.mutateAsync({ ...payload, id: editing?.id });
        }}
      />

      {isLoading ? (
        <p className="text-center text-muted-foreground py-10">جارٍ التحميل...</p>
      ) : rows.length === 0 ? (
        <div className="card-luxe p-12 text-center text-white/70">
          لا توجد وكالات حتى الآن — استخدم زر "إضافة وكالة" أو "مزامنة مع ناجز"
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-5">
          {rows.map((r) => (
            <PowerCard
              key={r.id}
              row={r}
              clientName={clients.find((c) => c.id === r.client_id)?.full_name}
              onEdit={() => { setEditing(r); setOpen(true); }}
              onDelete={() => { if (confirm(`حذف الوكالة ${r.wakalah_number}؟`)) del.mutate(r.id); }}
              onSync={() => sync.mutate()}
              syncing={sync.isPending}
              expiryClass={expiryClass}
              selected={selected.has(r.id)}
              onToggleSelect={() => toggleSelect(r.id)}
            />
          ))}
        </div>
      )}
    </>
  );
}

function PowerCard({
  row, clientName, onEdit, onDelete, onSync, syncing, expiryClass, selected, onToggleSelect,
}: {
  row: PowerRow; clientName?: string;
  onEdit: () => void; onDelete: () => void; onSync: () => void; syncing: boolean;
  expiryClass: (d?: string | null) => { className: string; level: "ok" | "warn" | "danger" | "expired" };
  selected: boolean; onToggleSelect: () => void;
}) {
  const { className, level } = expiryClass(row.expiry_date);
  const dl = daysLeft(row.expiry_date);
  const handlePrint = () =>
    exportRecordPdf({
      title: `وكالة قضائية رقم ${row.wakalah_number}`,
      subtitle: clientName ? `العميل: ${clientName}` : undefined,
      fields: [
        { label: "رقم الوكالة", value: row.wakalah_number },
        { label: "اسم الموكل", value: row.issuer_name },
        { label: "رقم هوية الموكل", value: row.issuer_id_number },
        { label: "اسم الوكيل", value: row.agent_name },
        { label: "رقم هوية الوكيل", value: row.agent_id_number },
        { label: "العميل المرتبط", value: clientName },
        { label: "تاريخ الإصدار", value: row.issue_date },
        { label: "تاريخ الانتهاء", value: row.expiry_date },
        { label: "الحالة", value: row.status },
        { label: "نطاق / موضوع الوكالة", value: row.scope },
        { label: "ملاحظات", value: row.notes },
        { label: "مصدر", value: row.najiz_id ? "ناجز" : "يدوي" },
        { label: "آخر مزامنة مع ناجز", value: row.najiz_synced_at },
      ],
      footer: "هذا المستند تم إنشاؤه آلياً للأرشفة والمراجعة.",
      fileName: `wakalah-${row.wakalah_number}.pdf`,
    }).catch((e) => toast.error(e?.message || "فشل التصدير"));

  return (
    <div className={`card-luxe aspect-square flex flex-col p-5 relative ${className} ${selected ? "ring-2 ring-gold/70" : ""}`}>
      <label className="absolute top-2 right-2 z-20 flex items-center gap-1 rounded-md bg-black/30 px-2 py-1 text-[10px] text-white/80 cursor-pointer">
        <input type="checkbox" checked={selected} onChange={onToggleSelect} className="accent-gold" />
        تحديد
      </label>
      <div className="flex items-start justify-between gap-2 relative z-10">
        <div className="grid h-11 w-11 place-items-center rounded-xl bg-gradient-to-br from-gold to-gold/60 text-primary shadow-md shrink-0">
          <FileSignature className="h-5 w-5" />
        </div>
        <div className="flex flex-col items-end gap-1.5">
          {row.najiz_id ? (
            <span className="inline-flex items-center gap-1 rounded-md border border-emerald-400/40 bg-emerald-400/10 px-2 py-0.5 text-[10px] font-bold text-emerald-300">
              <Network className="h-3 w-3" /> ناجز
            </span>
          ) : (
            <span className="inline-flex items-center gap-1 rounded-md border border-white/15 bg-white/5 px-2 py-0.5 text-[10px] font-bold text-white/70">
              يدوي
            </span>
          )}
          {dl != null && (level === "danger" || level === "expired" || level === "warn") && (
            <span
              data-testid="poa-expiry-badge"
              className={`inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-[11px] font-extrabold shadow-md border-2 border-red-600 bg-red-600 text-white ${level === "warn" ? "" : "animate-pulse"}`}
            >
              <AlertTriangle className="h-3.5 w-3.5" />
              {level === "expired" ? `منتهية منذ ${Math.abs(dl)} يوم` : `تنتهي خلال ${dl} يوم`}
            </span>
          )}
        </div>
      </div>

      {/* body */}
      <div className="mt-3 flex-1 min-h-0 relative z-10">
        <div className="text-[10px] uppercase tracking-[0.25em] text-gold/80">رقم الوكالة</div>
        <div className="mt-0.5 text-base font-extrabold text-white truncate" title={row.wakalah_number}>
          {row.wakalah_number}
        </div>

        <dl className="mt-3 space-y-1.5 text-[12px] text-white/80">
          <Row icon={User} label="الموكل" value={row.issuer_name} />
          <Row icon={User} label="هوية الموكل" value={row.issuer_id_number} />
          <Row icon={ShieldCheck} label="الوكيل" value={row.agent_name} />
          <Row icon={ShieldCheck} label="هوية الوكيل" value={row.agent_id_number} />
          {clientName && <Row icon={User} label="العميل" value={clientName} />}
          <Row icon={CalendarClock} label="الإصدار" value={row.issue_date} />
          <Row
            icon={CalendarClock}
            label="الانتهاء"
            value={row.expiry_date}
            highlight={level !== "ok"}
          />
          {row.scope && (
            <div className="text-[11px] text-white/65 line-clamp-2 pt-1 border-t border-white/10 mt-2">
              {row.scope}
            </div>
          )}
        </dl>
      </div>

      {/* footer */}
      <div className="mt-3 grid grid-cols-4 gap-1.5 relative z-10">
        <button
          onClick={onSync}
          disabled={syncing}
          title="مزامنة مع ناجز"
          className="h-8 rounded-lg border border-emerald-400/30 bg-emerald-400/10 text-emerald-200 hover:bg-emerald-400/20 transition grid place-items-center"
        >
          {syncing ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <RefreshCw className="h-3.5 w-3.5" />}
        </button>
        <button
          onClick={handlePrint}
          title="طباعة PDF"
          className="h-8 rounded-lg border border-gold/40 bg-gold/10 text-gold hover:bg-gold/20 transition grid place-items-center"
        >
          <Printer className="h-3.5 w-3.5" />
        </button>
        <button
          onClick={onEdit}
          title="تعديل"
          className="h-8 rounded-lg border border-white/15 bg-white/5 text-white/80 hover:bg-white/10 transition grid place-items-center"
        >
          <Pencil className="h-3.5 w-3.5" />
        </button>
        <button
          onClick={onDelete}
          title="حذف"
          className="h-8 rounded-lg border border-rose-400/30 bg-rose-400/10 text-rose-300 hover:bg-rose-400/20 transition grid place-items-center"
        >
          <Trash2 className="h-3.5 w-3.5" />
        </button>
      </div>
    </div>
  );
}

function Row({ icon: Icon, label, value, highlight }: { icon: any; label: string; value: any; highlight?: boolean }) {
  return (
    <div className="flex items-center gap-1.5 truncate">
      <Icon className="h-3 w-3 text-gold/70 shrink-0" />
      <span className="text-white/55 shrink-0">{label}:</span>
      <span className={`truncate ${highlight ? "text-rose-300 font-bold" : "text-white/90"}`}>{value || "—"}</span>
    </div>
  );
}

function PowerDialog({
  open, onOpenChange, editing, clients, cases, loading, onSubmit,
}: {
  open: boolean; onOpenChange: (v: boolean) => void;
  editing: PowerRow | null; clients: ClientRow[]; cases: CaseRow[];
  loading: boolean;
  onSubmit: (payload: Record<string, any>) => Promise<void>;
}) {
  const [mode, setMode] = useState<"existing" | "new">("existing");
  const [clientId, setClientId] = useState("");
  const [caseId, setCaseId] = useState("");
  const [newClientName, setNewClientName] = useState("");
  const [newClientPhone, setNewClientPhone] = useState("");
  const [v, setV] = useState<Record<string, any>>({});

  useEffect(() => {
    if (!open) return;
    setV({
      wakalah_number: editing?.wakalah_number ?? "",
      issuer_name: editing?.issuer_name ?? "",
      agent_name: editing?.agent_name ?? "",
      issuer_id_number: editing?.issuer_id_number ?? "",
      agent_id_number: editing?.agent_id_number ?? "",
      issue_date: editing?.issue_date ?? "",
      expiry_date: editing?.expiry_date ?? "",
      scope: editing?.scope ?? "",
      notes: editing?.notes ?? "",
    });
    setClientId(editing?.client_id ?? "");
    setCaseId("");
    setNewClientName("");
    setNewClientPhone("");
    setMode("existing");
  }, [open, editing]);


  const filteredCases = useMemo(
    () => cases.filter((c) => !clientId || c.client_id === clientId),
    [cases, clientId]
  );

  const handle = async (e: React.FormEvent) => {
    e.preventDefault();
    let finalClientId = clientId || null;
    if (mode === "new" && newClientName.trim()) {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) { toast.error("غير مسجل دخول"); return; }
      const { data, error } = await supabase
        .from("clients")
        .insert({ full_name: newClientName.trim(), phone: newClientPhone.trim() || null, owner_id: user.id } as never)
        .select("id").single();
      if (error) { toast.error(error.message); return; }
      finalClientId = (data as any).id;
    }
    const payload: Record<string, any> = {
      wakalah_number: v.wakalah_number,
      issuer_name: v.issuer_name || null,
      agent_name: v.agent_name || null,
      issuer_id_number: v.issuer_id_number || null,
      agent_id_number: v.agent_id_number || null,
      issue_date: v.issue_date || null,
      expiry_date: v.expiry_date || null,
      scope: v.scope || null,
      notes: v.notes || null,
      client_id: finalClientId,
    };
    if (caseId) payload.notes = `${payload.notes ?? ""}\nقضية مرتبطة: ${caseId}`.trim();
    await onSubmit(payload);
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto" dir="rtl">
        <DialogHeader>
          <DialogTitle className="text-right text-xl">{editing ? "تعديل وكالة" : "وكالة قضائية جديدة"}</DialogTitle>
          <DialogDescription className="text-right text-xs">اربط الوكالة بعميل مسجّل أو سجّل عميلاً جديداً.</DialogDescription>
        </DialogHeader>

        <form onSubmit={handle} className="grid grid-cols-1 md:grid-cols-2 gap-4 mt-2">
          {/* Client mode toggle */}
          <div className="md:col-span-2 flex flex-wrap items-center gap-2">
            <Label className="text-xs font-semibold ml-1">العميل:</Label>
            <div className="inline-flex rounded-lg border bg-muted/40 p-1">
              <button type="button" onClick={() => setMode("existing")} className={`px-3 py-1 text-xs rounded ${mode === "existing" ? "bg-primary text-primary-foreground" : ""}`}>عميل مسجّل</button>
              <button type="button" onClick={() => setMode("new")} className={`px-3 py-1 text-xs rounded ${mode === "new" ? "bg-primary text-primary-foreground" : ""}`}>عميل جديد</button>
            </div>
          </div>

          {mode === "existing" ? (
            <>
              <div>
                <Label className="text-xs font-semibold mb-1.5 block">اختر العميل</Label>
                <Select value={clientId} onValueChange={(v) => { setClientId(v); setCaseId(""); }}>
                  <SelectTrigger className="h-10"><SelectValue placeholder="— اختر —" /></SelectTrigger>
                  <SelectContent>
                    {clients.map((c) => <SelectItem key={c.id} value={c.id}>{c.full_name}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <div>
                <Label className="text-xs font-semibold mb-1.5 block">القضية المرتبطة (اختياري)</Label>
                <Select value={caseId} onValueChange={setCaseId}>
                  <SelectTrigger className="h-10"><SelectValue placeholder="— اختر —" /></SelectTrigger>
                  <SelectContent>
                    {filteredCases.length === 0 && <SelectItem disabled value="__none__">لا توجد قضايا</SelectItem>}
                    {filteredCases.map((c) => <SelectItem key={c.id} value={c.id}>#{c.case_number} — {c.title}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            </>
          ) : (
            <>
              <div>
                <Label className="text-xs font-semibold mb-1.5 block">اسم العميل الجديد</Label>
                <Input value={newClientName} onChange={(e) => setNewClientName(e.target.value)} required className="text-right" />
              </div>
              <div>
                <Label className="text-xs font-semibold mb-1.5 block">جوال العميل</Label>
                <Input value={newClientPhone} onChange={(e) => setNewClientPhone(e.target.value)} className="text-right" />
              </div>
            </>
          )}

          <FieldInput v={v} setV={setV} name="wakalah_number" label="رقم الوكالة" required />
          <FieldInput v={v} setV={setV} name="issuer_name" label="اسم الموكل" />
          <FieldInput v={v} setV={setV} name="agent_name" label="اسم الوكيل" />
          <FieldInput v={v} setV={setV} name="issuer_id_number" label="رقم هوية الموكل" />
          <FieldInput v={v} setV={setV} name="agent_id_number" label="رقم هوية الوكيل" />
          <FieldInput v={v} setV={setV} name="issue_date" label="تاريخ الإصدار" type="date" />
          <FieldInput v={v} setV={setV} name="expiry_date" label="تاريخ الانتهاء" type="date" />

          <div className="md:col-span-2">
            <Label className="text-xs font-semibold mb-1.5 block">نطاق / موضوع الوكالة</Label>
            <Textarea value={v.scope ?? ""} onChange={(e) => setV({ ...v, scope: e.target.value })} className="text-right min-h-[70px]" />
          </div>
          <div className="md:col-span-2">
            <Label className="text-xs font-semibold mb-1.5 block">ملاحظات</Label>
            <Textarea value={v.notes ?? ""} onChange={(e) => setV({ ...v, notes: e.target.value })} className="text-right min-h-[60px]" />
          </div>

          <DialogFooter className="md:col-span-2 gap-2 mt-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>إلغاء</Button>
            <Button type="submit" className="btn-gold" disabled={loading}>
              {loading ? <Loader2 className="h-4 w-4 animate-spin ml-2" /> : null}
              حفظ
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function FieldInput({ v, setV, name, label, type = "text", required }: {
  v: Record<string, any>; setV: (x: Record<string, any>) => void;
  name: string; label: string; type?: string; required?: boolean;
}) {
  return (
    <div>
      <Label className="text-xs font-semibold mb-1.5 block">
        {label} {required && <span className="text-destructive">*</span>}
      </Label>
      <Input type={type} value={v[name] ?? ""} onChange={(e) => setV({ ...v, [name]: e.target.value })} required={required} className="text-right" />
    </div>
  );
}
