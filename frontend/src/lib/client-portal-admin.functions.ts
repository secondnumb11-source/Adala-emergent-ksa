import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { z } from "zod";

/**
 * Client portal admin helpers — uses the existing `audit_log` table as the
 * source of truth for client portal sign-in / password-reset / provisioning
 * events. Filtering by entity_type='client_portal'.
 */

export const listClientLoginLogs = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: { client_id?: string; limit?: number } = {}) =>
    z
      .object({ client_id: z.string().uuid().optional(), limit: z.number().int().min(1).max(500).optional() })
      .parse(d),
  )
  .handler(async ({ data, context }) => {
    let q = context.supabase
      .from("audit_log")
      .select("id, action, entity_id, metadata, ip_address, user_agent, created_at, actor_id")
      .eq("entity_type", "client_portal")
      .order("created_at", { ascending: false })
      .limit(data.limit ?? 100);
    if (data.client_id) q = q.eq("entity_id", data.client_id);
    const { data: rows, error } = await q;
    if (error) throw new Error(error.message);
    return { rows: rows ?? [] };
  });

export const recordClientLogin = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: { client_id?: string; success?: boolean; event?: string; metadata?: Record<string, unknown> }) =>
    z
      .object({
        client_id: z.string().uuid().optional(),
        success: z.boolean().optional(),
        event: z.string().max(50).optional(),
        metadata: z.record(z.string(), z.unknown()).optional(),
      })
      .parse(d),
  )
  .handler(async ({ data, context }) => {
    const meta = { ...(data.metadata ?? {}), success: data.success ?? true };
    const { error } = await context.supabase.from("audit_log").insert({
      owner_id: context.userId,
      actor_id: context.userId,
      action: data.event ?? "sign_in",
      entity_type: "client_portal",
      entity_id: data.client_id ?? null,
      metadata: meta as never,
    });
    if (error) throw new Error(error.message);
    return { ok: true };
  });

export const sendPortalPasswordReset = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: { client_id: string; redirect_to?: string }) =>
    z.object({ client_id: z.string().uuid(), redirect_to: z.string().url().optional() }).parse(d),
  )
  .handler(async ({ data, context }) => {
    const { data: client, error: clientErr } = await context.supabase
      .from("clients")
      .select("id, email, portal_user_id, owner_id")
      .eq("id", data.client_id)
      .maybeSingle();
    if (clientErr) throw new Error(clientErr.message);
    if (!client) throw new Error("Client not found");
    if (client.owner_id !== context.userId) throw new Error("Forbidden");
    if (!client.email) throw new Error("Client has no email on file");

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { error } = await supabaseAdmin.auth.admin.generateLink({
      type: "recovery",
      email: client.email,
      options: data.redirect_to ? { redirectTo: data.redirect_to } : undefined,
    });
    if (error) throw new Error(error.message);

    await context.supabase.from("audit_log").insert({
      owner_id: context.userId,
      actor_id: context.userId,
      action: "password_reset_sent",
      entity_type: "client_portal",
      entity_id: data.client_id,
      metadata: { email: client.email } as never,
    });

    return { ok: true };
  });

export const getClientTimeline = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: { client_id: string; limit?: number }) =>
    z.object({ client_id: z.string().uuid(), limit: z.number().int().min(1).max(200).optional() }).parse(d),
  )
  .handler(async ({ data, context }) => {
    const limit = data.limit ?? 80;
    const [casesQ, notifsQ, loginsQ] = await Promise.all([
      context.supabase
        .from("cases")
        .select("id, title, case_number, status, created_at")
        .eq("client_id", data.client_id)
        .order("created_at", { ascending: false })
        .limit(limit),
      context.supabase
        .from("client_notifications")
        .select("id, message, channel, status, created_at")
        .eq("client_id", data.client_id)
        .order("created_at", { ascending: false })
        .limit(limit),
      context.supabase
        .from("audit_log")
        .select("id, action, metadata, created_at")
        .eq("entity_type", "client_portal")
        .eq("entity_id", data.client_id)
        .order("created_at", { ascending: false })
        .limit(limit),
    ]);

    // Get case ids for this client, then fetch sessions/documents.
    const caseIds = (casesQ.data ?? []).map((c) => c.id);
    const [sessionsQ, docsQ] = caseIds.length
      ? await Promise.all([
          context.supabase
            .from("sessions")
            .select("id, case_id, session_date, court, status")
            .in("case_id", caseIds)
            .order("session_date", { ascending: false })
            .limit(limit),
          context.supabase
            .from("documents")
            .select("id, case_id, title, doc_type, created_at")
            .in("case_id", caseIds)
            .order("created_at", { ascending: false })
            .limit(limit),
        ])
      : [{ data: [] as never[] }, { data: [] as never[] }];

    type Item = { id: string; kind: "case" | "session" | "document" | "notification" | "login"; title: string; subtitle?: string; at: string };
    const items: Item[] = [];
    for (const c of casesQ.data ?? []) items.push({ id: `c-${c.id}`, kind: "case", title: c.title ?? c.case_number ?? "قضية", subtitle: c.status ?? undefined, at: c.created_at });
    for (const s of (sessionsQ.data ?? []) as Array<{ id: string; session_date: string; court: string | null; status: string }>) items.push({ id: `s-${s.id}`, kind: "session", title: "جلسة", subtitle: [s.court, s.status].filter(Boolean).join(" · "), at: s.session_date });
    for (const d of (docsQ.data ?? []) as Array<{ id: string; title: string; doc_type: string; created_at: string }>) items.push({ id: `d-${d.id}`, kind: "document", title: d.title ?? "مستند", subtitle: d.doc_type ?? undefined, at: d.created_at });
    for (const n of notifsQ.data ?? []) items.push({ id: `n-${n.id}`, kind: "notification", title: (n.message ?? "").slice(0, 80) || "إشعار", subtitle: `${n.channel} · ${n.status}`, at: n.created_at });
    for (const l of loginsQ.data ?? []) {
      const meta = l.metadata as { success?: boolean } | null;
      items.push({ id: `l-${l.id}`, kind: "login", title: l.action, subtitle: meta?.success === false ? "فشل" : "ناجح", at: l.created_at });
    }
    items.sort((a, b) => (a.at < b.at ? 1 : -1));
    return { items: items.slice(0, limit) };
  });
