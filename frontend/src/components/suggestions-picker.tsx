import { useMemo, useState } from "react";
import { Sparkles, CheckCircle2, Loader2, Play } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Badge } from "@/components/ui/badge";
import { toast } from "sonner";

/**
 * Suggestion item shown at the end of a case/task stage.
 * Each suggestion is a discrete next-action the user can opt into.
 */
export type Suggestion = {
  id: string;
  title: string;
  description?: string;
  category?: string;
  /** Optional weight/priority shown as a small badge */
  priority?: "high" | "normal" | "low";
};

export type SuggestionsPickerProps = {
  title?: string;
  stageLabel?: string;
  suggestions: Suggestion[];
  /** Receives the selected suggestions in one shot. */
  onExecute: (selected: Suggestion[]) => Promise<void> | void;
  /** Default-selected ids (e.g. all "high" priority). */
  defaultSelected?: string[];
  emptyText?: string;
};

const PRIORITY_AR: Record<NonNullable<Suggestion["priority"]>, string> = {
  high: "أولوية عالية",
  normal: "عادية",
  low: "اختيارية",
};

const PRIORITY_CLASS: Record<NonNullable<Suggestion["priority"]>, string> = {
  high: "bg-rose-500/15 text-rose-500 border-rose-500/30",
  normal: "bg-gold/15 text-gold border-gold/30",
  low: "bg-muted text-muted-foreground border-border",
};

/**
 * Multi-select picker for AI suggestions that appear when a stage completes.
 * The user ticks any number of suggestions and clicks one execute button
 * to send them all to the server in a single batch.
 */
export function SuggestionsPicker({
  title = "اقتراحات لإكمال هذه المرحلة",
  stageLabel,
  suggestions,
  onExecute,
  defaultSelected,
  emptyText = "لا توجد اقتراحات حالياً.",
}: SuggestionsPickerProps) {
  const [selected, setSelected] = useState<Set<string>>(
    () => new Set(defaultSelected ?? suggestions.filter((s) => s.priority === "high").map((s) => s.id)),
  );
  const [running, setRunning] = useState(false);

  const selectedList = useMemo(
    () => suggestions.filter((s) => selected.has(s.id)),
    [suggestions, selected],
  );

  const toggle = (id: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const selectAll = () => setSelected(new Set(suggestions.map((s) => s.id)));
  const clearAll = () => setSelected(new Set());

  const execute = async () => {
    if (selectedList.length === 0) {
      toast.error("اختر اقتراحاً واحداً على الأقل");
      return;
    }
    setRunning(true);
    try {
      await onExecute(selectedList);
      toast.success(`تم تنفيذ ${selectedList.length} اقتراحاً`);
      setSelected(new Set());
    } catch (e: any) {
      toast.error(e?.message || "فشل تنفيذ بعض الاقتراحات");
    } finally {
      setRunning(false);
    }
  };

  return (
    <Card
      data-testid="suggestions-picker"
      className="card-3d border-none p-6 bg-gradient-to-bl from-gold/10 via-background to-background relative overflow-hidden"
      dir="rtl"
    >
      <div className="absolute -top-12 -left-12 h-40 w-40 rounded-full bg-gold/15 blur-3xl pointer-events-none" />
      <div className="relative">
        <div className="flex items-start justify-between gap-3 mb-4">
          <div className="flex items-center gap-3">
            <span className="grid place-items-center h-10 w-10 rounded-xl bg-gold/15 border border-gold/30 text-gold shrink-0">
              <Sparkles className="h-5 w-5" />
            </span>
            <div>
              {stageLabel && (
                <div className="text-[10px] uppercase tracking-[0.28em] text-gold/80 font-bold mb-0.5">
                  {stageLabel}
                </div>
              )}
              <h3 className="text-base md:text-lg font-extrabold tracking-tight leading-tight">{title}</h3>
              <p className="text-xs text-muted-foreground mt-0.5">
                اختر ما يناسبك ثم اضغط «تنفيذ المختار» مرة واحدة.
              </p>
            </div>
          </div>
          <div className="flex items-center gap-1.5 shrink-0">
            <Button variant="ghost" size="sm" onClick={selectAll} className="h-7 text-[11px] font-bold hover:text-gold">
              الكل
            </Button>
            <Button variant="ghost" size="sm" onClick={clearAll} className="h-7 text-[11px] font-bold hover:text-rose-500">
              إفراغ
            </Button>
          </div>
        </div>

        {suggestions.length === 0 ? (
          <p className="text-sm text-muted-foreground text-center py-8">{emptyText}</p>
        ) : (
          <ul className="space-y-2">
            {suggestions.map((s) => {
              const checked = selected.has(s.id);
              return (
                <li key={s.id}>
                  <label
                    className={`flex items-start gap-3 rounded-xl border p-3.5 cursor-pointer transition-all ${
                      checked
                        ? "border-gold/60 bg-gold/5 shadow-sm"
                        : "hover:border-gold/30 hover:bg-muted/40"
                    }`}
                  >
                    <Checkbox
                      checked={checked}
                      onCheckedChange={() => toggle(s.id)}
                      className="mt-0.5 data-[state=checked]:bg-gold data-[state=checked]:border-gold"
                    />
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="font-bold text-sm tracking-tight">{s.title}</span>
                        {s.priority && (
                          <Badge variant="outline" className={`text-[10px] font-bold ${PRIORITY_CLASS[s.priority]}`}>
                            {PRIORITY_AR[s.priority]}
                          </Badge>
                        )}
                        {s.category && (
                          <Badge variant="outline" className="text-[10px] font-semibold">
                            {s.category}
                          </Badge>
                        )}
                      </div>
                      {s.description && (
                        <p className="text-xs text-muted-foreground mt-1.5 leading-relaxed">
                          {s.description}
                        </p>
                      )}
                    </div>
                    {checked && <CheckCircle2 className="h-4 w-4 text-gold shrink-0 mt-0.5" />}
                  </label>
                </li>
              );
            })}
          </ul>
        )}

        {/* Sticky execution bar */}
        {suggestions.length > 0 && (
          <div className="mt-5 flex items-center justify-between gap-3 rounded-xl border border-gold/30 bg-gold/5 px-4 py-3">
            <div className="text-xs">
              <span className="text-muted-foreground">المختار: </span>
              <span className="font-extrabold text-base text-gold">{selectedList.length}</span>
              <span className="text-muted-foreground"> من {suggestions.length}</span>
            </div>
            <Button
              onClick={execute}
              disabled={running || selectedList.length === 0}
              className="btn-gold gap-2 h-10 px-5 font-bold"
            >
              {running ? <Loader2 className="h-4 w-4 animate-spin" /> : <Play className="h-4 w-4" />}
              تنفيذ المختار ({selectedList.length})
            </Button>
          </div>
        )}
      </div>
    </Card>
  );
}
