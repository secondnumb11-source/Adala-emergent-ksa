import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { z } from "zod";

/**
 * Pull executions data that was previously pushed into najiz_sync_logs by the
 * Chrome extension (kind='executions', status='pending') and upsert into the
 * executions table by najiz_id.
 *
 * Returns a summary: { logs_processed, inserted, updated, skipped, errors }.
 */
export const syncNajizExecutions = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { supabase, userId } = context;

    const { data: logs, error: logErr } = await supabase
      .from("najiz_sync_logs")
      .select("id, raw_payload, status")
      .eq("owner_id", userId)
      .eq("source", "extension:executions")
      .eq("status", "pending")
      .order("created_at", { ascending: true })
      .limit(50);

    if (logErr) throw new Error(logErr.message);

    let inserted = 0;
    let updated = 0;
    let skipped = 0;
    const errors: string[] = [];

    for (const log of logs ?? []) {
      const payload = log.raw_payload as unknown;
      const items = Array.isArray(payload) ? payload : (payload && typeof payload === "object" && Array.isArray((payload as any).items) ? (payload as any).items : []);
      let logInserted = 0;
      let logUpdated = 0;

      for (const raw of items) {
        if (!raw || typeof raw !== "object") { skipped++; continue; }
        const r = raw as Record<string, unknown>;
        const najizId = (r.najiz_id ?? r.id ?? r.execution_id) as string | undefined;
        const execNumber = (r.execution_number ?? r.number ?? najizId) as string | undefined;
        if (!execNumber) { skipped++; continue; }

        const row: Record<string, unknown> = {
          owner_id: userId,
          execution_number: String(execNumber),
          court: (r.court as string) ?? null,
          debtor_name: (r.debtor_name ?? r.defendant) as string ?? null,
          amount: r.amount != null ? Number(r.amount) : null,
          status: (r.status as string) ?? "pending",
          filed_date: (r.filed_date ?? r.date) as string ?? null,
          notes: (r.notes as string) ?? null,
          najiz_id: najizId ?? null,
          najiz_synced_at: new Date().toISOString(),
        };

        if (najizId) {
          const { data: existing } = await supabase
            .from("executions").select("id").eq("owner_id", userId).eq("najiz_id", najizId).maybeSingle();
          if (existing?.id) {
            const { error } = await supabase.from("executions").update(row as never).eq("id", existing.id);
            if (error) errors.push(error.message); else { logUpdated++; updated++; }
            continue;
          }
        }
        const { error } = await supabase.from("executions").insert(row as never);
        if (error) errors.push(error.message); else { logInserted++; inserted++; }
      }

      await supabase.from("najiz_sync_logs").update({
        status: errors.length ? "failed" : "success",
        items_count: items.length,
        inserted_count: logInserted,
        updated_count: logUpdated,
        error_message: errors.length ? errors.slice(0, 3).join(" | ") : null,
      }).eq("id", log.id);
    }

    return {
      logs_processed: logs?.length ?? 0,
      inserted,
      updated,
      skipped,
      errors: errors.slice(0, 5),
    };
  });

/**
 * Mark a specific najiz_sync_log row back to 'pending' so the next
 * syncNajizExecutions() run will process it again. Used by the "إعادة المحاولة" button.
 */
export const retryNajizSyncLog = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => z.object({ id: z.string().uuid() }).parse(input))
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context;
    const { data: log, error } = await supabase
      .from("najiz_sync_logs")
      .select("id, owner_id, status")
      .eq("id", data.id).maybeSingle();
    if (error) throw new Error(error.message);
    if (!log || log.owner_id !== userId) throw new Error("غير مصرّح");
    const { error: upErr } = await supabase
      .from("najiz_sync_logs")
      .update({ status: "pending", error_message: null })
      .eq("id", data.id);
    if (upErr) throw new Error(upErr.message);
    return { ok: true };
  });

/**
 * Save the portal configuration for an employee:
 *  - which app sections are visible to them (permissions)
 *  - which cases they can follow
 *  - which clients they can see
 */
export const saveEmployeePortalConfig = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) =>
    z.object({
      employee_id: z.string().uuid(),
      permissions: z.array(z.string()).default([]),
      assigned_cases: z.array(z.string().uuid()).default([]),
      assigned_clients: z.array(z.string().uuid()).default([]),
    }).parse(input)
  )
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context;
    const { data: emp, error: eErr } = await supabase
      .from("employees").select("id, owner_id").eq("id", data.employee_id).maybeSingle();
    if (eErr) throw new Error(eErr.message);
    if (!emp || emp.owner_id !== userId) throw new Error("غير مصرّح");

    const { error } = await supabase.from("employees").update({
      permissions: data.permissions as never,
      assigned_cases: data.assigned_cases as never,
      assigned_clients: data.assigned_clients as never,
    }).eq("id", data.employee_id);
    if (error) throw new Error(error.message);
    return { ok: true };
  });
