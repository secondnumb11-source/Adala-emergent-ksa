import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { ShieldCheck, Save, UserCog, Loader2, KeyRound, MessageSquare, Copy, ExternalLink, Send, Mail } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { PageHeader } from "@/components/section-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Checkbox } from "@/components/ui/checkbox";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { Textarea } from "@/components/ui/textarea";
import { useList } from "@/lib/data-hooks";
import { saveEmployeePortalConfig } from "@/lib/portal.functions";
import { provisionEmployeePortal } from "@/lib/employee-portal.functions";
import { ContactEmployeeButton } from "@/components/contact-employee-button";
import { RequireRole } from "@/components/require-role";
import { toast } from "sonner";

export const Route = createFileRoute("/_authenticated/app/employee-portal")({
  component: GuardedEmployeePortalPage,
});

function GuardedEmployeePortalPage() {
  return (
    <RequireRole allowed={["lawyer", "admin"]}>
      <EmployeePortalPage />
    </RequireRole>
  );
}

// Mirror of sidebar sections — what the employee may see in their portal.
const SECTIONS = [
  { id: "cases", label: "إدارة القضايا" },
  { id: "sessions", label: "مواعيد الجلسات" },
  { id: "clients", label: "العملاء" },
  { id: "powers", label: "الوكالات القضائية" },
  { id: "execution", label: "طلبات التنفيذ" },
  { id: "tasks", label: "المهام وتوزيع الأعمال" },
  { id: "notifications", label: "إشعارات العملاء" },
  { id: "archive", label: "أرشيف المستندات والأحكام" },
  { id: "ai", label: "المساعد الذكي" },
  { id: "library", label: "المكتبة القانونية" },
  { id: "gov", label: "الخدمات الحكومية" },
  { id: "verification", label: "خدمات التحقق" },
];

