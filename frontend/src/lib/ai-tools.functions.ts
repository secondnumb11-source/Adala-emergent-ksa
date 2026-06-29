import { createServerFn } from "@tanstack/react-start";
import { generateText } from "ai";
import { z } from "zod";
import { getDefaultChatModel, getOpenAIModel } from "@/lib/ai-gateway.server";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

const ToolInput = z.object({
  toolId: z.enum([
    "consultant",
    "analyze",
    "summarize",
    "memorandum",
    "lawsuit",
    "appeal",
    "objection",
    "notice",
    "contract",
    "fees_contract",
    "letter",
    "translate",
    "explain_article",
    "search_article",
  ]),
  context: z.string().min(3).max(20000),
  extras: z.record(z.string(), z.string()).optional(),
});

type Builder = (ctx: string, extras?: Record<string, string>) => { system: string; prompt: string };

const SAUDI_SYS = [
  "أنت محامٍ ومستشار قانوني سعودي مرخّص خبير بالأنظمة السعودية:",
  "- نظام المرافعات الشرعية ولائحته التنفيذية.",
  "- نظام المحاماة ولائحته (لصياغة عقود الأتعاب والتمثيل القانوني).",
  "- نظام المعاملات المدنية، نظام الإثبات، نظام التنفيذ.",
  "- نظام الشركات، النظام التجاري، نظام مكافحة التستر، نظام الأوراق التجارية.",
  "- نظام الاستثمار السعودي ولوائحه (لعقود الاستثمار والشراكة الأجنبية).",
  "- نظام العمل، أنظمة الزكاة والضريبة والجمارك، نظام التجارة الإلكترونية، نظام الامتياز التجاري ولائحته.",
  "قواعد ملزِمة عند كل إجابة:",
  "1) جميع المخرجات يجب أن تتوافق حصراً مع الأنظمة السعودية النافذة، ولا يجوز الاستناد لأي نظام أجنبي.",
  "2) اجعل الاختصاص للمحاكم السعودية المختصة والقانون الواجب التطبيق هو النظام السعودي.",
  "3) استشهد بأرقام المواد النظامية المتعلقة عند الإمكان مع التنبيه إن لم تكن متأكداً.",
  "4) أضف في نهاية كل مخرج تنبيهاً بأن هذه صياغة استرشادية لا تغني عن مراجعة محامٍ مرخّص.",
  "5) أجبّ باللغة العربية الفصحى بأسلوب قانوني منظَّم.",
].join("\n");

const PROCEDURAL_RULES = "التزم بنظام المرافعات الشرعية السعودي ولائحته: بيانات الأطراف، المحكمة المختصة، الوقائع، السند النظامي، الطلبات، التوقيع. راعِ المدد النظامية (م.178 للاستئناف 30 يوماً وللمستعجلة 10 أيام، م.193 للنقض، م.200 لالتماس إعادة النظر، م.166 لاستلام صك الحكم).";
const CONTRACT_RULES = "التزم بضوابط الأنظمة السعودية: نظام المعاملات المدنية، نظام الشركات، النظام التجاري، نظام الاستثمار، ونظام الامتياز التجاري حسب نوع العقد. اشترط الاختصاص للمحاكم السعودية، والامتثال لأنظمة مكافحة غسل الأموال والتستر التجاري، واشتراطات وزارة الاستثمار/التجارة عند الاقتضاء.";

