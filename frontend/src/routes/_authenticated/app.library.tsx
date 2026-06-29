import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useMemo, useRef, useState } from "react";
import { useChat } from "@ai-sdk/react";
import { type UIMessage } from "ai";
import { createAuthedChatTransport } from "@/lib/ai-chat-transport";
import {
  Library, ExternalLink, Sparkles, Search, Bot, Send, Loader2,
  BookOpen, Scale, Settings as SettingsIcon, X, User,
} from "lucide-react";
import { Link } from "@tanstack/react-router";
import { toast } from "sonner";
import { PageHeader } from "@/components/section-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from "@/components/ui/sheet";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { LAWS, loadLibraryUrls, type LawDef, type LawId } from "@/lib/legal-library";

export const Route = createFileRoute("/_authenticated/app/library")({
  component: LibraryPage,
});

function LibraryPage() {
  const [urls, setUrls] = useState<Record<LawId, string>>(() => loadLibraryUrls());
  const [activeLaw, setActiveLaw] = useState<LawDef | null>(null);

  // Refresh urls when window regains focus (in case user edited Settings).
  useEffect(() => {
    const refresh = () => setUrls(loadLibraryUrls());
    window.addEventListener("focus", refresh);
    return () => window.removeEventListener("focus", refresh);
  }, []);

  const openOfficial = (law: LawDef) => {
    const url = urls[law.id]?.trim();
    if (!url) {
      toast.error("لم يتم ضبط رابط هذا النظام بعد. أضف الرابط من الإعدادات.");
      return;
    }
    window.open(url, "_blank", "noopener,noreferrer");
  };

  return (
    <>
      <PageHeader
        icon={Library}
        title="المكتبة القانونية الشاملة"
        subtitle="مرصد ومستودع اللوائح والأنظمة السعودية واللوائح التنفيذية"
        action={
          <Button asChild variant="outline" size="sm">
            <Link to="/app/settings"><SettingsIcon className="h-4 w-4 ml-1" /> روابط الأنظمة</Link>
          </Button>
        }
      />

      {/* Smart assistant — article lookup & explanation */}
      <SmartAssistant />

      {/* Repository grid */}
      <section className="mt-10">
        <div className="mb-5 flex items-center gap-3">
          <div className="h-9 w-1.5 rounded-full bg-gradient-to-b from-gold to-amber-400" />
          <div>
            <h2 className="text-xl md:text-2xl font-extrabold text-gradient-royal">
              فهرس الأنظمة والتعويضات السعودي
            </h2>
            <p className="text-xs text-muted-foreground mt-0.5">
              تصفّح نصوص الأنظمة الرسمية وادخل إلى فقه المادة بالذكاء الاصطناعي
            </p>
          </div>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
          {LAWS.map((law) => (
            <LawCard
              key={law.id}
              law={law}
              onOpenOfficial={() => openOfficial(law)}
              onAsk={() => setActiveLaw(law)}
            />
          ))}
        </div>
      </section>

      <LawSheet law={activeLaw} onOpenChange={(o) => !o && setActiveLaw(null)} />
    </>
  );
}

/* ---------------- Smart Assistant (article search / explanation) ---------------- */

