import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

const BUCKET = "case-documents";

/**
 * Ensures the `case-documents` private storage bucket exists.
 * Idempotent: returns ok if already present. Fixes the "Bucket not found" error
 * that appears on first use of the archive page.
 */
export const ensureCaseDocumentsBucket = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .handler(async () => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: existing } = await supabaseAdmin.storage.getBucket(BUCKET);
    if (existing) return { ok: true, created: false };

    const { error } = await supabaseAdmin.storage.createBucket(BUCKET, {
      public: false,
      fileSizeLimit: 52428800, // 50MB
      allowedMimeTypes: [
        "application/pdf",
        "image/png",
        "image/jpeg",
        "image/webp",
        "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.ms-excel",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "text/plain",
      ],
    });
    if (error && !/already exists/i.test(error.message)) {
      throw new Error(error.message);
    }
    return { ok: true, created: true };
  });