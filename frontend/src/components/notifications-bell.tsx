import { useEffect, useRef, useState } from "react";
import { BellRing, Check, Trash2, X } from "lucide-react";
import { Link } from "@tanstack/react-router";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";


const KEY = "lovable.notifications.v1";

type Notification = {
  id: string;
  title: string;
  body?: string;
  createdAt: number;
  read: boolean;
  level?: "info" | "success" | "warning" | "danger";
  href?: string;
};

function load(): Notification[] {
  try {
    const raw = localStorage.getItem(KEY);
    if (raw) return JSON.parse(raw);
  } catch {
    /* ignore */
  }
  // Seed with sample notifications on first load
  const seed: Notification[] = [
    {
      id: crypto.randomUUID(),
      title: "جلسة قضائية غداً",
      body: "قضية رقم 124/1446 — محكمة الرياض، 09:30 صباحاً",
      createdAt: Date.now() - 1000 * 60 * 30,
      read: false,
      level: "warning",
    },
    {
      id: crypto.randomUUID(),
      title: "مذكرة جاهزة للمراجعة",
      body: "تم رفع مسودة المذكرة من المحامي خالد",
      createdAt: Date.now() - 1000 * 60 * 60 * 3,
      read: false,
      level: "info",
    },
    {
      id: crypto.randomUUID(),
      title: "تم استلام دفعة من العميل",
      body: "فاتورة #2026-0142 — 7,500 ر.س",
      createdAt: Date.now() - 1000 * 60 * 60 * 24,
      read: true,
      level: "success",
    },
  ];
  try {
    localStorage.setItem(KEY, JSON.stringify(seed));
  } catch {
    /* ignore */
  }
  return seed;
}

function save(items: Notification[]) {
  try {
    localStorage.setItem(KEY, JSON.stringify(items));
  } catch {
    /* ignore */
  }
}

function timeAgo(ts: number) {
  const diff = Date.now() - ts;
  const m = Math.floor(diff / 60000);
  if (m < 1) return "الآن";
  if (m < 60) return `قبل ${m} د`;
  const h = Math.floor(m / 60);
  if (h < 24) return `قبل ${h} س`;
  const d = Math.floor(h / 24);
  return `قبل ${d} يوم`;
}

const LEVEL_STYLES: Record<NonNullable<Notification["level"]>, string> = {
  info: "bg-sky-500/15 text-sky-600 border-sky-500/30",
  success: "bg-emerald-500/15 text-emerald-600 border-emerald-500/30",
  warning: "bg-amber-500/15 text-amber-600 border-amber-500/30",
  danger: "bg-rose-500/15 text-rose-600 border-rose-500/30",
};

