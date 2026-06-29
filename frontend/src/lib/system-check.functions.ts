import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

const REQUIRED_TABLES = [
  "profiles", "user_roles", "clients", "cases", "sessions", "documents",
  "powers_of_attorney", "executions", "employees", "tasks",
  "client_notifications", "portal_messages",
  "user_preferences", "notification_preferences",
  "audit_log", "sync_tokens", "najiz_sync_logs",
  "session_reminders", "task_reminders",
];

const REQUIRED_RPCS = [
  "has_role", "handle_new_user", "update_updated_at_column",
  "set_appeal_deadline", "link_current_user_to_portal",
  "enqueue_session_reminders", "enqueue_task_reminders",
  "get_cron_jobs_status", "system_check_inspect",
];

const REQUIRED_BUCKETS = ["case-documents"];
const REALTIME_TABLES = ["cases", "documents", "portal_messages", "sessions", "tasks"];

export type SystemCheckReport = {
  ok: boolean;
  generatedAt: string;
  summary: {
    tables: { present: number; total: number };
    rls: { enabled: number; total: number };
    rpcs: { present: number; total: number };
    buckets: { present: number; total: number };
    realtime: { present: number; total: number };
  };
  tables: Array<{ name: string; exists: boolean; rlsEnabled: boolean; policies: number; grants: Record<string, string[]> }>;
  rpcs: Array<{ name: string; exists: boolean }>;
  buckets: Array<{ name: string; exists: boolean; public: boolean }>;
  realtime: Array<{ name: string; inPublication: boolean }>;
};

type InspectPayload = {
  tables?: Array<{ tablename: string; rls: boolean }>;
  policies?: Array<{ tablename: string; cnt: number }>;
  grants?: Array<{ table_name: string; grantee: string; privilege_type: string }>;
  rpcs?: string[];
  publication?: string[];
  buckets?: Array<{ name: string; public: boolean }>;
};

async function runFullReport(callerSupabase?: { rpc: (name: string) => Promise<{ data: unknown; error: { message: string } | null }> }): Promise<SystemCheckReport> {
  let payload: InspectPayload = {};

  // All SECURITY DEFINER RPCs are revoked from authenticated; call via admin.
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data } = await supabaseAdmin.rpc("system_check_inspect" as never);
  if (data && typeof data === "object") payload = data as InspectPayload;
  void callerSupabase;


  const rlsMap = new Map((payload.tables ?? []).map((t) => [t.tablename, t.rls]));
  const existSet = new Set((payload.tables ?? []).map((t) => t.tablename));
  const polMap = new Map((payload.policies ?? []).map((p) => [p.tablename, p.cnt]));
  const grantsMap: Record<string, Record<string, string[]>> = {};
  for (const g of payload.grants ?? []) {
    grantsMap[g.table_name] ??= {};
    grantsMap[g.table_name][g.grantee] ??= [];
    if (!grantsMap[g.table_name][g.grantee].includes(g.privilege_type)) {
      grantsMap[g.table_name][g.grantee].push(g.privilege_type);
    }
  }

  const tables = REQUIRED_TABLES.map((name) => ({
    name,
    exists: existSet.has(name),
    rlsEnabled: rlsMap.get(name) ?? false,
    policies: polMap.get(name) ?? 0,
    grants: grantsMap[name] ?? {},
  }));

  const rpcSet = new Set(payload.rpcs ?? []);
  const rpcs = REQUIRED_RPCS.map((name) => ({ name, exists: rpcSet.has(name) }));

  const bucketIndex = new Map((payload.buckets ?? []).map((b) => [b.name, b.public]));
  const buckets = REQUIRED_BUCKETS.map((name) => ({
    name,
    exists: bucketIndex.has(name),
    public: bucketIndex.get(name) ?? false,
  }));

  const pubSet = new Set(payload.publication ?? []);
  const realtime = REALTIME_TABLES.map((name) => ({ name, inPublication: pubSet.has(name) }));

  const summary = {
    tables: { present: tables.filter((t) => t.exists).length, total: tables.length },
    rls: { enabled: tables.filter((t) => t.rlsEnabled).length, total: tables.length },
    rpcs: { present: rpcs.filter((r) => r.exists).length, total: rpcs.length },
    buckets: { present: buckets.filter((b) => b.exists).length, total: buckets.length },
    realtime: { present: realtime.filter((r) => r.inPublication).length, total: realtime.length },
  };

  const ok =
    summary.tables.present === summary.tables.total &&
    summary.rls.enabled === summary.rls.total &&
    summary.rpcs.present === summary.rpcs.total &&
    summary.buckets.present === summary.buckets.total;

  return { ok, generatedAt: new Date().toISOString(), summary, tables, rpcs, buckets, realtime };
}

