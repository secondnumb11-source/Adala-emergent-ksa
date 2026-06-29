import { useEffect } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

/**
 * Subscribe to Postgres changes on a table and invalidate the matching
 * React-Query cache key so the UI updates in real-time.
 */
export function useRealtimeTable(table: string, queryKey: unknown[] = [table]) {
  const qc = useQueryClient();
  useEffect(() => {
    const channel = supabase
      .channel(`rt:${table}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table },
        () => qc.invalidateQueries({ queryKey }),
      )
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [table]);
}
