import {
  createContext, useContext, useEffect, useMemo, useState, type ReactNode,
} from "react";
import {
  DndContext, PointerSensor, useSensor, useSensors, closestCenter,
  type DragEndEvent,
} from "@dnd-kit/core";
import {
  SortableContext, useSortable, rectSortingStrategy, arrayMove,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { GripVertical, Maximize2, Minimize2, RotateCcw, Pencil, Check } from "lucide-react";

/** Allowed column spans on the 12-col lg grid. */
export type CardSpan = 3 | 4 | 6 | 8 | 12;
const SPAN_CYCLE: CardSpan[] = [4, 6, 8, 12];
const SPAN_LABEL: Record<CardSpan, string> = {
  3: "ربع العرض",
  4: "ثلث العرض",
  6: "نصف العرض",
  8: "ثلثا العرض",
  12: "عرض كامل",
};

const SPAN_CLASS: Record<CardSpan, string> = {
  3: "lg:col-span-3",
  4: "lg:col-span-4",
  6: "lg:col-span-6",
  8: "lg:col-span-8",
  12: "lg:col-span-12",
};

type LayoutEntry = { id: string; span: CardSpan };
type StoredLayout = LayoutEntry[];

function storageKey(userId: string, scope: string) {
  return `lex:dash-layout:${scope}:${userId}`;
}

interface Ctx {
  editing: boolean;
  layout: Map<string, CardSpan>;
  order: string[];
  setSpan: (id: string, span: CardSpan) => void;
  registerDefault: (id: string, span: CardSpan) => void;
}
const LayoutCtx = createContext<Ctx | null>(null);

export function useDashboardEditing() {
  const ctx = useContext(LayoutCtx);
  return ctx?.editing ?? false;
}

interface ProviderProps {
  userId: string;
  scope?: string;
  children: ReactNode;
  /** Insertion order of cards declared by the page. */
  defaults: Array<{ id: string; span: CardSpan }>;
  /** Optional controlled editing state (lets a parent expose the toggle). */
  editing?: boolean;
  onEditingChange?: (editing: boolean) => void;
  /** Hide the built-in toolbar (when the parent renders its own toggle). */
  hideToolbar?: boolean;
}

/** Wraps a dashboard page; renders a 12-col grid and manages reorder/resize. */
export function DashboardLayout({ userId, scope = "main", defaults, children, editing: editingProp, onEditingChange, hideToolbar }: ProviderProps) {
  const key = storageKey(userId, scope);
  const [editingState, setEditingState] = useState(false);
  const editing = editingProp ?? editingState;
  const setEditing = (v: boolean | ((p: boolean) => boolean)) => {
    const next = typeof v === "function" ? (v as any)(editing) : v;
    if (onEditingChange) onEditingChange(next);
    else setEditingState(next);
  };


  const [order, setOrder] = useState<string[]>(() => defaults.map(d => d.id));
  const [spans, setSpans] = useState<Map<string, CardSpan>>(
    () => new Map(defaults.map(d => [d.id, d.span])),
  );

  // Hydrate from localStorage once.
  useEffect(() => {
    try {
      const raw = localStorage.getItem(key);
      if (!raw) return;
      const parsed = JSON.parse(raw) as StoredLayout;
      const known = new Set(defaults.map(d => d.id));
      const stored = parsed.filter(e => known.has(e.id));
      const missing = defaults.filter(d => !parsed.some(e => e.id === d.id));
      const finalOrder = [...stored.map(e => e.id), ...missing.map(m => m.id)];
      const finalSpans = new Map<string, CardSpan>();
      defaults.forEach(d => finalSpans.set(d.id, d.span));
      stored.forEach(e => finalSpans.set(e.id, e.span));
      setOrder(finalOrder);
      setSpans(finalSpans);
    } catch { /* ignore */ }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);

  const persist = (newOrder: string[], newSpans: Map<string, CardSpan>) => {
    try {
      const data: StoredLayout = newOrder.map(id => ({ id, span: newSpans.get(id) ?? 12 }));
      localStorage.setItem(key, JSON.stringify(data));
    } catch { /* ignore */ }
  };

  const setSpan = (id: string, span: CardSpan) => {
    setSpans(prev => {
      const next = new Map(prev);
      next.set(id, span);
      persist(order, next);
      return next;
    });
  };

  const registerDefault = (id: string, span: CardSpan) => {
    setSpans(prev => {
      if (prev.has(id)) return prev;
      const next = new Map(prev);
      next.set(id, span);
      return next;
    });
    setOrder(prev => (prev.includes(id) ? prev : [...prev, id]));
  };

  const reset = () => {
    const newOrder = defaults.map(d => d.id);
    const newSpans = new Map(defaults.map(d => [d.id, d.span] as const));
    setOrder(newOrder);
    setSpans(newSpans);
    persist(newOrder, newSpans);
  };

  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 6 } }));

  const onDragEnd = (e: DragEndEvent) => {
    const { active, over } = e;
    if (!over || active.id === over.id) return;
    setOrder(prev => {
      const oldIdx = prev.indexOf(String(active.id));
      const newIdx = prev.indexOf(String(over.id));
      if (oldIdx < 0 || newIdx < 0) return prev;
      const next = arrayMove(prev, oldIdx, newIdx);
      persist(next, spans);
      return next;
    });
  };

  const ctx = useMemo<Ctx>(() => ({
    editing, layout: spans, order, setSpan, registerDefault,
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }), [editing, spans, order]);

  return (
    <LayoutCtx.Provider value={ctx}>
      {/* Floating toolbar */}
      {!hideToolbar && (
        <div className="flex items-center justify-end gap-2" data-html2canvas-ignore="true">
          {editing && (
            <button
              onClick={reset}
              className="inline-flex items-center gap-1.5 rounded-lg border border-border bg-card px-3 py-1.5 text-xs font-semibold text-muted-foreground hover:bg-muted transition"
            >
              <RotateCcw className="h-3.5 w-3.5" /> إعادة التخطيط الافتراضي
            </button>
          )}
          <button
            onClick={() => setEditing(e => !e)}
            className={`inline-flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-xs font-bold transition ${
              editing
                ? "border-emerald-500/50 bg-emerald-500/15 text-emerald-300"
                : "border-gold/40 bg-gold/10 text-gold hover:bg-gold/20"
            }`}
          >
            {editing ? <><Check className="h-3.5 w-3.5" /> إنهاء التخصيص</> : <><Pencil className="h-3.5 w-3.5" /> تخصيص اللوحة</>}
          </button>
        </div>
      )}

      <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={onDragEnd}>

        <SortableContext items={order} strategy={rectSortingStrategy}>
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-5">
            <OrderedSlots order={order}>{children}</OrderedSlots>
          </div>
        </SortableContext>
      </DndContext>
    </LayoutCtx.Provider>
  );
}