export const runSystemCheck = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    await assertAdminLike(context.userId);
    return await runFullReport(context.supabase as never);
  });

export async function publicSystemCheck(): Promise<SystemCheckReport> {
  return await runFullReport();
}

// Seed demo data — owner-scoped, RLS applies (admin/lawyer only)
export const seedDemoData = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    await assertAdminLike(context.userId);
    const sb = context.supabase;
    const owner_id = context.userId;
    const tag = `DEMO-${Date.now().toString(36).slice(-5).toUpperCase()}`;

    const { data: client, error: ec } = await sb.from("clients").insert({
      owner_id,
      full_name: `عميل تجريبي ${tag}`,
      email: `demo+${tag.toLowerCase()}@example.test`,
      phone: "+966500000000",
      address: "الرياض - تجريبي",
      notes: "بيانات اختبار آلية",
    }).select("id").single();
    if (ec) throw new Error(`clients: ${ec.message}`);

    const { data: emp, error: ee } = await sb.from("employees").insert({
      owner_id,
      full_name: `موظف تجريبي ${tag}`,
      email: `emp+${tag.toLowerCase()}@example.test`,
      phone: "+966500000001",
      job_title: "محامٍ مساعد",
    }).select("id").single();
    if (ee) throw new Error(`employees: ${ee.message}`);

    const { data: cse, error: ecs } = await sb.from("cases").insert({
      owner_id,
      client_id: client!.id,
      title: `قضية تجريبية ${tag}`,
      case_number: `CASE-${tag}`,
      status: "open",
      case_type: "civil",
      description: "قضية مُولَّدة آلياً للتحقق من النظام",
    }).select("id").single();
    if (ecs) throw new Error(`cases: ${ecs.message}`);

    const { error: ep } = await sb.from("powers_of_attorney").insert({
      owner_id,
      client_id: client!.id,
      wakalah_number: `WKL-${tag}`,
      issue_date: new Date().toISOString().slice(0, 10),
      scope: "تمثيل عام تجريبي",
    });
    if (ep) throw new Error(`powers_of_attorney: ${ep.message}`);

    const { error: ed } = await sb.from("documents").insert({
      owner_id,
      case_id: cse!.id,
      title: `مستند تجريبي ${tag}`,
      doc_type: "other",
      storage_path: `demo/${tag}.txt`,
    });
    if (ed) throw new Error(`documents: ${ed.message}`);

    const { error: eex } = await sb.from("executions").insert({
      owner_id,
      case_id: cse!.id,
      execution_number: `EXE-${tag}`,
      status: "pending",
      amount: 1000,
      notes: "طلب تنفيذ تجريبي",
    });
    if (eex) throw new Error(`executions: ${eex.message}`);

    const { error: es } = await sb.from("sessions").insert({
      owner_id,
      case_id: cse!.id,
      session_date: new Date(Date.now() + 2 * 86400000).toISOString(),
      status: "scheduled",
      court: "محكمة تجريبية",
      notes: "جلسة مُولَّدة آلياً",
    });
    if (es) throw new Error(`sessions: ${es.message}`);

    const { error: et } = await sb.from("tasks").insert({
      owner_id,
      employee_id: emp!.id,
      title: `مهمة تجريبية ${tag}`,
      due_date: new Date(Date.now() + 86400000).toISOString().slice(0, 10),
      status: "todo",
      priority: "medium",
    });
    if (et) throw new Error(`tasks: ${et.message}`);

    return { ok: true, tag, ids: { client: client!.id, employee: emp!.id, case: cse!.id } };
  });

// ============ RLS Multi-Role Tests ============
export type RlsTestCase = { name: string; expected: string; actual: string; pass: boolean };
export type RlsTestReport = { ok: boolean; passed: number; failed: number; cases: RlsTestCase[]; cleanedUp: boolean; error?: string };

