import { createFileRoute, Link } from "@tanstack/react-router";
import {
  FolderArchive, Upload, Download, Trash2, FileText, FileImage,
  File as FileIcon, Loader2, Search, Eye, Sparkles, Calendar, Building2,
  Users, Briefcase, ArrowLeft,
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { PageHeader } from "@/components/section-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { useList } from "@/lib/data-hooks";
import { ensureCaseDocumentsBucket } from "@/lib/storage-setup.functions";
import { logAudit } from "@/lib/audit.functions";
import { useServerFn } from "@tanstack/react-start";
import { useQueryClient } from "@tanstack/react-query";
import JSZip from "jszip";


export const Route = createFileRoute("/_authenticated/app/archive")({
  component: ArchiveSection,
});

const BUCKET = "case-documents";

const DOC_TYPES: Array<{ id: DocType; label: string; needsJudgmentMeta?: boolean }> = [
  { id: "lawsuit", label: "صحيفة دعوى" },
  { id: "judgment_final", label: "حكم قطعي", needsJudgmentMeta: true },
  { id: "judgment_non_final", label: "حكم غير قطعي (يبدأ احتساب مهلة الاستئناف ٣٠ يوماً)", needsJudgmentMeta: true },
  { id: "appeal_judgment", label: "حكم استئناف", needsJudgmentMeta: true },
  { id: "memorandum_reply", label: "مذكرة جوابية" },
  { id: "session_minutes", label: "محضر ضبط الجلسة" },
  { id: "evidence", label: "مستند إثبات" },
  { id: "other", label: "أخرى" },
];

type DocType =
  | "lawsuit" | "judgment_final" | "judgment_non_final" | "appeal_judgment"
  | "memorandum_reply" | "session_minutes" | "power_of_attorney" | "evidence" | "other";

type Client = { id: string; full_name: string };
type Case = { id: string; client_id: string | null; case_number: string; title: string; court?: string | null };
type DocRow = {
  id: string; case_id: string | null; doc_type: DocType; title: string;
  description: string | null; storage_path: string | null; file_name: string | null;
  file_size: number | null; mime_type: string | null;
  filed_date: string | null; judgment_date: string | null;
  court: string | null; circuit_number: string | null; appeal_deadline: string | null;
  created_at: string;
};

function fmtSize(n: number | null) {
  if (!n) return "—";
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(2)} MB`;
}

function iconFor(mime: string | null) {
  if (!mime) return FileIcon;
  if (mime.startsWith("image/")) return FileImage;
  return FileText;
}

function ArchiveSection() {
  const ensureBucket = useServerFn(ensureCaseDocumentsBucket);
  const audit = useServerFn(logAudit);
  const [bucketReady, setBucketReady] = useState(false);
  useEffect(() => {
    ensureBucket({ data: undefined as any })
      .then(() => setBucketReady(true))
      .catch((e: any) => toast.error(`تعذّر تهيئة مخزن المستندات: ${e?.message ?? e}`));
  }, [ensureBucket]);

  const clients = useList<Client>("clients");
  const cases = useList<Case>("cases");
  const [selectedClientId, setSelectedClientId] = useState<string>("");
  const [selectedCaseId, setSelectedCaseId] = useState<string>("");
  const [q, setQ] = useState("");
  const [docs, setDocs] = useState<DocRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [uploadOpen, setUploadOpen] = useState(false);
  const [editDoc, setEditDoc] = useState<DocRow | null>(null);
  const [previewDoc, setPreviewDoc] = useState<{ url: string; mime: string; name: string } | null>(null);
  const [bulkBusy, setBulkBusy] = useState(false);
  const [zipBusy, setZipBusy] = useState(false);
  const qc = useQueryClient();


  const clientCases = useMemo(
    () => (cases.data ?? []).filter((c) => !selectedClientId || selectedClientId === "__all__" || c.client_id === selectedClientId),
    [cases.data, selectedClientId],
  );

  const loadDocs = async () => {
    setLoading(true);
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) { setLoading(false); setDocs([]); return; }
    let query = supabase
      .from("documents").select("*").eq("owner_id", user.id)
      .order("created_at", { ascending: false });
    if (selectedCaseId && selectedCaseId !== "__all__") {
      query = query.eq("case_id", selectedCaseId);
    } else if (selectedClientId && selectedClientId !== "__all__") {
      const caseIds = clientCases.map((c) => c.id);
      if (caseIds.length === 0) { setDocs([]); setLoading(false); return; }
      query = query.in("case_id", caseIds);
    }
    const { data, error } = await query;
    setLoading(false);
    if (error) { toast.error(error.message); return; }
    setDocs((data ?? []) as DocRow[]);
  };
  useEffect(() => { loadDocs(); /* eslint-disable-next-line */ }, [selectedCaseId, selectedClientId, cases.data?.length]);


  const handlePreview = async (d: DocRow) => {
    if (!d.storage_path) return toast.error("لا يوجد ملف مرفق");
    const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(d.storage_path, 600);
    if (error || !data) return toast.error(error?.message ?? "تعذر إنشاء رابط المعاينة");
    setPreviewDoc({ url: data.signedUrl, mime: d.mime_type ?? "", name: d.file_name ?? d.title });
  };
  const handleDownload = async (d: DocRow) => {
    if (!d.storage_path) return;
    const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(d.storage_path, 600, {
      download: d.file_name ?? true,
    });
    if (error || !data) return toast.error(error?.message ?? "تعذر التحميل");
    window.open(data.signedUrl, "_blank");
  };
  const handleDelete = async (d: DocRow) => {
    if (!confirm(`حذف المستند "${d.title}"؟`)) return;
    if (d.storage_path) await supabase.storage.from(BUCKET).remove([d.storage_path]);
    const { error } = await supabase.from("documents").delete().eq("id", d.id);
    if (error) return toast.error(error.message);
    toast.success("تم الحذف");
    audit({ data: { action: "document.delete", entity_type: "document", entity_id: d.id, metadata: { title: d.title, case_id: d.case_id } } }).catch(() => {});
    await loadDocs();
    qc.invalidateQueries({ queryKey: ["documents"] });
  };

  const handleBulkUpload = async (files: FileList | null) => {
    if (!files || files.length === 0) return;
    if (!selectedCaseId || selectedCaseId === "__all__") return toast.error("اختر قضية محدّدة قبل الرفع");
    setBulkBusy(true);
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) { setBulkBusy(false); return toast.error("غير مسجل دخول"); }
    let ok = 0, fail = 0;
    for (const file of Array.from(files)) {
      try {
        const safe = `${Date.now()}-${file.name.replace(/[^\w.\-]+/g, "_")}`;
        const path = `${user.id}/${selectedCaseId}/${safe}`;
        const { error: upErr } = await supabase.storage.from(BUCKET).upload(path, file, { upsert: false, contentType: file.type });
        if (upErr) throw upErr;
        const { data: ins, error: insErr } = await supabase.from("documents").insert({
          owner_id: user.id, case_id: selectedCaseId, doc_type: "other" as DocType,
          title: file.name, storage_path: path, file_name: file.name, file_size: file.size, mime_type: file.type,
          filed_date: new Date().toISOString().slice(0, 10),
        }).select("id").single();
        if (insErr) throw insErr;
        ok++;
        audit({ data: { action: "document.bulk_upload", entity_type: "document", entity_id: ins?.id, metadata: { title: file.name, case_id: selectedCaseId, size: file.size } } }).catch(() => {});
      } catch (e: any) {
        fail++;
        console.error("bulk upload failed", file.name, e);
      }
    }
    setBulkBusy(false);
    toast[fail === 0 ? "success" : "warning"](`رفع الدفعة: ${ok} ناجح${fail ? ` و ${fail} فاشل` : ""}`);
    await loadDocs();
    qc.invalidateQueries({ queryKey: ["documents"] });
  };

  const handleDownloadZip = async () => {
    if (filtered.length === 0) return toast.info("لا توجد مستندات لتحميلها");
    setZipBusy(true);
    try {
      const zip = new JSZip();
      let added = 0;
      for (const d of filtered) {
        if (!d.storage_path) continue;
        const { data, error } = await supabase.storage.from(BUCKET).download(d.storage_path);
        if (error || !data) continue;
        zip.file(d.file_name ?? `${d.title}-${d.id}`, data);
        added++;
      }
      if (added === 0) { toast.error("لم يتم العثور على ملفات قابلة للتحميل"); return; }
      const blob = await zip.generateAsync({ type: "blob" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `archive-${new Date().toISOString().slice(0, 10)}.zip`;
      a.click();
      URL.revokeObjectURL(url);
      toast.success(`تم تنزيل ${added} ملف`);
      audit({ data: { action: "document.zip_export", entity_type: "document", metadata: { count: added, case_id: selectedCaseId || null, client_id: selectedClientId || null } } }).catch(() => {});
    } catch (e: any) {
      toast.error(`تعذّر إنشاء الأرشيف: ${e?.message ?? e}`);
    } finally {
      setZipBusy(false);
    }
  };


  const filtered = docs.filter((d) =>
    !q.trim() || d.title.toLowerCase().includes(q.toLowerCase()) ||
    (d.file_name ?? "").toLowerCase().includes(q.toLowerCase()),
  );

  const currentCase = clientCases.find((c) => c.id === selectedCaseId);

  return (
    <>
      <PageHeader
        icon={FolderArchive}
        title="أرشيف المستندات والأحكام"
        subtitle="اعرض كل مستنداتك مباشرة، أو فلتر حسب العميل والقضية، أو ارفع مستنداً جديداً"
        action={
          <div className="flex gap-2 flex-wrap">
            <Button
              onClick={() => { if (!selectedCaseId || selectedCaseId === "__all__") return toast.info("اختر قضية محدّدة قبل الرفع"); setEditDoc(null); setUploadOpen(true); }}
              disabled={!bucketReady}
              className="btn-gold"
            >
              <Upload className="h-4 w-4 ml-1" /> رفع مستند جديد
            </Button>
            <Button asChild variant="outline" disabled={!bucketReady || bulkBusy} title="رفع عدة ملفات دفعة واحدة">
              <label className="cursor-pointer">
                {bulkBusy ? <Loader2 className="h-4 w-4 ml-1 animate-spin" /> : <Upload className="h-4 w-4 ml-1" />}
                رفع دفعة
                <input
                  type="file"
                  multiple
                  hidden
                  onChange={(e) => { void handleBulkUpload(e.target.files); e.currentTarget.value = ""; }}
                />
              </label>
            </Button>
            <Button variant="outline" onClick={handleDownloadZip} disabled={zipBusy || filtered.length === 0} title="تنزيل المعروض كأرشيف ZIP">
              {zipBusy ? <Loader2 className="h-4 w-4 ml-1 animate-spin" /> : <Download className="h-4 w-4 ml-1" />}
              تنزيل ZIP
            </Button>
          </div>
        }


      />

      {/* Selector cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
        <Card className="card-3d border-none p-5">
          <div className="flex items-center gap-2 mb-3 text-sm font-bold">
            <div className="grid h-9 w-9 place-items-center rounded-xl bg-gradient-to-br from-emerald-500 to-emerald-700 text-white shadow-md">
              <Users className="h-4 w-4" />
            </div>
            العميل
          </div>
          <Select value={selectedClientId} onValueChange={(v) => { setSelectedClientId(v); setSelectedCaseId(""); }}>
            <SelectTrigger className="h-11"><SelectValue placeholder="— كل العملاء —" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="__all__">— كل العملاء —</SelectItem>
              {(clients.data ?? []).map((c) => (
                <SelectItem key={c.id} value={c.id}>{c.full_name}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </Card>

        <Card className="card-3d border-none p-5">
          <div className="flex items-center gap-2 mb-3 text-sm font-bold">
            <div className="grid h-9 w-9 place-items-center rounded-xl bg-gradient-to-br from-violet-500 to-violet-700 text-white shadow-md">
              <Briefcase className="h-4 w-4" />
            </div>
            القضية
          </div>
          <Select value={selectedCaseId} onValueChange={setSelectedCaseId}>
            <SelectTrigger className="h-11"><SelectValue placeholder="— كل القضايا —" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="__all__">— كل القضايا —</SelectItem>
              {clientCases.length === 0 && <SelectItem disabled value="__empty__">لا توجد قضايا</SelectItem>}
              {clientCases.map((c) => (
                <SelectItem key={c.id} value={c.id}>
                  {c.case_number} — {c.title}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>

        </Card>
      </div>

      {currentCase && (
        <Card className="card-3d border-none p-4 mb-4 bg-gradient-to-l from-primary/5 to-transparent">
          <div className="flex flex-wrap items-center gap-4 text-sm">
            <div className="flex items-center gap-1.5"><Briefcase className="h-4 w-4 text-primary" /> <b>{currentCase.case_number}</b></div>
            <div>{currentCase.title}</div>
            {currentCase.court && <div className="flex items-center gap-1.5 text-muted-foreground"><Building2 className="h-3.5 w-3.5" /> {currentCase.court}</div>}
            <div className="mr-auto" />
            <Button asChild size="sm" variant="outline">
              <Link to="/app/ai/consultant"><Sparkles className="h-3.5 w-3.5 ml-1" /> تحليل القضية بالذكاء الاصطناعي</Link>
            </Button>
          </div>
        </Card>
      )}

      <div className="relative mb-4 max-w-md">
        <Search className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
        <Input placeholder="ابحث في المستندات..." value={q} onChange={(e) => setQ(e.target.value)} className="h-10 pr-10 text-right bg-muted/40 border-transparent" />
      </div>

      {loading ? (
        <Card className="card-3d p-10 text-center"><Loader2 className="h-6 w-6 animate-spin mx-auto text-primary" /></Card>
      ) : filtered.length === 0 ? (
        <Card className="card-3d p-10 text-center text-muted-foreground">
          لا توجد مستندات — استخدم زر "رفع مستند جديد" لإضافتها
        </Card>

      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {filtered.map((d) => {
            const Icon = iconFor(d.mime_type);
            const typeLabel = DOC_TYPES.find((t) => t.id === d.doc_type)?.label ?? d.doc_type;
            const isJudgment = d.doc_type.startsWith("judgment") || d.doc_type === "appeal_judgment";
            return (
              <Card key={d.id} className="card-3d border-none p-4 flex flex-col gap-3 group hover:scale-[1.01] transition-transform">
                <div className="flex items-start gap-3">
                  <div className="grid h-12 w-12 shrink-0 place-items-center rounded-xl bg-gradient-to-br from-primary to-primary/70 text-gold shadow-md"
                       style={{ boxShadow: "inset 0 1px 0 rgba(255,255,255,0.25), 0 6px 14px -4px rgba(0,0,0,0.3)" }}>
                    <Icon className="h-6 w-6" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="text-sm font-bold truncate" title={d.title}>{d.title}</div>
                    <div className="text-[11px] text-muted-foreground mt-0.5 truncate">{d.file_name} • {fmtSize(d.file_size)}</div>
                    <div className="mt-1 inline-block rounded-full bg-primary/10 text-primary text-[10px] font-bold px-2 py-0.5">{typeLabel}</div>
                  </div>
                </div>

                {(d.filed_date || d.judgment_date) && (
                  <div className="text-[11px] space-y-1 text-muted-foreground">
                    {d.filed_date && <div className="flex items-center gap-1"><Calendar className="h-3 w-3" /> تاريخ الإيداع: {d.filed_date}</div>}
                    {d.judgment_date && <div className="flex items-center gap-1"><Calendar className="h-3 w-3 text-rose-500" /> تاريخ الحكم: {d.judgment_date}</div>}
                    {d.court && <div className="flex items-center gap-1"><Building2 className="h-3 w-3" /> {d.court}{d.circuit_number ? ` — دائرة ${d.circuit_number}` : ""}</div>}
                  </div>
                )}

                {isJudgment && d.appeal_deadline && (
                  <div className="rounded-lg bg-amber-500/10 border border-amber-500/30 px-3 py-2 text-[11px] text-amber-700 dark:text-amber-300 font-semibold">
                    ⏰ مهلة الاستئناف تنتهي: {d.appeal_deadline}
                  </div>
                )}

                <div className="flex gap-1.5 mt-auto pt-1">
                  <Button size="sm" variant="outline" className="flex-1" onClick={() => handlePreview(d)} disabled={!d.storage_path}>
                    <Eye className="h-3.5 w-3.5 ml-1" /> عرض
                  </Button>
                  <Button size="sm" variant="outline" onClick={() => handleDownload(d)} disabled={!d.storage_path} title="تحميل">
                    <Download className="h-3.5 w-3.5" />
                  </Button>
                  <Button size="sm" variant="outline" onClick={() => { setEditDoc(d); setUploadOpen(true); }} title="تعديل">
                    <FileText className="h-3.5 w-3.5" />
                  </Button>
                  <Button size="sm" variant="outline" onClick={() => handleDelete(d)} className="text-destructive hover:bg-destructive/10" title="حذف">
                    <Trash2 className="h-3.5 w-3.5" />
                  </Button>
                </div>
              </Card>
            );
          })}
        </div>
      )}

      <UploadDialog
        open={uploadOpen}
        onOpenChange={(v) => { setUploadOpen(v); if (!v) setEditDoc(null); }}
        caseId={selectedCaseId}
        editing={editDoc}
        onSaved={() => { loadDocs(); qc.invalidateQueries({ queryKey: ["documents"] }); }}
      />

      <Dialog open={!!previewDoc} onOpenChange={(v) => !v && setPreviewDoc(null)}>
        <DialogContent className="max-w-5xl h-[85vh] flex flex-col">
          <DialogHeader>
            <DialogTitle>{previewDoc?.name}</DialogTitle>
          </DialogHeader>
          {previewDoc && (
            previewDoc.mime.startsWith("image/") ? (
              <img src={previewDoc.url} alt={previewDoc.name} className="flex-1 object-contain min-h-0" />
            ) : (
              <iframe src={previewDoc.url} title={previewDoc.name} className="flex-1 w-full border-0 rounded-lg min-h-0" />
            )
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => previewDoc && window.open(previewDoc.url, "_blank")}>
              <Download className="h-4 w-4 ml-1" /> فتح في تبويب جديد / تحميل
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

function UploadDialog({
  open, onOpenChange, caseId, editing, onSaved,
}: {
  open: boolean; onOpenChange: (v: boolean) => void;
  caseId: string; editing: DocRow | null; onSaved: () => void;
}) {
  const audit = useServerFn(logAudit);

  const [file, setFile] = useState<File | null>(null);
  const [docType, setDocType] = useState<DocType>("lawsuit");
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [filedDate, setFiledDate] = useState("");
  const [judgmentDate, setJudgmentDate] = useState("");
  const [court, setCourt] = useState("");
  const [circuit, setCircuit] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (open) {
      setFile(null);
      setDocType((editing?.doc_type as DocType) ?? "lawsuit");
      setTitle(editing?.title ?? "");
      setDescription(editing?.description ?? "");
      setFiledDate(editing?.filed_date ?? new Date().toISOString().slice(0, 10));
      setJudgmentDate(editing?.judgment_date ?? "");
      setCourt(editing?.court ?? "");
      setCircuit(editing?.circuit_number ?? "");
    }
  }, [open, editing]);

  const needsJudgment = DOC_TYPES.find((t) => t.id === docType)?.needsJudgmentMeta ?? false;

  const handleSave = async () => {
    if (!title.trim()) return toast.error("أدخل عنواناً للمستند");
    if (!caseId) return toast.error("اختر قضية أولاً");
    if (needsJudgment && !judgmentDate) return toast.error("أدخل تاريخ صدور الحكم");
    if (!editing && !file) return toast.error("اختر ملفاً للرفع");

    setSaving(true);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error("غير مسجل دخول");

      let storagePath = editing?.storage_path ?? null;
      let fileName = editing?.file_name ?? null;
      let fileSize = editing?.file_size ?? null;
      let mimeType = editing?.mime_type ?? null;

      if (file) {
        const safe = `${Date.now()}-${file.name.replace(/[^\w.\-]+/g, "_")}`;
        const path = `${user.id}/${caseId}/${safe}`;
        const { error: upErr } = await supabase.storage.from(BUCKET).upload(path, file, {
          upsert: false, contentType: file.type,
        });
        if (upErr) throw upErr;
        // remove old file if replacing
        if (editing?.storage_path) await supabase.storage.from(BUCKET).remove([editing.storage_path]);
        storagePath = path; fileName = file.name; fileSize = file.size; mimeType = file.type;
      }

      const payload: any = {
        owner_id: user.id, case_id: caseId, doc_type: docType,
        title: title.trim(), description: description.trim() || null,
        storage_path: storagePath, file_name: fileName, file_size: fileSize, mime_type: mimeType,
        filed_date: filedDate || null,
        judgment_date: needsJudgment ? (judgmentDate || null) : null,
        court: needsJudgment ? (court.trim() || null) : null,
        circuit_number: needsJudgment ? (circuit.trim() || null) : null,
      };
      const { data: row, error } = editing
        ? await supabase.from("documents").update(payload).eq("id", editing.id).select("id").single()
        : await supabase.from("documents").insert(payload).select("id").single();
      if (error) throw error;

      toast.success(editing ? "تم تحديث المستند" : "تم رفع المستند وحفظ بياناته");
      audit({ data: {
        action: editing ? "document.update" : "document.upload",
        entity_type: "document",
        entity_id: row?.id ?? editing?.id,
        metadata: { title: title.trim(), case_id: caseId, doc_type: docType, file_replaced: !!file && !!editing },
      } }).catch(() => {});
      if (needsJudgment && docType === "judgment_non_final" && judgmentDate) {
        toast.info("تم احتساب مهلة الاستئناف ٣٠ يوماً تلقائياً وربطها بالمهل النظامية");
      }
      onSaved(); onOpenChange(false);

    } catch (e: any) {
      toast.error(e?.message ?? "فشل الحفظ");
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto" dir="rtl">
        <DialogHeader>
          <DialogTitle>{editing ? "تعديل المستند" : "رفع مستند جديد"}</DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          <div>
            <Label>نوع المستند *</Label>
            <Select value={docType} onValueChange={(v) => setDocType(v as DocType)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {DOC_TYPES.map((t) => <SelectItem key={t.id} value={t.id}>{t.label}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>

          <div>
            <Label>عنوان المستند *</Label>
            <Input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="مثال: حكم ابتدائي رقم 1234" />
          </div>

          <div>
            <Label>وصف (اختياري)</Label>
            <Textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={2} />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>تاريخ الإيداع / الرفع</Label>
              <Input type="date" value={filedDate} onChange={(e) => setFiledDate(e.target.value)} />
            </div>
            {needsJudgment && (
              <div>
                <Label>تاريخ صدور الحكم *</Label>
                <Input type="date" value={judgmentDate} onChange={(e) => setJudgmentDate(e.target.value)} />
              </div>
            )}
          </div>

          {needsJudgment && (
            <div className="grid grid-cols-2 gap-3">
              <div>
                <Label>المحكمة</Label>
                <Input value={court} onChange={(e) => setCourt(e.target.value)} placeholder="المحكمة العامة بالرياض" />
              </div>
              <div>
                <Label>رقم الدائرة</Label>
                <Input value={circuit} onChange={(e) => setCircuit(e.target.value)} placeholder="مثال: الدائرة التجارية الثالثة" />
              </div>
            </div>
          )}

          {needsJudgment && docType === "judgment_non_final" && (
            <div className="rounded-lg bg-amber-500/10 border border-amber-500/30 p-3 text-xs text-amber-700 dark:text-amber-300">
              ⏰ سيقوم النظام تلقائياً بإنشاء تنبيه بمهلة الاستئناف (٣٠ يوماً من تاريخ صدور الحكم) في قسم المهل والمدد النظامية.
            </div>
          )}

          <div>
            <Label>{editing ? "استبدال الملف (اختياري)" : "الملف *"}</Label>
            <Input type="file" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
            {editing?.file_name && !file && <div className="text-xs text-muted-foreground mt-1">الحالي: {editing.file_name}</div>}
          </div>
        </div>

        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>إلغاء</Button>
          <Button onClick={handleSave} disabled={saving} className="btn-gold">
            {saving ? <Loader2 className="h-4 w-4 animate-spin ml-1" /> : <Upload className="h-4 w-4 ml-1" />}
            {editing ? "حفظ التعديلات" : "رفع وحفظ"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
