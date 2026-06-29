import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

type TableName =
  | "cases" | "clients" | "employees" | "powers_of_attorney"
  | "executions" | "tasks" | "sessions" | "documents"
  | "client_notifications" | "portal_messages" | "najiz_sync_logs"
  | "sync_tokens";

export function useList<T = any>(table: TableName, orderBy = "created_at", asc = false) {
  return useQuery({
    queryKey: [table, "list"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from(table)
        .select("*")
        .order(orderBy, { ascending: asc });
      if (error) throw error;
      return (data ?? []) as T[];
    },
  });
}

export function useUpsert(table: TableName) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (row: any) => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error("غير مسجل دخول");
      const payload = { ...row, owner_id: row.owner_id ?? user.id };
      const { data, error } = row.id
        ? await supabase.from(table).update(payload).eq("id", row.id).select().single()
        : await supabase.from(table).insert(payload).select().single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: [table] });
      toast.success("تم الحفظ بنجاح");
    },
    onError: (err: any) => toast.error(err.message || "فشل الحفظ"),
  });
}

export function useDelete(table: TableName) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from(table).delete().eq("id", id);
      if (error) throw error;
      return id;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: [table] });
      toast.success("تم الحذف");
    },
    onError: (err: any) => toast.error(err.message || "فشل الحذف"),
  });
}