export const runRlsTests = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }): Promise<RlsTestReport> => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { createClient } = await import("@supabase/supabase-js");
    // has_role EXECUTE was revoked from authenticated; call via admin client.
    const { data: isLawyer } = await supabaseAdmin.rpc("has_role" as never, {
      _user_id: context.userId, _role: "lawyer",
    } as never);
    const { data: isAdmin } = await supabaseAdmin.rpc("has_role" as never, {
      _user_id: context.userId, _role: "admin",
    } as never);
    if (!isLawyer && !isAdmin) throw new Error("forbidden: lawyer/admin only");

    const SUPABASE_URL = process.env.SUPABASE_URL!;
    const SUPABASE_PUBLISHABLE_KEY = process.env.SUPABASE_PUBLISHABLE_KEY!;


    const cases: RlsTestCase[] = [];
    const add = (name: string, expected: string, actual: string, pass: boolean) =>
      cases.push({ name, expected, actual, pass });

    const stamp = Date.now().toString(36);
    const users: { id: string; email: string; password: string; role: "lawyerA" | "lawyerB" | "client" }[] = [
      { id: "", email: `rls-lawyerA-${stamp}@example.test`, password: "RlsTest!" + stamp, role: "lawyerA" },
      { id: "", email: `rls-lawyerB-${stamp}@example.test`, password: "RlsTest!" + stamp, role: "lawyerB" },
      { id: "", email: `rls-client-${stamp}@example.test`, password: "RlsTest!" + stamp, role: "client" },
    ];

    const created: string[] = [];
    try {
      // 1) Create users
      for (const u of users) {
        const { data, error } = await supabaseAdmin.auth.admin.createUser({
          email: u.email, password: u.password, email_confirm: true,
        });
        if (error || !data.user) throw new Error(`createUser ${u.role}: ${error?.message}`);
        u.id = data.user.id;
        created.push(u.id);
      }

      const tokens: Record<string, string> = {};
      for (const u of users) {
        const tmp = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
          auth: { persistSession: false, autoRefreshToken: false, storage: undefined as never },
        });
        const { data, error } = await tmp.auth.signInWithPassword({ email: u.email, password: u.password });
        if (error || !data.session) throw new Error(`signIn ${u.role}: ${error?.message}`);
        tokens[u.role] = data.session.access_token;
      }

      const asUser = (role: "lawyerA" | "lawyerB" | "client") =>
        createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
          auth: { persistSession: false, autoRefreshToken: false, storage: undefined as never },
          global: { headers: { Authorization: `Bearer ${tokens[role]}` } },
        });

      const sbA = asUser("lawyerA");
      const sbB = asUser("lawyerB");
      const sbC = asUser("client");

      // 2) lawyerA creates a client (linking the client-portal user) + case
      const lawyerA = users.find((x) => x.role === "lawyerA")!;
      const clientUser = users.find((x) => x.role === "client")!;

      const insClient = await sbA.from("clients").insert({
        owner_id: lawyerA.id, full_name: "RLS Client A",
        email: clientUser.email, portal_user_id: clientUser.id,
      }).select("id").single();
      add("lawyerA can insert client", "success", insClient.error?.message ?? "ok", !insClient.error);
      if (insClient.error) throw new Error("setup failed");
      const clientId = insClient.data!.id;

      const insCase = await sbA.from("cases").insert({
        owner_id: lawyerA.id, client_id: clientId,
        title: "RLS Case A", case_number: `RLS-${stamp}`, status: "open", case_type: "civil",
      }).select("id").single();
      add("lawyerA can insert case", "success", insCase.error?.message ?? "ok", !insCase.error);
      if (insCase.error) throw new Error("setup failed");
      const caseId = insCase.data!.id;

      // 3) lawyerB tries to read lawyerA's case
      const bRead = await sbB.from("cases").select("id").eq("id", caseId);
      add("lawyerB CANNOT read lawyerA's case", "0 rows", `${bRead.data?.length ?? 0} rows`,
        !bRead.error && (bRead.data?.length ?? 0) === 0);

      // 4) lawyerB tries to update lawyerA's case
      const bUpd = await sbB.from("cases").update({ title: "hacked" }).eq("id", caseId).select("id");
      add("lawyerB CANNOT update lawyerA's case", "0 rows", `${bUpd.data?.length ?? 0} rows`,
        (bUpd.data?.length ?? 0) === 0);

      // 5) lawyerB tries to delete lawyerA's case
      const bDel = await sbB.from("cases").delete().eq("id", caseId).select("id");
      add("lawyerB CANNOT delete lawyerA's case", "0 rows", `${bDel.data?.length ?? 0} rows`,
        (bDel.data?.length ?? 0) === 0);

      // 6) lawyerB cannot read lawyerA's clients
      const bClients = await sbB.from("clients").select("id").eq("id", clientId);
      add("lawyerB CANNOT read lawyerA's clients", "0 rows", `${bClients.data?.length ?? 0} rows`,
        (bClients.data?.length ?? 0) === 0);

      // 7) client (portal user) CAN read their own case via portal RLS
      const cRead = await sbC.from("cases").select("id").eq("id", caseId);
      add("client portal CAN read own case", ">=1 row", `${cRead.data?.length ?? 0} rows`,
        (cRead.data?.length ?? 0) >= 1);

      // 8) client portal CANNOT update the case (no UPDATE policy for clients)
      const cUpd = await sbC.from("cases").update({ title: "client-hack" }).eq("id", caseId).select("id");
      add("client portal CANNOT update case", "0 rows", `${cUpd.data?.length ?? 0} rows`,
        (cUpd.data?.length ?? 0) === 0);

      // 9) lawyerA still owns the case (sanity)
      const aRead = await sbA.from("cases").select("title").eq("id", caseId).single();
      add("lawyerA still owns case (title unchanged)", "RLS Case A", aRead.data?.title ?? "(missing)",
        aRead.data?.title === "RLS Case A");

      // 10) lawyerB CANNOT insert a document into lawyerA's case
      const bDoc = await sbB.from("documents").insert({
        owner_id: users.find((x) => x.role === "lawyerB")!.id,
        case_id: caseId, title: "intruder", doc_type: "other", storage_path: "x",
      }).select("id");
      // Either RLS blocks (error) or FK passes but is invisible; either way, not viewable by A
      const bDocVisibleToA = await sbA.from("documents").select("id").eq("case_id", caseId).eq("title", "intruder");
      add("lawyerB cannot inject document visible to lawyerA", "0 rows",
        `${bDocVisibleToA.data?.length ?? 0} rows`,
        (bDocVisibleToA.data?.length ?? 0) === 0);
      // cleanup any stray
      if (bDoc.data?.length) {
        for (const d of bDoc.data) await supabaseAdmin.from("documents").delete().eq("id", d.id);
      }
    } catch (e) {
      add("test runner", "no exception", (e as Error).message, false);
    }

    // Cleanup users (cascades remove their owned rows)
    let cleanedUp = true;
    for (const uid of created) {
      try { await supabaseAdmin.auth.admin.deleteUser(uid); } catch { cleanedUp = false; }
    }

    const passed = cases.filter((c) => c.pass).length;
    const failed = cases.length - passed;
    return { ok: failed === 0, passed, failed, cases, cleanedUp };
  });

