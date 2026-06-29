import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Network, Download, ShieldCheck, KeyRound, Trash2, RefreshCw, Loader2, AlertCircle, CheckCircle2, RotateCw, Clock } from "lucide-react";
import { PageHeader } from "@/components/section-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { issueSyncToken, najizHealthCheck, revokeSyncToken } from "@/lib/najiz.functions";
import { retryNajizSyncLog, syncNajizExecutions } from "@/lib/portal.functions";

export const Route = createFileRoute("/_authenticated/app/najiz")({
  component: NajizPage,
});

type HealthResult = { ok: boolean; status: number; latency_ms: number; message: string };
type ConnTestResult = { ok: boolean; message: string; status?: number };

/**
 * Detect the correct base URL the extension must use to reach /api/public/najiz-sync.
 * The Lovable preview URL (id-preview--<id>.lovable.app) is access-gated and does NOT
 * serve the API route, so we auto-convert it to the stable runtime URL
 * (project--<id>-dev.lovable.app). Published / custom domains are used as-is.
 */
function detectSyncBaseUrl(): string {
  if (typeof window === "undefined") return "";
  const origin = window.location.origin;
  const m = origin.match(/^https?:\/\/id-preview--([a-z0-9-]+)\.lovable\.app$/i);
  if (m) return `https://project--${m[1]}-dev.lovable.app`;
  return origin;
}

/** The raw browser origin (may be a gated preview URL). */
function rawOrigin(): string {
  if (typeof window === "undefined") return "";
  return window.location.origin;
}

