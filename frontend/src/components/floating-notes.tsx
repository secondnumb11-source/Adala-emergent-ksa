import { useEffect, useState } from "react";
import { StickyNote, X, Plus, Trash2, Pencil, Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import { toast } from "sonner";

type NoteColor = "yellow" | "blue" | "green" | "pink" | "purple";

interface Note {
  id: string;
  text: string;
  color: NoteColor;
  createdAt: number;
  updatedAt: number;
}

const STORAGE_KEY = "lovable.floating-notes.v1";

const COLORS: Record<NoteColor, { bg: string; border: string; dot: string; label: string }> = {
  yellow: { bg: "bg-amber-50 dark:bg-amber-950/40", border: "border-amber-300 dark:border-amber-700", dot: "bg-amber-400", label: "أصفر" },
  blue:   { bg: "bg-sky-50 dark:bg-sky-950/40",     border: "border-sky-300 dark:border-sky-700",     dot: "bg-sky-400",   label: "أزرق" },
  green:  { bg: "bg-emerald-50 dark:bg-emerald-950/40", border: "border-emerald-300 dark:border-emerald-700", dot: "bg-emerald-400", label: "أخضر" },
  pink:   { bg: "bg-pink-50 dark:bg-pink-950/40",   border: "border-pink-300 dark:border-pink-700",   dot: "bg-pink-400",  label: "وردي" },
  purple: { bg: "bg-violet-50 dark:bg-violet-950/40", border: "border-violet-300 dark:border-violet-700", dot: "bg-violet-400", label: "بنفسجي" },
};

function loadNotes(): Note[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function saveNotes(notes: Note[]) {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(notes));
  } catch (err) {
    console.error("[notes] failed to persist:", err);
  }
}

