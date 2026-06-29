import { useQuery } from "@tanstack/react-query";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { CheckCircle2, AlertCircle, Clock, Database, ArrowDownToLine, RefreshCw } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";

type LogRow = {
  id: string;
  source: string | null;
  status: string | null;
  items_count: number | null;
  inserted_count: number | null;
  updated_count: number | null;
  error_message: string | null;
  created_at: string;
};

export function NajizSyncStatus() {
  const { data, isLoading, error } = useQuery({
    queryKey: ["najiz_sync_logs", "latest"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("najiz_sync_logs")
        .select("id, source, status, items_count, inserted_count, updated_count, error_message, created_at")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (error) throw error;
      return data as LogRow | null;
    },
    refetchInterval: 15000,
  });

  if (isLoading) {
    return (
      <Card className="p-6 space-y-3">
        <Skeleton className="h-5 w-40" />
        <Skeleton className="h-20 w-full" />
      </Card>
    );
  }

  if (error) {
    return (
      <Card className="p-6 flex items-center gap-3 text-destructive">
        <AlertCircle className="h-5 w-5" />
        <span>تعذّر تحميل حالة المزامنة</span>
      </Card>
    );
  }

  if (!data) {
    return (
      <Card className="p-6 flex items-center gap-3 text-muted-foreground">
        <Clock className="h-5 w-5" />
        <span>لا يوجد تشغيل سابق لـ najiz-sync بعد</span>
      </Card>
    );
  }

  const ok = data.status === "success" || data.status === "ok";
  return (
    <Card className="p-6 space-y-4">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-center gap-2">
          {ok ? (
            <CheckCircle2 className="h-5 w-5 text-emerald-500" />
          ) : (
            <AlertCircle className="h-5 w-5 text-destructive" />
          )}
          <h3 className="font-semibold text-lg">آخر تشغيل لـ najiz-sync</h3>
          <Badge variant={ok ? "default" : "destructive"}>{data.status ?? "—"}</Badge>
          {data.source && <Badge variant="secondary">{data.source}</Badge>}
        </div>
        <div className="text-sm text-muted-foreground flex items-center gap-1">
          <Clock className="h-4 w-4" />
          {new Date(data.created_at).toLocaleString("ar-SA")}
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <StatCard icon={<Database className="h-4 w-4" />} label="عدد العناصر" value={data.items_count ?? 0} />
        <StatCard icon={<ArrowDownToLine className="h-4 w-4" />} label="مُدرَج جديد" value={data.inserted_count ?? 0} accent="emerald" />
        <StatCard icon={<RefreshCw className="h-4 w-4" />} label="مُحدَّث" value={data.updated_count ?? 0} accent="blue" />
      </div>

      {data.error_message && (
        <div className="text-sm rounded-md border border-destructive/30 bg-destructive/5 text-destructive p-3">
          {data.error_message}
        </div>
      )}
    </Card>
  );
}

function StatCard({ icon, label, value, accent }: { icon: React.ReactNode; label: string; value: number; accent?: "emerald" | "blue" }) {
  const color =
    accent === "emerald" ? "text-emerald-600" : accent === "blue" ? "text-blue-600" : "text-foreground";
  return (
    <div className="rounded-lg border bg-card p-4">
      <div className="flex items-center gap-2 text-xs text-muted-foreground">
        {icon}
        <span>{label}</span>
      </div>
      <div className={`mt-1 text-2xl font-bold ${color}`}>{value}</div>
    </div>
  );
}
