import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { listAuditLogs } from "@/lib/audit.functions";
import { PageHeader } from "@/components/section-shell";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Loader2, ScrollText, RefreshCw } from "lucide-react";

export const Route = createFileRoute("/_authenticated/app/audit-log")({
  component: AuditLogPage,
});

function AuditLogPage() {
  const fn = useServerFn(listAuditLogs);
  const [entity, setEntity] = useState("");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");

  const { data, isLoading, refetch, isFetching } = useQuery({
    queryKey: ["audit-logs", entity, from, to],
    queryFn: () =>
      fn({
        data: {
          entity: entity || undefined,
          from: from ? new Date(from).toISOString() : undefined,
          to: to ? new Date(to).toISOString() : undefined,
          limit: 200,
        },
      }),
  });

  return (
    <div className="space-y-6" dir="rtl">
      <PageHeader icon={ScrollText} title="سجل التدقيق" subtitle="جميع العمليات الحرجة في النظام" />

      <Card className="p-4">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
          <div>
            <label className="text-xs text-muted-foreground">نوع الكيان</label>
            <Input value={entity} onChange={(e) => setEntity(e.target.value)} placeholder="case, document, client_portal…" />
          </div>
          <div>
            <label className="text-xs text-muted-foreground">من تاريخ</label>
            <Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
          </div>
          <div>
            <label className="text-xs text-muted-foreground">إلى تاريخ</label>
            <Input type="date" value={to} onChange={(e) => setTo(e.target.value)} />
          </div>
          <div className="flex items-end">
            <Button onClick={() => refetch()} disabled={isFetching} className="w-full">
              {isFetching ? <Loader2 className="h-4 w-4 animate-spin" /> : <RefreshCw className="h-4 w-4" />}
              <span className="ms-2">تحديث</span>
            </Button>
          </div>
        </div>
      </Card>

      <Card className="p-0 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-muted/40 text-muted-foreground">
              <tr className="text-right">
                <th className="px-3 py-2 font-medium">التاريخ</th>
                <th className="px-3 py-2 font-medium">العملية</th>
                <th className="px-3 py-2 font-medium">الكيان</th>
                <th className="px-3 py-2 font-medium">المعرف</th>
                <th className="px-3 py-2 font-medium">IP</th>
                <th className="px-3 py-2 font-medium">تفاصيل</th>
              </tr>
            </thead>
            <tbody>
              {isLoading && (
                <tr><td colSpan={6} className="px-3 py-8 text-center text-muted-foreground"><Loader2 className="inline h-4 w-4 animate-spin" /> جاري التحميل…</td></tr>
              )}
              {!isLoading && (data?.rows ?? []).length === 0 && (
                <tr><td colSpan={6} className="px-3 py-8 text-center text-muted-foreground">لا توجد سجلات</td></tr>
              )}
              {(data?.rows ?? []).map((r) => {
                const meta = r.metadata as Record<string, unknown> | null;
                return (
                  <tr key={r.id} className="border-t hover:bg-accent/30">
                    <td className="px-3 py-2 whitespace-nowrap">{new Date(r.created_at).toLocaleString("ar-SA")}</td>
                    <td className="px-3 py-2 font-medium">{r.action}</td>
                    <td className="px-3 py-2">{r.entity_type ?? "—"}</td>
                    <td className="px-3 py-2 text-xs font-mono text-muted-foreground">{r.entity_id ?? "—"}</td>
                    <td className="px-3 py-2 text-xs">{r.ip_address ?? "—"}</td>
                    <td className="px-3 py-2 text-xs text-muted-foreground max-w-md truncate">
                      {meta && Object.keys(meta).length ? JSON.stringify(meta) : "—"}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </Card>
    </div>
  );
}
