import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { z } from "zod";

export const logAudit = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: { action: string; entity_type?: string; entity_id?: string; metadata?: Record<string, unknown> }) =>
    z
      .object({
        action: z.string().min(1).max(100),
        entity_type: z.string().max(100).optional(),
        entity_id: z.string().max(100).optional(),
        metadata: z.record(z.string(), z.unknown()).optional(),
      })
      .parse(d),
  )
  .handler(async ({ data, context }) => {
    const { error } = await context.supabase.from("audit_log").insert({
      owner_id: context.userId,
      actor_id: context.userId,
      action: data.action,
      entity_type: data.entity_type ?? "system",
      entity_id: data.entity_id ?? null,
      metadata: (data.metadata ?? {}) as never,
    });
    if (error) throw new Error(error.message);
    return { ok: true };
  });

export const listAuditLogs = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: { limit?: number; entity?: string; from?: string; to?: string } = {}) =>
    z
      .object({
        limit: z.number().int().min(1).max(500).optional(),
        entity: z.string().optional(),
        from: z.string().optional(),
        to: z.string().optional(),
      })
      .parse(d),
  )
  .handler(async ({ data, context }) => {
    let q = context.supabase
      .from("audit_log")
      .select("id, actor_id, action, entity_type, entity_id, metadata, ip_address, user_agent, created_at")
      .order("created_at", { ascending: false })
      .limit(data.limit ?? 100);
    if (data.entity) q = q.eq("entity_type", data.entity);
    if (data.from) q = q.gte("created_at", data.from);
    if (data.to) q = q.lte("created_at", data.to);
    const { data: rows, error } = await q;
    if (error) throw new Error(error.message);
    return { rows: rows ?? [] };
  });