export function FloatingNotes() {
  const [open, setOpen] = useState(false);
  const [notes, setNotes] = useState<Note[]>([]);
  const [draft, setDraft] = useState("");
  const [draftColor, setDraftColor] = useState<NoteColor>("yellow");
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editText, setEditText] = useState("");

  // hydrate from localStorage after mount (ssr-safe)
  useEffect(() => {
    setNotes(loadNotes());
  }, []);

  // persist on change
  useEffect(() => {
    saveNotes(notes);
  }, [notes]);

  const addNote = () => {
    const text = draft.trim();
    if (!text) {
      toast.error("اكتب نص الملاحظة أولاً");
      return;
    }
    if (text.length > 2000) {
      toast.error("النص طويل جداً (الحد 2000 حرف)");
      return;
    }
    const now = Date.now();
    const newNote: Note = {
      id: `${now}-${Math.random().toString(36).slice(2, 8)}`,
      text,
      color: draftColor,
      createdAt: now,
      updatedAt: now,
    };
    setNotes((prev) => [newNote, ...prev]);
    setDraft("");
    toast.success("تم حفظ الملاحظة");
  };

  const removeNote = (id: string) => {
    setNotes((prev) => prev.filter((n) => n.id !== id));
    if (editingId === id) setEditingId(null);
    toast.success("تم حذف الملاحظة");
  };

  const startEdit = (note: Note) => {
    setEditingId(note.id);
    setEditText(note.text);
  };

  const saveEdit = (id: string) => {
    const text = editText.trim();
    if (!text) {
      toast.error("لا يمكن أن تكون الملاحظة فارغة");
      return;
    }
    setNotes((prev) =>
      prev.map((n) => (n.id === id ? { ...n, text, updatedAt: Date.now() } : n)),
    );
    setEditingId(null);
    toast.success("تم تحديث الملاحظة");
  };

  const changeColor = (id: string, color: NoteColor) => {
    setNotes((prev) => prev.map((n) => (n.id === id ? { ...n, color, updatedAt: Date.now() } : n)));
  };

  return (
    <>
      <button
        onClick={() => setOpen((v) => !v)}
        aria-label="فتح الملاحظات"
        className="fixed bottom-6 left-6 z-40 inline-flex items-center gap-2 rounded-full bg-gradient-to-br from-amber-400 to-amber-600 px-4 py-2.5 text-sm font-semibold text-white shadow-2xl shadow-amber-500/30 ring-2 ring-amber-300/50 transition-all hover:scale-105 hover:shadow-amber-500/50 active:scale-95"
      >
        <StickyNote className="h-4 w-4" />
        الملاحظات
        {notes.length > 0 && (
          <span className="inline-flex h-5 min-w-5 items-center justify-center rounded-full bg-white/90 px-1.5 text-[10px] font-bold text-amber-700">
            {notes.length}
          </span>
        )}
      </button>

      {open && (
        <div
          dir="rtl"
          className="fixed bottom-20 left-6 z-40 flex h-[min(560px,80vh)] w-[min(380px,92vw)] flex-col overflow-hidden rounded-2xl border border-border bg-card shadow-2xl animate-fade-in"
        >
          <div className="flex items-center justify-between border-b border-border px-4 py-3">
            <div className="flex items-center gap-2 font-bold">
              <StickyNote className="h-4 w-4 text-amber-500" />
              ملاحظاتي السريعة
            </div>
            <button
              onClick={() => setOpen(false)}
              aria-label="إغلاق"
              className="rounded-md p-1 text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
            >
              <X className="h-4 w-4" />
            </button>
          </div>

          {/* Composer */}
          <div className="border-b border-border bg-muted/30 p-3">
            <textarea
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              placeholder="اكتب ملاحظتك هنا..."
              rows={3}
              maxLength={2000}
              className="w-full resize-none rounded-lg border border-input bg-background p-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-400"
            />
            <div className="mt-2 flex items-center justify-between gap-2">
              <div className="flex items-center gap-1.5">
                {(Object.keys(COLORS) as NoteColor[]).map((c) => (
                  <button
                    key={c}
                    onClick={() => setDraftColor(c)}
                    aria-label={`اختر اللون ${COLORS[c].label}`}
                    title={COLORS[c].label}
                    className={`h-5 w-5 rounded-full ${COLORS[c].dot} transition-all ${
                      draftColor === c ? "scale-125 ring-2 ring-offset-1 ring-foreground/40" : "hover:scale-110"
                    }`}
                  />
                ))}
              </div>
              <Button
                size="sm"
                onClick={addNote}
                className="h-8 gap-1 bg-amber-500 text-white hover:bg-amber-600"
              >
                <Plus className="h-3.5 w-3.5" />
                إضافة
              </Button>
            </div>
          </div>

          {/* List */}
          <div className="flex-1 overflow-y-auto p-3 space-y-2">
            {notes.length === 0 ? (
              <div className="py-12 text-center text-sm text-muted-foreground">
                لا توجد ملاحظات بعد.
                <br />
                اكتب أول ملاحظة في الأعلى.
              </div>
            ) : (
              notes.map((note) => {
                const colors = COLORS[note.color];
                const isEditing = editingId === note.id;
                return (
                  <div
                    key={note.id}
                    className={`group rounded-lg border ${colors.border} ${colors.bg} p-3 shadow-sm transition-all hover:shadow-md`}
                  >
                    {isEditing ? (
                      <>
                        <textarea
                          value={editText}
                          onChange={(e) => setEditText(e.target.value)}
                          rows={3}
                          maxLength={2000}
                          className="w-full resize-none rounded border border-input bg-background p-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-amber-400"
                        />
                        <div className="mt-2 flex justify-end gap-1">
                          <button
                            onClick={() => setEditingId(null)}
                            className="rounded p-1.5 text-muted-foreground hover:bg-background"
                            aria-label="إلغاء"
                          >
                            <X className="h-3.5 w-3.5" />
                          </button>
                          <button
                            onClick={() => saveEdit(note.id)}
                            className="rounded bg-emerald-500 p-1.5 text-white hover:bg-emerald-600"
                            aria-label="حفظ التعديل"
                          >
                            <Check className="h-3.5 w-3.5" />
                          </button>
                        </div>
                      </>
                    ) : (
                      <>
                        <div className="whitespace-pre-wrap break-words text-sm leading-relaxed text-foreground">
                          {note.text}
                        </div>
                        <div className="mt-2 flex items-center justify-between gap-2 border-t border-foreground/5 pt-2">
                          <div className="flex items-center gap-1">
                            {(Object.keys(COLORS) as NoteColor[]).map((c) => (
                              <button
                                key={c}
                                onClick={() => changeColor(note.id, c)}
                                aria-label={`غيّر اللون إلى ${COLORS[c].label}`}
                                title={COLORS[c].label}
                                className={`h-3 w-3 rounded-full ${COLORS[c].dot} transition-transform ${
                                  note.color === c ? "scale-150 ring-1 ring-foreground/30" : "hover:scale-125 opacity-60"
                                }`}
                              />
                            ))}
                          </div>
                          <div className="flex items-center gap-1">
                            <span className="text-[10px] text-muted-foreground">
                              {new Date(note.updatedAt).toLocaleDateString("ar-SA")}
                            </span>
                            <button
                              onClick={() => startEdit(note)}
                              className="rounded p-1 text-muted-foreground opacity-0 group-hover:opacity-100 hover:bg-foreground/10 hover:text-foreground"
                              aria-label="تعديل"
                            >
                              <Pencil className="h-3.5 w-3.5" />
                            </button>
                            <button
                              onClick={() => removeNote(note.id)}
                              className="rounded p-1 text-muted-foreground opacity-0 group-hover:opacity-100 hover:bg-destructive/20 hover:text-destructive"
                              aria-label="حذف"
                            >
                              <Trash2 className="h-3.5 w-3.5" />
                            </button>
                          </div>
                        </div>
                      </>
                    )}
                  </div>
                );
              })
            )}
          </div>
        </div>
      )}
    </>
  );
}
