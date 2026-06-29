import { createServerFn } from "@tanstack/react-start";
import { randomBytes } from "crypto";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { z } from "zod";


const provisionSchema = z.object({
  client_id: z.string().uuid(),
  email: z.string().trim().email("بريد غير صالح"),
  password: z.string().min(6, "كلمة السر 6 أحرف على الأقل").optional().nullable(),
  username: z.string().trim().min(2).max(120).optional().nullable(),
  assigned_cases: z.array(z.string().uuid()).default([]),
  permissions: z.array(z.string()).default([]),
  user_notes: z.string().optional().nullable(),
});

const CONFIG_MARK = "<!--PORTAL_CONFIG:";
const CONFIG_END = ":END-->";

function encodeNotes(userNotes: string | null | undefined, cfg: { assigned_cases: string[]; permissions: string[]; username: string | null }) {
  const json = JSON.stringify(cfg);
  const clean = (userNotes ?? "").replace(new RegExp(`${CONFIG_MARK}[\\s\\S]*?${CONFIG_END}`, "g"), "").trim();
  return `${clean}\n\n${CONFIG_MARK}${json}${CONFIG_END}`.trim();
}

/**
 * Provision (or update) a real auth user for a client and link them to the
 * client row. Returns credentials + access code; lawyer forwards via WhatsApp.
 */
export const provisionClientPortal = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => provisionSchema.parse(input))
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context;
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const { data: client, error: cErr } = await supabase
      .from("clients").select("id, owner_id, portal_user_id, notes")
      .eq("id", data.client_id).maybeSingle();
    if (cErr) throw new Error(cErr.message);
    if (!client || client.owner_id !== userId) throw new Error("غير مصرّح بالوصول لهذا العميل");

    const email = data.email.toLowerCase();
    let portalUserId = client.portal_user_id as string | null;
    let created = false;

    if (!portalUserId) {
      const { data: list } = await supabaseAdmin.auth.admin.listUsers({ page: 1, perPage: 200 });
      const existing = list?.users?.find((u) => u.email?.toLowerCase() === email);
      if (existing) {
        portalUserId = existing.id;
        if (data.password) await supabaseAdmin.auth.admin.updateUserById(existing.id, { password: data.password });
      } else {
        if (!data.password) throw new Error("كلمة السر مطلوبة لإنشاء حساب جديد");
        const { data: createdUser, error: createErr } = await supabaseAdmin.auth.admin.createUser({
          email,
          password: data.password,
          email_confirm: true,
          user_metadata: { full_name: data.username || email, account_type: "client" },
        });
        if (createErr) throw new Error(createErr.message);
        portalUserId = createdUser.user!.id;
        created = true;
      }
      await supabaseAdmin.from("user_roles").upsert(
        { user_id: portalUserId!, role: "client" } as never,
        { onConflict: "user_id,role" },
      );
    } else if (data.password) {
      await supabaseAdmin.auth.admin.updateUserById(portalUserId, { password: data.password, email });
    }

    const codePart = () => randomBytes(3).toString("hex").toUpperCase().slice(0, 4);
    const accessCode = `${codePart()}-${codePart()}`;


    const nextNotes = encodeNotes(data.user_notes ?? (client as any).notes, {
      assigned_cases: data.assigned_cases,
      permissions: data.permissions,
      username: data.username || email,
    });

    const update: Record<string, unknown> = {
      portal_user_id: portalUserId,
      email,
      notes: nextNotes,
    };
    const { error: uErr } = await supabaseAdmin.from("clients").update(update as never).eq("id", data.client_id);
    if (uErr) throw new Error(uErr.message);
    await supabaseAdmin.from("client_portal_credentials").upsert(
      { client_id: data.client_id, owner_id: userId, portal_access_code: accessCode } as never,
      { onConflict: "client_id" },
    );

    return { ok: true, created, portal_user_id: portalUserId, email, access_code: accessCode };
  });

export const revokeClientPortal = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => z.object({ client_id: z.string().uuid(), delete_user: z.boolean().default(false) }).parse(input))
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context;
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const { data: client, error } = await supabase
      .from("clients").select("id, owner_id, portal_user_id, notes")
      .eq("id", data.client_id).maybeSingle();
    if (error) throw new Error(error.message);
    if (!client || client.owner_id !== userId) throw new Error("غير مصرّح");

    const cleanNotes = ((client as any).notes ?? "")
      .replace(new RegExp(`${CONFIG_MARK}[\\s\\S]*?${CONFIG_END}`, "g"), "")
      .trim();

    await supabaseAdmin.from("clients").update({
      portal_user_id: null,
      notes: cleanNotes || null,
    } as never).eq("id", data.client_id);
    await supabaseAdmin.from("client_portal_credentials").delete().eq("client_id", data.client_id);

    if (data.delete_user && client.portal_user_id) {
      await supabaseAdmin.from("user_roles").delete().eq("user_id", client.portal_user_id).eq("role", "client");
      await supabaseAdmin.auth.admin.deleteUser(client.portal_user_id);
    }
    return { ok: true };
  });

