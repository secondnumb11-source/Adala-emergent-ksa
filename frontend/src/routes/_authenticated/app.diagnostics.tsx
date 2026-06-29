import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { useServerFn } from "@tanstack/react-start";
import { supabase } from "@/integrations/supabase/client";
import { getCronJobsStatusFn, runEnqueueSessionReminders } from "@/lib/system-check.functions";
import { PageHeader } from "@/components/section-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Activity, CheckCircle2, XCircle, Loader2, PlayCircle, Clock, Database, Eye, EyeOff } from "lucide-react";
import { toast } from "sonner";


export const Route = createFileRoute("/_authenticated/app/diagnostics")({
  component: DiagnosticsPage,
});

type ConnInfo = {
  url: string | null;
  hostname: string | null;
  projectRef: string | null;
  anonKeyPreview: string | null;
  pingMs: number | null;
  pingOk: boolean | null;
  pingError: string | null;
  rowsSeen: number | null;
};

function maskKey(k?: string | null) {
  if (!k) return null;
  if (k.length <= 14) return "•".repeat(k.length);
  return `${k.slice(0, 8)}…${k.slice(-6)}`;
}

function extractProjectRef(url: string | null): string | null {
  if (!url) return null;
  try {
    const host = new URL(url).hostname;
    const m = host.match(/^([a-z0-9]+)\.supabase\.co$/i);
    return m ? m[1] : host;
  } catch { return null; }
}

type Check = { name: string; ok: boolean | null; detail?: string };
type CronRow = {
  jobid: number;
  jobname: string;
  schedule: string;
  active: boolean;
  last_start: string | null;
  last_status: string | null;
  last_message: string | null;
};

function Row({ check }: { check: Check }) {
  return (
    <div className="flex items-center justify-between border-b last:border-0 py-2 text-sm">
      <span className="font-medium">{check.name}</span>
      <div className="flex items-center gap-2">
        {check.detail && <span className="text-xs text-muted-foreground">{check.detail}</span>}
        {check.ok === null ? (
          <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
        ) : check.ok ? (
          <Badge variant="default" className="gap-1"><CheckCircle2 className="h-3 w-3" /> سليم</Badge>
        ) : (
          <Badge variant="destructive" className="gap-1"><XCircle className="h-3 w-3" /> مشكلة</Badge>
        )}
      </div>
    </div>
  );
}