function SmartAssistant() {
  const [mode, setMode] = useState<"search" | "explain">("search");
  const [lawId, setLawId] = useState<LawId>("civil");
  const [articleNo, setArticleNo] = useState("");
  const [articleText, setArticleText] = useState("");

  const lawDef = LAWS.find((l) => l.id === lawId)!;

  const { messages, sendMessage, status, setMessages, error } = useChat({
    transport: createAuthedChatTransport("/api/ai-chat"),
    onError: (e) => toast.error(e.message || "حدث خطأ"),
  });
  const isLoading = status === "submitted" || status === "streaming";

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (isLoading) return;
    let prompt = "";
    if (mode === "search") {
      const n = normalizeArticleNumber(articleNo);
      if (!n) return toast.error("اكتب رقم المادة");
      if (!/^\d+$/.test(n)) {
        toast.message("الرقم غير معياري — سيتم البحث النصي", { description: "للحصول على نتائج دقيقة استخدم أرقاماً (٧٧ أو 77)" });
      }
      prompt = `أنا أبحث عن المادة رقم (${n}) من ${lawDef.title}. السياق: ${lawDef.context}\n\nاذكر نص المادة كما وردت حرفياً، ثم اشرحها قانونياً مع أمثلة. إن لم تكن المادة موجودة بهذا الرقم اقترح أقرب 3 مواد ذات صلة.`;
    } else {
      const t = articleText.trim();
      if (t.length < 10) return toast.error("ألصق نص المادة (10 أحرف على الأقل)");
      prompt = `لديّ نص مادة قانونية من ${lawDef.title}. السياق: ${lawDef.context}\n\nالنص:\n«${t}»\n\nقدّم شرحاً وافياً للمادة: المعنى، النطاق، الاستثناءات، وأمثلة تطبيقية.`;
    }
    setMessages([]);
    await sendMessage({ text: prompt });
  };

  return (
    <Card className="card-3d border-none overflow-hidden">
      <div className="bg-gradient-to-l from-indigo-700 via-blue-700 to-cyan-600 text-white p-5">
        <div className="flex items-center gap-3">
          <div className="grid h-12 w-12 place-items-center rounded-2xl bg-white/15 border border-white/30 backdrop-blur shadow-xl">
            <Sparkles className="h-6 w-6" />
          </div>
          <div className="flex-1">
            <h3 className="text-lg font-bold">خدمات المساندة والتحقق الذكي</h3>
            <p className="text-xs opacity-85">
              ابحث عن مادة بالرقم، أو ألصق نص المادة ليقوم الذكاء الاصطناعي بشرحها
            </p>
          </div>
        </div>
      </div>

      <div className="p-5">
        <Tabs value={mode} onValueChange={(v) => setMode(v as "search" | "explain")}>
          <TabsList className="grid grid-cols-2 h-auto p-1.5 bg-muted/60 rounded-2xl mb-4">
            <TabsTrigger value="search" className="flex items-center gap-2 py-2.5 data-[state=active]:bg-gradient-to-br data-[state=active]:from-primary data-[state=active]:to-primary/80 data-[state=active]:text-gold rounded-xl">
              <Search className="h-4 w-4" /> البحث عن مادة برقمها
            </TabsTrigger>
            <TabsTrigger value="explain" className="flex items-center gap-2 py-2.5 data-[state=active]:bg-gradient-to-br data-[state=active]:from-primary data-[state=active]:to-primary/80 data-[state=active]:text-gold rounded-xl">
              <BookOpen className="h-4 w-4" /> شرح نص مادة
            </TabsTrigger>
          </TabsList>

          <form onSubmit={handleSubmit} className="space-y-3">
            <div className="grid md:grid-cols-[1fr_auto] gap-3">
              <select
                value={lawId}
                onChange={(e) => setLawId(e.target.value as LawId)}
                className="h-11 rounded-xl border bg-card px-3 text-sm font-semibold"
              >
                {LAWS.map((l) => (
                  <option key={l.id} value={l.id}>{l.title}</option>
                ))}
              </select>
            </div>

            <TabsContent value="search" className="m-0">
              <Input
                value={articleNo}
                onChange={(e) => setArticleNo(e.target.value)}
                placeholder="مثال: 77 أو المادة الثانية والعشرين"
                className="h-11 text-right"
              />
            </TabsContent>

            <TabsContent value="explain" className="m-0">
              <Textarea
                value={articleText}
                onChange={(e) => setArticleText(e.target.value)}
                placeholder="الصق نص المادة هنا..."
                rows={4}
                className="text-right"
              />
            </TabsContent>

            <Button type="submit" disabled={isLoading} className="btn-gold h-11 px-6 w-full md:w-auto">
              {isLoading ? <Loader2 className="h-4 w-4 animate-spin ml-2" /> : <Sparkles className="h-4 w-4 ml-2" />}
              {mode === "search" ? "اعثر على المادة واشرحها" : "اشرح هذه المادة"}
            </Button>
          </form>

          {(messages.length > 0 || error) && (
            <div className="mt-5 rounded-2xl border bg-gradient-to-b from-muted/30 to-transparent p-4 max-h-[420px] overflow-y-auto">
              {error && <div className="text-sm text-destructive">{error.message}</div>}
              {messages
                .filter((m) => m.role === "assistant")
                .map((m) => (
                  <article key={m.id} className="prose-sm text-sm whitespace-pre-wrap leading-relaxed">
                    {m.parts.map((p) => (p.type === "text" ? p.text : "")).join("")}
                  </article>
                ))}
              {isLoading && (
                <div className="flex items-center gap-2 text-xs text-muted-foreground mt-3">
                  <Loader2 className="h-3.5 w-3.5 animate-spin" /> يحلل الذكاء الاصطناعي المادة...
                </div>
              )}
            </div>
          )}
        </Tabs>
      </div>
    </Card>
  );
}

/* ---------------- Law card (3D, colored, animated) ---------------- */

