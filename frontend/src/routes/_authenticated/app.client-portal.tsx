import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import {
  ShieldCheck, Save, Loader2, Users2, Copy, Send, Trash2, Link as LinkIcon,
  KeyRound, RefreshCw, Eye, EyeOff,
} from "lucide-react";
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
import { provisionClientPortal, revokeClientPortal } from "@/lib/client-portal.functions";
import { sendPortalPasswordReset, listClientLoginLogs } from "@/lib/client-portal-admin.functions";
import { ClientTimeline } from "@/components/client-timeline";
import { parsePortalConfig } from "@/lib/client-portal-config";
import { toast } from "sonner";
import { useQuery } from "@tanstack/react-query";

export const Route = createFileRoute("/_authenticated/app/client-portal")({
  component: ClientPortalSetupPage,
});

const SECTIONS = [
  { id: "cases", label: "قضاياي" },
  { id: "sessions", label: "مواعيد الجلسات" },
  { id: "documents", label: "المستندات والأحكام" },
  { id: "powers", label: "الوكالات" },
  { id: "execution", label: "طلبات التنفيذ" },
  { id: "notifications", label: "الإشعارات" },
  { id: "messages", label: "مراسلة المكتب" },
];

function genPassword(len = 10) {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789";
  let out = "";
  for (let i = 0; i < len; i++) out += chars[Math.floor(Math.random() * chars.length)];
  return out;
}

