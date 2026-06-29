import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { z } from "zod";

const statsSchema = z.object({
  employee_name: z.string().max(200),
  total: z.number(),
  done: z.number(),
  in_progress: z.number(),
  todo: z.number(),
  overdue: z.number(),
  on_time_done: z.number(),
  avg_completion_days: z.number().nullable(),
});

const inputSchema = z.object({
  stats: z.array(statsSchema).max(500),
  focus: z.string().max(200).nullable().optional(),
});

export const analyzePerformance = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => inputSchema.parse(input))
  .handler(async ({ data, context }) => {
    // Restrict firm-wide performance analysis to lawyers/admins only.
    const [{ data: isLawyer }, { data: isAdmin }] = await Promise.all([
      context.supabase.rpc("has_role", { _user_id: context.userId, _role: "lawyer" }),
      context.supabase.rpc("has_role", { _user_id: context.userId, _role: "admin" }),
    ]);
    if (!isLawyer && !isAdmin) throw new Error("forbidden");

    if (!data.stats?.length) return { text: "لا توجد بيانات كافية للتحليل." };

    const { getDefaultChatModel, getOpenAIModel } = await import("@/lib/ai-gateway.server");
    const { generateText } = await import("ai");

    const focusLine = data.focus ? `\nركّز التحليل على الموظف: ${data.focus}.` : "";
    const table = data.stats.map((s) =>
      `- ${s.employee_name}: مُسنَدة=${s.total}, مُنجَزة=${s.done}, جارية=${s.in_progress}, قيد البدء=${s.todo}, متأخّرة=${s.overdue}, مُنجَزة بالموعد=${s.on_time_done}, متوسّط الإنجاز=${s.avg_completion_days ?? "—"} يوم`,
    ).join("\n");

    let text: string;
    try {
      const model = getDefaultChatModel();
      const result = await generateText({
        model,
        system:
          "أنت محلل أداء وظيفي في مكتب محاماة. اكتب تحليلاً مهنياً موجزاً بالعربية الفصحى. " +
          "أعطِ نقاط القوة، نقاط الضعف، وتوصيات عملية. لا تخترع أرقاماً غير مذكورة.",
        prompt: `بيانات أداء الموظفين خلال الفترة الحالية:\n${table}${focusLine}\n\nاكتب التحليل في 6-10 أسطر بصياغة احترافية.`,
      });
      text = result.text;
    } catch {
      // Fallback to OpenAI
      const model = getOpenAIModel();
      const result = await generateText({
        model,
        system:
          "أنت محلل أداء وظيفي في مكتب محاماة. اكتب تحليلاً مهنياً موجزاً بالعربية الفصحى. " +
          "أعطِ نقاط القوة، نقاط الضعف، وتوصيات عملية. لا تخترع أرقاماً غير مذكورة.",
        prompt: `بيانات أداء الموظفين خلال الفترة الحالية:\n${table}${focusLine}\n\nاكتب التحليل في 6-10 أسطر بصياغة احترافية.`,
      });
      text = result.text;
    }
    return { text };
  });