function LawCard({
  law,
  onOpenOfficial,
  onAsk,
}: {
  law: LawDef;
  onOpenOfficial: () => void;
  onAsk: () => void;
}) {
  return (
    <div className="group relative [perspective:1200px]">
      <div
        className={`relative overflow-hidden rounded-3xl bg-gradient-to-br ${law.gradient} p-6 text-white
          transition-all duration-500 ease-out
          [transform:translateZ(0)]
          group-hover:-translate-y-2 group-hover:[transform:perspective(1200px)_rotateX(4deg)_rotateY(-4deg)]
          ${law.glow} group-hover:shadow-2xl
          ring-1 ring-white/15`}
      >
        {/* Glossy highlight */}
        <div className="pointer-events-none absolute inset-x-0 top-0 h-1/2 bg-gradient-to-b from-white/25 to-transparent" />
        <div className="pointer-events-none absolute -top-12 -right-12 h-40 w-40 rounded-full bg-white/15 blur-2xl" />
        <div className="pointer-events-none absolute -bottom-16 -left-12 h-44 w-44 rounded-full bg-black/20 blur-3xl" />

        <div className="relative flex items-start gap-3">
          <div className="grid h-12 w-12 shrink-0 place-items-center rounded-2xl bg-white/20 backdrop-blur border border-white/30 shadow-lg">
            <Scale className="h-6 w-6 drop-shadow" />
          </div>
          <div className="flex-1">
            <h3 className="text-lg font-extrabold tracking-tight drop-shadow-[0_2px_6px_rgba(0,0,0,0.35)]">
              {law.title}
            </h3>
            <span className="mt-1 inline-flex items-center gap-1 rounded-full bg-white/20 backdrop-blur border border-white/30 px-2.5 py-0.5 text-[11px] font-bold">
              {law.short}
            </span>
          </div>
        </div>

        <p className="relative mt-4 text-sm leading-relaxed text-white/95 drop-shadow-[0_1px_2px_rgba(0,0,0,0.35)]">
          {law.description}
        </p>

        <div className="relative mt-5 grid grid-cols-2 gap-2">
          <button
            type="button"
            onClick={onOpenOfficial}
            className="inline-flex items-center justify-center gap-1.5 rounded-xl bg-white text-slate-900 text-xs font-bold px-3 py-2.5 shadow-md hover:shadow-xl transition hover:-translate-y-0.5"
          >
            <ExternalLink className="h-3.5 w-3.5" />
            فتح النظام الرسمي
          </button>
          <button
            type="button"
            onClick={onAsk}
            className="inline-flex items-center justify-center gap-1.5 rounded-xl bg-black/30 backdrop-blur border border-white/30 text-white text-xs font-bold px-3 py-2.5 hover:bg-black/40 transition hover:-translate-y-0.5"
          >
            <Bot className="h-3.5 w-3.5" />
            اسأل الذكاء الاصطناعي
          </button>
        </div>
      </div>
    </div>
  );
}

/* ---------------- Per-law chat sheet ---------------- */

function LawSheet({ law, onOpenChange }: { law: LawDef | null; onOpenChange: (o: boolean) => void }) {
  if (!law) return null;
  return (
    <Sheet open={!!law} onOpenChange={onOpenChange}>
      <SheetContent side="left" className="w-full sm:max-w-2xl p-0 flex flex-col">
        <SheetHeader className={`bg-gradient-to-l ${law.gradient} text-white p-5`}>
          <SheetTitle className="text-white text-xl font-extrabold drop-shadow flex items-center gap-2">
            <Scale className="h-5 w-5" /> {law.title}
          </SheetTitle>
          <SheetDescription className="text-white/90 text-xs">
            اطرح سؤالاً قانونياً محدداً داخل فقه هذا النظام — يجيب الذكاء الاصطناعي بسياقه.
          </SheetDescription>
        </SheetHeader>
        <LawChat law={law} key={law.id} />
      </SheetContent>
    </Sheet>
  );
}

const HISTORY_PREFIX = "legal-library-chat:";

function loadHistory(lawId: LawId): UIMessage[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = localStorage.getItem(HISTORY_PREFIX + lawId);
    return raw ? (JSON.parse(raw) as UIMessage[]) : [];
  } catch { return []; }
}

// Normalize Arabic-Indic digits to Latin so users can type ٧٧ or 77.
function normalizeArticleNumber(s: string): string {
  return s.replace(/[\u0660-\u0669]/g, (c) => String(c.charCodeAt(0) - 0x0660))
          .replace(/[\u06F0-\u06F9]/g, (c) => String(c.charCodeAt(0) - 0x06F0))
          .trim();
}