function ClientPortalSetupPage() {
  const qc = useQueryClient();
  const { data: clients = [], isLoading } = useList<any>("clients");
  const { data: cases = [] } = useList<any>("cases");

  const [clientId, setClientId] = useState<string>("");
  const [email, setEmail] = useState("");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [showPwd, setShowPwd] = useState(false);
  const [assignedCases, setAssignedCases] = useState<string[]>([]);
  const [permissions, setPermissions] = useState<string[]>(SECTIONS.map((s) => s.id));
  const [userNotes, setUserNotes] = useState("");
  const [lastResult, setLastResult] = useState<{ access_code: string; email: string } | null>(null);

  const client = useMemo(() => clients.find((c) => c.id === clientId), [clients, clientId]);
  const clientCases = useMemo(
    () => cases.filter((c) => c.client_id === clientId),
    [cases, clientId],
  );

  useEffect(() => {
    if (!client) return;
    const cfg = parsePortalConfig(client.notes);
    setEmail(client.email || "");
    setUsername(cfg.username || client.full_name || "");
    setPassword("");
    setAssignedCases(cfg.assigned_cases.length ? cfg.assigned_cases : []);
    setPermissions(cfg.permissions.length ? cfg.permissions : SECTIONS.map((s) => s.id));
    setUserNotes(cfg.user_notes);
    setLastResult(null);
  }, [client]);

  const provisionFn = useServerFn(provisionClientPortal);
  const revokeFn = useServerFn(revokeClientPortal);

  const save = useMutation({
    mutationFn: async () => provisionFn({
      data: {
        client_id: clientId,
        email,
        password: password || null,
        username: username || null,
        assigned_cases: assignedCases,
        permissions,
        user_notes: userNotes,
      },
    }),
    onSuccess: (res) => {
      toast.success(res.created ? "تم إنشاء حساب البوابة بنجاح" : "تم تحديث بيانات البوابة");
      setLastResult({ access_code: res.access_code, email: res.email });
      qc.invalidateQueries({ queryKey: ["clients"] });
    },
    onError: (e: any) => toast.error(e.message || "تعذّر الحفظ"),
  });

  const revoke = useMutation({
    mutationFn: async (delete_user: boolean) => revokeFn({ data: { client_id: clientId, delete_user } }),
    onSuccess: () => {
      toast.success("تم إلغاء صلاحية البوابة");
      setLastResult(null); setPassword("");
      qc.invalidateQueries({ queryKey: ["clients"] });
    },
    onError: (e: any) => toast.error(e.message || "فشل الإلغاء"),
  });

  // Password reset + login logs
  const resetFn = useServerFn(sendPortalPasswordReset);
  const sendReset = useMutation({
    mutationFn: async () => resetFn({ data: { client_id: clientId, redirect_to: typeof window !== "undefined" ? `${window.location.origin}/auth` : undefined } }),
    onSuccess: () => toast.success("تم إرسال رابط استعادة كلمة المرور"),
    onError: (e: any) => toast.error(e.message || "تعذر إرسال الرابط"),
  });
  const logsFn = useServerFn(listClientLoginLogs);
  const loginLogsQ = useQuery({
    queryKey: ["client-login-logs", clientId],
    queryFn: () => logsFn({ data: { client_id: clientId, limit: 30 } }),
    enabled: !!clientId,
  });

  const portalUrl = typeof window !== "undefined" ? `${window.location.origin}/auth` : "/auth";

  const buildMessage = () =>
    [
      `مرحباً ${client?.full_name || "بك"}،`,
      `تم تفعيل بوابتك على منصة العدالة للاطلاع على بيانات قضاياك.`,
      ``,
      `رابط الدخول: ${portalUrl}`,
      `البريد: ${email}`,
      password ? `كلمة السر: ${password}` : `كلمة السر: (تم إرسالها سابقاً)`,
      lastResult?.access_code ? `رمز البوابة: ${lastResult.access_code}` : "",
      ``,
      `للدخول: افتح الرابط، اختر «عميل»، وأدخل البريد وكلمة السر.`,
    ].filter(Boolean).join("\n");

  const sendWhatsApp = () => {
    const phone = (client?.phone || "").replace(/[^\d]/g, "");
    const text = encodeURIComponent(buildMessage());
    const url = phone ? `https://wa.me/${phone}?text=${text}` : `https://wa.me/?text=${text}`;
    window.open(url, "_blank", "noopener,noreferrer");
  };

  const copyAll = async () => {
    await navigator.clipboard.writeText(buildMessage());
    toast.success("تم نسخ بيانات البوابة");
  };

  const toggle = (list: string[], set: (v: string[]) => void, id: string) => {
    set(list.includes(id) ? list.filter((x) => x !== id) : [...list, id]);
  };

  return (
    <>
      <PageHeader
        icon={ShieldCheck}
        title="بوابة العملاء"
        subtitle="هيّئ حساب دخول حقيقي للعميل واختر القضايا والأقسام التي يطّلع عليها"
        action={
          <Button
            onClick={() => save.mutate()}
            disabled={!clientId || !email || save.isPending}
            className="btn-gold gap-2"
          >
            {save.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
            حفظ وتفعيل البوابة
          </Button>
        }
      />

      {isLoading ? (
        <p className="text-center text-muted-foreground py-10">جارٍ التحميل...</p>
      ) : clients.length === 0 ? (
        <Card className="p-10 text-center">
          <p className="text-muted-foreground">لا يوجد عملاء مسجّلون. أضف العملاء أولاً من «سجل بيانات العملاء».</p>
        </Card>
      ) : (
        <div className="grid gap-6 lg:grid-cols-3">
          {/* Client list */}
          <Card className="card-luxe border-none p-5 lg:col-span-1">
            <div className="flex items-center gap-2 mb-4">
              <Users2 className="h-5 w-5 text-gold" />
              <h3 className="font-bold">اختر العميل</h3>
              <Badge variant="outline" className="mr-auto">{clients.length}</Badge>
            </div>
            <div className="space-y-2 max-h-[520px] overflow-y-auto pr-1">
              {clients.map((c) => {
                const active = (c as any).portal_user_id;
                return (
                  <button
                    key={c.id}
                    onClick={() => setClientId(c.id)}
                    className={`w-full text-right rounded-xl border p-3 transition-all hover:-translate-y-0.5 ${
                      clientId === c.id ? "border-gold bg-gold/10 shadow-lg" : "hover:bg-muted/40"
                    }`}
                  >
                    <div className="flex items-center justify-between">
                      <div className="font-bold text-sm">{c.full_name}</div>
                      {active ? (
                        <Badge className="bg-emerald-500/15 text-emerald-500 border-emerald-500/30">مُفعّل</Badge>
                      ) : (
                        <Badge variant="outline" className="text-muted-foreground">غير مفعّل</Badge>
                      )}
                    </div>
                    <div className="text-[11px] text-muted-foreground mt-1">{c.email || c.phone || "—"}</div>
                  </button>
                );
              })}
            </div>
          </Card>

          {/* Configuration */}
          <Card className="card-luxe border-none p-6 lg:col-span-2">
            {!clientId ? (
              <p className="text-sm text-muted-foreground text-center py-20">
                اختر عميلاً من اليمين لبدء تهيئة البوابة
              </p>
            ) : (
              <div className="space-y-6">
                {/* Credentials */}
                <section>
                  <div className="flex items-center gap-2 mb-3">
                    <KeyRound className="h-4 w-4 text-gold" />
                    <Label className="text-sm font-bold">بيانات الدخول</Label>
                  </div>
                  <div className="grid sm:grid-cols-2 gap-3">
                    <div>
                      <Label className="text-xs">اسم العميل (يظهر للترحيب)</Label>
                      <Input value={username} onChange={(e) => setUsername(e.target.value)} placeholder="اسم العرض" />
                    </div>
                    <div>
                      <Label className="text-xs">البريد الإلكتروني (اسم المستخدم)</Label>
                      <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="client@example.com" />
                    </div>
                    <div className="sm:col-span-2">
                      <Label className="text-xs">كلمة السر {client?.portal_user_id ? "(اتركها فارغة للإبقاء على الحالية)" : "(مطلوبة لإنشاء الحساب)"}</Label>
                      <div className="flex gap-2">
                        <div className="relative flex-1">
                          <Input
                            type={showPwd ? "text" : "password"}
                            value={password}
                            onChange={(e) => setPassword(e.target.value)}
                            placeholder="6 أحرف على الأقل"
                          />
                          <button type="button" onClick={() => setShowPwd((v) => !v)}
                            className="absolute left-2 top-1/2 -translate-y-1/2 p-1 text-muted-foreground hover:text-foreground">
                            {showPwd ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                          </button>
                        </div>
                        <Button type="button" variant="outline" onClick={() => { const p = genPassword(); setPassword(p); setShowPwd(true); }} className="gap-1">
                          <RefreshCw className="h-3.5 w-3.5" /> توليد
                        </Button>
                      </div>
                    </div>
                  </div>
                  {client?.portal_user_id && (
                    <div className="mt-3 flex items-center justify-between rounded-lg border border-dashed p-3 bg-muted/30">
                      <div className="text-xs text-muted-foreground">
                        إرسال رابط استعادة كلمة المرور إلى بريد العميل.
                      </div>
                      <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        onClick={() => sendReset.mutate()}
                        disabled={sendReset.isPending || !client?.email}
                      >
                        {sendReset.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <KeyRound className="h-3.5 w-3.5" />}
                        <span className="ms-1">إرسال رابط استعادة</span>
                      </Button>
                    </div>
                  )}
                </section>

                <Separator />

                {/* Login logs + timeline */}
                {client?.portal_user_id && (
                  <section className="grid lg:grid-cols-2 gap-4">
                    <div>
                      <Label className="text-sm font-bold mb-2 block">سجل الدخول</Label>
                      <div className="rounded-lg border p-2 max-h-64 overflow-y-auto">
                        {loginLogsQ.isLoading ? (
                          <p className="text-xs text-muted-foreground p-2"><Loader2 className="inline h-3 w-3 animate-spin" /> جاري التحميل…</p>
                        ) : (loginLogsQ.data?.rows ?? []).length === 0 ? (
                          <p className="text-xs text-muted-foreground p-2">لا توجد سجلات بعد.</p>
                        ) : (
                          <ul className="space-y-1 text-xs">
                            {(loginLogsQ.data?.rows ?? []).map((r) => (
                              <li key={r.id} className="flex items-center justify-between border-b last:border-0 py-1.5">
                                <span className="font-medium">{r.action}</span>
                                <span className="text-muted-foreground">{new Date(r.created_at).toLocaleString("ar-SA")}</span>
                              </li>
                            ))}
                          </ul>
                        )}
                      </div>
                    </div>
                    <div>
                      <Label className="text-sm font-bold mb-2 block">الخط الزمني للعميل</Label>
                      <div className="rounded-lg border p-3 max-h-64 overflow-y-auto">
                        <ClientTimeline clientId={clientId} />
                      </div>
                    </div>
                  </section>
                )}

                <Separator />

                {/* Cases */}
                <section>
                  <Label className="text-sm font-bold mb-3 block">القضايا التي يطّلع عليها العميل</Label>
                  {clientCases.length === 0 ? (
                    <p className="text-xs text-muted-foreground">لا توجد قضايا مرتبطة بهذا العميل. اربط قضية أولاً من قسم القضايا.</p>
                  ) : (
                    <div className="grid sm:grid-cols-2 gap-2 max-h-56 overflow-y-auto">
                      <label className="flex items-center gap-2 rounded-lg border border-dashed p-2.5 hover:bg-muted/40 cursor-pointer">
                        <Checkbox
                          checked={assignedCases.length === 0}
                          onCheckedChange={() => setAssignedCases([])}
                        />
                        <span className="text-xs font-bold">كل قضاياه (افتراضي)</span>
                      </label>
                      {clientCases.map((c) => (
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
                </section>

                <Separator />

                {/* Sections */}
                <section>
                  <Label className="text-sm font-bold mb-3 block">الأقسام الظاهرة في بوابته</Label>
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
                </section>

                <Separator />

                <section>
                  <Label className="text-sm font-bold mb-2 block">ملاحظات داخلية (لا تظهر للعميل)</Label>
                  <Textarea value={userNotes} onChange={(e) => setUserNotes(e.target.value)} rows={2} />
                </section>

                {/* Share box */}
                {lastResult && (
                  <Card className="p-4 border-gold/30 bg-gold/5">
                    <div className="flex items-center gap-2 mb-3">
                      <LinkIcon className="h-4 w-4 text-gold" />
                      <span className="font-bold text-sm">بيانات البوابة جاهزة للإرسال</span>
                    </div>
                    <div className="grid sm:grid-cols-2 gap-3 text-xs mb-3">
                      <div><span className="text-muted-foreground">الرابط:</span> <code className="bg-background px-2 py-0.5 rounded">{portalUrl}</code></div>
                      <div><span className="text-muted-foreground">البريد:</span> <code className="bg-background px-2 py-0.5 rounded">{lastResult.email}</code></div>
                      <div><span className="text-muted-foreground">رمز البوابة:</span> <code className="bg-background px-2 py-0.5 rounded">{lastResult.access_code}</code></div>
                      {password && <div><span className="text-muted-foreground">كلمة السر:</span> <code className="bg-background px-2 py-0.5 rounded">{password}</code></div>}
                    </div>
                    <div className="flex flex-wrap gap-2">
                      <Button size="sm" variant="outline" onClick={copyAll} className="gap-1"><Copy className="h-3.5 w-3.5" /> نسخ الرسالة</Button>
                      <Button size="sm" onClick={sendWhatsApp} className="gap-1 bg-emerald-600 hover:bg-emerald-700 text-white"><Send className="h-3.5 w-3.5" /> إرسال واتساب</Button>
                      <Button size="sm" variant="destructive" onClick={() => revoke.mutate(false)} disabled={revoke.isPending} className="gap-1 mr-auto">
                        <Trash2 className="h-3.5 w-3.5" /> إلغاء البوابة
                      </Button>
                    </div>
                  </Card>
                )}
              </div>
            )}
          </Card>
        </div>
      )}
    </>
  );
}