export function NotificationsBell() {
  const [items, setItems] = useState<Notification[]>([]);
  const [open, setOpen] = useState(false);
  const popRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setItems(load());
  }, []);

  // Inject auto-notifications for powers of attorney that expire soon
  useEffect(() => {
    let cancelled = false;
    const SEEN_KEY = "lovable.notifications.powers.seen.v1";
    const run = async () => {
      try {
        const { data: { user } } = await supabase.auth.getUser();
        if (!user) return;
        const today = new Date(); today.setHours(0, 0, 0, 0);
        const horizon = new Date(today); horizon.setDate(horizon.getDate() + 60);
        const { data, error } = await supabase
          .from("powers_of_attorney")
          .select("id, wakalah_number, expiry_date, issuer_name")
          .eq("owner_id", user.id)
          .not("expiry_date", "is", null)
          .lte("expiry_date", horizon.toISOString().slice(0, 10));
        if (error || cancelled) return;
        const seenRaw = (() => { try { return JSON.parse(localStorage.getItem(SEEN_KEY) || "{}"); } catch { return {}; } })();
        const seen: Record<string, string> = seenRaw && typeof seenRaw === "object" ? seenRaw : {};
        const existing = load();
        const toAdd: Notification[] = [];
        for (const p of data ?? []) {
          const key = `${p.id}:${p.expiry_date}`;
          if (seen[key]) continue;
          const dl = Math.ceil((new Date(p.expiry_date as string).getTime() - today.getTime()) / 86_400_000);
          const expired = dl < 0;
          toAdd.push({
            id: `pow-${p.id}-${p.expiry_date}`,
            title: expired ? `وكالة منتهية: ${p.wakalah_number}` : `وكالة توشك على الانتهاء (${dl} يوم)`,
            body: `الموكل: ${p.issuer_name ?? "—"} — تاريخ الانتهاء ${p.expiry_date}`,
            createdAt: Date.now(),
            read: false,
            level: expired || dl <= 14 ? "danger" : "warning",
          });
          seen[key] = new Date().toISOString();
        }
        if (toAdd.length) {
          const merged = [
            ...toAdd,
            ...existing.filter((e) => !toAdd.some((a) => a.id === e.id)),
          ];
          save(merged);
          setItems(merged);
          try { localStorage.setItem(SEEN_KEY, JSON.stringify(seen)); } catch { /* ignore */ }
        }
      } catch { /* ignore */ }
    };
    run();
    const t = setInterval(run, 5 * 60_000);
    return () => { cancelled = true; clearInterval(t); };
  }, []);

  // Live alerts for new employee chat messages
  useEffect(() => {
    let cancelled = false;
    let channel: ReturnType<typeof supabase.channel> | null = null;
    const SEEN_KEY = "lovable.notifications.empmsg.seen.v1";
    const seenIds = new Set<string>(
      (() => { try { return JSON.parse(localStorage.getItem(SEEN_KEY) || "[]"); } catch { return []; } })(),
    );
    const persistSeen = () => {
      try { localStorage.setItem(SEEN_KEY, JSON.stringify(Array.from(seenIds).slice(-500))); } catch { /* ignore */ }
    };
    const pushFromRow = (row: { id: string; body: string | null; created_at: string; sender_id: string }) => {
      if (seenIds.has(row.id)) return;
      seenIds.add(row.id);
      const existing = load();
      const body = row.body ?? "رسالة جديدة";
      const note: Notification = {
        id: `msg-${row.id}`,
        title: "رسالة جديدة من زميل",
        body: body.length > 140 ? body.slice(0, 140) + "…" : body,
        createdAt: new Date(row.created_at).getTime() || Date.now(),
        read: false,
        level: "info",
        href: "/app/team-chat",
      };
      const merged = [note, ...existing.filter((e) => e.id !== note.id)];
      save(merged);
      setItems(merged);
      persistSeen();
    };
    const init = async () => {
      try {
        const { data: { user } } = await supabase.auth.getUser();
        if (!user || cancelled) return;
        // Backfill unread on mount
        const { data } = await supabase
          .from("employee_messages")
          .select("id, body, created_at, sender_id")
          .eq("recipient_id", user.id)
          .eq("is_read", false)
          .order("created_at", { ascending: false })
          .limit(20);
        (data ?? []).forEach(pushFromRow);

        channel = supabase
          .channel("rt:bell:employee_messages")
          .on(
            "postgres_changes",
            { event: "INSERT", schema: "public", table: "employee_messages", filter: `recipient_id=eq.${user.id}` },
            (payload) => pushFromRow(payload.new as { id: string; body: string | null; created_at: string; sender_id: string }),
          )
          .subscribe();
      } catch { /* ignore */ }
    };
    init();
    return () => { cancelled = true; if (channel) supabase.removeChannel(channel); };
  }, []);

  // Live alerts for client inquiries (owner sees new questions; client sees replies)
  useEffect(() => {
    let cancelled = false;
    let channel: ReturnType<typeof supabase.channel> | null = null;
    const SEEN_KEY = "lovable.notifications.inquiries.seen.v1";
    const seenIds = new Set<string>(
      (() => { try { return JSON.parse(localStorage.getItem(SEEN_KEY) || "[]"); } catch { return []; } })(),
    );
    const persistSeen = () => {
      try { localStorage.setItem(SEEN_KEY, JSON.stringify(Array.from(seenIds).slice(-500))); } catch { /* ignore */ }
    };
    const push = (
      row: { id: string; body: string; created_at: string; author_role: string; subject: string | null },
      mode: "owner" | "client",
    ) => {
      if (seenIds.has(row.id)) return;
      seenIds.add(row.id);
      const existing = load();
      const note: Notification = {
        id: `inq-${row.id}`,
        title: mode === "owner" ? "استفسار جديد من عميل" : "رد جديد على استفسارك",
        body: (row.subject ? `${row.subject} — ` : "") + (row.body.length > 140 ? row.body.slice(0, 140) + "…" : row.body),
        createdAt: new Date(row.created_at).getTime() || Date.now(),
        read: false,
        level: mode === "owner" ? "warning" : "success",
        href: mode === "owner" ? "/app/clients" : "/app",
      };
      const merged = [note, ...existing.filter((e) => e.id !== note.id)];
      save(merged);
      setItems(merged);
      persistSeen();
    };

    const init = async () => {
      try {
        const { data: { user } } = await supabase.auth.getUser();
        if (!user || cancelled) return;

        // Determine role: client (has portal_user_id on a clients row) vs owner
        const { data: clientRow } = await supabase
          .from("clients")
          .select("id, owner_id")
          .eq("portal_user_id", user.id)
          .maybeSingle();

        if (clientRow) {
          // Client: backfill unread replies addressed to me
          const { data } = await (supabase as any)
            .from("client_inquiries")
            .select("id, body, created_at, author_role, subject, read_at, client_id")
            .eq("client_id", clientRow.id)
            .is("read_at", null)
            .neq("author_role", "client")
            .order("created_at", { ascending: false })
            .limit(20);
          (data ?? []).forEach((r: any) => push(r, "client"));

          channel = supabase
            .channel(`rt:bell:inquiries:client:${clientRow.id}`)
            .on(
              "postgres_changes",
              { event: "INSERT", schema: "public", table: "client_inquiries", filter: `client_id=eq.${clientRow.id}` },
              (payload) => {
                const row = payload.new as any;
                if (row.author_role !== "client") push(row, "client");
              },
            )
            .subscribe();
        } else {
          // Owner/lawyer: alerts on new client-authored inquiries in my workspace
          const { data } = await (supabase as any)
            .from("client_inquiries")
            .select("id, body, created_at, author_role, subject, read_at")
            .eq("owner_id", user.id)
            .eq("author_role", "client")
            .is("read_at", null)
            .order("created_at", { ascending: false })
            .limit(20);
          (data ?? []).forEach((r: any) => push(r, "owner"));

          channel = supabase
            .channel(`rt:bell:inquiries:owner:${user.id}`)
            .on(
              "postgres_changes",
              { event: "INSERT", schema: "public", table: "client_inquiries", filter: `owner_id=eq.${user.id}` },
              (payload) => {
                const row = payload.new as any;
                if (row.author_role === "client") push(row, "owner");
              },
            )
            .subscribe();
        }
      } catch { /* ignore */ }
    };
    init();
    return () => { cancelled = true; if (channel) supabase.removeChannel(channel); };
  }, []);



  useEffect(() => {
    if (!open) return;
    const h = (e: MouseEvent) => {
      if (popRef.current && !popRef.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", h);
    return () => document.removeEventListener("mousedown", h);
  }, [open]);

  const unread = items.filter((i) => !i.read).length;

  const update = (next: Notification[]) => {
    setItems(next);
    save(next);
  };

  return (
    <div className="relative" ref={popRef}>
      <Button
        variant="ghost"
        size="icon"
        onClick={() => setOpen((v) => !v)}
        className="relative"
        aria-label="الإشعارات"
      >
        <BellRing className="h-5 w-5" />
        {unread > 0 && (
          <span className="absolute -top-1 -left-1 min-w-[18px] h-[18px] px-1 rounded-full bg-destructive text-destructive-foreground text-[10px] font-bold grid place-items-center shadow">
            {unread > 9 ? "9+" : unread}
          </span>
        )}
      </Button>

      {open && (
        <div
          className="absolute left-0 mt-2 w-[360px] max-h-[70vh] rounded-2xl border border-border bg-popover shadow-2xl z-50 flex flex-col overflow-hidden"
          dir="rtl"
        >
          <div className="flex items-center justify-between px-4 py-3 border-b border-border bg-gradient-to-bl from-primary/5 to-transparent">
            <div>
              <div className="font-bold text-sm">الإشعارات</div>
              <div className="text-[11px] text-muted-foreground">
                {unread > 0 ? `${unread} غير مقروء` : "كل الإشعارات مقروءة"}
              </div>
            </div>
            <div className="flex items-center gap-1">
              {unread > 0 && (
                <button
                  onClick={() => update(items.map((i) => ({ ...i, read: true })))}
                  className="text-[11px] text-primary hover:text-gold inline-flex items-center gap-1 font-semibold"
                >
                  <Check className="h-3.5 w-3.5" />
                  تعليم الكل
                </button>
              )}
              <button
                onClick={() => setOpen(false)}
                className="p-1 rounded hover:bg-accent"
                aria-label="إغلاق"
              >
                <X className="h-4 w-4" />
              </button>
            </div>
          </div>

          <div className="flex-1 overflow-y-auto">
            {items.length === 0 ? (
              <div className="p-10 text-center text-sm text-muted-foreground">
                لا توجد إشعارات
              </div>
            ) : (
              items.map((n) => (
                <div
                  key={n.id}
                  className={`group flex gap-3 px-4 py-3 border-b border-border/60 hover:bg-accent/40 transition-colors ${
                    !n.read ? "bg-accent/20" : ""
                  }`}
                >
                  <div
                    className={`mt-0.5 h-2 w-2 rounded-full shrink-0 ${
                      n.read ? "bg-transparent" : "bg-destructive"
                    }`}
                  />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-start gap-2">
                      <span
                        className={`text-[9px] font-bold uppercase px-1.5 py-0.5 rounded border ${
                          LEVEL_STYLES[n.level ?? "info"]
                        }`}
                      >
                        {n.level ?? "info"}
                      </span>
                      <span className="text-[10px] text-muted-foreground mr-auto">
                        {timeAgo(n.createdAt)}
                      </span>
                    </div>
                    {n.href ? (
                      <Link
                        to={n.href}
                        onClick={() => {
                          update(items.map((i) => (i.id === n.id ? { ...i, read: true } : i)));
                          setOpen(false);
                        }}
                        className="block mt-1 text-sm font-semibold leading-snug hover:text-primary"
                      >
                        {n.title}
                      </Link>
                    ) : (
                      <div className="mt-1 text-sm font-semibold leading-snug">{n.title}</div>
                    )}
                    {n.body && (
                      <div className="mt-0.5 text-xs text-muted-foreground leading-relaxed">
                        {n.body}
                      </div>
                    )}
                  </div>
                  <div className="flex flex-col gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                    {!n.read && (
                      <button
                        onClick={() =>
                          update(items.map((i) => (i.id === n.id ? { ...i, read: true } : i)))
                        }
                        className="p-1 rounded hover:bg-accent"
                        title="تعليم كمقروء"
                      >
                        <Check className="h-3.5 w-3.5" />
                      </button>
                    )}
                    <button
                      onClick={() => update(items.filter((i) => i.id !== n.id))}
                      className="p-1 rounded hover:bg-destructive/20 text-destructive"
                      title="حذف"
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </button>
                  </div>
                </div>
              ))
            )}
          </div>

          {items.length > 0 && (
            <button
              onClick={() => update([])}
              className="px-4 py-2.5 text-xs font-semibold text-muted-foreground hover:text-destructive hover:bg-destructive/10 border-t border-border transition-colors"
            >
              مسح كل الإشعارات
            </button>
          )}
        </div>
      )}
    </div>
  );
}