const PROMPTS: Record<string, Builder> = {
  consultant: (ctx, extras) => ({
    system: `${SAUDI_SYS}\nأجب بإيجاز ودقة مع التنظيم في نقاط.`,
    prompt: `استشارة قانونية:\n${extras?.caseTitle ? `القضية المرتبطة: ${extras.caseTitle}\n` : ""}${extras?.client ? `العميل: ${extras.client}\n` : ""}\nالسؤال/الموضوع:\n${ctx}`,
  }),
  analyze: (ctx, extras) => ({
    system: `${SAUDI_SYS}\nقدّم تحليلاً قانونياً متكاملاً.`,
    prompt: `حلّل الموقف القانوني التالي وأعطني:\n1) ملخص الوقائع\n2) التكييف القانوني\n3) نقاط القوة\n4) نقاط الضعف\n5) المواد النظامية ذات الصلة\n6) الاستراتيجية المقترحة\n7) احتمالية النجاح التقديرية (مع التحفّظ)\n\n${extras?.caseTitle ? `القضية: ${extras.caseTitle}\n` : ""}الوقائع:\n${ctx}`,
  }),
  summarize: (ctx) => ({
    system: `${SAUDI_SYS}\nأنت متخصص في تلخيص المستندات والأحكام.`,
    prompt: `لخّص المستند التالي تلخيصاً تنفيذياً، ثم اذكر النقاط الجوهرية، ثم الملاحظات القانونية:\n\n${ctx}`,
  }),
  memorandum: (ctx, extras) => ({
    system: `${SAUDI_SYS}\n${PROCEDURAL_RULES}\nصِغ مذكرة قانونية أمام المحاكم السعودية بأسلوب رصين، مع: المقدمة، الوقائع، الأسانيد النظامية، الدفوع، الطلبات.`,
    prompt: `اصغ ${extras?.memoType ?? "مذكرة قانونية"} حول:\nنوع الدعوى: ${extras?.caseType ?? "—"}\nصفة الموكل: ${extras?.role ?? "—"}\nاسم القضية: ${extras?.caseTitle ?? "—"}\n\nالوقائع والتفاصيل:\n${ctx}`,
  }),
  lawsuit: (ctx, extras) => ({
    system: `${SAUDI_SYS}\n${PROCEDURAL_RULES}\nصغ صحيفة/لائحة دعوى متكاملة وفق المادة (39) وما بعدها من نظام المرافعات الشرعية السعودي: بيانات المدعي والمدعى عليه، المحكمة المختصة، موضوع الدعوى، الوقائع، الأسانيد، الطلبات.`,
    prompt: `صحيفة دعوى:\nالمدعي: ${extras?.plaintiff ?? "—"}\nالمدعى عليه: ${extras?.defendant ?? "—"}\nالمحكمة المختصة: ${extras?.court ?? "—"}\nنوع الدعوى: ${extras?.caseType ?? "—"}\n\nالوقائع والطلبات:\n${ctx}`,
  }),
  appeal: (ctx, extras) => ({
    system: `${SAUDI_SYS}\n${PROCEDURAL_RULES}\nصغ لائحة استئنافية أمام محكمة الاستئناف السعودية مع: الديباجة، أسباب الاستئناف، الطلبات، والإشارة إلى المادة 178 من نظام المرافعات الشرعية وضرورة تقديمها خلال المدة النظامية (30 يوماً للأحكام العادية و10 أيام للمستعجلة).`,
    prompt: `لائحة استئنافية على الحكم رقم: ${extras?.judgmentNo ?? "—"}\nتاريخ الحكم: ${extras?.judgmentDate ?? "—"}\nالقضية: ${extras?.caseTitle ?? "—"}\n\nأسباب الاستئناف والوقائع:\n${ctx}`,
  }),
  objection: (ctx, extras) => ({
    system: `${SAUDI_SYS}\n${PROCEDURAL_RULES}\nصغ لائحة اعتراض/التماس إعادة نظر وفق نظام المرافعات الشرعية (م.200) مع مراعاة المدد النظامية وأسباب الالتماس الحصرية.`,
    prompt: `لائحة اعتراض/إعادة نظر:\nالحكم: ${extras?.judgmentNo ?? "—"}\nالقضية: ${extras?.caseTitle ?? "—"}\n\nالأسباب والوقائع:\n${ctx}`,
  }),
  notice: (ctx, extras) => ({
    system: `${SAUDI_SYS}\nصغ إنذاراً/إشعاراً قانونياً رسمياً حازماً.`,
    prompt: `${extras?.noticeType ?? "إنذار قانوني"} موجه إلى: ${extras?.recipient ?? "—"}\nمن: ${extras?.sender ?? "—"}\n\nالموضوع:\n${ctx}`,
  }),
  contract: (ctx, extras) => ({
    system: `${SAUDI_SYS}\n${CONTRACT_RULES}\nصغ عقداً متكاملاً وفق الأنظمة السعودية يتضمن: الديباجة، الأطراف وأهليتهم، التعريفات، محل العقد، الالتزامات المتقابلة، البدل وآلية السداد، المدة والتجديد، الإنهاء والفسخ، السرية، عدم المنافسة (عند الاقتضاء)، القوة القاهرة، الضرائب والزكاة، فض النزاعات أمام المحاكم السعودية المختصة، التوقيعات. لعقود الشراكة/الاستثمار/المقاولات/التوريد/الامتياز التجاري التزم بنظام الشركات، نظام الاستثمار، النظام التجاري، ونظام الامتياز التجاري ولائحته (تسجيل الامتياز لدى وزارة التجارة).`,
    prompt: `عقد من نوع: ${extras?.contractType ?? "—"}\nالطرف الأول: ${extras?.partyA ?? "—"}\nالطرف الثاني: ${extras?.partyB ?? "—"}\nمدة العقد: ${extras?.duration ?? "—"}\nالبدل/القيمة: ${extras?.amount ?? "—"}\n\nالتفاصيل:\n${ctx}\n\nاحرص على تضمين البنود الإلزامية حسب نوع العقد (شراكة/استثمار/مقاولات/توريد/امتياز تجاري/استشارات قانونية/تمثيل قانوني) وفق الأنظمة السعودية ذات الصلة.`,
  }),
  fees_contract: (ctx, extras) => ({
    system: `${SAUDI_SYS}\nصغ عقد أتعاب/تمثيل قانوني وفق نظام المحاماة السعودي ولائحته التنفيذية وضوابط الهيئة السعودية للمحامين، يتضمن: الأطراف، نطاق التوكيل ونوع القضية/الخدمة، الأتعاب وطريقة السداد، نسبة النجاح (بما لا يخالف الضوابط)، المصاريف، السرية المهنية (م.17 من نظام المحاماة)، حالات الإنهاء، الاختصاص للمحاكم السعودية.`,
    prompt: `عقد أتعاب محاماة:\nالمكتب: ${extras?.firmName ?? "—"}\nالعميل: ${extras?.client ?? "—"}\nنوع القضية/الخدمة: ${extras?.caseType ?? "—"}\nالأتعاب الإجمالية: ${extras?.amount ?? "—"}\nنسبة النجاح: ${extras?.successFee ?? "—"}\n\nالتفاصيل:\n${ctx}`,
  }),
  letter: (ctx, extras) => ({
    system: `${SAUDI_SYS}\nصغ خطاباً رسمياً منظماً.`,
    prompt: `${extras?.letterType ?? "خطاب رسمي"} إلى: ${extras?.recipient ?? "—"}\n\n${ctx}`,
  }),
  translate: (ctx, extras) => ({
    system: "أنت مترجم قانوني محترف. حافظ على المصطلحات القانونية الدقيقة.",
    prompt: `ترجم النص التالي إلى ${extras?.target ?? "الإنجليزية"}:\n\n${ctx}`,
  }),
  explain_article: (ctx, extras) => ({
    system: `${SAUDI_SYS}\nأنت أستاذ فقه قانوني. اشرح المادة شرحاً مفصّلاً مع الأمثلة التطبيقية والصلة بالمواد الأخرى.`,
    prompt: `اشرح ${extras?.system ? `المادة (${ctx}) من ${extras.system}` : `المادة التالية`}:\n${extras?.articleText ? `\nنص المادة:\n${extras.articleText}` : ""}\n\nأعطني: المعنى، التفسير الفقهي، التطبيق العملي، الأمثلة، والمواد المرتبطة.`,
  }),
  search_article: (ctx, extras) => ({
    system: `${SAUDI_SYS}\nأنت باحث قانوني. أعد رقم المادة ونصها التقريبي ومصدرها من ${extras?.system ?? "الأنظمة السعودية"}.`,
    prompt: `ابحث عن المادة المتعلقة بـ: ${ctx}\nالنظام: ${extras?.system ?? "أي نظام سعودي"}\n\nأعطني: رقم المادة، نصها، النظام الذي وردت فيه، وشرحاً موجزاً.`,
  }),
};

