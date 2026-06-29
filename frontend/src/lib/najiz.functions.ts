import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { z } from "zod";
import { createHash, randomBytes } from "crypto";

// Hash helper
function sha256(value: string) {
  return createHash("sha256").update(value).digest("hex");
}

/**
 * Issue a new sync token for the Chrome extension.
 * Returns the plaintext token only once.
 */
export const issueSyncToken = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => z.object({ label: z.string().min(1).max(80).optional() }).parse(input))
  .handler(async ({ data, context }) => {
    const raw = randomBytes(32).toString("base64url");
    const token = `adala_${raw}`;
    const hash = sha256(token);
    const { error } = await context.supabase.from("sync_tokens").insert({
      owner_id: context.userId,
      token_hash: hash,
      label: data.label ?? "Chrome Extension",
    });
    if (error) throw new Error(error.message);
    return { token, owner_id: context.userId };
  });

/**
 * Najiz portal health-check.
 * Does a lightweight check that the public Najiz portal is reachable.
 * Returns a uniform shape: { ok, status, latency_ms, message }.
 */
export const najizHealthCheck = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .handler(async () => {
    const url = "https://najiz.sa";
    const start = Date.now();
    try {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), 8000);
      const res = await fetch(url, { method: "HEAD", signal: ctrl.signal, redirect: "follow" });
      clearTimeout(timer);
      const latency = Date.now() - start;
      return {
        ok: res.ok,
        status: res.status,
        latency_ms: latency,
        message: res.ok ? "بوابة ناجز تستجيب بشكل طبيعي" : `استجابة غير متوقعة من بوابة ناجز (${res.status})`,
      };
    } catch (err) {
      const latency = Date.now() - start;
      const message = err instanceof Error ? err.message : "تعذّر الوصول إلى ناجز";
      return {
        ok: false,
        status: 0,
        latency_ms: latency,
        message: `فشل الاتصال ببوابة ناجز: ${message}`,
      };
    }
  });

/**
 * Revoke a sync token.
 */
export const revokeSyncToken = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => z.object({ id: z.string().uuid() }).parse(input))
  .handler(async ({ data, context }) => {
    const { error } = await context.supabase
      .from("sync_tokens").update({ is_revoked: true }).eq("id", data.id).eq("owner_id", context.userId);
    if (error) throw new Error(error.message);
    return { ok: true };
  });