function DiagnosticsPage() {
  const [checks, setChecks] = useState<Check[]>([]);
  const [running, setRunning] = useState(false);
  const [cronJobs, setCronJobs] = useState<CronRow[] | null>(null);
  const [cronErr, setCronErr] = useState<string | null>(null);
  const [cronLoading, setCronLoading] = useState(false);
  const [triggering, setTriggering] = useState(false);
  const [triggerError, setTriggerError] = useState<string | null>(null);
  const [conn, setConn] = useState<ConnInfo | null>(null);
  const [revealKey, setRevealKey] = useState(false);

  async function loadConnection() {
    const url = (import.meta.env.VITE_SUPABASE_URL as string | undefined) ?? null;
    const anon =
      (import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined) ??
      (import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined) ??
      null;
    const hostname = (() => { try { return url ? new URL(url).hostname : null; } catch { return null; } })();
    const projectRef = extractProjectRef(url);
    const t0 = performance.now();
    const { data, error, count } = await supabase
      .from("profiles")
      .select("id", { count: "exact", head: true });
    const dt = Math.round(performance.now() - t0);
    void data;
    setConn({
      url,
      hostname,
      projectRef,
      anonKeyPreview: anon,
      pingMs: dt,
      pingOk: !error,
      pingError: error?.message ?? null,
      rowsSeen: count ?? null,
    });
  }


  async function runChecks() {
    setRunning(true);
    const next: Check[] = [];
    const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
    next.push({ name: "Supabase URL", ok: !!url, detail: url ? new URL(url).hostname : "غير محدد" });

    const { data: userRes } = await supabase.auth.getUser();
    next.push({ name: "جلسة المستخدم", ok: !!userRes.user, detail: userRes.user?.email ?? "غير مسجل" });

    const { error: dbErr } = await supabase.from("profiles").select("id").limit(1);
    next.push({ name: "قراءة من قاعدة البيانات", ok: !dbErr, detail: dbErr?.message });

    try {
      const r = await fetch("/api/ai-chat", { method: "OPTIONS" });
      next.push({ name: "AI Gateway", ok: r.status < 500, detail: `HTTP ${r.status}` });
    } catch (e) {
      next.push({ name: "AI Gateway", ok: false, detail: (e as Error).message });
    }

    try {
      const rpcRes = await fetch("/api/public/system-check");
      next.push({ name: "RPC system-check endpoint", ok: rpcRes.ok, detail: `HTTP ${rpcRes.status}` });
    } catch (e) {
      next.push({ name: "RPC system-check endpoint", ok: false, detail: (e as Error).message });
    }

    setChecks(next);
    setRunning(false);
  }

  const callCronStatus = useServerFn(getCronJobsStatusFn);
  const callEnqSession = useServerFn(runEnqueueSessionReminders);

  async function loadCronJobs() {
    setCronLoading(true);
    setCronErr(null);
    try {
      const data = await callCronStatus();
      setCronJobs((data as unknown as CronRow[]) ?? []);
    } catch (e) {
      setCronErr((e as Error).message);
      setCronJobs(null);
    } finally {
      setCronLoading(false);
    }
  }

  async function triggerSessionReminders() {
    setTriggering(true);
    setTriggerError(null);
    try {
      const data = await callEnqSession();
      setTriggerError(null);
      toast.success(`تم تشغيل تذكيرات الجلسات يدوياً (نتيجة: ${JSON.stringify(data)})`);
      loadCronJobs();
    } catch (e) {
      const m = (e as Error).message;
      const msg = /permission|denied|not authorized|forbidden/i.test(m)
        ? `لا تملك صلاحية كافية: ${m}` : `فشل التشغيل: ${m}`;
      setTriggerError(msg);
      toast.error(msg);
    } finally {
      setTriggering(false);
    }
  }


  useEffect(() => {
    runChecks();
    loadCronJobs();
    loadConnection();
  }, []);

  return (
    <div className="space-y-6" dir="rtl">
      <PageHeader icon={Activity} title="تشخيص النظام" subtitle="فحص حالة المصادقة، قاعدة البيانات، الذكاء الاصطناعي، والمهام المجدولة" />

      <Card className="p-4" data-testid="connection-info-card">
        <div className="flex items-center justify-between mb-3">
          <h3 className="font-semibold flex items-center gap-2"><Database className="h-4 w-4" /> الاتصال بقاعدة البيانات (Supabase)</h3>
          <Button onClick={loadConnection} size="sm" variant="outline">إعادة الاختبار</Button>
        </div>
        {conn === null ? (
          <div className="text-sm text-muted-foreground"><Loader2 className="inline h-4 w-4 animate-spin" /> جارٍ الفحص…</div>
        ) : (
          <div className="grid gap-2 text-sm sm:grid-cols-2">
            <div className="flex justify-between border-b py-1.5"><span className="text-muted-foreground">Project Ref</span><code data-testid="conn-project-ref" className="font-mono">{conn.projectRef ?? "—"}</code></div>
            <div className="flex justify-between border-b py-1.5"><span className="text-muted-foreground">Hostname</span><code data-testid="conn-hostname" className="font-mono">{conn.hostname ?? "—"}</code></div>
            <div className="flex justify-between border-b py-1.5 sm:col-span-2"><span className="text-muted-foreground">SUPABASE_URL</span><code data-testid="conn-url" className="font-mono break-all">{conn.url ?? "غير محدد"}</code></div>
            <div className="flex items-center justify-between border-b py-1.5 sm:col-span-2">
              <span className="text-muted-foreground">Publishable / anon key</span>
              <div className="flex items-center gap-2">
                <code data-testid="conn-anon-key" className="font-mono text-xs">
                  {revealKey ? (conn.anonKeyPreview ?? "—") : maskKey(conn.anonKeyPreview) ?? "—"}
                </code>
                <Button size="icon" variant="ghost" className="h-6 w-6" onClick={() => setRevealKey(v => !v)}>
                  {revealKey ? <EyeOff className="h-3.5 w-3.5" /> : <Eye className="h-3.5 w-3.5" />}
                </Button>
              </div>
            </div>
            <div className="flex justify-between border-b py-1.5"><span className="text-muted-foreground">استعلام تجريبي (profiles)</span>
              {conn.pingOk ? (
                <Badge variant="default" data-testid="conn-ping-ok" className="gap-1"><CheckCircle2 className="h-3 w-3" /> نجاح · {conn.pingMs}ms</Badge>
              ) : (
                <Badge variant="destructive" data-testid="conn-ping-fail" className="gap-1"><XCircle className="h-3 w-3" /> فشل</Badge>
              )}
            </div>
            <div className="flex justify-between border-b py-1.5"><span className="text-muted-foreground">عدد السجلات المرئية</span><span>{conn.rowsSeen ?? "—"}</span></div>
            {conn.pingError && (
              <div className="sm:col-span-2 text-xs text-destructive">خطأ: {conn.pingError}</div>
            )}
          </div>
        )}
        <p className="mt-3 text-[11px] text-muted-foreground">
          متاحة للمطوّرين/المشرفين فقط — تستعرض المتغيرات البيئية العامة (VITE_*) فقط، ولا تكشف عن المفاتيح السرية.
        </p>
      </Card>

      <Card className="p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="font-semibold">الفحوصات الأساسية</h3>
          <Button onClick={runChecks} disabled={running} size="sm">
            {running ? <Loader2 className="h-4 w-4 animate-spin" /> : "إعادة الفحص"}
          </Button>
        </div>
        <div className="space-y-1">
          {checks.map((c) => <Row key={c.name} check={c} />)}
        </div>
      </Card>

      <Card className="p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="font-semibold">المهام المجدولة (pg_cron)</h3>
          <div className="flex gap-2">
            <Button onClick={loadCronJobs} disabled={cronLoading} size="sm" variant="outline">
              {cronLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : "تحديث"}
            </Button>
            <Button onClick={triggerSessionReminders} disabled={triggering} size="sm" className="gap-1">
              {triggering ? <Loader2 className="h-4 w-4 animate-spin" /> : <PlayCircle className="h-4 w-4" />}
              تشغيل تذكيرات الجلسات الآن
            </Button>
          </div>
        </div>

        {triggerError && (
          <div data-testid="trigger-error" className="rounded-md border border-destructive/40 bg-destructive/10 p-3 text-xs text-destructive mb-3">
            {triggerError}
          </div>
        )}

        {(() => {
          const r = (cronJobs ?? []).find((j) => j.jobname === "enqueue-session-reminders");
          if (!r) return null;
          return (
            <div data-testid="session-reminders-summary" className="rounded-md border border-primary/30 bg-primary/5 p-3 text-xs mb-3 flex flex-wrap gap-3 items-center">
              <span className="font-semibold">enqueue-session-reminders</span>
              <span>الجدولة: <code>{r.schedule}</code></span>
              <span>آخر تشغيل: {r.last_start ? new Date(r.last_start).toLocaleString("ar") : "—"}</span>
              {r.last_status && (
                <Badge variant={r.last_status === "succeeded" ? "default" : "destructive"}>
                  النتيجة: {r.last_status}
                </Badge>
              )}
              <a className="underline text-primary" href="/api/public/cron/session-reminders" target="_blank" rel="noreferrer">
                logs / endpoint
              </a>
            </div>
          );
        })()}


        {cronErr ? (
          <div className="rounded-md border border-amber-500/30 bg-amber-500/10 p-3 text-xs text-amber-700 dark:text-amber-300">
            تعذّر قراءة حالة pg_cron: <code>{cronErr}</code>
            <br />
            شغّل ملف <code className="bg-muted px-1 rounded">docs/sql/cron-jobs-status.sql</code> في Supabase SQL Editor لتفعيل عرض الحالة المباشرة (يحتاج صلاحية admin).
          </div>
        ) : cronJobs === null ? (
          <div className="text-sm text-muted-foreground"><Loader2 className="inline h-4 w-4 animate-spin" /> جارٍ التحميل…</div>
        ) : cronJobs.length === 0 ? (
          <div className="text-sm text-muted-foreground">لا توجد مهام مجدولة.</div>
        ) : (
          <div className="space-y-2">
            {cronJobs.map((j) => (
              <div key={j.jobid} className="flex items-center justify-between border-b last:border-0 py-2 text-sm">
                <div className="flex flex-col">
                  <span className="font-medium">{j.jobname}</span>
                  <span className="text-xs text-muted-foreground">
                    <Clock className="inline h-3 w-3 ml-1" />
                    {j.schedule}
                    {j.last_start && <> — آخر تشغيل: {new Date(j.last_start).toLocaleString("ar")}</>}
                  </span>
                  {j.last_message && (
                    <span className="text-[11px] text-muted-foreground truncate max-w-[420px]" title={j.last_message}>
                      {j.last_message}
                    </span>
                  )}
                </div>
                <div className="flex items-center gap-2">
                  <Badge variant={j.active ? "default" : "secondary"}>
                    {j.active ? "مفعّل" : "متوقف"}
                  </Badge>
                  {j.last_status && (
                    <Badge variant={j.last_status === "succeeded" ? "default" : "destructive"}>
                      {j.last_status}
                    </Badge>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}

        <p className="mt-3 text-xs text-muted-foreground">
          مهمة <code className="bg-muted px-1 rounded">enqueue-session-reminders</code> مجدولة كل ٥ دقائق عبر <code className="bg-muted px-1 rounded">pg_cron</code> وتُنشئ تذكيرات الجلسات والمهام معاً.
          يوجد أيضاً endpoint بديل <code className="bg-muted px-1 rounded">/api/public/cron/session-reminders</code> (يتطلب رأس <code className="bg-muted px-1 rounded">x-cron-secret</code>).
        </p>
      </Card>
    </div>
  );
}