export const runAiTool = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((data: unknown) => ToolInput.parse(data))
  .handler(async ({ data, context }) => {
    // Role gate: only lawyer/admin may invoke AI legal tooling.
    const [{ data: isLawyer }, { data: isAdmin }] = await Promise.all([
      context.supabase.rpc("has_role" as never, { _user_id: context.userId, _role: "lawyer" } as never),
      context.supabase.rpc("has_role" as never, { _user_id: context.userId, _role: "admin" } as never),
    ]);
    if (!isLawyer && !isAdmin) throw new Error("forbidden");

    const builder = PROMPTS[data.toolId];
    if (!builder) throw new Error("أداة غير معروفة");

    const { system, prompt } = builder(data.context, data.extras);

    // Use Gemini as primary, OpenAI as fallback
    try {
      const model = getDefaultChatModel();
      const { text } = await generateText({ model, system, prompt });
      return { text };
    } catch (primaryErr) {
      // Fallback to OpenAI if Gemini fails
      try {
        const model = getOpenAIModel();
        const { text } = await generateText({ model, system, prompt });
        return { text };
      } catch (fallbackErr) {
        const message = fallbackErr instanceof Error ? fallbackErr.message : "تعذّر توليد النتيجة";
        if (message.includes("429")) throw new Error("تم تجاوز حد الاستخدام. حاول لاحقاً.");
        if (message.includes("402")) throw new Error("نفدت رصيد الذكاء الاصطناعي. يرجى تجديد الباقة.");
        throw new Error(message);
      }
    }
  });
