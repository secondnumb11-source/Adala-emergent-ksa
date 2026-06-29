import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { supabase } from "@/integrations/supabase/client";

type Row = {
  id: string;
  source: string | null;
  status: string | null;
  kind: string | null;
  items_count: number | null;
  inserted_count: number | null;
  updated_count: number | null;
  error_message: string | null;
  created_at: string;
};

export function NajizSyncLogsTable() {
  const [status, setStatus] = useState<string>("all");
  const [source, setSource] = useState<string>("all");
  const [search, setSearch] = useState("");

  const { data, isLoading } = useQuery({
    queryKey: ["najiz_sync_logs", "table"],
    queryFn: async () => {
      // Explicitly exclude raw_payload / trace
      const { data, error } = await supabase
        .from("najiz_sync_logs")
        .select("id, source, status, kind, items_count, inserted_count, updated_count, error_message, created_at")
        .order("created_at", { ascending: false })
        .limit(200);
      if (error) throw error;
      return ((data ?? []) as unknown) as Row[];
    },
    refetchInterval: 30000,
  });

  const sources = useMemo(() => {
    const s = new Set<string>();
    (data ?? []).forEach((r) => r.source && s.add(r.source));
    return Array.from(s);
  }, [data]);
  const statuses = useMemo(() => {
    const s = new Set<string>();
    (data ?? []).forEach((r) => r.status && s.add(r.status));
    return Array.from(s);
  }, [data]);

  const filtered = useMemo(() => {
    return (data ?? []).filter((r) => {
      if (status !== "all" && r.status !== status) return false;
      if (source !== "all" && r.source !== source) return false;
      if (search && !(r.error_message ?? "").toLowerCase().includes(search.toLowerCase())) return false;
      return true;
    });
  }, [data, status, source, search]);

  return (
    <Card className="p-4 space-y-4">
      <div className="flex flex-wrap gap-2 items-center">
        <h3 className="font-semibold mr-auto">سجلات najiz_sync_logs</h3>
        <Select value={status} onValueChange={setStatus}>
          <SelectTrigger className="w-36"><SelectValue placeholder="الحالة" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">كل الحالات</SelectItem>
            {statuses.map((s) => (<SelectItem key={s} value={s}>{s}</SelectItem>))}
          </SelectContent>
        </Select>
        <Select value={source} onValueChange={setSource}>
          <SelectTrigger className="w-40"><SelectValue placeholder="المصدر" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">كل المصادر</SelectItem>
            {sources.map((s) => (<SelectItem key={s} value={s}>{s}</SelectItem>))}
          </SelectContent>
        </Select>
        <Input
          placeholder="بحث في رسالة الخطأ"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="w-56"
        />
      </div>

      <div className="rounded-md border overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>التاريخ</TableHead>
              <TableHead>الحالة</TableHead>
              <TableHead>المصدر</TableHead>
              <TableHead>النوع</TableHead>
              <TableHead className="text-right">عناصر</TableHead>
              <TableHead className="text-right">مُدرَج</TableHead>
              <TableHead className="text-right">مُحدَّث</TableHead>
              <TableHead>الخطأ</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {isLoading && (
              <TableRow><TableCell colSpan={8}><Skeleton className="h-6 w-full" /></TableCell></TableRow>
            )}
            {!isLoading && filtered.length === 0 && (
              <TableRow><TableCell colSpan={8} className="text-center text-muted-foreground py-6">لا توجد سجلات مطابقة</TableCell></TableRow>
            )}
            {filtered.map((r) => {
              const ok = r.status === "success" || r.status === "ok";
              return (
                <TableRow key={r.id}>
                  <TableCell className="whitespace-nowrap text-xs">{new Date(r.created_at).toLocaleString("ar-SA")}</TableCell>
                  <TableCell><Badge variant={ok ? "default" : "destructive"}>{r.status ?? "—"}</Badge></TableCell>
                  <TableCell>{r.source ?? "—"}</TableCell>
                  <TableCell className="text-muted-foreground">{r.kind ?? "—"}</TableCell>
                  <TableCell className="text-right tabular-nums">{r.items_count ?? 0}</TableCell>
                  <TableCell className="text-right tabular-nums text-emerald-600">{r.inserted_count ?? 0}</TableCell>
                  <TableCell className="text-right tabular-nums text-blue-600">{r.updated_count ?? 0}</TableCell>
                  <TableCell className="max-w-xs truncate text-destructive text-xs" title={r.error_message ?? ""}>
                    {r.error_message ?? ""}
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </div>
      <p className="text-xs text-muted-foreground">لا يتم عرض raw_payload لحماية الخصوصية.</p>
    </Card>
  );
}
