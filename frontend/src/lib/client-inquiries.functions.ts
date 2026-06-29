import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { z } from "zod";

/**
 * Post a new inquiry (from a client) or a reply (from owner/lawyer/admin).
 * Server validates that the caller is either:
 *   - the owner of the client row (lawyer/admin), or
 *   - the portal_user_id of the client (the client themselves).
 */
const postSchema = z.object({
  client_id: z.string().uuid(),
  case_id: z.string().uuid().nullable().optional(),
  parent_id: z.string().uuid().nullable().optional(),
  subject: z.string().trim().max(200).nullable().optional(),
  body: z.string().trim().min(1, "الرسالة مطلوبة").max(4000),
});

export const postClientInquiry = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => postSchema.parse(input))
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context;

    const { data: client, error: cErr } = await supabase
      .from("clients")
      .select("id, owner_id, portal_user_id")
      .eq("id", data.client_id)
      .maybeSingle();
    if (cErr) throw new Error(cErr.message);
    if (!client) throw new Error("العميل غير موجود");

    let role: "client" | "admin" | "lawyer" = "lawyer";
    if (client.portal_user_id === userId) role = "client";
    else if (client.owner_id === userId) role = "lawyer";
    else throw new Error("غير مصرّح بإرسال استفسار لهذا العميل");

    const row = {
      owner_id: client.owner_id,
      client_id: client.id,
      case_id: data.case_id ?? null,
      parent_id: data.parent_id ?? null,
      author_id: userId,
      author_role: role,
      subject: data.subject ?? null,
      body: data.body,
    };

    const { data: inserted, error } = await (supabase as any)
      .from("client_inquiries")
      .insert(row)
      .select("*")
      .single();
    if (error) throw new Error(error.message);
    return inserted;
  });

const markReadSchema = z.object({
  ids: z.array(z.string().uuid()).min(1),
});

export const markInquiriesRead = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => markReadSchema.parse(input))
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context;
    // Idempotent: only stamp read_at when it's still NULL, and never on
    // messages the caller authored. Re-opening the thread won't overwrite
    // the original timestamp.
    const { error } = await (supabase as any)
      .from("client_inquiries")
      .update({ read_at: new Date().toISOString() })
      .in("id", data.ids)
      .is("read_at", null)
      .neq("author_id", userId);
    if (error) throw new Error(error.message);
    return { ok: true };
  });
