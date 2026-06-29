import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { z } from "zod";

export type NotificationPrefs = {
  channels: { whatsapp: boolean; sms: boolean; email: boolean };
  sessions: { enabled: boolean; lead_hours: number[] };
  tasks: { enabled: boolean; lead_hours: number[] };
  appeals: { enabled: boolean; lead_days: number[] };
  quiet_hours: { enabled: boolean; start: string; end: string };
};

const DEFAULT_PREFS: NotificationPrefs = {
  channels: { whatsapp: true, sms: false, email: true },
  sessions: { enabled: true, lead_hours: [24, 1] },
  tasks: { enabled: true, lead_hours: [24] },
  appeals: { enabled: true, lead_days: [7, 3, 1] },
  quiet_hours: { enabled: false, start: "22:00", end: "07:00" },
};

export const getNotificationPrefs = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { data, error } = await context.supabase
      .from("notification_preferences")
      .select("channels, sessions, tasks, appeals, quiet_hours")
      .eq("owner_id", context.userId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    if (!data) return DEFAULT_PREFS;
    return {
      channels: (data.channels as NotificationPrefs["channels"]) ?? DEFAULT_PREFS.channels,
      sessions: (data.sessions as NotificationPrefs["sessions"]) ?? DEFAULT_PREFS.sessions,
      tasks: (data.tasks as NotificationPrefs["tasks"]) ?? DEFAULT_PREFS.tasks,
      appeals: (data.appeals as NotificationPrefs["appeals"]) ?? DEFAULT_PREFS.appeals,
      quiet_hours: (data.quiet_hours as NotificationPrefs["quiet_hours"]) ?? DEFAULT_PREFS.quiet_hours,
    };
  });

const PrefsSchema = z.object({
  channels: z.object({ whatsapp: z.boolean(), sms: z.boolean(), email: z.boolean() }),
  sessions: z.object({ enabled: z.boolean(), lead_hours: z.array(z.number().int().min(0).max(720)).max(8) }),
  tasks: z.object({ enabled: z.boolean(), lead_hours: z.array(z.number().int().min(0).max(720)).max(8) }),
  appeals: z.object({ enabled: z.boolean(), lead_days: z.array(z.number().int().min(0).max(60)).max(8) }),
  quiet_hours: z.object({
    enabled: z.boolean(),
    start: z.string().regex(/^\d{2}:\d{2}$/),
    end: z.string().regex(/^\d{2}:\d{2}$/),
  }),
});

export const updateNotificationPrefs = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: NotificationPrefs) => PrefsSchema.parse(d))
  .handler(async ({ data, context }) => {
    const { error } = await context.supabase
      .from("notification_preferences")
      .upsert(
        {
          owner_id: context.userId,
          channels: data.channels as never,
          sessions: data.sessions as never,
          tasks: data.tasks as never,
          appeals: data.appeals as never,
          quiet_hours: data.quiet_hours as never,
        },
        { onConflict: "owner_id" },
      );
    if (error) throw new Error(error.message);
    return { ok: true };
  });
