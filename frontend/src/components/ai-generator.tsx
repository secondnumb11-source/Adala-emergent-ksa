import { useState } from "react";
import { useServerFn } from "@tanstack/react-start";
import { Loader2, Sparkles, Copy, Check, Wand2, Download } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { toast } from "sonner";
import { runAiTool } from "@/lib/ai-tools.functions";
import { useList } from "@/lib/data-hooks";

export type AiField = {
  key: string;
  label: string;
  placeholder?: string;
  options?: string[];
  type?: "text" | "select" | "case" | "client";
};

type RunArgs = {
  toolId:
    | "consultant" | "analyze" | "summarize" | "memorandum"
    | "lawsuit" | "appeal" | "objection" | "notice"
    | "contract" | "fees_contract" | "letter" | "translate"
    | "explain_article" | "search_article";
  context: string;
  extras?: Record<string, string>;
};

export function AiGenerator({
  title,
  description,
  toolId,
  fields = [],
  contextLabel = "التفاصيل / السياق",
  contextPlaceholder = "اكتب التفاصيل هنا...",
  minLen = 5,
  rows = 8,
}: {
  title: string;
  description: string;
  toolId: RunArgs["toolId"];
  fields?: AiField[];
  contextLabel?: string;
  contextPlaceholder?: string;
  minLen?: number;
  rows?: number;
}) {
  const run = useServerFn(runAiTool);
  const [context, setContext] = useState("");
  const [extras, setExtras] = useState<Record<string, string>>({});
  const [result, setResult] = useState("");
  const [loading, setLoading] = useState(false);
  const [copied, setCopied] = useState(false);

  const casesQ = useList<{ id: string; title?: string; case_number?: string }>("cases");
  const clientsQ = useList<{ id: string; full_name?: string; name?: string }>("clients");

  const onRun = async () => {
    if (context.trim().length < minLen) {
      toast.error(`الرجاء إدخال تفاصيل كافية (${minLen} أحرف على الأقل)`);
      return;
    }
    setLoading(true);
    setResult("");
    try {
      const res = await run({ data: { toolId, context, extras } as RunArgs });
      setResult(res.text);
      toast.success("تم التوليد بنجاح");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "حدث خطأ");
    } finally {
      setLoading(false);
    }
  };

  const onCopy = async () => {
    await navigator.clipboard.writeText(result);
    setCopied(true);
    toast.success("تم النسخ");
    setTimeout(() => setCopied(false), 2000);
  };

  const onDownload = () => {
    const blob = new Blob([result], { type: "text/plain;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${title}-${Date.now()}.txt`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="grid lg:grid-cols-2 gap-6">
      <Card className="card-3d border-none p-6">
        <div className="mb-5">
          <h3 className="font-bold text-lg flex items-center gap-2"><Wand2 className="h-5 w-5 text-gold" /> {title}</h3>
          <p className="text-xs text-muted-foreground mt-1">{description}</p>
        </div>

        <div className="space-y-3">
          {fields.map((f) => (
            <div key={f.key}>
              <label className="text-xs font-semibold mb-1.5 block">{f.label}</label>
              {f.type === "case" ? (
                <select
                  value={extras[f.key] ?? ""}
                  onChange={(e) => {
                    const id = e.target.value;
                    const c = casesQ.data?.find((x) => x.id === id);
                    const label = c ? `${c.title ?? ""} ${c.case_number ? `(${c.case_number})` : ""}`.trim() : "";
                    setExtras({ ...extras, [f.key]: label, [`${f.key}_id`]: id });
                  }}
                  className="w-full h-10 rounded-lg border bg-background px-3 text-sm"
                >
                  <option value="">{casesQ.isLoading ? "جارٍ التحميل..." : "— اختر قضية —"}</option>
                  {casesQ.data?.map((c) => (
                    <option key={c.id} value={c.id}>{c.title ?? c.case_number ?? c.id}</option>
                  ))}
                </select>
              ) : f.type === "client" ? (
                <select
                  value={extras[f.key] ?? ""}
                  onChange={(e) => {
                    const id = e.target.value;
                    const c = clientsQ.data?.find((x) => x.id === id);
                    setExtras({ ...extras, [f.key]: c?.full_name ?? c?.name ?? "", [`${f.key}_id`]: id });
                  }}
                  className="w-full h-10 rounded-lg border bg-background px-3 text-sm"
                >
                  <option value="">{clientsQ.isLoading ? "جارٍ التحميل..." : "— اختر عميلاً —"}</option>
                  {clientsQ.data?.map((c) => (
                    <option key={c.id} value={c.id}>{c.full_name ?? c.name ?? c.id}</option>
                  ))}
                </select>
              ) : f.options ? (
                <select
                  value={extras[f.key] ?? ""}
                  onChange={(e) => setExtras({ ...extras, [f.key]: e.target.value })}
                  className="w-full h-10 rounded-lg border bg-background px-3 text-sm"
                >
                  <option value="">— اختر —</option>
                  {f.options.map((o) => <option key={o} value={o}>{o}</option>)}
                </select>
              ) : (
                <Input
                  value={extras[f.key] ?? ""}
                  onChange={(e) => setExtras({ ...extras, [f.key]: e.target.value })}
                  placeholder={f.placeholder}
                  className="text-right h-10"
                />
              )}
            </div>
          ))}

          <div>
            <label className="text-xs font-semibold mb-1.5 block">{contextLabel}</label>
            <Textarea
              value={context}
              onChange={(e) => setContext(e.target.value)}
              placeholder={contextPlaceholder}
              rows={rows}
              className="text-right resize-none"
            />
            <p className="text-[10px] text-muted-foreground mt-1">{context.length} حرف</p>
          </div>

          <Button onClick={onRun} disabled={loading} className="btn-gold w-full h-11">
            {loading ? (
              <><Loader2 className="h-4 w-4 animate-spin ml-2" /> جارٍ التوليد...</>
            ) : (
              <><Wand2 className="h-4 w-4 ml-2" /> توليد بالذكاء الاصطناعي</>
            )}
          </Button>
        </div>
      </Card>

      <Card className="card-3d border-none p-6 bg-gradient-to-br from-card to-muted/30 min-h-[400px] flex flex-col">
        <div className="flex items-center justify-between mb-4">
          <h3 className="font-bold flex items-center gap-2">
            <Sparkles className="h-4 w-4 text-gold" /> النتيجة
          </h3>
          {result && (
            <div className="flex gap-2">
              <Button variant="outline" size="sm" onClick={onDownload} className="gap-1.5">
                <Download className="h-3.5 w-3.5" /> تنزيل
              </Button>
              <Button variant="outline" size="sm" onClick={onCopy} className="gap-1.5">
                {copied ? <Check className="h-3.5 w-3.5 text-emerald-600" /> : <Copy className="h-3.5 w-3.5" />}
                {copied ? "تم النسخ" : "نسخ"}
              </Button>
            </div>
          )}
        </div>

        {loading && (
          <div className="flex-1 flex flex-col items-center justify-center text-muted-foreground gap-3">
            <Loader2 className="h-10 w-10 animate-spin text-gold" />
            <p className="text-sm">يصيغ المساعد النص الآن...</p>
            <Badge variant="outline" className="text-[10px]">قد تستغرق حتى 30 ثانية</Badge>
          </div>
        )}

        {!loading && !result && (
          <div className="flex-1 flex flex-col items-center justify-center text-muted-foreground gap-3 text-center">
            <div className="grid h-16 w-16 place-items-center rounded-2xl bg-muted">
              <Sparkles className="h-8 w-8 opacity-30" />
            </div>
            <p className="text-sm">ستظهر النتيجة هنا بعد التوليد</p>
          </div>
        )}

        {result && (
          <div className="flex-1 overflow-y-auto rounded-xl bg-background border p-5 text-sm leading-relaxed whitespace-pre-wrap font-[500]">
            {result}
          </div>
        )}
      </Card>
    </div>
  );
}
