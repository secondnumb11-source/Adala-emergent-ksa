import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { z } from "zod";

const portalLinkSchema = z.object({
  account_type: z.enum(["lawyer", "client", "employee"]).default("lawyer"),
  access_code: z.string().trim().optional().nullable(),
});

export const linkPortalAccount = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => portalLinkSchema.parse(input))
  .handler(async ({ data, context }) => {
    const { userId } = context;
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    if (data.account_type === "lawyer") {
      // Privilege-escalation guard: only allow self-assignment of the 'lawyer' role
      // when the caller has no existing client/employee role. Lawyer accounts otherwise
      // come from the signup trigger (handle_new_user) or must be granted by an admin.
      const { data: existingRoles, error: rolesError } = await supabaseAdmin
        .from("user_roles")
        .select("role")
        .eq("user_id", userId);
      if (rolesError) throw new Error(rolesError.message);
      const roles = (existingRoles ?? []).map((r) => r.role);
      if (roles.includes("client") || roles.includes("employee")) {
        throw new Error("لا يمكن ترقية حساب بوابة العميل أو الموظف إلى محامٍ.");
      }
      if (!roles.includes("lawyer")) {
        await supabaseAdmin
          .from("user_roles")
          .upsert({ user_id: userId, role: "lawyer" }, { onConflict: "user_id,role" });
      }
      return { linked: true, role: "lawyer" as const };
    }

    const { data: authUser, error: authError } = await supabaseAdmin.auth.admin.getUserById(userId);
    if (authError || !authUser?.user?.email) throw new Error("تعذر قراءة بريد المستخدم الحالي");

    const email = authUser.user.email.trim().toLowerCase();
    const code = data.access_code?.trim() || null;

    if (data.account_type === "client") {
      const { data: alreadyLinked, error: currentError } = await supabaseAdmin
        .from("clients")
        .select("id")
        .eq("portal_user_id", userId)
        .maybeSingle();
      if (currentError) throw new Error(currentError.message);

      let clientId = alreadyLinked?.id ?? null;
      if (!clientId) {
        const { data: candidates, error } = await supabaseAdmin
          .from("clients")
          .select("id, client_portal_credentials(portal_access_code)")
          .or(`portal_user_id.is.null,portal_user_id.eq.${userId}`)
          .ilike("email", email)
          .order("created_at", { ascending: false })
          .limit(10);
        if (error) throw new Error(error.message);
        const match = (candidates ?? []).find((c: any) => {
          const cred = Array.isArray(c.client_portal_credentials)
            ? c.client_portal_credentials[0]?.portal_access_code ?? null
            : c.client_portal_credentials?.portal_access_code ?? null;
          return code ? cred === code : cred == null;
        });
        if (match?.id) {
          const { error: updateError } = await supabaseAdmin
            .from("clients")
            .update({ portal_user_id: userId })
            .eq("id", match.id);
          if (updateError) throw new Error(updateError.message);
          clientId = match.id;
        }
      }

      if (!clientId) throw new Error("لم يتم العثور على عميل بنفس البريد. أضف العميل من إدارة العملاء أو أدخل رمز البوابة الصحيح.");
      await supabaseAdmin.from("user_roles").upsert({ user_id: userId, role: "client" }, { onConflict: "user_id,role" });
      // Strict portal separation: client portal must never inherit lawyer / employee roles.
      await supabaseAdmin.from("user_roles").delete().eq("user_id", userId).in("role", ["lawyer", "employee"]);
      return { linked: true, role: "client" as const, id: clientId };
    }

    const { data: alreadyLinked, error: currentError } = await supabaseAdmin
      .from("employees")
      .select("id")
      .eq("user_id", userId)
      .maybeSingle();
    if (currentError) throw new Error(currentError.message);

    let employeeId = alreadyLinked?.id ?? null;
    if (!employeeId) {
      const { data: candidates, error } = await supabaseAdmin
        .from("employees")
        .select("id, employee_portal_credentials(portal_access_code)")
        .or(`user_id.is.null,user_id.eq.${userId}`)
        .ilike("email", email)
        .order("created_at", { ascending: false })
        .limit(10);
      if (error) throw new Error(error.message);
      const match = (candidates ?? []).find((c: any) => {
        const cred = Array.isArray(c.employee_portal_credentials)
          ? c.employee_portal_credentials[0]?.portal_access_code ?? null
          : c.employee_portal_credentials?.portal_access_code ?? null;
        return code ? cred === code : cred == null;
      });
      if (match?.id) {
        const { error: updateError } = await supabaseAdmin
          .from("employees")
          .update({ user_id: userId })
          .eq("id", match.id);
        if (updateError) throw new Error(updateError.message);
        employeeId = match.id;
      }
    }

    if (!employeeId) throw new Error("لم يتم العثور على موظف بنفس البريد. أضف الموظف من بيانات الموظفين أو أدخل رمز البوابة الصحيح.");
    await supabaseAdmin.from("user_roles").upsert({ user_id: userId, role: "employee" }, { onConflict: "user_id,role" });
    // Strict portal separation: employee portal must never inherit lawyer / client roles.
    await supabaseAdmin.from("user_roles").delete().eq("user_id", userId).in("role", ["lawyer", "client"]);
    return { linked: true, role: "employee" as const, id: employeeId };
  });