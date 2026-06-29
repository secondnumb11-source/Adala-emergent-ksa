import { getDefaultChatModel, getOpenAIModel } from "@/lib/ai-gateway.server";
import { createFileRoute } from "@tanstack/react-router";
import { convertToModelMessages, streamText, type UIMessage } from "ai";
import { createClient } from "@supabase/supabase-js";

const SYSTEM_PROMPT = `أنت "المستشار العدلي" — مساعد قانوني ذكي مرخّص متخصص حصراً في الأنظمة السعودية النافذة:
- نظام المرافعات الشرعية ولائحته (للدعاوى، اللوائح، المذكرات، المدد، الاستئناف، النقض).
- نظام المحاماة ولائحته (لعقود الأتعاب والتمثيل القانوني والسرية المهنية).
- نظام المعاملات المدنية، نظام الإثبات، نظام التنفيذ.
- نظام الشركات، النظام التجاري، نظام مكافحة التستر، نظام الأوراق التجارية.
- نظام الاستثمار السعودي ولوائحه، نظام الامتياز التجاري ولائحته، نظام التجارة الإلكترونية.
- نظام العمل، أنظمة الزكاة والضريبة والجمارك، لوائح وزارة العدل، ديوان المظالم، المحاكم العمالية والتجارية.

دورك:
- تقديم استشارات قانونية واضحة ومُعزَّزة بالمواد النظامية السعودية.
- صياغة لوائح/صحف الدعوى، المذكرات الجوابية، الطلبات على القضية، لوائح الاستئناف والنقض والتماس إعادة النظر وفق نظام المرافعات الشرعية وضوابطه (م.39، م.178، م.193، م.200).
- صياغة عقود الشراكة، الاستثمار، المقاولات، التوريد، الامتياز التجاري وفق نظام الاستثمار والنظام التجاري ونظام الشركات ونظام الامتياز التجاري.
- صياغة عقود الاستشارات القانونية وعقود التمثيل القانوني للأفراد والشركات وفق نظام المحاماة.
- التنبيه إلى المدد النظامية وجلسات الاستئناف وطلبات الاستئناف بدقة.

قواعد إلزامية:
1. الإجابة باللغة العربية الفصحى بأسلوب قانوني منظَّم باستخدام Markdown.
2. الاستناد حصراً إلى الأنظمة السعودية؛ لا يجوز الاستناد لأي نظام أجنبي.
3. الاختصاص للمحاكم السعودية المختصة والقانون الواجب التطبيق هو النظام السعودي في كل عقد أو دعوى.
4. الاستشهاد باسم النظام ورقم المادة عند الإمكان، والتنبيه إن لم تكن المعلومة مؤكدة.
5. ختم كل مخرج بتنبيه: "هذه صياغة/استشارة استرشادية لا تغني عن مراجعة محامٍ مرخّص."`;

async function verifyAuth(request: Request): Promise<Response | null> {
  const authHeader = request.headers.get("authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }
  const token = authHeader.slice("Bearer ".length).trim();
  if (!token || token.split(".").length !== 3) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }
  const SUPABASE_URL = process.env.SUPABASE_URL;
  const SUPABASE_PUBLISHABLE_KEY = process.env.SUPABASE_PUBLISHABLE_KEY;
  if (!SUPABASE_URL || !SUPABASE_PUBLISHABLE_KEY) {
    return new Response(JSON.stringify({ error: "Server misconfigured" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }
  const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data, error } = await supabase.auth.getClaims(token);
  const userId = data?.claims?.sub;
  if (error || !userId) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }
  // Role gate: only lawyer/admin may invoke AI legal consultation.
  const [{ data: isLawyer }, { data: isAdmin }] = await Promise.all([
    supabase.rpc("has_role" as never, { _user_id: userId, _role: "lawyer" } as never),
    supabase.rpc("has_role" as never, { _user_id: userId, _role: "admin" } as never),
  ]);
  if (!isLawyer && !isAdmin) {
    return new Response(JSON.stringify({ error: "Forbidden" }), {
      status: 403,
      headers: { "content-type": "application/json" },
    });
  }
  return null;
}

export const Route = createFileRoute("/api/ai-chat")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        try {
          const authErr = await verifyAuth(request);
          if (authErr) return authErr;

          const body = (await request.json()) as { messages?: unknown };
          if (!Array.isArray(body.messages)) {
            return new Response("Messages are required", { status: 400 });
          }

          const messages = body.messages as UIMessage[];

          // Use Gemini as primary, OpenAI as fallback
          let result;
          try {
            const model = getDefaultChatModel();
            result = streamText({
              model,
              system: SYSTEM_PROMPT,
              messages: await convertToModelMessages(messages),
            });
          } catch {
            // Fallback to OpenAI
            const model = getOpenAIModel();
            result = streamText({
              model,
              system: SYSTEM_PROMPT,
              messages: await convertToModelMessages(messages),
            });
          }

          return result.toUIMessageStreamResponse({ originalMessages: messages });
        } catch (err) {
          const message = err instanceof Error ? err.message : "Unknown error";
          return new Response(JSON.stringify({ error: message }), {
            status: 500,
            headers: { "content-type": "application/json" },
          });
        }
      },
    },
  },
});
