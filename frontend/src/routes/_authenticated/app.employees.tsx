import { createFileRoute } from "@tanstack/react-router";
import { useState, useMemo, useEffect } from "react";
import { UserCog, Phone, Mail, IdCard, Briefcase, GraduationCap, CalendarClock, KeyRound, Pencil, Trash2, Search, AlertTriangle, Copy, MessageCircle, Send, FileEdit } from "lucide-react";
import { PageHeader } from "@/components/section-shell";
import { CrudDialog, AddButton, type Field } from "@/components/crud-dialog";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { useList, useUpsert, useDelete } from "@/lib/data-hooks";
import { ContactEmployeeButton } from "@/components/contact-employee-button";
import { supabase as supabaseTyped } from "@/integrations/supabase/client";
import { toast } from "sonner";

const supabase = supabaseTyped as any;

const DEFAULT_WELCOME_TEMPLATE = `مرحباً {name}،
تم إنشاء حساب لك على بوابة الموظفين.

رابط الدخول: {portal_url}
رمز الدخول الخاص بك: {code}

خطوات الدخول:
1) افتح الرابط أعلاه.
2) أنشئ حساباً بالبريد الإلكتروني المعتمد لديك.
3) أدخل رمز الدخول أعلاه عند طلبه لربط حسابك ببوابة الموظفين.

بالتوفيق.`;

const renderTemplate = (tpl: string, name: string, code: string) => {
  const origin = typeof window !== "undefined" ? window.location.origin : "";
  return tpl
    .replaceAll("{name}", name || "أيها الزميل")
    .replaceAll("{code}", code || "")
    .replaceAll("{portal_url}", `${origin}/auth`);
};

const onlyDigits = (v?: string | null) => String(v || "").replace(/[^\d+]/g, "").replace(/^\+/, "");



export const Route = createFileRoute("/_authenticated/app/employees")({
  component: EmployeesPage,
});

function useEmpFields(employees: any[]): Field[] {
  return [
    { name: "full_name", label: "اسم الموظف", required: true },
    { name: "nationality", label: "الجنسية" },
    { name: "national_id", label: "رقم الهوية" },
    { name: "phone", label: "رقم الجوال", type: "tel" },
    { name: "email", label: "البريد الإلكتروني", type: "email" },
    { name: "residence_expiry", label: "تاريخ انتهاء الإقامة/الهوية", type: "date" },
    { name: "job_title", label: "المسمى الوظيفي" },
    { name: "qualification", label: "المؤهل الدراسي" },
    { name: "direct_manager_id", label: "المدير المباشر", type: "select",
      options: employees.map((e) => ({ value: e.id, label: e.full_name })) },
    { name: "start_date", label: "تاريخ بدء العمل", type: "date" },
    { name: "end_date", label: "تاريخ انتهاء العمل", type: "date" },
  ];
}

const daysLeft = (d?: string | null) => {
  if (!d) return null;
  const t = new Date(d).getTime();
  const now = new Date(); now.setHours(0, 0, 0, 0);
  return Math.ceil((t - now.getTime()) / 86_400_000);
};