/**
 * Reorders DashboardCard children to match the saved order.
 * Children that are not DashboardCard pass through in original position.
 */
function OrderedSlots({ order, children }: { order: string[]; children: ReactNode }) {
  // Flatten children, then sort the DashboardCard slots by `order`.
  const arr = Array.isArray(children) ? children : [children];
  const cards: Array<{ id: string; node: ReactNode }> = [];
  const others: ReactNode[] = [];
  arr.forEach((c, i) => {
    if (c && typeof c === "object" && "props" in (c as any) && (c as any).props?.id) {
      cards.push({ id: (c as any).props.id, node: c });
    } else if (c) {
      others.push(<div key={`__other-${i}`} className="lg:col-span-12">{c}</div>);
    }
  });
  const sorted = [...cards].sort((a, b) => order.indexOf(a.id) - order.indexOf(b.id));
  return <>{others}{sorted.map(s => s.node)}</>;
}

interface CardProps {
  id: string;
  defaultSpan: CardSpan;
  title?: string;
  children: ReactNode;
}

export function DashboardCard({ id, defaultSpan, title, children }: CardProps) {
  const ctx = useContext(LayoutCtx);
  const span = ctx?.layout.get(id) ?? defaultSpan;
  const editing = ctx?.editing ?? false;

  useEffect(() => {
    ctx?.registerDefault(id, defaultSpan);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id, disabled: !editing,
  });
  const style: React.CSSProperties = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.6 : 1,
  };

  const cycleSpan = () => {
    if (!ctx) return;
    const idx = SPAN_CYCLE.indexOf(span as CardSpan);
    const next = SPAN_CYCLE[(idx + 1) % SPAN_CYCLE.length];
    ctx.setSpan(id, next);
  };
  const shrinkSpan = () => {
    if (!ctx) return;
    const idx = SPAN_CYCLE.indexOf(span as CardSpan);
    const next = SPAN_CYCLE[(idx - 1 + SPAN_CYCLE.length) % SPAN_CYCLE.length];
    ctx.setSpan(id, next);
  };

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={`relative col-span-1 ${SPAN_CLASS[span]} ${editing ? "ring-2 ring-gold/50 ring-offset-2 ring-offset-background rounded-2xl" : ""}`}
    >
      {editing && (
        <div
          className="absolute -top-3 right-3 z-30 flex items-center gap-1 rounded-full border border-gold/40 bg-card/95 backdrop-blur px-1.5 py-1 shadow-lg"
          data-html2canvas-ignore="true"
        >
          <button
            {...attributes}
            {...listeners}
            title="اسحب لإعادة الترتيب"
            className="grid h-7 w-7 place-items-center rounded-full text-gold hover:bg-gold/15 cursor-grab active:cursor-grabbing"
          >
            <GripVertical className="h-4 w-4" />
          </button>
          <button
            onClick={shrinkSpan}
            title="تصغير"
            className="grid h-7 w-7 place-items-center rounded-full text-muted-foreground hover:bg-muted hover:text-foreground"
          >
            <Minimize2 className="h-3.5 w-3.5" />
          </button>
          <span className="text-[10px] font-bold text-gold px-1 select-none whitespace-nowrap">
            {SPAN_LABEL[span as CardSpan]}
          </span>
          <button
            onClick={cycleSpan}
            title="تكبير"
            className="grid h-7 w-7 place-items-center rounded-full text-muted-foreground hover:bg-muted hover:text-foreground"
          >
            <Maximize2 className="h-3.5 w-3.5" />
          </button>
          {title && (
            <span className="hidden md:inline text-[10px] text-muted-foreground border-r border-border pr-2 mr-1 max-w-[140px] truncate">
              {title}
            </span>
          )}
        </div>
      )}
      <div className={editing ? "pointer-events-none select-none opacity-95" : ""}>
        {children}
      </div>
    </div>
  );
}
