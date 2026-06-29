import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/public/cron/session-reminders")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const secret = process.env.CRON_SECRET;
        const provided = request.headers.get("x-cron-secret");
        if (!secret || provided !== secret) {
          return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401, headers: { "Content-Type": "application/json" } });
        }
        const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
        const sessionRes = await supabaseAdmin.rpc("enqueue_session_reminders" as never);
        const taskRes = await supabaseAdmin.rpc("enqueue_task_reminders" as never);
        if (sessionRes.error || taskRes.error) {
          return new Response(
            JSON.stringify({ error: sessionRes.error?.message ?? taskRes.error?.message }),
            { status: 500, headers: { "Content-Type": "application/json" } },
          );
        }
        return new Response(
          JSON.stringify({ ok: true, sessions_enqueued: sessionRes.data ?? 0, tasks_enqueued: taskRes.data ?? 0 }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        );
      },
      GET: async () => new Response(null, { status: 404 }),
    },
  },
});
