import { createFileRoute, Link } from "@tanstack/react-router";
import { useState, useRef, useEffect } from "react";
import { useChat } from "@ai-sdk/react";
import { type UIMessage } from "ai";
import { createAuthedChatTransport } from "@/lib/ai-chat-transport";
import {
  Bot, Send, Loader2, User, Sparkles, ArrowRight, Upload, FileText,
  Brain, ScanSearch, MessageSquare, Download, Trash2,
} from "lucide-react";
import { PageHeader } from "@/components/section-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { toast } from "sonner";
import { AiGenerator } from "@/components/ai-generator";
import { useList } from "@/lib/data-hooks";

const CHAT_KEY = "ai-consultant-chat:v1";

function loadConsultantHistory(): UIMessage[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = localStorage.getItem(CHAT_KEY);
    return raw ? (JSON.parse(raw) as UIMessage[]) : [];
  } catch { return []; }
}

function messagesToText(messages: UIMessage[]): string {
  return messages.map((m) => {
    const role = m.role === "user" ? "أنت" : "المستشار";
    const text = m.parts.map((p) => (p.type === "text" ? p.text : "")).join("");
    return `[${role}]\n${text}\n`;
  }).join("\n---\n\n");
}

async function exportChatTxt(messages: UIMessage[]) {
  const txt = `استشارة قانونية — ${new Date().toLocaleString("ar-SA")}\n\n${messagesToText(messages)}`;
  const blob = new Blob([txt], { type: "text/plain;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url; a.download = `consultation-${Date.now()}.txt`;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 3000);
}

async function exportChatPdf(messages: UIMessage[]) {
  const { default: jsPDF } = await import("jspdf");
  const pdf = new jsPDF({ orientation: "portrait", unit: "pt", format: "a4" });
  const pageW = pdf.internal.pageSize.getWidth();
  const margin = 40;
  pdf.setFontSize(14);
  pdf.text("Legal Consultation Transcript", margin, margin);
  pdf.setFontSize(10);
  pdf.text(new Date().toLocaleString("en-US"), margin, margin + 18);
  let y = margin + 40;
  pdf.setFontSize(11);
  for (const m of messages) {
    const role = m.role === "user" ? "USER" : "ASSISTANT";
    const text = m.parts.map((p) => (p.type === "text" ? p.text : "")).join("");
    const block = `[${role}]\n${text}`;
    const lines = pdf.splitTextToSize(block, pageW - margin * 2);
    if (y + lines.length * 14 > pdf.internal.pageSize.getHeight() - margin) {
      pdf.addPage(); y = margin;
    }
    pdf.text(lines, margin, y);
    y += lines.length * 14 + 10;
  }
  pdf.save(`consultation-${Date.now()}.pdf`);
}

export const Route = createFileRoute("/_authenticated/app/ai/consultant")({
  component: ConsultantPage,
});

function ConsultantPage() {
  return (
    <>
      <PageHeader
        icon={Bot}
        title="المستشار والمحلل القانوني الذكي"
        subtitle="استشارات قانونية فورية وتحليل احترافي لقضاياك وفق الأنظمة السعودية"
        action={
          <Button asChild variant="outline" size="sm">
            <Link to="/app/ai"><ArrowRight className="h-4 w-4 ml-1" /> العودة لمركز الذكاء الاصطناعي</Link>
          </Button>
        }
      />

      <Tabs defaultValue="chat" className="w-full">
        <TabsList className="grid grid-cols-3 h-auto p-1.5 bg-muted/60 backdrop-blur rounded-2xl mb-6">
          <TabsTrigger value="chat" className="flex items-center gap-2 py-2.5 data-[state=active]:bg-gradient-to-br data-[state=active]:from-primary data-[state=active]:to-primary/80 data-[state=active]:text-gold rounded-xl">
            <MessageSquare className="h-4 w-4" /> استشارة فورية
          </TabsTrigger>
          <TabsTrigger value="analyze" className="flex items-center gap-2 py-2.5 data-[state=active]:bg-gradient-to-br data-[state=active]:from-primary data-[state=active]:to-primary/80 data-[state=active]:text-gold rounded-xl">
            <Brain className="h-4 w-4" /> تحليل قضية
          </TabsTrigger>
          <TabsTrigger value="document" className="flex items-center gap-2 py-2.5 data-[state=active]:bg-gradient-to-br data-[state=active]:from-primary data-[state=active]:to-primary/80 data-[state=active]:text-gold rounded-xl">
            <ScanSearch className="h-4 w-4" /> تحليل مستند
          </TabsTrigger>
        </TabsList>

        <TabsContent value="chat" className="mt-0"><ChatConsole /></TabsContent>

        <TabsContent value="analyze" className="mt-0">
          <AiGenerator
            title="تحليل القضية والموقف القانوني"
            description="حلّل تفاصيل القضية وتلقَّ تقريراً يشمل نقاط القوة والضعف والاستراتيجية المقترحة."
            toolId="analyze"
            fields={[
              { key: "caseTitle", label: "القضية الحالية (اختياري)", type: "case" },
              { key: "caseType", label: "نوع القضية", options: ["عمالية", "تجارية", "تنفيذية", "مدنية", "إدارية", "أحوال شخصية", "جزائية"] },
            ]}
            contextPlaceholder="اذكر وقائع القضية، الأطراف، التواريخ، والمستندات المتوفرة..."
            rows={10}
          />
        </TabsContent>

        <TabsContent value="document" className="mt-0"><DocumentAnalyzer /></TabsContent>
      </Tabs>
    </>
  );
}

function ChatConsole() {
  const [input, setInput] = useState("");
  const [caseId, setCaseId] = useState("");
  const scrollRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const cases = useList<{ id: string; title?: string; case_number?: string }>("cases");

  const initial = useRef(loadConsultantHistory());
  const { messages, sendMessage, status, error, setMessages } = useChat({
    messages: initial.current,
    transport: createAuthedChatTransport("/api/ai-chat"),
    onError: (err) => toast.error(err.message || "حدث خطأ"),
  });
  const isLoading = status === "submitted" || status === "streaming";

  // Persist transcript to localStorage so it survives reload
  useEffect(() => {
    if (typeof window === "undefined") return;
    try { localStorage.setItem(CHAT_KEY, JSON.stringify(messages)); } catch { /* quota */ }
  }, [messages]);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: "smooth" });
  }, [messages, status]);
  useEffect(() => { inputRef.current?.focus(); }, [status]);

  const clearChat = () => {
    setMessages([]);
    try { localStorage.removeItem(CHAT_KEY); } catch { /* noop */ }
    toast.success("تم مسح المحادثة");
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const text = input.trim();
    if (!text || isLoading) return;
    const c = cases.data?.find((x) => x.id === caseId);
    const prefix = c ? `[القضية المرتبطة: ${c.title ?? c.case_number}]\n` : "";
    setInput("");
    await sendMessage({ text: prefix + text });
  };

  const suggestions = [
    "ما هي مدة التظلم في الأحكام العمالية؟",
    "اشرح الفرق بين الوكالة العامة والخاصة",
    "ما الإجراءات النظامية لرفع دعوى تنفيذ؟",
    "كيف أحسب مكافأة نهاية الخدمة؟",
  ];

  return (
    <Card className="card-3d border-none overflow-hidden flex flex-col h-[calc(100vh-24rem)] min-h-[520px]">
      <div className="bg-gradient-to-l from-indigo-600 via-blue-600 to-cyan-500 text-white p-4 flex items-center gap-3">
        <div className="grid h-11 w-11 place-items-center rounded-xl bg-white/20 backdrop-blur border border-white/30 shadow-xl">
          <Bot className="h-5 w-5" />
        </div>
        <div className="flex-1">
          <h3 className="font-bold">المستشار العدلي الذكي</h3>
          <p className="text-xs opacity-80">متخصص في الأنظمة السعودية</p>
        </div>
        <select
          value={caseId}
          onChange={(e) => setCaseId(e.target.value)}
          className="h-9 rounded-lg bg-white/15 border border-white/30 text-white text-xs px-3 backdrop-blur"
        >
          <option value="" className="text-foreground">— ربط بقضية —</option>
          {cases.data?.map((c) => (
            <option key={c.id} value={c.id} className="text-foreground">
              {c.title ?? c.case_number}
            </option>
          ))}
        </select>
        {messages.length > 0 && (
          <div className="flex items-center gap-1">
            <button type="button" onClick={() => exportChatPdf(messages)} title="تصدير PDF"
              className="grid h-9 w-9 place-items-center rounded-lg bg-white/15 border border-white/30 hover:bg-white/25 text-white">
              <Download className="h-4 w-4" />
            </button>
            <button type="button" onClick={() => exportChatTxt(messages)} title="تصدير TXT"
              className="grid h-9 w-9 place-items-center rounded-lg bg-white/15 border border-white/30 hover:bg-white/25 text-white">
              <FileText className="h-4 w-4" />
            </button>
            <button type="button" onClick={clearChat} title="مسح المحادثة"
              className="grid h-9 w-9 place-items-center rounded-lg bg-white/15 border border-white/30 hover:bg-rose-500/40 text-white">
              <Trash2 className="h-4 w-4" />
            </button>
          </div>
        )}
      </div>


      <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 space-y-4 bg-gradient-to-b from-muted/20 to-transparent">
        {messages.length === 0 && (
          <div className="text-center py-8">
            <div className="mx-auto h-16 w-16 rounded-2xl bg-gradient-to-br from-indigo-500 to-blue-600 grid place-items-center text-white mb-4 shadow-xl">
              <Sparkles className="h-8 w-8" />
            </div>
            <h4 className="font-bold text-lg mb-1">مرحباً بك في المستشار العدلي</h4>
            <p className="text-sm text-muted-foreground mb-6">اسألني عن أي شأن قانوني سعودي</p>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-2 max-w-2xl mx-auto">
              {suggestions.map((s) => (
                <button
                  key={s}
                  onClick={() => setInput(s)}
                  className="text-right text-sm p-3 rounded-xl bg-card border hover:border-gold hover:shadow-md transition-all"
                >💡 {s}</button>
              ))}
            </div>
          </div>
        )}

        {messages.map((m) => <Bubble key={m.id} message={m} />)}

        {status === "submitted" && (
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <div className="grid h-8 w-8 place-items-center rounded-full bg-primary text-gold">
              <Bot className="h-4 w-4" />
            </div>
            <Loader2 className="h-4 w-4 animate-spin" /> يفكّر المستشار...
          </div>
        )}

        {error && (
          <div className="rounded-lg bg-destructive/10 border border-destructive/30 p-3 text-sm text-destructive">
            {error.message}
          </div>
        )}
      </div>

      <form onSubmit={handleSubmit} className="border-t bg-card p-3 flex gap-2">
        <Input
          ref={inputRef}
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="اكتب سؤالك القانوني هنا..."
          disabled={isLoading}
          className="text-right h-11"
          autoFocus
        />
        <Button type="submit" disabled={isLoading || !input.trim()} className="btn-gold h-11 px-5">
          {isLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
        </Button>
      </form>
    </Card>
  );
}