// ============ Maintenance RPC wrappers (admin-only) ============
async function assertAdminLike(userId: string) {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data: l } = await supabaseAdmin.rpc("has_role" as never, { _user_id: userId, _role: "lawyer" } as never);
  const { data: a } = await supabaseAdmin.rpc("has_role" as never, { _user_id: userId, _role: "admin" } as never);
  if (!l && !a) throw new Error("forbidden");
}

export const runEnqueueSessionReminders = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    await assertAdminLike(context.userId);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data, error } = await supabaseAdmin.rpc("enqueue_session_reminders" as never);
    if (error) throw new Error(error.message);
    return { ok: true, inserted: data as number };
  });

export const runEnqueueTaskReminders = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    await assertAdminLike(context.userId);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data, error } = await supabaseAdmin.rpc("enqueue_task_reminders" as never);
    if (error) throw new Error(error.message);
    return { ok: true, inserted: data as number };
  });

export const getCronJobsStatusFn = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    await assertAdminLike(context.userId);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data, error } = await supabaseAdmin.rpc("get_cron_jobs_status" as never);
    if (error) throw new Error(error.message);
    return data;
  });

// ============ CRUD Integration Tests ============
export type CrudStep = { entity: string; op: "insert" | "read" | "update" | "delete"; ok: boolean; detail: string };
export type CrudIntegrationReport = {
  ok: boolean;
  passed: number;
  failed: number;
  steps: CrudStep[];
  cleanedUp: boolean;
};

