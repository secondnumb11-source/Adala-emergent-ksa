import { createFileRoute } from "@tanstack/react-router";
import { createHash, timingSafeEqual } from "crypto";
import { z } from "zod";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, X-Sync-Token",
  "Access-Control-Max-Age": "86400",
};

// Hard limits — defence in depth against oversized / malformed callers.
const MAX_BODY_BYTES = 2_000_000; // ~2 MB JSON payload cap
const MIN_TOKEN_LEN = 24;
const MAX_TOKEN_LEN = 256;
const TOKEN_RE = /^[A-Za-z0-9_\-+/=.]+$/; // hex / base64 / url-safe variants

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...CORS },
  });
}

// Constant-time compare of two hex hashes of equal length.
function safeEqHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  try {
    return timingSafeEqual(Buffer.from(a, "hex"), Buffer.from(b, "hex"));
  } catch {
    return false;
  }
}

// Shape coming from the Chrome extension
// Reusable field helpers — trim + length bounds + format checks
const ID = z.string().trim().min(1, "معرّف فارغ").max(120, "معرّف طويل جداً");
const SHORT = z.string().trim().min(1).max(200);
const LONG = z.string().trim().min(1).max(500);
const OPT_SHORT = z.string().trim().max(200).optional().or(z.literal("").transform(() => undefined));
const OPT_LONG = z.string().trim().max(500).optional().or(z.literal("").transform(() => undefined));

// Accept ISO date (YYYY-MM-DD) or full ISO timestamp
const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?)?$/;
const OPT_DATE = z
  .string()
  .trim()
  .regex(ISO_DATE_RE, "تاريخ غير صالح")
  .optional()
  .or(z.literal("").transform(() => undefined));
const REQ_DATE = z
  .string()
  .trim()
  .regex(ISO_DATE_RE, "تاريخ الجلسة غير صالح")
  .refine((v) => {
    const t = Date.parse(v);
    if (!Number.isFinite(t)) return false;
    const year = new Date(t).getUTCFullYear();
    return year >= 1970 && year <= 2100;
  }, "تاريخ خارج النطاق المسموح");

const MAX_ITEMS = 2000;

const PayloadSchema = z
  .object({
    kind: z.enum(["cases", "powers", "executions", "sessions", "documents", "mixed"]),
    sourceUrl: z.string().trim().max(1000).optional(),
    documents: z
      .array(
        z.object({
          najiz_id: ID,
          title: SHORT,
          case_number: OPT_SHORT,
          court: OPT_SHORT,
          status: OPT_SHORT,
          filed_date: OPT_DATE,
          source_url: z.string().trim().max(1000).optional(),
        }),
      )
      .max(MAX_ITEMS)
      .optional(),
    cases: z
      .array(
        z.object({
          najiz_id: ID,
          case_number: SHORT,
          title: OPT_LONG,
          court: OPT_SHORT,
          case_type: OPT_SHORT,
          status: OPT_SHORT,
          opened_at: OPT_DATE,
          client_name: OPT_SHORT,
        }),
      )
      .max(MAX_ITEMS, `تجاوز الحد الأقصى ${MAX_ITEMS} عنصر`)
      .optional(),
    powers: z
      .array(
        z.object({
          najiz_id: ID,
          wakalah_number: SHORT,
          issuer_name: OPT_SHORT,
          agent_name: OPT_SHORT,
          issue_date: OPT_DATE,
          expiry_date: OPT_DATE,
          scope: OPT_LONG,
        }),
      )
      .max(MAX_ITEMS)
      .optional(),
    executions: z
      .array(
        z.object({
          najiz_id: ID,
          execution_number: SHORT,
          court: OPT_SHORT,
          amount: z
            .number()
            .finite("قيمة غير صالحة")
            .min(0, "المبلغ لا يمكن أن يكون سالباً")
            .max(1_000_000_000_000, "المبلغ كبير جداً")
            .optional(),
          debtor_name: OPT_SHORT,
          status: OPT_SHORT,
          filed_date: OPT_DATE,
        }),
      )
      .max(MAX_ITEMS)
      .optional(),
    sessions: z
      .array(
        z.object({
          najiz_case_id: ID,
          session_date: REQ_DATE,
          court: OPT_SHORT,
          room: OPT_SHORT,
          status: OPT_SHORT,
        }),
      )
      .max(MAX_ITEMS)
      .optional(),
  })
  .superRefine((p, ctx) => {
    const counts = {
      cases: p.cases?.length ?? 0,
      powers: p.powers?.length ?? 0,
      executions: p.executions?.length ?? 0,
      sessions: p.sessions?.length ?? 0,
      documents: p.documents?.length ?? 0,
    };
    const total = counts.cases + counts.powers + counts.executions + counts.sessions + counts.documents;
    if (total === 0) {
      ctx.addIssue({ code: "custom", message: "لا توجد بيانات لحفظها — الحمولة فارغة" });
    }
    if (p.kind !== "mixed" && counts[p.kind] === 0) {
      ctx.addIssue({ code: "custom", path: [p.kind], message: `النوع "${p.kind}" مُعلَن لكن لا توجد عناصر مطابقة` });
    }
    for (const key of ["cases", "powers", "executions", "documents"] as const) {
      const arr = p[key];
      if (!arr) continue;
      const seen = new Set<string>();
      arr.forEach((item, i) => {
        const id = item.najiz_id;
        if (seen.has(id)) {
          ctx.addIssue({ code: "custom", path: [key, i, "najiz_id"], message: `معرّف مكرر في نفس الدفعة: ${id}` });
        }
        seen.add(id);
      });
    }
  });

