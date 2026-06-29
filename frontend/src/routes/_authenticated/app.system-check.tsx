import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useRef, useState } from "react";
import { useServerFn } from "@tanstack/react-start";
import { supabase } from "@/integrations/supabase/client";
import { runSystemCheck, seedDemoData, runRlsTests, runEnqueueSessionReminders, runEnqueueTaskReminders, runCrudIntegrationTests, type SystemCheckReport, type RlsTestReport, type CrudIntegrationReport } from "@/lib/system-check.functions";
import { PageHeader } from "@/components/section-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  ShieldCheck, CheckCircle2, XCircle, Loader2, PlayCircle, Database,
  Radio, Sparkles, Upload, FileText, Users,
} from "lucide-react";
import { toast } from "sonner";
import { RequireRole } from "@/components/require-role";

export const Route = createFileRoute("/_authenticated/app/system-check")({
  component: SystemCheckPageGuarded,
});

function SystemCheckPageGuarded() {
  return (
    <RequireRole allowed={["lawyer", "admin"]}>
      <SystemCheckPage />
    </RequireRole>
  );
}

type LogEntry = { t: string; level: "info" | "ok" | "err"; msg: string };

function SystemCheckPage() {
  const callCheck = useServerFn(runSystemCheck);
  const callSeed = useServerFn(seedDemoData);
  const callRls = useServerFn(runRlsTests);
  const callCrud = useServerFn(runCrudIntegrationTests);
  const [rlsRunning, setRlsRunning] = useState(false);
  const [rlsReport, setRlsReport] = useState<RlsTestReport | null>(null);
  const [crudRunning, setCrudRunning] = useState(false);
  const [crudReport, setCrudReport] = useState<CrudIntegrationReport | null>(null);

  async function doCrudTests() {
    setCrudRunning(true);
    setCrudReport(null);
    try {
      const r = await callCrud();
      setCrudReport(r);
      log(r.ok ? "ok" : "err",
        `اختبارات التكامل CRUD: ${r.passed}/${r.passed + r.failed} ناجحة${r.cleanedUp ? "" : " (تنبيه: تنظيف ناقص)"}`);
      if (r.ok) toast.success("نجحت جميع اختبارات حفظ البيانات");
      else toast.error(`فشل ${r.failed} خطوة من اختبارات CRUD`);
    } catch (e) {
      log("err", `CRUD tests: ${(e as Error).message}`);
      toast.error((e as Error).message);
    } finally {
      setCrudRunning(false);
    }
  }

  async function doRlsTests() {
    setRlsRunning(true);
    setRlsReport(null);
    try {
      const r = await callRls();
      setRlsReport(r);
      log(r.ok ? "ok" : "err",
        `اختبارات RLS: ${r.passed}/${r.passed + r.failed} ناجحة${r.cleanedUp ? "" : " (تنبيه: تنظيف ناقص)"}`);
      if (r.ok) toast.success("كل اختبارات RLS نجحت");
      else toast.error(`فشل ${r.failed} اختبار RLS`);
    } catch (e) {
      log("err", `RLS tests: ${(e as Error).message}`);
      toast.error((e as Error).message);
    } finally {
      setRlsRunning(false);
    }
  }

  const [report, setReport] = useState<SystemCheckReport | null>(null);
  const [loadingReport, setLoadingReport] = useState(false);
  const [reportError, setReportError] = useState<string | null>(null);

  const [seeding, setSeeding] = useState(false);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const log = (level: LogEntry["level"], msg: string) =>
    setLogs((l) => [{ t: new Date().toLocaleTimeString("ar"), level, msg }, ...l].slice(0, 80));

  const [rtStatus, setRtStatus] = useState<Record<string, "idle" | "subscribed" | "received" | "error">>({});
  const channelRef = useRef<ReturnType<typeof supabase.channel>[]>([]);

  const [storageStatus, setStorageStatus] = useState<"idle" | "ok" | "err">("idle");
  const [storageDetail, setStorageDetail] = useState<string>("");

  const [triggering, setTriggering] = useState<"session" | "task" | null>(null);

  async function loadReport() {
    setLoadingReport(true);
    setReportError(null);
    try {
      const r = await callCheck();
      setReport(r);
      log(r.ok ? "ok" : "err", `تقرير الجاهزية: ${r.ok ? "✅ النظام جاهز" : "⚠️ توجد نواقص"}`);
    } catch (e) {
      setReportError((e as Error).message);
      log("err", `فشل التقرير: ${(e as Error).message}`);
    } finally {
      setLoadingReport(false);
    }
  }

  async function doSeed() {
    setSeeding(true);
    try {
      const r = await callSeed();
      log("ok", `تم إنشاء بيانات تجريبية بوسم ${r.tag}`);
      toast.success(`تم توليد عينة كاملة (${r.tag})`);
    } catch (e) {
      log("err", `فشل التوليد: ${(e as Error).message}`);
      toast.error((e as Error).message);
    } finally {
      setSeeding(false);
    }
  }

  const callEnqSession = useServerFn(runEnqueueSessionReminders);
  const callEnqTask = useServerFn(runEnqueueTaskReminders);
  async function trigger(name: "enqueue_session_reminders" | "enqueue_task_reminders") {
    setTriggering(name === "enqueue_session_reminders" ? "session" : "task");
    try {
      const data = name === "enqueue_session_reminders" ? await callEnqSession() : await callEnqTask();
      log("ok", `${name} → ${JSON.stringify(data)}`);
      toast.success(`تم تشغيل ${name}`);
    } catch (e) {
      log("err", `${name}: ${(e as Error).message}`);
      toast.error((e as Error).message);
    } finally {
      setTriggering(null);
    }
  }

  // Realtime subscriptions
  useEffect(() => {
    const tables = ["cases", "documents", "portal_messages"];
    tables.forEach((tbl) => {
      const ch = supabase
        .channel(`sys-check-${tbl}`)
        .on("postgres_changes", { event: "*", schema: "public", table: tbl }, (payload) => {
          setRtStatus((s) => ({ ...s, [tbl]: "received" }));
          log("ok", `📡 Realtime ${tbl}: ${payload.eventType}`);
        })
        .subscribe((status) => {
          if (status === "SUBSCRIBED") {
            setRtStatus((s) => ({ ...s, [tbl]: s[tbl] === "received" ? "received" : "subscribed" }));
          } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
            setRtStatus((s) => ({ ...s, [tbl]: "error" }));
          }
        });
      channelRef.current.push(ch);
    });
    return () => {
      channelRef.current.forEach((c) => supabase.removeChannel(c));
      channelRef.current = [];
    };
  }, []);

  async function testStorage() {
    setStorageStatus("idle");
    setStorageDetail("جارٍ الاختبار…");
    try {
      const { data: userRes } = await supabase.auth.getUser();
      const uid = userRes.user?.id ?? "anon";
      const path = `${uid}/system-check-${Date.now()}.txt`;
      const body = new Blob([`hello ${new Date().toISOString()}`], { type: "text/plain" });
      const up = await supabase.storage.from("case-documents").upload(path, body, { upsert: true });
      if (up.error) throw new Error(`upload: ${up.error.message}`);
      const dl = await supabase.storage.from("case-documents").download(path);
      if (dl.error) throw new Error(`download: ${dl.error.message}`);
      const text = await dl.data.text();
      await supabase.storage.from("case-documents").remove([path]);
      setStorageStatus("ok");
      setStorageDetail(`نجح: قُرئ ${text.length} حرف من ${path}`);
      log("ok", `Storage: رفع/قراءة/حذف ناجح (${path})`);
    } catch (e) {
      setStorageStatus("err");
      setStorageDetail((e as Error).message);
      log("err", `Storage: ${(e as Error).message}`);
    }
  }

  useEffect(() => {
    loadReport();
  }, []);

  const Stat = ({ label, present, total, ok }: { label: string; present: number; total: number; ok?: boolean }) => (
    <div className="flex flex-col items-start gap-1 rounded-md border bg-card p-3">
      <span className="text-xs text-muted-foreground">{label}</span>
      <div className="flex items-baseline gap-1">
        <span className="text-2xl font-bold tabular-nums">{present}</span>
        <span className="text-sm text-muted-foreground">/{total}</span>
      </div>
      {ok !== undefined && (
        <Badge variant={ok ? "default" : "destructive"} className="gap-1">
          {ok ? <CheckCircle2 className="h-3 w-3" /> : <XCircle className="h-3 w-3" />}
          {ok ? "مكتمل" : "ناقص"}
        </Badge>
      )}
    </div>
  );

  return (
    <div className="space-y-6" dir="rtl">
      <PageHeader
        icon={ShieldCheck}
        title="فحص جاهزية النظام"
        subtitle="تحقق آلي من قاعدة البيانات، RLS، الصلاحيات، RPCs، التخزين، Realtime، وتوليد بيانات تجريبية"
      />

      {/* Report */}
      <Card className="p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="font-semibold flex items-center gap-2">
            <Database className="h-4 w-4" /> تقرير الجاهزية الشامل
          </h3>
          <div className="flex gap-2">
            <Button size="sm" variant="outline" onClick={loadReport} disabled={loadingReport}>
              {loadingReport ? <Loader2 className="h-4 w-4 animate-spin" /> : "إعادة الفحص"}
            </Button>
            <a
              className="text-xs underline text-primary self-center"
              href="/api/public/system-check"
              target="_blank"
              rel="noreferrer"
            >
              JSON Endpoint
            </a>
          </div>
        </div>

        {reportError && (
          <div className="rounded-md border border-destructive/40 bg-destructive/10 p-3 text-xs text-destructive">
            {reportError}
          </div>
        )}

        {report && (
          <>
            <div className="grid grid-cols-2 sm:grid-cols-5 gap-3 mb-4">
              <Stat label="الجداول" present={report.summary.tables.present} total={report.summary.tables.total} ok={report.summary.tables.present === report.summary.tables.total} />
              <Stat label="RLS" present={report.summary.rls.enabled} total={report.summary.rls.total} ok={report.summary.rls.enabled === report.summary.rls.total} />
              <Stat label="RPCs" present={report.summary.rpcs.present} total={report.summary.rpcs.total} ok={report.summary.rpcs.present === report.summary.rpcs.total} />
              <Stat label="Buckets" present={report.summary.buckets.present} total={report.summary.buckets.total} ok={report.summary.buckets.present === report.summary.buckets.total} />
              <Stat label="Realtime" present={report.summary.realtime.present} total={report.summary.realtime.total} ok={report.summary.realtime.present === report.summary.realtime.total} />
            </div>

            <details className="rounded-md border bg-muted/30 p-3" open>
              <summary className="cursor-pointer text-sm font-medium">تفاصيل الجداول والصلاحيات</summary>
              <div className="mt-3 overflow-x-auto">
                <table className="w-full text-xs">
                  <thead>
                    <tr className="text-right border-b">
                      <th className="py-1.5 pr-2">الجدول</th>
                      <th>موجود</th>
                      <th>RLS</th>
                      <th>سياسات</th>
                      <th>authenticated</th>
                      <th>service_role</th>
                      <th>anon</th>
                    </tr>
                  </thead>
                  <tbody>
                    {report.tables.map((t) => (
                      <tr key={t.name} className="border-b last:border-0">
                        <td className="py-1 pr-2 font-mono">{t.name}</td>
                        <td>{t.exists ? "✅" : "❌"}</td>
                        <td>{t.rlsEnabled ? "✅" : "⚠️"}</td>
                        <td className="tabular-nums">{t.policies}</td>
                        <td className="text-[10px] text-muted-foreground">{(t.grants.authenticated ?? []).length || "—"}</td>
                        <td className="text-[10px] text-muted-foreground">{(t.grants.service_role ?? []).length || "—"}</td>
                        <td className="text-[10px] text-muted-foreground">{(t.grants.anon ?? []).length || "—"}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </details>

            <details className="rounded-md border bg-muted/30 p-3 mt-3">
              <summary className="cursor-pointer text-sm font-medium">RPCs و Buckets و Realtime</summary>
              <div className="grid sm:grid-cols-3 gap-3 mt-3 text-xs">
                <div>
                  <div className="font-semibold mb-1">RPCs</div>
                  {report.rpcs.map((r) => (
                    <div key={r.name} className="flex justify-between border-b py-1">
                      <code>{r.name}</code><span>{r.exists ? "✅" : "❌"}</span>
                    </div>
                  ))}
                </div>
                <div>
                  <div className="font-semibold mb-1">Storage Buckets</div>
                  {report.buckets.map((b) => (
                    <div key={b.name} className="flex justify-between border-b py-1">
                      <code>{b.name}</code><span>{b.exists ? (b.public ? "🌐" : "🔒") : "❌"}</span>
                    </div>
                  ))}
                </div>
                <div>
                  <div className="font-semibold mb-1">Realtime Publication</div>
                  {report.realtime.map((r) => (
                    <div key={r.name} className="flex justify-between border-b py-1">
                      <code>{r.name}</code><span>{r.inPublication ? "✅" : "❌"}</span>
                    </div>
                  ))}
                </div>
              </div>
            </details>
          </>
        )}
      </Card>

      {/* Reminders RPCs */}
      <Card className="p-4">
        <h3 className="font-semibold flex items-center gap-2 mb-3"><PlayCircle className="h-4 w-4" /> جدولة التذكيرات (RPCs)</h3>
        <div className="flex flex-wrap gap-2">
          <Button onClick={() => trigger("enqueue_session_reminders")} disabled={triggering !== null} size="sm" className="gap-2">
            {triggering === "session" ? <Loader2 className="h-4 w-4 animate-spin" /> : <PlayCircle className="h-4 w-4" />}
            تشغيل enqueue_session_reminders
          </Button>
          <Button onClick={() => trigger("enqueue_task_reminders")} disabled={triggering !== null} size="sm" variant="secondary" className="gap-2">
            {triggering === "task" ? <Loader2 className="h-4 w-4 animate-spin" /> : <PlayCircle className="h-4 w-4" />}
            تشغيل enqueue_task_reminders
          </Button>
        </div>
        <p className="text-xs text-muted-foreground mt-2">
          النتيجة الفعلية لكل تشغيل تظهر في السجل الحي بالأسفل. لعرض حالة pg_cron الكاملة، استخدم صفحة <a className="underline" href="/app/diagnostics">التشخيص</a>.
        </p>
      </Card>

      {/* Realtime tester */}
      <Card className="p-4">
        <h3 className="font-semibold flex items-center gap-2 mb-3"><Radio className="h-4 w-4" /> اختبار Realtime</h3>
        <div className="grid sm:grid-cols-3 gap-3 text-sm">
          {["cases", "documents", "portal_messages"].map((t) => {
            const s = rtStatus[t] ?? "idle";
            const color = s === "received" ? "default" : s === "subscribed" ? "secondary" : s === "error" ? "destructive" : "outline";
            const label = s === "received" ? "تم استقبال حدث" : s === "subscribed" ? "متصل وينتظر" : s === "error" ? "خطأ" : "تهيئة…";
            return (
              <div key={t} className="rounded-md border p-3 flex items-center justify-between">
                <code className="text-xs">{t}</code>
                <Badge variant={color as never}>{label}</Badge>
              </div>
            );
          })}
        </div>
        <p className="text-xs text-muted-foreground mt-2">
          اضغط "توليد بيانات تجريبية" أدناه — يجب أن تتلقى أحداثاً على <code>cases</code> و <code>documents</code> فوراً.
        </p>
      </Card>

      {/* Storage tester */}
      <Card className="p-4">
        <h3 className="font-semibold flex items-center gap-2 mb-3"><Upload className="h-4 w-4" /> اختبار رفع/قراءة المستندات</h3>
        <div className="flex items-center gap-2">
          <Button size="sm" variant="outline" onClick={testStorage} className="gap-2">
            <FileText className="h-4 w-4" /> تشغيل اختبار Storage
          </Button>
          {storageStatus === "ok" && <Badge variant="default" className="gap-1"><CheckCircle2 className="h-3 w-3" /> ناجح</Badge>}
          {storageStatus === "err" && <Badge variant="destructive" className="gap-1"><XCircle className="h-3 w-3" /> فشل</Badge>}
        </div>
        {storageDetail && <p className="mt-2 text-xs text-muted-foreground break-all">{storageDetail}</p>}
      </Card>

      {/* Seed demo */}
      <Card className="p-4 border-primary/40 bg-primary/5">
        <h3 className="font-semibold flex items-center gap-2 mb-3"><Sparkles className="h-4 w-4" /> توليد بيانات تجريبية</h3>
        <p className="text-sm text-muted-foreground mb-3">
          يولّد عينة كاملة (عميل، موظف، قضية، وكالة، مستند، طلب تنفيذ، جلسة، مهمة) باسم المستخدم الحالي مع تطبيق RLS.
          يُستخدم للتأكد أن جميع الأقسام تحفظ البيانات بنجاح.
        </p>
        <Button onClick={doSeed} disabled={seeding} className="gap-2">
          {seeding ? <Loader2 className="h-4 w-4 animate-spin" /> : <Sparkles className="h-4 w-4" />}
          إنشاء عينة كاملة
        </Button>
      </Card>

      {/* CRUD integration tests */}
      <Card className="p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="font-semibold flex items-center gap-2"><Database className="h-4 w-4" /> اختبارات تكامل الحفظ (CRUD)</h3>
          <Button size="sm" onClick={doCrudTests} disabled={crudRunning} className="gap-2">
            {crudRunning ? <Loader2 className="h-4 w-4 animate-spin" /> : <PlayCircle className="h-4 w-4" />}
            تشغيل اختبارات الحفظ
          </Button>
        </div>
        <p className="text-xs text-muted-foreground mb-3">
          يُنفّذ دورة كاملة (إنشاء/قراءة/تحديث/حذف) باسم المستخدم الحالي على
          <code className="mx-1">clients</code>،<code>employees</code>،<code>cases</code>،
          <code>powers_of_attorney</code>،<code>documents</code>،<code>executions</code>،<code>sessions</code>،<code>tasks</code>،
          ثم يحذف كل ما أنشأه للتأكد أن الحفظ يعمل فعلياً وأن RLS لا يحجبه.
        </p>
        {crudReport && (
          <div className="space-y-2">
            <div className="flex items-center gap-2 text-sm">
              <Badge variant={crudReport.ok ? "default" : "destructive"}>
                {crudReport.passed} نجح / {crudReport.failed} فشل
              </Badge>
              {!crudReport.cleanedUp && <Badge variant="destructive">تنظيف ناقص</Badge>}
            </div>
            <div className="overflow-x-auto max-h-80 overflow-y-auto">
              <table className="w-full text-xs">
                <thead className="sticky top-0 bg-background"><tr className="border-b text-right">
                  <th className="py-1">الجدول</th><th>العملية</th><th>التفاصيل</th><th></th>
                </tr></thead>
                <tbody>
                  {crudReport.steps.map((s, i) => (
                    <tr key={i} className="border-b last:border-0">
                      <td className="py-1 pr-2 font-mono">{s.entity}</td>
                      <td className="text-muted-foreground">{s.op}</td>
                      <td className="text-muted-foreground break-all">{s.detail}</td>
                      <td>{s.ok ? "✅" : "❌"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </Card>

      {/* RLS multi-role tests */}
      <Card className="p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="font-semibold flex items-center gap-2"><Users className="h-4 w-4" /> اختبارات RLS متعددة الأدوار</h3>
          <Button size="sm" onClick={doRlsTests} disabled={rlsRunning} className="gap-2">
            {rlsRunning ? <Loader2 className="h-4 w-4 animate-spin" /> : <PlayCircle className="h-4 w-4" />}
            تشغيل الاختبارات
          </Button>
        </div>
        <p className="text-xs text-muted-foreground mb-3">
          يُنشئ 3 حسابات مؤقتة (محاميان + عميل بوابة)، يُجري محاولات وصول متقاطعة على جداول
          <code className="mx-1">cases</code>/<code>clients</code>/<code>documents</code>،
          ثم يحذف الحسابات تلقائياً.
        </p>
        {rlsReport && (
          <div className="space-y-2">
            <div className="flex items-center gap-2 text-sm">
              <Badge variant={rlsReport.ok ? "default" : "destructive"}>
                {rlsReport.passed} نجح / {rlsReport.failed} فشل
              </Badge>
              {!rlsReport.cleanedUp && <Badge variant="destructive">تنظيف ناقص</Badge>}
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead><tr className="border-b text-right">
                  <th className="py-1">الاختبار</th><th>المتوقع</th><th>الفعلي</th><th></th>
                </tr></thead>
                <tbody>
                  {rlsReport.cases.map((c, i) => (
                    <tr key={i} className="border-b last:border-0">
                      <td className="py-1 pr-2">{c.name}</td>
                      <td className="text-muted-foreground">{c.expected}</td>
                      <td className="text-muted-foreground">{c.actual}</td>
                      <td>{c.pass ? "✅" : "❌"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </Card>


      {/* Live log */}
      <Card className="p-4">
        <h3 className="font-semibold mb-2">السجل الحي</h3>
        <div className="font-mono text-xs max-h-72 overflow-auto rounded-md border bg-muted/30 p-3 space-y-1">
          {logs.length === 0 ? (
            <span className="text-muted-foreground">لا توجد أحداث بعد.</span>
          ) : logs.map((l, i) => (
            <div key={i} className={l.level === "err" ? "text-destructive" : l.level === "ok" ? "text-emerald-600 dark:text-emerald-400" : ""}>
              [{l.t}] {l.msg}
            </div>
          ))}
        </div>
      </Card>
    </div>
  );
}