function EmployeePortalPage() {
  const qc = useQueryClient();
  const { data: employees = [], isLoading } = useList<any>("employees");
  const { data: cases = [] } = useList<any>("cases");
  const { data: clients = [] } = useList<any>("clients");
  const { data: tasks = [] } = useList<any>("tasks");

  const [empId, setEmpId] = useState<string>("");
  const [permissions, setPermissions] = useState<string[]>([]);
  const [assignedCases, setAssignedCases] = useState<string[]>([]);
  const [assignedClients, setAssignedClients] = useState<string[]>([]);

  // Credentials & WhatsApp template state
  const [credEmail, setCredEmail] = useState("");
  const [credUsername, setCredUsername] = useState("");
  const [credPassword, setCredPassword] = useState("");
  const [issuedCreds, setIssuedCreds] = useState<{ username: string; password: string; access_code: string; email: string } | null>(null);
  const [waPhone, setWaPhone] = useState("");
  const [waTemplate, setWaTemplate] = useState("");
  const [managerName, setManagerName] = useState<string>("المدير المباشر");

  useEffect(() => {
    (async () => {
      const { data: { user } } = await supabase.auth.getUser();
      const fn = (user?.user_metadata?.full_name as string | undefined)
        || user?.email?.split("@")[0]
        || "المدير المباشر";
      setManagerName(fn);
    })();
  }, []);

  const employee = useMemo(() => employees.find((e) => e.id === empId), [employees, empId]);
  const portalLoginUrl = typeof window !== "undefined" ? `${window.location.origin}/login` : "/login";

  useEffect(() => {
    if (!employee) {
      setCredEmail(""); setCredUsername(""); setCredPassword(""); setIssuedCreds(null); setWaPhone(""); setWaTemplate("");
      return;
    }
    setPermissions(Array.isArray(employee.permissions) ? employee.permissions : []);
    setAssignedCases(Array.isArray(employee.assigned_cases) ? employee.assigned_cases : []);
    setAssignedClients(Array.isArray(employee.assigned_clients) ? employee.assigned_clients : []);
    setCredEmail(employee.email || "");
    setCredUsername(employee.full_name || "");
    setCredPassword("");
    setWaPhone(employee.phone || "");
    setIssuedCreds(null);
  }, [employee]);

  const buildTemplate = (creds: { username: string; password: string; access_code: string; email: string }) => {
    const fullName = employee?.full_name || "—";
    const empNo = employee?.id?.slice(0, 8).toUpperCase() || "—";
    return [
      `السلام عليكم ورحمة الله وبركاته،`,
      `الأستاذ/ة ${fullName}`,
      ``,
      `نرحّب بانضمامك إلى فريق العمل، وفيما يلي بيانات الدخول الخاصة بك إلى بوابة الموظفين:`,
      ``,
      `• الاسم الكامل: ${fullName}`,
      `• الرقم الوظيفي: ${empNo}`,
      `• اسم المستخدم: ${creds.username}`,
      `• البريد الإلكتروني: ${creds.email}`,
      `• كلمة المرور: ${creds.password}`,
      `• رمز الدخول: ${creds.access_code}`,
      `• المدير المباشر: ${managerName}`,
      `• رابط بوابة الموظف: ${portalLoginUrl}`,
      ``,
      `يرجى تغيير كلمة المرور بعد أول تسجيل دخول للحفاظ على سرّية حسابك.`,
      ``,
      `مع التحية،`,
      `${managerName}`,
    ].join("\n");
  };

  const save = useMutation({
    mutationFn: async () => await saveEmployeePortalConfig({
      data: {
        employee_id: empId,
        permissions,
        assigned_cases: assignedCases,
        assigned_clients: assignedClients,
      },
    }),
    onSuccess: () => {
      toast.success("تم حفظ تهيئة البوابة");
      qc.invalidateQueries({ queryKey: ["employees"] });
    },
    onError: (e: any) => toast.error(e.message || "فشل الحفظ"),
  });

  const provision = useMutation({
    mutationFn: async () => await provisionEmployeePortal({
      data: {
        employee_id: empId,
        email: credEmail,
        username: credUsername || null,
        password: credPassword || null,
      },
    }),
    onSuccess: (res) => {
      const creds = {
        username: res.username,
        password: credPassword || "(لم تتغيّر)",
        access_code: res.access_code,
        email: res.email,
      };
      setIssuedCreds(creds);
      setWaTemplate(buildTemplate(creds));
      toast.success(res.created ? "تم إنشاء حساب الموظف" : "تم تحديث بيانات الدخول");
      qc.invalidateQueries({ queryKey: ["employees"] });
    },
    onError: (e: any) => toast.error(e.message || "فشل التفعيل"),
  });

  const toggle = (list: string[], set: (v: string[]) => void, id: string) => {
    set(list.includes(id) ? list.filter((x) => x !== id) : [...list, id]);
  };

  const sanitizePhone = (p: string) => p.replace(/[^\d+]/g, "").replace(/^00/, "+").replace(/^\+?/, "");
  const openWhatsApp = (phone: string) => {
    if (!waTemplate.trim()) { toast.error("جهّز بيانات الدخول أولاً"); return; }
    const clean = sanitizePhone(phone);
    if (!clean) { toast.error("رقم واتساب غير صالح"); return; }
    const url = `https://wa.me/${clean}?text=${encodeURIComponent(waTemplate)}`;
    window.open(url, "_blank", "noopener,noreferrer");
  };

  const openEmail = () => {
    if (!waTemplate.trim()) { toast.error("جهّز بيانات الدخول أولاً"); return; }
    const subject = encodeURIComponent("بيانات الدخول لبوابة الموظفين");
    const body = encodeURIComponent(waTemplate);
    const to = encodeURIComponent(credEmail || "");
    window.location.href = `mailto:${to}?subject=${subject}&body=${body}`;
  };

  const copyTemplate = async () => {
    if (!waTemplate.trim()) return;
    try { await navigator.clipboard.writeText(waTemplate); toast.success("تم نسخ الرسالة كاملة"); }
    catch { toast.error("تعذّر النسخ"); }
  };

  const employeeTasks = useMemo(() =>
    empId ? tasks.filter((t) => t.employee_id === empId) : [],
  [tasks, empId]);

  return (
    <>
      <PageHeader
        icon={ShieldCheck}
        title="بوابة الموظفين والصلاحيات"
        subtitle="حدّد الأقسام والقضايا والعملاء التي تظهر للموظف في بوابته"
        action={
          <Button onClick={() => save.mutate()} disabled={!empId || save.isPending} className="btn-gold gap-2">
            {save.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
            حفظ التهيئة
          </Button>
        }
      />

      {isLoading ? <p className="text-center text-muted-foreground py-10">جارٍ التحميل...</p> : (
        <div className="grid gap-6 lg:grid-cols-3">
          {/* Employee selector */}
          <Card className="card-3d border-none p-6 lg:col-span-1">
            <div className="flex items-center gap-2 mb-4">
              <UserCog className="h-5 w-5 text-gold" />
              <h3 className="font-bold">اختر الموظف</h3>
            </div>
            {employees.length === 0 ? (
              <p className="text-xs text-muted-foreground">لا يوجد موظفون مسجّلون — أضف الموظفين أولاً من قسم بيانات الموظفين.</p>
            ) : (
              <div className="space-y-2 max-h-[420px] overflow-y-auto">
                {employees.map((e) => (
                  <div key={e.id} className={`rounded-lg border p-3 transition-colors ${empId === e.id ? "border-gold bg-gold/10" : "hover:bg-muted/40"}`}>
                    <div className="flex items-start justify-between gap-2">
                      <button
                        onClick={() => setEmpId(e.id)}
                        className="flex-1 text-right"
                      >
                        <div className="font-bold text-sm">{e.full_name}</div>
                        <div className="text-[11px] text-muted-foreground">{e.job_title || "—"}</div>
                        <div className="mt-1.5 flex flex-wrap gap-1 text-[10px]">
                          <Badge variant="outline">{(e.permissions ?? []).length} صلاحية</Badge>
                          <Badge variant="outline">{(e.assigned_cases ?? []).length} قضية</Badge>
                        </div>
                      </button>
                      <ContactEmployeeButton userId={e.user_id} iconOnly size="icon"
                        className="h-8 w-8 shrink-0 border-gold/30 bg-gold/10 text-gold hover:bg-gold/20" />
                    </div>
                  </div>
                ))}
              </div>
            )}
          </Card>

          {/* Config */}
          <Card className="card-3d border-none p-6 lg:col-span-2">
            {!empId ? (
              <p className="text-sm text-muted-foreground text-center py-16">اختر موظفاً من اليمين لبدء التهيئة</p>
            ) : (
              <div className="space-y-6">
                {/* Credentials & WhatsApp invite */}
                <div className="rounded-xl border border-gold/30 bg-gold/5 p-4 space-y-4">
                  <div className="flex items-center gap-2">
                    <KeyRound className="h-5 w-5 text-gold" />
                    <h3 className="font-bold text-sm">بيانات الدخول لبوابة الموظف</h3>
                  </div>
                  <div className="grid sm:grid-cols-3 gap-3">
                    <div>
                      <Label className="text-xs mb-1 block">البريد الإلكتروني</Label>
                      <Input type="email" value={credEmail} onChange={(e) => setCredEmail(e.target.value)} placeholder="employee@example.com" />
                    </div>
                    <div>
                      <Label className="text-xs mb-1 block">اسم المستخدم</Label>
                      <Input value={credUsername} onChange={(e) => setCredUsername(e.target.value)} placeholder="username" />
                    </div>
                    <div>
                      <Label className="text-xs mb-1 block">كلمة المرور {employee?.user_id ? "(تركها فارغة = لا تتغيّر)" : ""}</Label>
                      <Input type="text" value={credPassword} onChange={(e) => setCredPassword(e.target.value)} placeholder="••••••••" />
                    </div>
                  </div>
                  <div className="flex flex-wrap items-center gap-2">
                    <Button
                      onClick={() => provision.mutate()}
                      disabled={!empId || !credEmail || provision.isPending}
                      className="btn-gold gap-2"
                      size="sm"
                    >
                      {provision.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <KeyRound className="h-4 w-4" />}
                      {employee?.user_id ? "تحديث بيانات الدخول" : "تفعيل الحساب وإصدار رمز الدخول"}
                    </Button>
                    {issuedCreds && (
                      <Badge variant="outline" className="text-[10px]">
                        رمز الدخول: {issuedCreds.access_code}
                      </Badge>
                    )}
                  </div>

                  {issuedCreds && (
                    <div className="space-y-2 border-t pt-3">
                      <div className="flex items-center gap-2">
                        <MessageSquare className="h-4 w-4 text-gold" />
                        <Label className="text-xs font-bold">رسالة ترحيبية (واتساب) — قابلة للتعديل</Label>
                      </div>
                      <Textarea
                        value={waTemplate}
                        onChange={(e) => setWaTemplate(e.target.value)}
                        rows={9}
                        className="text-xs font-mono leading-relaxed"
                      />
                      <div className="flex flex-wrap items-end gap-2">
                        <div className="flex-1 min-w-[180px]">
                          <Label className="text-[10px] mb-1 block">رقم واتساب للإرسال</Label>
                          <Input
                            value={waPhone}
                            onChange={(e) => setWaPhone(e.target.value)}
                            placeholder="9665XXXXXXXX"
                            dir="ltr"
                            className="text-xs"
                          />
                        </div>
                        <Button size="sm" variant="outline" onClick={copyTemplate} className="gap-1">
                          <Copy className="h-3.5 w-3.5" /> نسخ
                        </Button>
                        <Button size="sm" onClick={() => openWhatsApp(waPhone)} className="btn-gold gap-1">
                          <Send className="h-3.5 w-3.5" /> إرسال عبر واتساب
                        </Button>
                        <Button size="sm" variant="outline" onClick={openEmail} className="gap-1">
                          <Mail className="h-3.5 w-3.5" /> إرسال بالبريد
                        </Button>
                        <a
                          href={portalLoginUrl}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="inline-flex items-center gap-1 text-xs text-primary hover:underline"
                        >
                          <ExternalLink className="h-3.5 w-3.5" /> رابط الدخول
                        </a>
                      </div>
                    </div>
                  )}
                </div>

                <Separator />

                <div>
                  <Label className="text-sm font-bold mb-3 block">الأقسام التي تظهر للموظف</Label>
                  <div className="grid sm:grid-cols-2 gap-2">
                    {SECTIONS.map((s) => (
                      <label key={s.id} className="flex items-center gap-2 rounded-lg border p-2.5 hover:bg-muted/40 cursor-pointer">
                        <Checkbox
                          checked={permissions.includes(s.id)}
                          onCheckedChange={() => toggle(permissions, setPermissions, s.id)}
                        />
                        <span className="text-sm">{s.label}</span>
                      </label>
                    ))}
                  </div>
                </div>

                <Separator />

                <div>
                  <Label className="text-sm font-bold mb-3 block">القضايا التي يتابعها</Label>
                  {cases.length === 0 ? (
                    <p className="text-xs text-muted-foreground">لا توجد قضايا — أضف قضايا أولاً.</p>
                  ) : (
                    <div className="grid sm:grid-cols-2 gap-2 max-h-56 overflow-y-auto">
                      {cases.map((c) => (
                        <label key={c.id} className="flex items-start gap-2 rounded-lg border p-2.5 hover:bg-muted/40 cursor-pointer">
                          <Checkbox
                            checked={assignedCases.includes(c.id)}
                            onCheckedChange={() => toggle(assignedCases, setAssignedCases, c.id)}
                          />
                          <div className="text-xs">
                            <div className="font-bold">#{c.case_number}</div>
                            <div className="text-muted-foreground line-clamp-1">{c.title}</div>
                          </div>
                        </label>
                      ))}
                    </div>
                  )}
                </div>

                <Separator />

                <div>
                  <Label className="text-sm font-bold mb-3 block">العملاء المرتبطون</Label>
                  {clients.length === 0 ? (
                    <p className="text-xs text-muted-foreground">لا يوجد عملاء.</p>
                  ) : (
                    <div className="grid sm:grid-cols-2 gap-2 max-h-56 overflow-y-auto">
                      {clients.map((c) => (
                        <label key={c.id} className="flex items-center gap-2 rounded-lg border p-2.5 hover:bg-muted/40 cursor-pointer">
                          <Checkbox
                            checked={assignedClients.includes(c.id)}
                            onCheckedChange={() => toggle(assignedClients, setAssignedClients, c.id)}
                          />
                          <span className="text-sm">{c.full_name}</span>
                        </label>
                      ))}
                    </div>
                  )}
                </div>

                <Separator />

                <div>
                  <Label className="text-sm font-bold mb-3 block">المهام المُسندة (مزامنة تلقائية مع البوابة)</Label>
                  {employeeTasks.length === 0 ? (
                    <p className="text-xs text-muted-foreground">لا توجد مهام مُسندة لهذا الموظف بعد — أسند المهام من قسم «المهام وتوزيع الأعمال».</p>
                  ) : (
                    <div className="space-y-2 max-h-56 overflow-y-auto">
                      {employeeTasks.map((t) => (
                        <div key={t.id} className="flex items-center justify-between gap-2 rounded-lg border p-2.5 text-xs">
                          <div>
                            <div className="font-bold">{t.title}</div>
                            <div className="text-muted-foreground">{t.due_date ? `الاستحقاق: ${t.due_date}` : "بدون موعد"}</div>
                          </div>
                          <Badge variant="outline">{t.status}</Badge>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              </div>
            )}
          </Card>
        </div>
      )}
    </>
  );
}