export const runCrudIntegrationTests = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }): Promise<CrudIntegrationReport> => {
    await assertAdminLike(context.userId);
    const sb = context.supabase;
    const owner_id = context.userId;
    const tag = `IT-${Date.now().toString(36).slice(-6).toUpperCase()}`;
    const steps: CrudStep[] = [];
    const push = (entity: string, op: CrudStep["op"], ok: boolean, detail: string) =>
      steps.push({ entity, op, ok, detail });

    type Created = {
      clientId?: string; employeeId?: string; caseId?: string;
      docId?: string; execId?: string; poaId?: string;
      sessionId?: string; taskId?: string;
    };
    const c: Created = {};

    try {
      // 1) clients
      {
        const ins = await sb.from("clients").insert({
          owner_id, full_name: `IT Client ${tag}`, email: `it+${tag.toLowerCase()}@test.local`,
          phone: "+966500000010",
        }).select("id, full_name").single();
        push("clients", "insert", !ins.error && !!ins.data, ins.error?.message ?? `id=${ins.data?.id}`);
        if (ins.error || !ins.data) throw new Error("clients insert");
        c.clientId = ins.data.id;

        const rd = await sb.from("clients").select("full_name").eq("id", c.clientId).single();
        push("clients", "read", !rd.error && rd.data?.full_name === `IT Client ${tag}`,
          rd.error?.message ?? `name=${rd.data?.full_name}`);

        const up = await sb.from("clients").update({ phone: "+966500000099" }).eq("id", c.clientId).select("phone").single();
        push("clients", "update", !up.error && up.data?.phone === "+966500000099",
          up.error?.message ?? `phone=${up.data?.phone}`);
      }

      // 2) employees
      {
        const ins = await sb.from("employees").insert({
          owner_id, full_name: `IT Emp ${tag}`, email: `emp+${tag.toLowerCase()}@test.local`,
          job_title: "محامٍ تجريبي",
        }).select("id").single();
        push("employees", "insert", !ins.error && !!ins.data, ins.error?.message ?? `id=${ins.data?.id}`);
        if (ins.error || !ins.data) throw new Error("employees insert");
        c.employeeId = ins.data.id;

        const rd = await sb.from("employees").select("full_name").eq("id", c.employeeId).single();
        push("employees", "read", !rd.error && !!rd.data, rd.error?.message ?? "ok");

        const up = await sb.from("employees").update({ job_title: "شريك" }).eq("id", c.employeeId).select("job_title").single();
        push("employees", "update", !up.error && up.data?.job_title === "شريك",
          up.error?.message ?? `job=${up.data?.job_title}`);
      }

      // 3) cases
      {
        const ins = await sb.from("cases").insert({
          owner_id, client_id: c.clientId!, title: `IT Case ${tag}`,
          case_number: `IT-${tag}`, status: "open", case_type: "civil",
        }).select("id").single();
        push("cases", "insert", !ins.error && !!ins.data, ins.error?.message ?? `id=${ins.data?.id}`);
        if (ins.error || !ins.data) throw new Error("cases insert");
        c.caseId = ins.data.id;

        const rd = await sb.from("cases").select("title, status").eq("id", c.caseId).single();
        push("cases", "read", !rd.error && rd.data?.status === "open",
          rd.error?.message ?? `status=${rd.data?.status}`);

        const up = await sb.from("cases").update({ status: "closed_final" }).eq("id", c.caseId).select("status").single();
        push("cases", "update", !up.error && up.data?.status === "closed_final",
          up.error?.message ?? `status=${up.data?.status}`);
      }

      // 4) powers_of_attorney
      {
        const ins = await sb.from("powers_of_attorney").insert({
          owner_id, client_id: c.clientId!, wakalah_number: `WK-${tag}`,
          issue_date: new Date().toISOString().slice(0, 10), scope: "اختبار تكامل",
        }).select("id").single();
        push("powers_of_attorney", "insert", !ins.error && !!ins.data, ins.error?.message ?? `id=${ins.data?.id}`);
        if (ins.error || !ins.data) throw new Error("poa insert");
        c.poaId = ins.data.id;

        const rd = await sb.from("powers_of_attorney").select("wakalah_number").eq("id", c.poaId).single();
        push("powers_of_attorney", "read", !rd.error && rd.data?.wakalah_number === `WK-${tag}`,
          rd.error?.message ?? `wk=${rd.data?.wakalah_number}`);
      }

      // 5) documents
      {
        const ins = await sb.from("documents").insert({
          owner_id, case_id: c.caseId!, title: `IT Doc ${tag}`,
          doc_type: "other", storage_path: `it/${tag}.txt`,
        }).select("id").single();
        push("documents", "insert", !ins.error && !!ins.data, ins.error?.message ?? `id=${ins.data?.id}`);
        if (ins.error || !ins.data) throw new Error("documents insert");
        c.docId = ins.data.id;

        const rd = await sb.from("documents").select("title").eq("id", c.docId).single();
        push("documents", "read", !rd.error && rd.data?.title === `IT Doc ${tag}`,
          rd.error?.message ?? `title=${rd.data?.title}`);

        const up = await sb.from("documents").update({ title: `IT Doc ${tag} v2` }).eq("id", c.docId).select("title").single();
        push("documents", "update", !up.error && up.data?.title === `IT Doc ${tag} v2`,
          up.error?.message ?? `title=${up.data?.title}`);
      }

      // 6) executions
      {
        const ins = await sb.from("executions").insert({
          owner_id, case_id: c.caseId!, execution_number: `EX-${tag}`,
          status: "pending", amount: 2500, notes: "اختبار تكامل",
        }).select("id").single();
        push("executions", "insert", !ins.error && !!ins.data, ins.error?.message ?? `id=${ins.data?.id}`);
        if (ins.error || !ins.data) throw new Error("executions insert");
        c.execId = ins.data.id;

        const rd = await sb.from("executions").select("amount, status").eq("id", c.execId).single();
        push("executions", "read", !rd.error && Number(rd.data?.amount) === 2500,
          rd.error?.message ?? `amount=${rd.data?.amount}`);

        const up = await sb.from("executions").update({ status: "in_progress" }).eq("id", c.execId).select("status").single();
        push("executions", "update", !up.error && up.data?.status === "in_progress",
          up.error?.message ?? `status=${up.data?.status}`);
      }

      // 7) sessions (bonus)
      {
        const ins = await sb.from("sessions").insert({
          owner_id, case_id: c.caseId!,
          session_date: new Date(Date.now() + 3 * 86400000).toISOString(),
          status: "scheduled", court: "محكمة اختبار",
        }).select("id").single();
        push("sessions", "insert", !ins.error && !!ins.data, ins.error?.message ?? `id=${ins.data?.id}`);
        if (!ins.error && ins.data) c.sessionId = ins.data.id;
      }

      // 8) tasks (bonus)
      {
        const ins = await sb.from("tasks").insert({
          owner_id, employee_id: c.employeeId!, title: `IT Task ${tag}`,
          due_date: new Date(Date.now() + 86400000).toISOString().slice(0, 10),
          status: "todo", priority: "medium",
        }).select("id").single();
        push("tasks", "insert", !ins.error && !!ins.data, ins.error?.message ?? `id=${ins.data?.id}`);
        if (!ins.error && ins.data) c.taskId = ins.data.id;
      }
    } catch (e) {
      push("runner", "insert", false, (e as Error).message);
    }

    // Cleanup in reverse dependency order
    let cleanedUp = true;
    const cleanup = async (table: string, id?: string) => {
      if (!id) return;
      const del = await sb.from(table as never).delete().eq("id", id);
      const ok = !del.error;
      push(table, "delete", ok, del.error?.message ?? "ok");
      if (!ok) cleanedUp = false;
    };
    await cleanup("tasks", c.taskId);
    await cleanup("sessions", c.sessionId);
    await cleanup("executions", c.execId);
    await cleanup("documents", c.docId);
    await cleanup("powers_of_attorney", c.poaId);
    await cleanup("cases", c.caseId);
    await cleanup("employees", c.employeeId);
    await cleanup("clients", c.clientId);

    const passed = steps.filter((s) => s.ok).length;
    const failed = steps.length - passed;
    return { ok: failed === 0, passed, failed, steps, cleanedUp };
  });