function NajizPage() {
  const qc = useQueryClient();
  const [health, setHealth] = useState<HealthResult | null>(null);
  const [issuedToken, setIssuedToken] = useState<string | null>(null);
  const [tokenLabel, setTokenLabel] = useState("Chrome Extension");
  const [syncBaseUrl] = useState<string>(() => detectSyncBaseUrl());
  const [previewOrigin] = useState<string>(() => rawOrigin());
  const [testToken, setTestToken] = useState("");
  const [connResult, setConnResult] = useState<ConnTestResult | null>(null);
  const isConverted = previewOrigin !== syncBaseUrl && /id-preview--/.test(previewOrigin);

  const copy = (value: string, label: string) => {
    navigator.clipboard.writeText(value);
    toast.success(label);
  };

  // Connection test: GET the public sync endpoint with the token header. Verifies
  // BOTH that the Base URL is reachable and that the token is valid — before sync.
  const connTest = useMutation({
    mutationFn: async (): Promise<ConnTestResult> => {
      const token = (testToken || issuedToken || "").trim();
      const url = `${syncBaseUrl}/api/public/najiz-sync`;
      let res: Response;
      try {
        res = await fetch(url, {
          method: "GET",
          headers: token ? { "X-Sync-Token": token, Accept: "application/json" } : { Accept: "application/json" },
          cache: "no-store",
        });
      } catch (e: any) {
        return { ok: false, message: `تعذّر الوصول إلى الرابط (${url}). تأكد من اتصال الإنترنت وأن الرابط صحيح.` };
      }
      const text = await res.text();
      // Endpoint not reached — gated preview returns the HTML app shell instead of JSON.
      if (/Only HTML requests are supported here/i.test(text) || /No published build/i.test(text) || /<!DOCTYPE html/i.test(text)) {
        return { ok: false, status: res.status, message: "الرابط لا يصل إلى واجهة المزامنة (أعاد صفحة HTML بدل بيانات). استخدم الرابط الثابت المعروض أعلاه وليس رابط المعاينة." };
      }
      let data: any = null;
      try { data = JSON.parse(text); } catch { /* non-JSON */ }
      if (!data) {
        return { ok: false, status: res.status, message: `استجابة غير متوقعة من الخادم (HTTP ${res.status}). تأكد من صحة الرابط.` };
      }
      if (data.ok) {
        const note = data.authenticated ? "" : " (لم يتم التحقق من الرمز — أدخل رمزاً لاختباره)";
        return { ok: true, status: res.status, message: (data.message || "الاتصال سليم") + note };
      }
      return { ok: false, status: res.status, message: data?.error?.message || `فشل الاختبار (HTTP ${res.status}).` };
    },
    onSuccess: (r) => {
      setConnResult(r);
      if (r.ok) toast.success(r.message); else toast.error(r.message);
    },
    onError: (e: any) => {
      const r = { ok: false, message: e?.message || "فشل اختبار الاتصال" };
      setConnResult(r);
      toast.error(r.message);
    },
  });

  const tokens = useQuery({
    queryKey: ["sync_tokens"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("sync_tokens").select("*").order("created_at", { ascending: false });
      if (error) throw error;
      return data ?? [];
    },
  });

  const logs = useQuery({
    queryKey: ["najiz_sync_logs"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("najiz_sync_logs").select("*").order("created_at", { ascending: false }).limit(50);
      if (error) throw error;
      return data ?? [];
    },
  });

  const retry = useMutation({
    mutationFn: async (id: string) => await retryNajizSyncLog({ data: { id } }),
    onSuccess: async () => {
      toast.info("جارٍ إعادة المحاولة...");
      try {
        const r = await syncNajizExecutions();
        toast.success(`تمت المعالجة — ${r.inserted} جديد · ${r.updated} محدّث`);
      } catch (e: any) {
        toast.error(e.message || "فشل تشغيل المزامنة");
      }
      qc.invalidateQueries({ queryKey: ["najiz_sync_logs"] });
      qc.invalidateQueries({ queryKey: ["executions"] });
    },
    onError: (e: any) => toast.error(e.message || "فشل إعادة المحاولة"),
  });

  const healthCheck = useMutation({
    mutationFn: async () => await najizHealthCheck(),
    onSuccess: (res) => {
      setHealth(res);
      if (res.ok) toast.success(res.message);
      else toast.error(res.message);
    },
    onError: (err: any) => toast.error(err.message || "فشل التحقق"),
  });

  const issueMutation = useMutation({
    mutationFn: async () => await issueSyncToken({ data: { label: tokenLabel } }),
    onSuccess: (res) => {
      setIssuedToken(res.token);
      toast.success("تم إصدار رمز جديد — احفظه فوراً");
      qc.invalidateQueries({ queryKey: ["sync_tokens"] });
    },
    onError: (err: any) => toast.error(err.message || "فشل إصدار الرمز"),
  });

  const revokeMutation = useMutation({
    mutationFn: async (id: string) => await revokeSyncToken({ data: { id } }),
    onSuccess: () => {
      toast.success("تم إلغاء الرمز");
      qc.invalidateQueries({ queryKey: ["sync_tokens"] });
    },
  });

  const handleDownload = async () => {
    const url = "/najiz-helper.zip";
    toast.info("جارٍ تنزيل الإضافة...");
    console.log("[najiz] downloading extension from", url);
    try {
      const res = await fetch(url, { cache: "no-store" });
      console.log("[najiz] fetch status", res.status, res.statusText);
      if (!res.ok) {
        toast.error(`فشل التنزيل: ${res.status} ${res.statusText}`);
        return;
      }
      const blob = await res.blob();
      console.log("[najiz] blob size", blob.size, "type", blob.type);
      if (blob.size < 1000) {
        toast.error("ملف الإضافة غير صالح (حجم صغير جداً)");
        return;
      }
      // Validate ZIP contains required files (magic byte check + size threshold)
      const head = new Uint8Array(await blob.slice(0, 4).arrayBuffer());
      if (!(head[0] === 0x50 && head[1] === 0x4b)) {
        toast.error("الملف ليس بصيغة ZIP صالحة");
        return;
      }
      const link = document.createElement("a");
      link.href = URL.createObjectURL(blob);
      link.download = "adala-najiz-extension.zip";
      document.body.appendChild(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(link.href), 5000);
      toast.success("تم تنزيل الإضافة بنجاح");
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error("[najiz] download error", err);
      toast.error("فشل تنزيل الإضافة: " + msg);
    }
  };

  return (
    <>
        <PageHeader
        icon={Network}
        title="تكامل ناجز"
        subtitle="أداة هجينة متكاملة (RPA + بوت تلقائي + قراءة شاشة) لسحب القضايا والوكالات والتنفيذ والجلسات تلقائياً"
        action={
          <Button onClick={() => healthCheck.mutate()} disabled={healthCheck.isPending} className="gap-2" variant="outline">
            {healthCheck.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <ShieldCheck className="h-4 w-4" />}
            فحص حالة بوابة ناجز
          </Button>
        }
      />

      {/* Health result */}
      {health && (
        <Card className={`card-3d border-none p-4 mb-6 ${health.ok ? "bg-emerald-500/5" : "bg-destructive/5"}`}>
          <div className="flex items-center gap-3">
            {health.ok ? <CheckCircle2 className="h-6 w-6 text-emerald-500" /> : <AlertCircle className="h-6 w-6 text-destructive" />}
            <div className="flex-1">
              <div className="font-bold text-sm">{health.message}</div>
              <div className="text-xs text-muted-foreground mt-0.5">
                الحالة: {health.status || "—"} · زمن الاستجابة: {health.latency_ms}ms
              </div>
            </div>
            <Badge variant={health.ok ? "default" : "destructive"}>
              {health.ok ? "متصل" : "غير متاح"}
            </Badge>
          </div>
        </Card>
      )}

      <div className="grid gap-6 lg:grid-cols-2">
        {/* Download extension */}
        <Card className="card-3d border-none p-6">
          <div className="flex items-start justify-between mb-4">
            <div>
              <h3 className="font-bold text-lg">إضافة متصفح Chrome v4.1</h3>
              <p className="text-xs text-muted-foreground mt-1">إصدار محسّن: سكرابرز جداول هجينة + fallback مرن للقضايا والجلسات + إصلاح الإدراج في قاعدة البيانات. البوت يفتح ناجز، ينتظر نفاذ، يسحب كل البيانات ويرسلها للنظام بصيغة API الصحيحة.</p>
            </div>
            <div className="grid h-12 w-12 place-items-center rounded-xl bg-primary/10">
              <Download className="h-6 w-6 text-primary" />
            </div>
          </div>
          <ol className="text-xs text-muted-foreground space-y-2 mb-4 pr-4">
            <li>1. حمّل ملف الإضافة (ZIP) وفك ضغطها</li>
            <li>2. أنشئ رمز مزامنة (Sync Token) من اليسار</li>
            <li>3. ثبّت الإضافة في Chrome (الوضع المطوّر — chrome://extensions)</li>
            <li>4. افتح الإضافة، أدخل الرابط والرمز، ثم اضغط <strong>"فتح ناجز وتشغيل البوت"</strong></li>
            <li>5. البوت يفتح ناجز → ينتظر تسجيل دخولك عبر نفاذ → يسحب كل البيانات تلقائياً</li>
          </ol>
          <div className="text-[10px] text-muted-foreground bg-primary/5 border border-primary/20 rounded-lg p-2 mb-3">
            <strong>آلية العمل:</strong> البوت يفتح المتصفح ← ينتظر تسجيل الدخول يدوياً (نفاذ) ← يتنقل تلقائياً بين (القضايا/الأحكام/القرارات/الطلبات/التنفيذ/الوكالات/الجلسات) ← يمرر كل صفحة ← يسحب البيانات ← يرسلها للنظام ← النظام يوزعها على الأقسام المخصصة
          </div>
          <Button onClick={handleDownload} className="btn-gold gap-2 w-full" data-testid="download-extension-btn">
            <Download className="h-4 w-4" /> تنزيل الإضافة v4.1 (ZIP)
          </Button>
        </Card>

        {/* Sync tokens */}
        <Card className="card-3d border-none p-6">
          <div className="flex items-start justify-between mb-4">
            <div>
              <h3 className="font-bold text-lg">مفتاح الربط (API Key) ورموز المزامنة</h3>
              <p className="text-xs text-muted-foreground mt-1">أنشئ مفتاحاً سرياً تستخدمه الأداة للاتصال بمنصتك بأمان — انسخ المفتاح والرابط معاً في إعدادات الأداة</p>
            </div>
            <div className="grid h-12 w-12 place-items-center rounded-xl bg-gold/15">
              <KeyRound className="h-6 w-6 text-gold" />
            </div>
          </div>

          {/* Persistent Base URL — auto-detected correct endpoint, always visible beside the key */}
          <div className="rounded-lg border border-primary/30 bg-primary/5 p-3 mb-3">
            <div className="flex items-center justify-between gap-2 mb-1">
              <div className="text-[10px] font-bold text-foreground">رابط المنصة الصحيح (Base URL) — يُكتشف تلقائياً · أدخله في إعدادات الأداة</div>
              <Button size="sm" variant="ghost" className="h-6 px-2 text-[10px]" onClick={() => copy(syncBaseUrl, "تم نسخ الرابط")}>نسخ الرابط</Button>
            </div>
            <code className="text-xs break-all block bg-background p-2 rounded border" dir="ltr">{syncBaseUrl}</code>

            {/* Show both original preview link and the converted stable URL with explanation */}
            {isConverted && (
              <div className="mt-2 rounded border border-border/60 bg-muted/40 p-2 space-y-1">
                <div className="text-[10px] text-muted-foreground">
                  رابط المعاينة الحالي مُقيَّد بتسجيل الدخول ولا يخدم واجهة المزامنة، لذلك حوّلناه تلقائياً إلى الرابط الثابت أعلاه.
                </div>
                <div className="text-[10px] font-bold text-muted-foreground">رابط المعاينة الأصلي (لا تستخدمه في الأداة):</div>
                <code className="text-[10px] break-all block bg-background/60 p-1.5 rounded border text-muted-foreground line-through" dir="ltr">{previewOrigin}</code>
              </div>
            )}
          </div>

          <div className="flex gap-2 mb-3">
            <Input value={tokenLabel} onChange={(e) => setTokenLabel(e.target.value)} placeholder="وصف الرمز" className="text-right" />
            <Button onClick={() => issueMutation.mutate()} disabled={issueMutation.isPending} className="btn-gold">
              {issueMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : "إنشاء"}
            </Button>
          </div>
          {issuedToken && (
            <div className="rounded-lg border border-gold/30 bg-gold/5 p-3 mb-3">
              <div className="text-[10px] font-bold text-gold mb-1">⚠️ احفظ هذا الرمز الآن — لن يظهر مرة أخرى</div>
              <code className="text-xs break-all block bg-background p-2 rounded border">{issuedToken}</code>
              <div className="flex gap-2 mt-2">
                <Button size="sm" variant="ghost" className="h-7 text-xs" onClick={() => {
                  navigator.clipboard.writeText(issuedToken);
                  toast.success("تم نسخ المفتاح");
                }}>نسخ المفتاح</Button>
                <Button size="sm" variant="ghost" className="h-7 text-xs" onClick={() => copy(syncBaseUrl, "تم نسخ الرابط")}>نسخ الرابط</Button>
                <Button size="sm" variant="ghost" className="h-7 text-xs" onClick={() => {
                  navigator.clipboard.writeText(`Base URL: ${syncBaseUrl}\nAPI Key: ${issuedToken}`);
                  toast.success("تم نسخ الإعدادات كاملة");
                }}>نسخ الإعدادات كاملة</Button>
              </div>
            </div>
          )}

          {/* Connection test — verify Base URL + token reachability before syncing */}
          <div className="rounded-lg border border-border/60 bg-card/50 p-3 mb-3">
            <div className="text-[10px] font-bold text-foreground mb-2">اختبار الاتصال — تحقّق من الرابط والرمز قبل بدء المزامنة</div>
            <div className="flex gap-2">
              <Input
                value={testToken}
                onChange={(e) => setTestToken(e.target.value)}
                placeholder={issuedToken ? "سيُستخدم الرمز المُصدَر — أو ألصق رمزاً للاختبار" : "ألصق رمز المزامنة للاختبار"}
                className="text-right h-9 text-xs"
                dir="ltr"
              />
              <Button onClick={() => connTest.mutate()} disabled={connTest.isPending} variant="outline" className="h-9 gap-1 text-xs whitespace-nowrap">
                {connTest.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <ShieldCheck className="h-4 w-4" />}
                اختبار الاتصال
              </Button>
            </div>
            {connResult && (
              <div className={`mt-2 flex items-start gap-2 rounded p-2 text-[11px] ${connResult.ok ? "bg-emerald-500/10 text-emerald-600" : "bg-destructive/10 text-destructive"}`}>
                {connResult.ok ? <CheckCircle2 className="h-4 w-4 mt-0.5 shrink-0" /> : <AlertCircle className="h-4 w-4 mt-0.5 shrink-0" />}
                <span>{connResult.message}</span>
              </div>
            )}
          </div>

          <div className="space-y-2 max-h-56 overflow-y-auto">
            {tokens.data?.length === 0 && <p className="text-xs text-muted-foreground text-center py-4">لا توجد رموز بعد</p>}
            {tokens.data?.map((t: any) => (
              <div key={t.id} className="flex items-center justify-between gap-2 rounded-lg border bg-card/50 p-2.5">
                <div className="flex-1 min-w-0">
                  <div className="text-xs font-bold">{t.label}</div>
                  <div className="text-[10px] mt-0.5">
                    {t.is_revoked ? (
                      <Badge variant="destructive" className="h-4 px-1.5 text-[9px]">ملغى</Badge>
                    ) : t.last_used_at ? (
                      <Badge variant="default" className="h-4 px-1.5 text-[9px] gap-1">
                        <CheckCircle2 className="h-2.5 w-2.5" /> استُخدم: {new Date(t.last_used_at).toLocaleString("ar-SA")}
                      </Badge>
                    ) : (
                      <Badge variant="outline" className="h-4 px-1.5 text-[9px] gap-1">
                        <Clock className="h-2.5 w-2.5" /> لم يُستخدم بعد
                      </Badge>
                    )}
                  </div>
                </div>
                {!t.is_revoked && (
                  <Button size="icon" variant="ghost" className="h-7 w-7 text-destructive" onClick={() => revokeMutation.mutate(t.id)}>
                    <Trash2 className="h-3.5 w-3.5" />
                  </Button>
                )}
              </div>
            ))}
          </div>
        </Card>
      </div>

      {/* Sync logs */}
      <Card className="card-3d border-none p-6 mt-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="font-bold text-lg">سجلات المزامنة الأخيرة</h3>
          <Button size="sm" variant="ghost" onClick={() => qc.invalidateQueries({ queryKey: ["najiz_sync_logs"] })} className="gap-2">
            <RefreshCw className="h-4 w-4" /> تحديث
          </Button>
        </div>
        {(() => {
          const counts = (logs.data ?? []).reduce((a: any, l: any) => {
            a[l.status] = (a[l.status] ?? 0) + 1; return a;
          }, {} as Record<string, number>);
          return (
            <div className="flex flex-wrap gap-2 mb-3 text-xs">
              <Badge variant="default" className="gap-1"><CheckCircle2 className="h-3 w-3" />نجاح: {counts.success ?? 0}</Badge>
              <Badge variant="destructive" className="gap-1"><AlertCircle className="h-3 w-3" />فشل: {counts.failed ?? 0}</Badge>
              <Badge variant="outline" className="gap-1"><Clock className="h-3 w-3" />قيد المعالجة: {counts.pending ?? 0}</Badge>
            </div>
          );
        })()}
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="text-right text-muted-foreground border-b">
                <th className="py-2 px-2 font-bold">التاريخ</th>
                <th className="py-2 px-2 font-bold">النوع</th>
                <th className="py-2 px-2 font-bold">الحالة</th>
                <th className="py-2 px-2 font-bold">العناصر</th>
                <th className="py-2 px-2 font-bold">مُدرج / مُحدّث</th>
                <th className="py-2 px-2 font-bold">رسالة الخطأ</th>
                <th className="py-2 px-2 font-bold">إجراء</th>
              </tr>
            </thead>
            <tbody>
              {logs.data?.length === 0 && (
                <tr><td colSpan={7} className="text-center py-6 text-muted-foreground">لا توجد سجلات بعد</td></tr>
              )}
              {logs.data?.map((l: any) => {
                const canRetry = l.status === "pending" || l.status === "failed";
                return (
                  <tr key={l.id} className="border-t border-border/50">
                    <td className="py-2 px-2">{new Date(l.created_at).toLocaleString("ar-SA")}</td>
                    <td className="py-2 px-2"><Badge variant="outline">{l.kind}</Badge></td>
                    <td className="py-2 px-2">
                      {l.status === "success" ? (
                        <Badge variant="default" className="gap-1"><CheckCircle2 className="h-3 w-3" />نجاح</Badge>
                      ) : l.status === "pending" ? (
                        <Badge variant="outline" className="gap-1"><Clock className="h-3 w-3" />قيد المعالجة</Badge>
                      ) : (
                        <Badge variant="destructive" className="gap-1"><AlertCircle className="h-3 w-3" />فشل</Badge>
                      )}
                    </td>
                    <td className="py-2 px-2">{l.items_count ?? 0}</td>
                    <td className="py-2 px-2">{l.inserted_count ?? 0} / {l.updated_count ?? 0}</td>
                    <td className="py-2 px-2 text-muted-foreground max-w-xs truncate" title={l.error_message || ""}>
                      {l.error_message || "—"}
                    </td>
                    <td className="py-2 px-2">
                      {canRetry ? (
                        <Button
                          size="sm" variant="outline"
                          className="h-7 gap-1 text-xs"
                          onClick={() => retry.mutate(l.id)}
                          disabled={retry.isPending}
                        >
                          {retry.isPending ? <Loader2 className="h-3 w-3 animate-spin" /> : <RotateCw className="h-3 w-3" />}
                          إعادة المحاولة
                        </Button>
                      ) : <span className="text-muted-foreground">—</span>}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </Card>
    </>
  );
}
