import { createServerFn } from "@tanstack/react-start";
import { randomBytes } from "crypto";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

import { z } from "zod";

const provisionSchema = z.object({
  employee_id: z.string().uuid(),
  email: z.string().trim().email("بريد غير صالح"),
  username: z.string().trim().min(2).max(120).optional().nullable(),
  password: z.string().min(6, "كلمة السر 6 أحرف على الأقل").optional().nullable(),
});

/**
 * Create (or update) a real auth user for an employee and link them to
 * the employees row via user_id. Returns credentials so the lawyer can
 * forward them via WhatsApp.
 */
export const provisionEmployeePortal = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => provisionSchema.parse(input))
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context;
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const { data: emp, error: eErr } = await supabase
      .from("employees")
      .select("id, owner_id, user_id, full_name, email, phone")
      .eq("id", data.employee_id)
      .maybeSingle();
    if (eErr) throw new Error(eErr.message);
    if (!emp || emp.owner_id !== userId) throw new Error("غير مصرّح بالوصول لهذا الموظف");

    const email = data.email.toLowerCase();
    let portalUserId = emp.user_id as string | null;
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
          user_metadata: { full_name: data.username || emp.full_name, account_type: "employee" },
        });
        if (createErr) throw new Error(createErr.message);
        portalUserId = createdUser.user!.id;
        created = true;
      }
      await supabaseAdmin.from("user_roles").upsert(
        { user_id: portalUserId!, role: "employee" } as never,
        { onConflict: "user_id,role" },
      );
    } else if (data.password) {
      await supabaseAdmin.auth.admin.updateUserById(portalUserId, { password: data.password, email });
    }

    const codePart = () => randomBytes(3).toString("hex").toUpperCase().slice(0, 4);
    const accessCode = `${codePart()}-${codePart()}`;


    const update: Record<string, unknown> = {
      user_id: portalUserId,
      email,
    };
    const { error: uErr } = await (supabaseAdmin as any)
      .from("employees")
      .update(update)
      .eq("id", data.employee_id);
    if (uErr) throw new Error(uErr.message);
    await supabaseAdmin.from("employee_portal_credentials").upsert(
      {
        employee_id: data.employee_id,
        owner_id: userId,
        portal_access_code: accessCode,
        portal_username: data.username || email,
      } as never,
      { onConflict: "employee_id" },
    );

    return {
      ok: true, created,
      user_id: portalUserId, email,
      username: data.username || email,
      access_code: accessCode,
      phone: emp.phone ?? null,
      full_name: emp.full_name,
    };
  });
