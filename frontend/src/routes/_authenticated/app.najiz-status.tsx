import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Button } from "@/components/ui/button";
import { PageHeader } from "@/components/section-shell";
import { RefreshCw, Loader2, Activity } from "lucide-react";
import { toast } from "sonner";
import { NajizSyncStatus } from "@/components/najiz-sync-status";
import { NajizSyncLogsTable } from "@/components/najiz-sync-logs-table";
import { syncNajizExecutions } from "@/lib/portal.functions";

export const Route = createFileRoute("/_authenticated/app/najiz-status")({
  component: NajizStatusPage,
});

function NajizStatusPage() {
  const qc = useQueryClient();
  const runSync = useMutation({
    mutationFn: async () => await syncNajizExecutions(),
    onSuccess: (r: any) => {
      toast.success(`تمت المزامنة — ${r?.inserted ?? 0} جديد · ${r?.updated ?? 0} محدّث`);
      qc.invalidateQueries({ queryKey: ["najiz_sync_logs"] });
    },
    onError: (e: any) => toast.error(e?.message || "فشل تشغيل المزامنة"),
  });

  return (
    <div className="space-y-6">
      <PageHeader
        icon={Activity}
        title="حالة مزامنة ناجز"
        subtitle="عرض آخر تشغيل لـ najiz-sync وسجل العمليات السابقة"
        action={
          <Button onClick={() => runSync.mutate()} disabled={runSync.isPending}>
            {runSync.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <RefreshCw className="h-4 w-4" />}
            تشغيل المزامنة الآن
          </Button>
        }
      />
      <NajizSyncStatus />
      <NajizSyncLogsTable />
    </div>
  );
}