function EmployeesPage() {
  const { data: rows = [], isLoading } = useList<any>("employees");
  const upsert = useUpsert("employees");
  const del = useDelete("employees");
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<any | null>(null);
  const [q, setQ] = useState("");
  const fields = useEmpFields(rows);

  // Per-office welcome template (loaded from office_settings; falls back to default)
  const [ownerId, setOwnerId] = useState<string | null>(null);
  const [template, setTemplate] = useState<string>(DEFAULT_WELCOME_TEMPLATE);
  const [tplOpen, setTplOpen] = useState(false);
  const [tplDraft, setTplDraft] = useState<string>(DEFAULT_WELCOME_TEMPLATE);
  const [tplSaving, setTplSaving] = useState(false);
  type TplAudit = { id: string; changed_by: string | null; old_template: string | null; new_template: string | null; created_at: string };
  const [tplAudit, setTplAudit] = useState<TplAudit[]>([]);
  const [showAudit, setShowAudit] = useState(false);
  const [codeMap, setCodeMap] = useState<Record<string, string>>({});

  useEffect(() => {
    let alive = true;
    (async () => {
      const { data } = await supabase.from("employee_portal_credentials")
        .select("employee_id, portal_access_code");
      if (!alive) return;
      const map: Record<string, string> = {};
      (data ?? []).forEach((r: any) => { if (codeMap[r.id]) map[r.employee_id] = codeMap[r.id]; });
      setCodeMap(map);
    })();
    return () => { alive = false; };
  }, [rows.length]);

  const loadAudit = async (oid: string) => {
    const { data } = await supabase.from("welcome_template_audit")
      .select("id, changed_by, old_template, new_template, created_at")
      .eq("owner_id", oid)
      .order("created_at", { ascending: false })
      .limit(20);
    setTplAudit((data ?? []) as TplAudit[]);
  };

  useEffect(() => {
    let alive = true;
    (async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user || !alive) return;
      // owner_id = my id if I'm the office owner; else my employer's owner_id
      const { data: emp } = await supabase.from("employees")
        .select("owner_id").eq("user_id", user.id).maybeSingle();
      const oid = (emp?.owner_id as string | undefined) ?? user.id;
      if (!alive) return;
      setOwnerId(oid);
      const { data: row } = await supabase.from("office_settings")
        .select("employee_welcome_template").eq("owner_id", oid).maybeSingle();
      const tpl = (row?.employee_welcome_template as string | undefined) || DEFAULT_WELCOME_TEMPLATE;
      if (!alive) return;
      setTemplate(tpl); setTplDraft(tpl);
      loadAudit(oid);
    })();
    return () => { alive = false; };
  }, []);

  const saveTemplate = async () => {
    if (!ownerId) return;
    setTplSaving(true);
    const { error } = await supabase.from("office_settings")
      .upsert({ owner_id: ownerId, employee_welcome_template: tplDraft }, { onConflict: "owner_id" });
    setTplSaving(false);
    if (error) { toast.error("تعذّر الحفظ"); return; }
    setTemplate(tplDraft); setTplOpen(false); toast.success("تم حفظ قالب رسالة الترحيب");
    if (ownerId) loadAudit(ownerId);
  };

  const buildMsg = (r: any) => renderTemplate(template, r.full_name, codeMap[r.id] ?? "");
  const copyMsg = async (r: any) => {
    try { await navigator.clipboard.writeText(buildMsg(r)); toast.success("تم نسخ رسالة التعريف"); }
    catch { toast.error("تعذّر النسخ"); }
  };
  const sendWhatsApp = (r: any) => {
    const phone = onlyDigits(r.phone);
    const text = encodeURIComponent(buildMsg(r));
    const url = phone ? `https://wa.me/${phone}?text=${text}` : `https://wa.me/?text=${text}`;
    window.open(url, "_blank", "noopener,noreferrer");
  };
  const sendEmail = (r: any) => {
    if (!r.email) { toast.error("لا يوجد بريد لهذا الموظف"); return; }
    const subject = encodeURIComponent("بيانات الدخول إلى بوابة الموظفين");
    const body = encodeURIComponent(buildMsg(r));
    window.location.href = `mailto:${r.email}?subject=${subject}&body=${body}`;
  };

  const filtered = useMemo(() => {
    const s = q.trim().toLowerCase();
    if (!s) return rows;
    return rows.filter((r) =>
      `${r.full_name ?? ""} ${r.job_title ?? ""} ${r.phone ?? ""} ${r.email ?? ""} ${r.national_id ?? ""}`
        .toLowerCase().includes(s),
    );
  }, [rows, q]);

  return (
    <>
      <PageHeader icon={UserCog} title="بيانات الموظفين" subtitle={`${rows.length} موظف`}
        action={
          <div className="flex gap-2">
            <Button variant="outline" size="sm" onClick={() => { setTplDraft(template); setTplOpen(true); }}>
              <FileEdit className="h-4 w-4 ml-1" /> تحرير قالب الترحيب
            </Button>
            <AddButton label="إضافة موظف" onClick={() => { setEditing(null); setOpen(true); }} />
          </div>
        } />

      <div className="relative mb-4 max-w-md">
        <Search className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
        <Input placeholder="بحث عن موظف..." value={q} onChange={(e) => setQ(e.target.value)}
          className="text-right pr-9" />
      </div>

      <CrudDialog open={open} onOpenChange={setOpen} title={editing ? "تعديل موظف" : "موظف جديد"}
        fields={fields} initial={editing ?? {}}
        loading={upsert.isPending}
        onSubmit={async (v) => {
          await upsert.mutateAsync({
            ...v,
            id: editing?.id,
          });
        }} />

      {isLoading ? (
        <p className="text-center text-muted-foreground py-10">جارٍ التحميل...</p>
      ) : filtered.length === 0 ? (
        <div className="card-luxe p-12 text-center text-white/70">
          {rows.length === 0 ? "لا يوجد موظفون بعد — استخدم زر إضافة موظف" : "لا توجد نتائج"}
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-5">
          {filtered.map((r) => {
            const dl = daysLeft(r.residence_expiry);
            const expiring = dl != null && dl >= 0 && dl <= 90;
            const expired = dl != null && dl < 0;
            return (
              <div key={r.id} className={`card-luxe aspect-square flex flex-col p-5 relative ${expired ? "expiry-pulse" : expiring ? "expiry-glow" : ""}`}>
                <div className="flex items-start justify-between gap-2 relative z-10">
                  <div className="grid h-14 w-14 place-items-center rounded-xl bg-gradient-to-br from-gold to-gold/60 text-primary shadow-md shrink-0 text-lg font-extrabold">
                    {(r.full_name || "؟").trim().charAt(0)}
                  </div>
                  <div className="flex flex-col items-end gap-1.5">
                    {codeMap[r.id] && (
                      <button
                        type="button"
                        title="نسخ رسالة تعريف الموظف ببوابته"
                        onClick={() => copyMsg(r)}
                        className="inline-flex items-center gap-1 rounded-md border border-gold/40 bg-gold/10 px-2 py-0.5 text-[10px] font-bold text-gold hover:bg-gold/20 transition-colors"
                      >
                        <KeyRound className="h-3 w-3" /> {codeMap[r.id]}
                        <Copy className="h-3 w-3 opacity-70" />
                      </button>
                    )}
                    {(expired || expiring) && (
                      <span
                        data-testid="employee-expiry-badge"
                        className="inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-[11px] font-extrabold shadow-md border-2 border-red-600 bg-red-600 text-white animate-pulse"
                      >
                        <AlertTriangle className="h-3.5 w-3.5" />
                        {expired ? `الهوية منتهية` : `هوية تنتهي خلال ${dl} يوم`}
                      </span>
                    )}
                  </div>
                </div>

                <div className="mt-3 flex-1 min-h-0 relative z-10">
                  <div className="text-[10px] uppercase tracking-[0.25em] text-gold/80">الموظف</div>
                  <div className="mt-0.5 text-base font-extrabold text-white truncate">{r.full_name || "—"}</div>

                  <dl className="mt-3 space-y-1.5 text-[12px] text-white/80">
                    <Row icon={Briefcase} label="الوظيفة" value={r.job_title} />
                    <Row icon={GraduationCap} label="المؤهل" value={r.qualification} />
                    <Row icon={IdCard} label="الهوية" value={r.national_id} />
                    <Row icon={Phone} label="الجوال" value={r.phone} />
                    <Row icon={Mail} label="البريد" value={r.email} />
                    <Row icon={CalendarClock} label="انتهاء الهوية" value={r.residence_expiry} highlight={expired || expiring} />
                  </dl>
                </div>

                <div className="mt-3 grid grid-cols-3 gap-1.5 relative z-10">
                  <ContactEmployeeButton
                    userId={r.user_id}
                    className="h-8 text-xs border-gold/30 bg-gold/10 text-gold hover:bg-gold/20"
                    label="راسِل"
                  />
                  <button onClick={() => { setEditing(r); setOpen(true); }}
                    className="h-8 rounded-lg border border-white/15 bg-white/5 text-white/85 hover:bg-white/10 grid place-items-center gap-1 text-xs flex-row inline-flex">
                    <Pencil className="h-3.5 w-3.5" /> تعديل
                  </button>
                  <button onClick={() => { if (confirm(`حذف الموظف ${r.full_name}؟`)) del.mutate(r.id); }}
                    className="h-8 rounded-lg border border-rose-400/30 bg-rose-400/10 text-rose-300 hover:bg-rose-400/20 grid place-items-center gap-1 text-xs flex-row inline-flex">
                    <Trash2 className="h-3.5 w-3.5" /> حذف
                  </button>
                </div>
                {codeMap[r.id] && (
                  <div className="mt-2 grid grid-cols-2 gap-1.5 relative z-10">
                    <button onClick={() => sendWhatsApp(r)}
                      title={r.phone ? `إرسال إلى ${r.phone}` : "فتح واتساب لاختيار المستلم"}
                      className="h-8 rounded-lg border border-emerald-400/30 bg-emerald-400/10 text-emerald-300 hover:bg-emerald-400/20 grid place-items-center gap-1 text-xs flex-row inline-flex">
                      <MessageCircle className="h-3.5 w-3.5" /> {r.user_id ? "واتساب" : "تذكير واتساب"}
                    </button>
                    <button onClick={() => sendEmail(r)}
                      title={r.email || "لا يوجد بريد"}
                      disabled={!r.email}
                      className="h-8 rounded-lg border border-sky-400/30 bg-sky-400/10 text-sky-300 hover:bg-sky-400/20 grid place-items-center gap-1 text-xs flex-row inline-flex disabled:opacity-50 disabled:cursor-not-allowed">
                      <Send className="h-3.5 w-3.5" /> {r.user_id ? "بريد" : "تذكير بريد"}
                    </button>
                  </div>
                )}
                {!r.user_id && codeMap[r.id] && (
                  <div className="mt-1.5 text-[10px] text-amber-300/90 text-center relative z-10">
                    لم يربط حسابه بعد — أرسل تذكيراً
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {/* Welcome template editor */}
      <Dialog open={tplOpen} onOpenChange={setTplOpen}>
        <DialogContent className="max-w-4xl">
          <DialogHeader>
            <DialogTitle>تحرير قالب رسالة الترحيب</DialogTitle>
          </DialogHeader>
          <div className="text-xs text-muted-foreground mb-2">
            استخدم المتغيرات: <code className="bg-muted px-1 rounded">{"{name}"}</code> اسم الموظف،{" "}
            <code className="bg-muted px-1 rounded">{"{code}"}</code> رمز الدخول،{" "}
            <code className="bg-muted px-1 rounded">{"{portal_url}"}</code> رابط البوابة.
          </div>
          <div className="grid md:grid-cols-2 gap-3">
            <div>
              <div className="text-[11px] font-bold text-muted-foreground mb-1">المحرر</div>
              <Textarea value={tplDraft} onChange={(e) => setTplDraft(e.target.value)} rows={14}
                className="font-mono text-sm leading-relaxed" dir="rtl" />
            </div>
            <div>
              <div className="text-[11px] font-bold text-muted-foreground mb-1">المعاينة (بيانات تجريبية)</div>
              <div className="rounded-md border bg-muted/30 p-3 text-sm whitespace-pre-wrap h-[336px] overflow-y-auto leading-relaxed" dir="rtl">
                {renderTemplate(tplDraft, "محمد العتيبي", "EMP-AB12CD")}
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowAudit((v) => !v)}>
              {showAudit ? "إخفاء السجل" : `سجل التغييرات (${tplAudit.length})`}
            </Button>
            <Button variant="outline" onClick={() => { setTplDraft(DEFAULT_WELCOME_TEMPLATE); }}>
              استعادة الافتراضي
            </Button>
            <Button onClick={saveTemplate} disabled={tplSaving} className="btn-gold">
              {tplSaving ? "جارٍ الحفظ..." : "حفظ"}
            </Button>
          </DialogFooter>
          {showAudit && (
            <div className="mt-2 max-h-60 overflow-y-auto rounded-md border bg-muted/20 p-2 text-xs space-y-2" dir="rtl">
              {tplAudit.length === 0 ? (
                <div className="text-muted-foreground text-center py-3">لا توجد تغييرات سابقة.</div>
              ) : (
                tplAudit.map((a) => (
                  <div key={a.id} className="border-b last:border-b-0 pb-2">
                    <div className="flex items-center justify-between text-[11px] text-muted-foreground">
                      <span>بواسطة: {a.changed_by ? a.changed_by.slice(0, 8) : "—"}</span>
                      <span>{new Date(a.created_at).toLocaleString("ar-SA")}</span>
                    </div>
                    <details className="mt-1">
                      <summary className="cursor-pointer text-gold text-[11px]">عرض النص السابق ↔ الجديد</summary>
                      <div className="grid md:grid-cols-2 gap-2 mt-2">
                        <div>
                          <div className="font-bold text-[10px] mb-1">قبل</div>
                          <div className="bg-background border rounded p-2 whitespace-pre-wrap text-[11px] max-h-32 overflow-y-auto">
                            {a.old_template || "—"}
                          </div>
                        </div>
                        <div>
                          <div className="font-bold text-[10px] mb-1">بعد</div>
                          <div className="bg-background border rounded p-2 whitespace-pre-wrap text-[11px] max-h-32 overflow-y-auto">
                            {a.new_template || "—"}
                          </div>
                        </div>
                      </div>
                    </details>
                  </div>
                ))
              )}
            </div>
          )}
        </DialogContent>
      </Dialog>
    </>
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