function LawChat({ law }: { law: LawDef }) {
  const [input, setInput] = useState("");
  const scrollRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const system = useMemo(
    () =>
      `أنت خبير قانوني سعودي متخصص حصرياً في: ${law.title}.
السياق المرجعي: ${law.context}
- أجب باللغة العربية الفصحى بأسلوب قانوني واضح.
- استشهد بأرقام المواد من ${law.title} عند الإمكان مع ربط الإجابة بمكانها داخل فقه المادة.
- إذا كان السؤال خارج هذا النظام، نبّه المستخدم باختصار ووجّهه للنظام الصحيح.
- استخدم Markdown (عناوين، نقاط، اقتباس النصوص).`,
    [law],
  );

  const initialMessages = useMemo(() => loadHistory(law.id), [law.id]);

  const { messages, sendMessage, status, error, setMessages } = useChat({
    id: `law-${law.id}`,
    messages: initialMessages,
    transport: createAuthedChatTransport("/api/ai-chat", { body: { system } }),
    onError: (e) => toast.error(e.message || "حدث خطأ"),
  });
  const isLoading = status === "submitted" || status === "streaming";

  // Persist conversation to localStorage on every update (survives reload)
  useEffect(() => {
    if (typeof window === "undefined") return;
    try {
      localStorage.setItem(HISTORY_PREFIX + law.id, JSON.stringify(messages));
    } catch { /* quota */ }
  }, [messages, law.id]);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: "smooth" });
  }, [messages, status]);
  useEffect(() => { inputRef.current?.focus(); }, [status]);

  const clearHistory = () => {
    setMessages([]);
    try { localStorage.removeItem(HISTORY_PREFIX + law.id); } catch { /* noop */ }
  };

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const t = input.trim();
    if (!t || isLoading) return;
    setInput("");
    await sendMessage({ text: t });
  };

  const suggestions = [
    `ما الأحكام العامة في ${law.short}؟`,
    `اشرح أبرز المواد في ${law.short}`,
    `ما العقوبات الواردة في ${law.short}؟`,
  ];

  return (
    <div className="flex-1 flex flex-col min-h-0">
      {messages.length > 0 && (
        <div className="flex items-center justify-between border-b px-4 py-2 bg-muted/30">
          <span className="text-[11px] text-muted-foreground">
            محفوظة في الجلسة • {messages.length} رسالة
          </span>
          <Button type="button" size="sm" variant="ghost" onClick={clearHistory} className="h-7 text-xs">
            <X className="h-3.5 w-3.5 ml-1" /> مسح المحادثة
          </Button>
        </div>
      )}
      <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 space-y-3 bg-gradient-to-b from-muted/20 to-transparent">

        {messages.length === 0 && (
          <div className="text-center py-6">
            <p className="text-sm text-muted-foreground mb-4">اقتراحات للبدء:</p>
            <div className="space-y-2 max-w-md mx-auto">
              {suggestions.map((s) => (
                <button
                  key={s}
                  type="button"
                  onClick={() => setInput(s)}
                  className="block w-full text-right text-sm p-3 rounded-xl bg-card border hover:border-gold hover:shadow-md transition-all"
                >💡 {s}</button>
              ))}
            </div>
          </div>
        )}

        {messages.map((m) => <Bubble key={m.id} message={m} />)}

        {status === "submitted" && (
          <div className="flex items-center gap-2 text-xs text-muted-foreground">
            <Loader2 className="h-3.5 w-3.5 animate-spin" /> يفكر الذكاء الاصطناعي...
          </div>
        )}
        {error && (
          <div className="rounded-lg bg-destructive/10 border border-destructive/30 p-3 text-sm text-destructive">
            {error.message}
          </div>
        )}
      </div>

      <form onSubmit={onSubmit} className="border-t bg-card p-3 flex gap-2">
        <Input
          ref={inputRef}
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder={`اسأل عن ${law.short}...`}
          disabled={isLoading}
          className="text-right h-11"
          autoFocus
        />
        <Button type="submit" disabled={isLoading || !input.trim()} className="btn-gold h-11 px-5">
          {isLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
        </Button>
      </form>
    </div>
  );
}

function Bubble({ message }: { message: UIMessage }) {
  const isUser = message.role === "user";
  const text = message.parts.map((p) => (p.type === "text" ? p.text : "")).join("");
  return (
    <div className={`flex gap-2 ${isUser ? "flex-row-reverse" : ""}`}>
      <div className={`grid h-7 w-7 shrink-0 place-items-center rounded-full ${isUser ? "bg-gold text-primary" : "bg-primary text-gold"}`}>
        {isUser ? <User className="h-3.5 w-3.5" /> : <Bot className="h-3.5 w-3.5" />}
      </div>
      <div className={`max-w-[88%] rounded-2xl px-3.5 py-2 text-sm leading-relaxed whitespace-pre-wrap ${
        isUser ? "bg-primary text-primary-foreground rounded-tr-sm" : "bg-card border rounded-tl-sm shadow-sm"
      }`}>
        {text || <span className="opacity-50">...</span>}
      </div>
    </div>
  );
}
