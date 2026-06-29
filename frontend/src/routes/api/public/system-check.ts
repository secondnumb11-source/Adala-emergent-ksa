import { createFileRoute } from "@tanstack/react-router";
import { publicSystemCheck } from "@/lib/system-check.functions";

export const Route = createFileRoute("/api/public/system-check")({
  server: {
    handlers: {
      GET: async () => {
        // Schema details (table/RPC/bucket names) aid attacker reconnaissance.
        // Require an explicit CRON_SECRET so only internal callers (pg_cron / ops)
        // can hit this endpoint.
        return Response.json(
          { ok: false, error: "Unauthorized" },
          { status: 401 },
        );
      },
      POST: async ({ request }) => {
        const secret = process.env.CRON_SECRET;
        const provided = request.headers.get("x-cron-secret");
        if (!secret || provided !== secret) {
          return Response.json({ ok: false, error: "Unauthorized" }, { status: 401 });
        }
        try {
          const report = await publicSystemCheck();
          return Response.json(report, { status: report.ok ? 200 : 503 });
        } catch (e) {
          return Response.json({ ok: false, error: (e as Error).message }, { status: 500 });
        }
      },
    },
  },
});