function Bubble({ message }: { message: UIMessage }) {
  const isUser = message.role === "user";
  const text = message.parts.map((p) => (p.type === "text" ? p.text : "")).join("");
  return (
    <div className={`flex gap-3 ${isUser ? "flex-row-reverse" : ""}`}>
      <div className={`grid h-8 w-8 shrink-0 place-items-center rounded-full ${isUser ? "bg-gold text-primary" : "bg-primary text-gold"}`}>
        {isUser ? <User className="h-4 w-4" /> : <Bot className="h-4 w-4" />}
      </div>
      <div className={`max-w-[85%] rounded-2xl px-4 py-2.5 text-sm leading-relaxed whitespace-pre-wrap ${
        isUser ? "bg-primary text-primary-foreground rounded-tr-sm" : "bg-card border rounded-tl-sm shadow-sm"
      }`}>
        {text || <span className="opacity-50">...</span>}
      </div>
    </div>
  );
}

function DocumentAnalyzer() {
  const [fileName, setFileName] = useState("");
  const [fileText, setFileText] = useState("");

  const onFile = async (file: File) => {
    setFileName(file.name);
    if (file.type.startsWith("text/") || file.name.endsWith(".txt") || file.name.endsWith(".md")) {
      const text = await file.text();
      setFileText(text);
      toast.success("تم استخراج النص من الملف");
    } else {
      toast.info("الصق نص المستند يدوياً في المربع أدناه (PDF/Word غير مدعوم في المتصفح حالياً)");
    }
  };

  return (
    <div className="space-y-4">
      <Card className="card-3d border-none p-5">
        <label className="flex items-center justify-center gap-3 h-28 rounded-xl border-2 border-dashed border-gold/40 bg-gold/5 cursor-pointer hover:bg-gold/10 transition">
          <Upload className="h-6 w-6 text-gold" />
          <div className="text-center">
            <div className="font-semibold text-sm">ارفع مستنداً للتحليل</div>
            <div className="text-xs text-muted-foreground">TXT/MD مدعوم — للملفات الأخرى الصق النص يدوياً</div>
            {fileName && <div className="text-xs text-gold mt-1 flex items-center gap-1 justify-center"><FileText className="h-3 w-3" /> {fileName}</div>}
          </div>
          <input
            type="file"
            className="hidden"
            accept=".txt,.md,.text"
            onChange={(e) => e.target.files?.[0] && onFile(e.target.files[0])}
          />
        </label>
      </Card>

      <AiGenerator
        title="تحليل وتلخيص المستند"
        description="ألصق نص المستند أو الحكم وسيقدّم المساعد ملخصاً، النقاط الرئيسية، والملاحظات القانونية."
        toolId="summarize"
        contextLabel="نص المستند"
        contextPlaceholder="الصق نص المستند أو الحكم هنا..."
        rows={12}
        minLen={30}
      />
      {fileText && (
        <Card className="card-3d border-none p-4">
          <div className="text-xs text-muted-foreground mb-2">المعاينة: {fileName}</div>
          <pre className="text-xs whitespace-pre-wrap max-h-40 overflow-y-auto">{fileText.slice(0, 1000)}{fileText.length > 1000 ? "..." : ""}</pre>
        </Card>
      )}
    </div>
  );
}