function mapCaseType(raw?: string): string {
  if (!raw) return "other";
  const t = raw.toLowerCase();
  if (t.includes("عمل")) return "labor";
  if (t.includes("تجار")) return "commercial";
  if (t.includes("تنفيذ")) return "execution";
  if (t.includes("أحوال") || t.includes("احوال")) return "personal_status";
  if (t.includes("إدار") || t.includes("ادار")) return "administrative";
  if (t.includes("جناي") || t.includes("جزائ")) return "criminal";
  if (t.includes("مدن")) return "civil";
  return "other";
}

function mapCaseStatus(raw?: string): string {
  if (!raw) return "open";
  const t = raw.toLowerCase();
  if (t.includes("منته") || t.includes("مغلق")) return "closed_final";
  if (t.includes("استئناف")) return "appealed";
  if (t.includes("دراس")) return "in_study";
  return "open";
}

function mapExecutionStatus(raw?: string): string {
  if (!raw) return "pending";
  const t = raw.toLowerCase();
  if (t.includes("منته") || t.includes("مكتم")) return "completed";
  if (t.includes("جار") || t.includes("تنفيذ")) return "in_progress";
  if (t.includes("رفض")) return "rejected";
  return "pending";
}

export const Route = createFileRoute("/api/public/najiz-sync")({
  server: {
    handlers: {
      OPTIONS: async () => new Response(null, { status: 204, headers: CORS }),

      // Lightweight connection test — verifies the Base URL is reachable AND the
      // X-Sync-Token is valid, WITHOUT sending any data. Used by the dashboard
      // "Test connection" button and by the extension's pre-flight check.
      GET: async ({ request }) => {
        try {
          const token = request.headers.get("x-sync-token")?.trim();
          if (!token) {
            // Reachable endpoint, but no token supplied → confirm route works.
            return json({ ok: true, endpoint: "najiz-sync", authenticated: false, message: "الواجهة متاحة — لم يتم تقديم رمز للتحقق" });
          }
          if (token.length < MIN_TOKEN_LEN || token.length > MAX_TOKEN_LEN || !TOKEN_RE.test(token)) {
            return json({ ok: false, error: { code: "unauthorized", message: "رمز المزامنة غير صالح الصيغة" } }, 401);
          }
          const hash = createHash("sha256").update(token).digest("hex");
          const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
          const { data: tokenRow, error: tokErr } = await (supabaseAdmin as any)
            .from("sync_tokens").select("is_revoked, expires_at, token_hash, last_used_at").eq("token_hash", hash).maybeSingle();
          if (tokErr) {
            return json({ ok: false, error: { code: "server_error", message: "تعذّر التحقق من الرمز حالياً" } }, 500);
          }
          if (!tokenRow || !safeEqHex(String(tokenRow.token_hash ?? ""), hash)) {
            return json({ ok: false, error: { code: "unauthorized", message: "رمز المزامنة غير معروف — تأكد من نسخه كاملاً" } }, 401);
          }
          if (tokenRow.is_revoked) {
            return json({ ok: false, error: { code: "unauthorized", message: "تم إلغاء هذا الرمز — أنشئ رمزاً جديداً" } }, 401);
          }
          if (tokenRow.expires_at && new Date(tokenRow.expires_at) < new Date()) {
            return json({ ok: false, error: { code: "unauthorized", message: "انتهت صلاحية رمز المزامنة — أنشئ رمزاً جديداً" } }, 401);
          }
          return json({ ok: true, endpoint: "najiz-sync", authenticated: true, last_used_at: tokenRow.last_used_at ?? null, message: "الاتصال سليم — الرابط والرمز صحيحان وجاهزان للمزامنة" });
        } catch (e: any) {
          return json({ ok: false, error: { code: "server_error", message: "تعذّر إجراء اختبار الاتصال" } }, 500);
        }
      },

      POST: async ({ request }) => {
        const reqId = `najiz-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
        const trace: any[] = [];
        const log = (step: string, info?: unknown) => {
          const entry = { step, t: Date.now(), info };
          trace.push(entry);
          // live server-log output for debugging from server-function-logs / dev terminal
          console.log(`[najiz-sync ${reqId}] ${step}`, info !== undefined ? info : "");
        };

        try {
          // ---- content-type & size guards (before any work) ----
          const ctype = request.headers.get("content-type") ?? "";
          if (!ctype.toLowerCase().includes("application/json")) {
            log("bad_content_type", ctype);
            return json(
              { error: { code: "bad_request", message: "Content-Type يجب أن يكون application/json" } },
              415,
            );
          }
          const declaredLen = Number(request.headers.get("content-length") ?? "0");
          if (Number.isFinite(declaredLen) && declaredLen > MAX_BODY_BYTES) {
            log("payload_too_large_header", declaredLen);
            return json(
              { error: { code: "payload_too_large", message: "حجم الحمولة يتجاوز الحد المسموح" } },
              413,
            );
          }

          // ---- auth ----
          const token = request.headers.get("x-sync-token")?.trim();
          if (!token) {
            log("auth_missing");
            return json({ error: { code: "unauthorized", message: "X-Sync-Token مفقود" } }, 401);
          }
          if (
            token.length < MIN_TOKEN_LEN ||
            token.length > MAX_TOKEN_LEN ||
            !TOKEN_RE.test(token)
          ) {
            log("auth_bad_format");
            // Generic message — do not hint at token shape to callers.
            return json({ error: { code: "unauthorized", message: "رمز المزامنة غير صالح" } }, 401);
          }
          const hash = createHash("sha256").update(token).digest("hex");
          log("auth_hashed");

          const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
          const { data: tokenRow, error: tokErr } = await (supabaseAdmin as any)
            .from("sync_tokens").select("owner_id, is_revoked, expires_at, token_hash")
            .eq("token_hash", hash).maybeSingle();
          if (tokErr) {
            log("auth_db_error", tokErr.message);
            return json({ error: { code: "unauthorized", message: "تعذّر التحقق من الرمز" } }, 401);
          }
          if (!tokenRow || tokenRow.is_revoked || !safeEqHex(String(tokenRow.token_hash ?? ""), hash)) {
            log("auth_invalid");
            return json({ error: { code: "unauthorized", message: "رمز المزامنة غير صالح أو ملغى" } }, 401);
          }
          if (tokenRow.expires_at && new Date(tokenRow.expires_at) < new Date()) {
            log("auth_expired");
            return json({ error: { code: "unauthorized", message: "انتهت صلاحية رمز المزامنة" } }, 401);
          }
          const owner_id = tokenRow.owner_id;
          if (!owner_id || typeof owner_id !== "string") {
            log("auth_owner_missing");
            return json({ error: { code: "unauthorized", message: "رمز المزامنة غير صالح" } }, 401);
          }
          log("auth_ok", { owner_id });

          // ---- payload (size-capped read, then JSON.parse) ----
          const bodyText = await request.text().catch(() => "");
          if (!bodyText) {
            log("payload_empty");
            return json({ error: { code: "bad_request", message: "حمولة فارغة" } }, 400);
          }
          if (bodyText.length > MAX_BODY_BYTES) {
            log("payload_too_large", bodyText.length);
            return json(
              { error: { code: "payload_too_large", message: "حجم الحمولة يتجاوز الحد المسموح" } },
              413,
            );
          }
          let raw: unknown = null;
          try {
            raw = JSON.parse(bodyText);
          } catch {
            raw = null;
          }
          if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
            log("payload_invalid");
            return json({ error: { code: "bad_request", message: "حمولة JSON غير صالحة" } }, 400);
          }
          const parsed = PayloadSchema.safeParse(raw);
          if (!parsed.success) {
            log("payload_zod_failed", parsed.error.issues);
            // Return only field paths + safe messages — never the offending values.
            const safeIssues = parsed.error.issues.slice(0, 50).map((i) => ({
              path: i.path.join("."),
              message: i.message,
              code: i.code,
            }));
            return json(
              { error: { code: "bad_request", message: "حقول مفقودة أو غير صالحة", details: safeIssues } },
              400,
            );
          }
          const payload = parsed.data;
          log("payload_ok", { kind: payload.kind, counts: {
            cases: payload.cases?.length ?? 0,
            powers: payload.powers?.length ?? 0,
            executions: payload.executions?.length ?? 0,
            sessions: payload.sessions?.length ?? 0,
          }});

          let inserted = 0;
          let updated = 0;
          let total = 0;

          // ---- CASES (do NOT mix with executions/powers) ----
          if (payload.cases?.length) {
            log("mapping_cases", { count: payload.cases.length });
            const rows = payload.cases.map((c) => ({
              owner_id,
              najiz_id: c.najiz_id,
              case_number: c.case_number,
              title: c.title || c.case_number,
              court: c.court ?? null,
              case_type: mapCaseType(c.case_type) as any,
              status: mapCaseStatus(c.status) as any,
              opened_at: c.opened_at ?? new Date().toISOString().slice(0, 10),
              najiz_synced_at: new Date().toISOString(),
            }));
            total += rows.length;
            const { data, error } = await (supabaseAdmin as any)
              .from("cases")
              .upsert(rows, { onConflict: "owner_id,najiz_id", ignoreDuplicates: false })
              .select("id");
            if (error) {
              log("cases_upsert_error", error.message);
              throw new Error(`cases upsert: ${error.message}`);
            }
            inserted += data?.length ?? 0;
            log("cases_done", { affected: data?.length });
          }

          // ---- POWERS (separate; never written to executions) ----
          if (payload.powers?.length) {
            log("mapping_powers", { count: payload.powers.length });
            const rows = payload.powers.map((p) => ({
              owner_id,
              najiz_id: p.najiz_id,
              wakalah_number: p.wakalah_number,
              issuer_name: p.issuer_name ?? null,
              agent_name: p.agent_name ?? null,
              issue_date: p.issue_date ?? null,
              expiry_date: p.expiry_date ?? null,
              scope: p.scope ?? null,
              najiz_synced_at: new Date().toISOString(),
            }));
            total += rows.length;
            const { data, error } = await (supabaseAdmin as any)
              .from("powers_of_attorney")
              .upsert(rows, { onConflict: "owner_id,najiz_id" })
              .select("id");
            if (error) {
              log("powers_upsert_error", error.message);
              throw new Error(`powers upsert: ${error.message}`);
            }
            updated += data?.length ?? 0;
            log("powers_done", { affected: data?.length });
          }

          // ---- EXECUTIONS (separate target table) ----
          if (payload.executions?.length) {
            log("mapping_executions", { count: payload.executions.length });
            const rows = payload.executions.map((e) => ({
              owner_id,
              najiz_id: e.najiz_id,
              execution_number: e.execution_number,
              court: e.court ?? null,
              amount: e.amount ?? null,
              debtor_name: e.debtor_name ?? null,
              status: mapExecutionStatus(e.status) as any,
              filed_date: e.filed_date ?? null,
              najiz_synced_at: new Date().toISOString(),
            }));
            total += rows.length;
            const { data, error } = await (supabaseAdmin as any)
              .from("executions")
              .upsert(rows, { onConflict: "owner_id,najiz_id" })
              .select("id");
            if (error) {
              log("executions_upsert_error", error.message);
              throw new Error(`executions upsert: ${error.message}`);
            }
            updated += data?.length ?? 0;
            log("executions_done", { affected: data?.length });
          }

          // ---- SESSIONS (linked to existing cases; auto-create placeholder cases for unmatched IDs so sessions are never silently dropped) ----
          if (payload.sessions?.length) {
            log("mapping_sessions", { count: payload.sessions.length });
            const caseIds = Array.from(new Set(payload.sessions.map((s) => s.najiz_case_id)));
            const { data: linkedCases } = await (supabaseAdmin as any)
              .from("cases").select("id, najiz_id").eq("owner_id", owner_id).in("najiz_id", caseIds);
            const map = new Map((linkedCases ?? []).map((c: { najiz_id: string; id: string }) => [c.najiz_id, c.id]));

            // Auto-create placeholder cases for any session referring to a najiz_id that doesn't yet exist
            const missing = caseIds.filter((id) => !map.has(id));
            if (missing.length) {
              log("sessions_auto_create_placeholders", { count: missing.length });
              const placeholderRows = missing.map((najiz_id) => ({
                owner_id,
                najiz_id,
                case_number: najiz_id.replace(/^case_/, ""),
                title: `قضية (من جلسة) — ${najiz_id.replace(/^case_/, "")}`,
                court: null,
                case_type: "other" as any,
                status: "open" as any,
                opened_at: new Date().toISOString().slice(0, 10),
                najiz_synced_at: new Date().toISOString(),
              }));
              const { data: created } = await (supabaseAdmin as any)
                .from("cases")
                .upsert(placeholderRows, { onConflict: "owner_id,najiz_id", ignoreDuplicates: false })
                .select("id, najiz_id");
              (created ?? []).forEach((c: { najiz_id: string; id: string }) => map.set(c.najiz_id, c.id));
            }

            const rows = payload.sessions
              .filter((s) => map.has(s.najiz_case_id))
              .map((s) => ({
                owner_id,
                case_id: map.get(s.najiz_case_id)!,
                session_date: s.session_date,
                court: s.court ?? null,
                room: s.room ?? null,
              }));
            total += rows.length;
            if (rows.length) {
              // Deduplicate against existing sessions (same case + date) to avoid double-inserts on resync
              const dedupeKeys = rows.map((r) => `${r.case_id}|${r.session_date}`);
              const { data: existingSessions } = await (supabaseAdmin as any)
                .from("sessions").select("case_id, session_date").in("case_id", rows.map((r) => r.case_id));
              const existing = new Set((existingSessions ?? []).map((s: any) => `${s.case_id}|${s.session_date}`));
              const newRows = rows.filter((r, i) => !existing.has(dedupeKeys[i]));
              if (newRows.length) {
                const { error } = await (supabaseAdmin as any).from("sessions").insert(newRows);
                if (error) {
                  log("sessions_insert_error", error.message);
                  throw new Error(`sessions insert: ${error.message}`);
                }
                inserted += newRows.length;
              }
            }
            log("sessions_done", { affected: rows.length });
          }

          // ---- DOCUMENTS (judgments / decisions / requests-on-cases → documents archive) ----
          if (payload.documents?.length) {
            log("mapping_documents", { count: payload.documents.length });
            // Build a najiz_id → cases.id lookup for linking documents to cases when possible
            const caseNumbers = Array.from(new Set(payload.documents.map((d) => d.case_number).filter(Boolean) as string[]));
            let caseMap = new Map<string, string>();
            if (caseNumbers.length) {
              const { data: linkedCases } = await (supabaseAdmin as any)
                .from("cases").select("id, najiz_id").eq("owner_id", owner_id).in("najiz_id", caseNumbers);
              caseMap = new Map((linkedCases ?? []).map((c: { najiz_id: string; id: string }) => [c.najiz_id, c.id]));
            }
            const inferDocType = (title: string) => {
              const t = (title || "").toLowerCase();
              if (/استئناف|نقض/.test(t)) return "judgment_appeal" as any;
              if (/حكم|صك|judgment/.test(t)) return "judgment_final" as any;
              if (/قرار|decision/.test(t)) return "decision" as any;
              if (/محضر|ضبط/.test(t)) return "minute" as any;
              return "lawsuit" as any;
            };
            const rows = payload.documents.map((d) => ({
              owner_id,
              title: d.title,
              case_id: d.case_number ? caseMap.get(d.case_number) ?? null : null,
              court: d.court ?? null,
              filed_date: d.filed_date ?? null,
              description: d.source_url ? `مصدر: ${d.source_url}` : null,
              doc_type: inferDocType(d.title),
            }));
            total += rows.length;
            if (rows.length) {
              // Idempotent: skip documents that already exist by (owner_id, title, filed_date)
              const titles = rows.map((r) => r.title);
              const { data: existingDocs } = await (supabaseAdmin as any)
                .from("documents").select("title, filed_date").eq("owner_id", owner_id).in("title", titles);
              const existSet = new Set((existingDocs ?? []).map((d: any) => `${d.title}|${d.filed_date ?? ""}`));
              const newRows = rows.filter((r) => !existSet.has(`${r.title}|${r.filed_date ?? ""}`));
              if (newRows.length) {
                const { data, error } = await (supabaseAdmin as any).from("documents").insert(newRows).select("id");
                if (error) {
                  log("documents_insert_error", error.message);
                  throw new Error(`documents insert: ${error.message}`);
                }
                inserted += data?.length ?? 0;
              }
            }
            log("documents_done", { affected: rows.length });
          }


          // ---- record sync log ----
          await (supabaseAdmin as any).from("najiz_sync_logs").insert({
            owner_id,
            source: `extension:${payload.kind}`,
            status: "success",
            items_count: total,
            inserted_count: inserted,
            updated_count: updated,
            raw_payload: { payload, trace } as any,
          });

          await (supabaseAdmin as any).from("sync_tokens")
            .update({ last_used_at: new Date().toISOString() })
            .eq("token_hash", hash);


          log("done");
          return json({ ok: true, total, inserted, updated });
        } catch (err) {
          const message = err instanceof Error ? err.message : "خطأ غير معروف";
          trace.push({ step: "fatal_error", info: message });
          // Log full error server-side only; never echo internal details to the caller.
          console.error("[najiz-sync] fatal", err);
          try {
            const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
            const token = request.headers.get("x-sync-token")?.trim();
            if (token) {
              const hash = createHash("sha256").update(token).digest("hex");
              const { data: tokenRow } = await (supabaseAdmin as any)
                .from("sync_tokens").select("owner_id").eq("token_hash", hash).maybeSingle();
              if (tokenRow) {
                await (supabaseAdmin as any).from("najiz_sync_logs").insert({
                  owner_id: (tokenRow as any).owner_id,
                  source: "extension:mixed",
                  status: "failed",
                  error_message: message,
                  raw_payload: { trace } as any,
                });
              }
            }
          } catch { /* swallow logging errors */ }
          return json(
            { error: { code: "internal", message: "حدث خطأ داخلي. يرجى المحاولة لاحقاً." } },
            500,
          );
        }
      },
    },
  },
});
