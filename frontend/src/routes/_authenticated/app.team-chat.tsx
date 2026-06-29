import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useMemo, useRef, useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { MessageSquare, Send, Loader2, Users2, Shield, Eye, Search, Check, CheckCheck, Paperclip, FileText, X } from "lucide-react";
import { PageHeader } from "@/components/section-shell";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
import { supabase as supabaseTyped } from "@/integrations/supabase/client";
// employee_messages is created via db/phase6_employee_messages.sql; types regenerate after apply.
const supabase = supabaseTyped as any;
import { toast } from "sonner";

export const Route = createFileRoute("/_authenticated/app/team-chat")({
  validateSearch: (search: Record<string, unknown>) => ({
    peer: typeof search.peer === "string" ? search.peer : undefined,
  }),
  component: TeamChatPage,
});

type Peer = { id: string; user_id: string | null; full_name: string; job_title: string | null; is_owner?: boolean; unlinked?: boolean };
type Msg = {
  id: string; owner_id: string; sender_id: string; recipient_id: string;
  body: string; is_read: boolean; created_at: string; read_at?: string | null; attachment_url?: string | null;
};

function TeamChatPage() {
  const qc = useQueryClient();
  const { peer: peerFromUrl } = Route.useSearch();
  const [me, setMe] = useState<{ id: string; email?: string | null } | null>(null);
  const [tenantOwnerId, setTenantOwnerId] = useState<string | null>(null);
  const [isManager, setIsManager] = useState(false);
  const [peers, setPeers] = useState<Peer[]>([]);
  const [activePeerUid, setActivePeerUid] = useState<string | null>(peerFromUrl ?? null);
  const [draft, setDraft] = useState("");
  const [pendingFile, setPendingFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const [search, setSearch] = useState("");
  const [convSearch, setConvSearch] = useState("");
  const [monitorMode, setMonitorMode] = useState(false);
  const [monitorPair, setMonitorPair] = useState<{ a: string; b: string } | null>(null);
  const [peerTyping, setPeerTyping] = useState(false);
  const typingChRef = useRef<any>(null);
  const typingTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lastTypingSentRef = useRef<number>(0);
  const markedReadRef = useRef<Set<string>>(new Set());
  const scrollRef = useRef<HTMLDivElement>(null);

  // React to URL peer changes (links from other pages)
  useEffect(() => {
    if (peerFromUrl) setActivePeerUid(peerFromUrl);
  }, [peerFromUrl]);

  // Resolve identity + tenant
  useEffect(() => {
    let alive = true;
    (async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user || !alive) return;
      setMe({ id: user.id, email: user.email });

      // Manager = office owner who has employees rows where owner_id = user.id
      const { data: ownedEmps } = await supabase.from("employees")
        .select("id, user_id, full_name, job_title, owner_id").eq("owner_id", user.id);

      // Employee = appears as an employees.user_id
      const { data: empRow } = await supabase.from("employees")
        .select("owner_id, full_name").eq("user_id", user.id).maybeSingle();

      const tenant = (empRow?.owner_id as string | undefined) ?? user.id;
      if (!alive) return;
      setTenantOwnerId(tenant);
      setIsManager(tenant === user.id);

      // Pull every employee in tenant via safe directory RPC (sensitive columns excluded).
      const { data: rosterRaw } = await supabase.rpc("get_employees_directory");
      const roster = (rosterRaw ?? []).filter((e: any) => e.owner_id === tenant);


      const list: Peer[] = (roster ?? [])
        .filter((e: any) => e.user_id !== user.id) // exclude self only
        .map((e: any) => ({
          id: e.id,
          user_id: e.user_id ?? null,
          full_name: e.full_name,
          job_title: e.job_title,
          unlinked: !e.user_id, // employee row not linked to an auth account yet
        }));

      // Add manager as a peer when current user is an employee
      if (tenant !== user.id) {
        list.unshift({ id: "owner", user_id: tenant, full_name: "إدارة المكتب", job_title: "المدير", is_owner: true });
      }
      setPeers(list);
      const firstChatable = list.find((p) => p.user_id);
      if (firstChatable && !activePeerUid) setActivePeerUid(firstChatable.user_id);
    })();
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Conversation query (1-on-1 thread between me and active peer)
  const threadQ = useQuery({
    queryKey: ["emp_msg_thread", me?.id, activePeerUid],
    enabled: !!me && !!activePeerUid && !monitorMode,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("employee_messages")
        .select("*")
        .or(`and(sender_id.eq.${me!.id},recipient_id.eq.${activePeerUid}),and(sender_id.eq.${activePeerUid},recipient_id.eq.${me!.id})`)
        .order("created_at", { ascending: true })
        .limit(500);
      if (error) throw error;
      return (data ?? []) as Msg[];
    },
  });

  // Manager monitor: read every conversation within tenant
  const monitorQ = useQuery({
    queryKey: ["emp_msg_monitor", tenantOwnerId, monitorPair?.a, monitorPair?.b],
    enabled: isManager && monitorMode,
    queryFn: async () => {
      let q = supabase.from("employee_messages").select("*").eq("owner_id", tenantOwnerId!);
      if (monitorPair) {
        q = q.or(`and(sender_id.eq.${monitorPair.a},recipient_id.eq.${monitorPair.b}),and(sender_id.eq.${monitorPair.b},recipient_id.eq.${monitorPair.a})`);
      }
      const { data, error } = await q.order("created_at", { ascending: true }).limit(1000);
      if (error) throw error;
      return (data ?? []) as Msg[];
    },
  });

  // Realtime subscribe
  useEffect(() => {
    if (!me) return;
    const ch = supabase
      .channel("rt:employee_messages")
      .on("postgres_changes", { event: "*", schema: "public", table: "employee_messages" }, () => {
        qc.invalidateQueries({ queryKey: ["emp_msg_thread"] });
        qc.invalidateQueries({ queryKey: ["emp_msg_monitor"] });
        qc.invalidateQueries({ queryKey: ["emp_msg_unread_by_peer"] });
      })
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [me, qc]);

  // Per-peer unread counts (incoming to me, !is_read)
  const unreadByPeerQ = useQuery({
    queryKey: ["emp_msg_unread_by_peer", me?.id],
    enabled: !!me && !monitorMode,
    queryFn: async () => {
      const { data, error } = await supabase.from("employee_messages")
        .select("sender_id, is_read").eq("recipient_id", me!.id).eq("is_read", false);
      if (error) throw error;
      const map: Record<string, number> = {};
      (data ?? []).forEach((r: any) => { map[r.sender_id] = (map[r.sender_id] || 0) + 1; });
      return map;
    },
  });
  useEffect(() => {
    qc.invalidateQueries({ queryKey: ["emp_msg_unread_by_peer"] });
  }, [threadQ.data, qc]);

  // Auto-mark incoming messages as read — only stamp once; dedupe via ref
  // and via server-side trigger (preserve_read_at) so re-opening the chat
  // does not overwrite the original timestamp.
  useEffect(() => {
    if (!me || monitorMode) return;
    const fresh = (threadQ.data ?? []).filter(
      (m) => m.recipient_id === me.id && !m.is_read && !markedReadRef.current.has(m.id),
    );
    if (!fresh.length) return;
    const ids = fresh.map((m) => m.id);
    ids.forEach((id) => markedReadRef.current.add(id));
    supabase
      .from("employee_messages")
      .update({ is_read: true, read_at: new Date().toISOString() })
      .in("id", ids)
      .is("read_at", null)
      .then();
  }, [threadQ.data, me, monitorMode]);

  // Reset dedupe set when switching peers (cheap; trigger still protects DB)
  useEffect(() => {
    markedReadRef.current = new Set();
  }, [activePeerUid, monitorMode]);

  // Typing indicator via Realtime broadcast (per 1-on-1 pair)
  useEffect(() => {
    if (!me || !activePeerUid || monitorMode) { setPeerTyping(false); return; }
    const key = [me.id, activePeerUid].sort().join("|");
    const ch = supabase
      .channel(`typing:${key}`, {
        config: { broadcast: { self: false }, presence: { key: me.id } },
      })
      .on("broadcast", { event: "typing" }, (payload: any) => {
        if (payload?.payload?.from === activePeerUid) {
          setPeerTyping(true);
          if (typingTimeoutRef.current) clearTimeout(typingTimeoutRef.current);
          typingTimeoutRef.current = setTimeout(() => setPeerTyping(false), 3000);
        }
      })
      .on("broadcast", { event: "stop_typing" }, (payload: any) => {
        if (payload?.payload?.from === activePeerUid) {
          if (typingTimeoutRef.current) clearTimeout(typingTimeoutRef.current);
          setPeerTyping(false);
        }
      })
      .on("presence", { event: "leave" }, () => {
        // peer disconnected: stop showing typing immediately
        if (typingTimeoutRef.current) clearTimeout(typingTimeoutRef.current);
        setPeerTyping(false);
      })
      .subscribe(async (status: string) => {
        if (status === "SUBSCRIBED") {
          try { await ch.track({ online_at: Date.now() }); } catch { /* noop */ }
        }
      });
    typingChRef.current = ch;

    const clearOnHide = () => {
      if (document.visibilityState === "hidden") {
        try { ch.send({ type: "broadcast", event: "stop_typing", payload: { from: me.id } }); } catch { /* noop */ }
        if (typingTimeoutRef.current) clearTimeout(typingTimeoutRef.current);
        setPeerTyping(false);
      }
    };
    document.addEventListener("visibilitychange", clearOnHide);
    window.addEventListener("beforeunload", clearOnHide);

    return () => {
      if (typingTimeoutRef.current) clearTimeout(typingTimeoutRef.current);
      document.removeEventListener("visibilitychange", clearOnHide);
      window.removeEventListener("beforeunload", clearOnHide);
      try { ch.send({ type: "broadcast", event: "stop_typing", payload: { from: me.id } }); } catch { /* noop */ }
      supabase.removeChannel(ch);
      typingChRef.current = null;
      setPeerTyping(false);
    };
  }, [me, activePeerUid, monitorMode]);

  const broadcastTyping = () => {
    if (!typingChRef.current || !me) return;
    const now = Date.now();
    if (now - lastTypingSentRef.current < 1500) return; // throttle
    lastTypingSentRef.current = now;
    typingChRef.current.send({ type: "broadcast", event: "typing", payload: { from: me.id } });
  };
  const broadcastStopTyping = () => {
    if (!typingChRef.current || !me) return;
    lastTypingSentRef.current = 0;
    try {
      typingChRef.current.send({ type: "broadcast", event: "stop_typing", payload: { from: me.id } });
    } catch { /* noop */ }
  };

  // Scroll to bottom on new messages
  useEffect(() => {
    if (scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
  }, [threadQ.data, monitorQ.data]);

  const sendMut = useMutation({
    mutationFn: async () => {
      if (!me || !tenantOwnerId || !activePeerUid) throw new Error("لا يوجد مستلم");
      const body = draft.trim();
      if (!body && !pendingFile) throw new Error("اكتب رسالة أو أرفق ملفاً");
      let attachment_url: string | null = null;
      if (pendingFile) {
        setUploading(true);
        const path = `${tenantOwnerId}/chat/${me.id}/${Date.now()}-${pendingFile.name}`;
        const up = await supabase.storage.from("case-documents").upload(path, pendingFile, { upsert: false, contentType: pendingFile.type });
        setUploading(false);
        if (up.error) throw new Error("فشل رفع المرفق");
        attachment_url = path;
      }
      const { error } = await supabase.from("employee_messages").insert({
        owner_id: tenantOwnerId, sender_id: me.id, recipient_id: activePeerUid,
        body: body || (pendingFile ? `📎 ${pendingFile.name}` : ""),
        attachment_url,
      } as never);
      if (error) throw error;
    },
    onSuccess: () => {
      setDraft("");
      setPendingFile(null);
      broadcastStopTyping();
      qc.invalidateQueries({ queryKey: ["emp_msg_thread"] });
      qc.invalidateQueries({ queryKey: ["emp_msg_unread_by_peer"] });
    },
    onError: (e: any) => toast.error(e.message),
  });

  const openAttachment = async (path: string) => {
    const { data, error } = await supabase.storage.from("case-documents").createSignedUrl(path, 600);
    if (error || !data) { toast.error("تعذّر فتح المرفق"); return; }
    window.open(data.signedUrl, "_blank", "noopener,noreferrer");
  };

  const filteredPeers = useMemo(
    () => peers.filter((p) => p.full_name.toLowerCase().includes(search.toLowerCase())),
    [peers, search],
  );

  // Build pair list for manager monitor (sender ↔ recipient unique combos)
  const monitorPairs = useMemo(() => {
    if (!isManager || !monitorMode || monitorPair) return [];
    const seen = new Map<string, { a: string; b: string; last: string; preview: string }>();
    for (const m of monitorQ.data ?? []) {
      const [a, b] = [m.sender_id, m.recipient_id].sort();
      const key = `${a}|${b}`;
      if (!seen.has(key) || seen.get(key)!.last < m.created_at) {
        seen.set(key, { a, b, last: m.created_at, preview: m.body });
      }
    }
    const nameMap = new Map<string, string>();
    nameMap.set(tenantOwnerId!, "المدير");
    peers.forEach((p) => p.user_id && nameMap.set(p.user_id, p.full_name));
    return Array.from(seen.values())
      .sort((x, y) => y.last.localeCompare(x.last))
      .map((p) => ({ ...p, label: `${nameMap.get(p.a) || "؟"} ↔ ${nameMap.get(p.b) || "؟"}` }));
  }, [isManager, monitorMode, monitorQ.data, peers, tenantOwnerId, monitorPair]);

  const visible = monitorMode ? (monitorQ.data ?? []) : (threadQ.data ?? []);

  return (
    <>
      <PageHeader
        icon={MessageSquare}
        title="دردشة فريق العمل"
        subtitle={isManager ? "تواصل مع موظفيك، أو فعّل وضع المراقبة لمتابعة كافة المحادثات" : "تواصل مع زملائك وإدارة المكتب"}
        action={isManager ? (
          <Button variant={monitorMode ? "default" : "outline"} className={monitorMode ? "btn-gold" : ""}
            onClick={() => { setMonitorMode((v) => !v); setMonitorPair(null); }}>
            <Eye className="h-4 w-4 ml-2" />
            {monitorMode ? "إنهاء وضع المراقبة" : "وضع المراقبة (مدير)"}
          </Button>
        ) : null}
      />

      <div className="grid gap-4 lg:grid-cols-[300px_1fr]">
        {/* Sidebar */}
        <Card className="p-3 h-[70vh] flex flex-col">
          <div className="flex items-center gap-2 mb-3">
            {monitorMode ? <Shield className="h-4 w-4 text-amber-500" /> : <Users2 className="h-4 w-4 text-gold" />}
            <h3 className="font-bold text-sm">{monitorMode ? "كل المحادثات" : "المحادثات"}</h3>
            <Badge variant="outline" className="mr-auto text-[10px]">
              {monitorMode ? monitorPairs.length : peers.length}
            </Badge>
          </div>

          {!monitorMode && (
            <div className="relative mb-2">
              <Search className="h-3.5 w-3.5 absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground" />
              <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="ابحث عن زميل..." className="pr-7 text-xs" />
            </div>
          )}

          <div className="flex-1 overflow-y-auto space-y-1">
            {monitorMode ? (
              monitorPairs.length === 0 ? (
                <p className="text-xs text-muted-foreground text-center py-6">لا توجد محادثات بعد.</p>
              ) : (
                monitorPairs.map((p) => (
                  <button key={`${p.a}|${p.b}`} onClick={() => setMonitorPair({ a: p.a, b: p.b })}
                    className={`w-full text-right rounded-lg border p-2.5 text-xs hover:bg-muted/40 transition-colors ${
                      monitorPair?.a === p.a && monitorPair?.b === p.b ? "border-gold bg-gold/10" : ""
                    }`}>
                    <div className="font-bold">{p.label}</div>
                    <div className="text-muted-foreground line-clamp-1 mt-0.5">{p.preview}</div>
                  </button>
                ))
              )
            ) : (
              filteredPeers.map((p) => (
                <button key={p.user_id || p.id} onClick={() => p.user_id && setActivePeerUid(p.user_id)}
                  disabled={!p.user_id}
                  title={p.unlinked ? "هذا الموظف لم يقم بإنشاء حساب دخول بعد — لا يمكن مراسلته" : ""}
                  className={`w-full text-right rounded-lg border p-2.5 transition-colors ${
                    !p.user_id ? "opacity-60 cursor-not-allowed" : "hover:bg-muted/40"
                  } ${activePeerUid === p.user_id ? "border-gold bg-gold/10" : ""}`}>
                  <div className="flex items-center justify-between">
                    <div className="font-bold text-xs">{p.full_name}</div>
                    <div className="flex items-center gap-1">
                      {p.user_id && (unreadByPeerQ.data?.[p.user_id] ?? 0) > 0 && (
                        <Badge className="bg-destructive text-destructive-foreground text-[9px] h-4 min-w-4 px-1">
                          {unreadByPeerQ.data?.[p.user_id]}
                        </Badge>
                      )}
                      {p.is_owner && <Badge className="bg-amber-500/15 text-amber-600 border-amber-500/30 text-[9px]">مدير</Badge>}
                      {p.unlinked && <Badge className="bg-muted text-muted-foreground border text-[9px]">لم يفعّل حسابه</Badge>}
                    </div>
                  </div>
                  <div className="text-[10px] text-muted-foreground mt-0.5">{p.job_title || "موظف"}</div>
                </button>
              ))
            )}
          </div>
        </Card>

        {/* Conversation */}
        <Card className="p-0 h-[70vh] flex flex-col overflow-hidden">
          <div className="px-4 py-3 border-b flex items-center justify-between">
            <div className="font-bold text-sm">
              {monitorMode
                ? monitorPair ? "محادثة مُراقَبة" : "اختر محادثة لعرضها"
                : peers.find((p) => p.user_id === activePeerUid)?.full_name || "اختر مستلماً"}
              {!monitorMode && peerTyping && (
                <span className="mr-2 inline-flex items-center gap-1 text-[11px] font-normal text-gold animate-pulse">
                  <span className="inline-flex gap-0.5">
                    <span className="h-1 w-1 rounded-full bg-gold animate-bounce" style={{ animationDelay: "0ms" }} />
                    <span className="h-1 w-1 rounded-full bg-gold animate-bounce" style={{ animationDelay: "150ms" }} />
                    <span className="h-1 w-1 rounded-full bg-gold animate-bounce" style={{ animationDelay: "300ms" }} />
                  </span>
                  يكتب الآن...
                </span>
              )}
            </div>
            {monitorMode && monitorPair && (
              <Button size="sm" variant="ghost" onClick={() => setMonitorPair(null)}>كل المحادثات</Button>
            )}
            {!monitorMode && activePeerUid && (
              <div className="relative w-48">
                <Search className="h-3.5 w-3.5 absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground" />
                <Input value={convSearch} onChange={(e) => setConvSearch(e.target.value)}
                  placeholder="ابحث في المحادثة..." className="pr-7 text-xs h-8" />
              </div>
            )}
          </div>

          <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 space-y-2 bg-gradient-to-bl from-muted/20 to-transparent">
            {(monitorMode ? monitorQ.isLoading : threadQ.isLoading) ? (
              <div className="text-center text-sm text-muted-foreground py-10"><Loader2 className="inline h-4 w-4 animate-spin" /> تحميل...</div>
            ) : visible.length === 0 ? (
              <div className="text-center text-sm text-muted-foreground py-10">لا توجد رسائل بعد. ابدأ المحادثة أدناه.</div>
            ) : (
              visible.map((m) => {
                const mine = m.sender_id === me?.id && !monitorMode;
                const matched = convSearch.trim() && m.body?.toLowerCase().includes(convSearch.toLowerCase());
                const dimmed = convSearch.trim() && !matched && !monitorMode;
                return (
                  <div key={m.id} className={`flex ${mine ? "justify-start" : "justify-end"}`}>
                    <div className={`max-w-[75%] rounded-2xl px-3 py-2 text-sm leading-relaxed shadow-sm transition-opacity ${
                      mine ? "bg-primary text-primary-foreground" : "bg-card border"
                    } ${matched ? "ring-2 ring-amber-400" : ""} ${dimmed ? "opacity-30" : ""}`}>
                      {monitorMode && (
                        <div className="text-[10px] font-bold mb-1 opacity-70">
                          {m.sender_id === tenantOwnerId ? "المدير" : peers.find((p) => p.user_id === m.sender_id)?.full_name || "موظف"}
                        </div>
                      )}
                      <div className="whitespace-pre-wrap break-words">{m.body}</div>
                      {m.attachment_url && (() => {
                        const raw = m.attachment_url.split("/").pop() || "ملف مرفق";
                        const fname = raw.replace(/^\d+-/, "");
                        return (
                          <button
                            onClick={() => openAttachment(m.attachment_url!)}
                            title={fname}
                            className={`mt-2 inline-flex items-center gap-1.5 max-w-full text-[11px] font-bold rounded-lg border px-2 py-1 transition ${
                              mine ? "border-white/40 bg-white/10 hover:bg-white/20" : "border-gold/40 bg-gold/10 text-gold hover:bg-gold/20"
                            }`}
                          >
                            <FileText className="h-3.5 w-3.5 shrink-0" />
                            <span className="truncate max-w-[220px]">{fname}</span>
                          </button>
                        );
                      })()}
                      <div className="text-[10px] mt-1 opacity-60 flex items-center gap-1 justify-end">
                        {new Date(m.created_at).toLocaleString("ar-SA", { hour: "2-digit", minute: "2-digit" })}
                        {mine && (m.is_read
                          ? <span className="inline-flex items-center gap-0.5" title={m.read_at ? `تمت القراءة: ${new Date(m.read_at).toLocaleString("ar-SA")}` : "تمت القراءة"}>
                              <CheckCheck className="h-3 w-3" />
                              {m.read_at && <span className="text-[9px]">{new Date(m.read_at).toLocaleTimeString("ar-SA", { hour: "2-digit", minute: "2-digit" })}</span>}
                            </span>
                          : <Check className="h-3 w-3" />)}
                      </div>
                    </div>
                  </div>
                );
              })
            )}
          </div>

          {!monitorMode && (
            <div className="p-3 border-t bg-background space-y-2">
              {pendingFile && (
                <div className="flex items-center gap-2 rounded-lg border border-gold/40 bg-gold/10 px-2 py-1.5 text-[11px]">
                  <FileText className="h-3.5 w-3.5 text-gold" />
                  <span className="truncate flex-1">{pendingFile.name}</span>
                  <button onClick={() => setPendingFile(null)} className="p-0.5 rounded hover:bg-destructive/20 text-destructive">
                    <X className="h-3 w-3" />
                  </button>
                </div>
              )}
              <div className="flex gap-2 items-end">
                <label className={`grid h-[42px] w-[42px] place-items-center rounded-md border cursor-pointer transition ${activePeerUid ? "border-gold/40 bg-gold/10 hover:bg-gold/20 text-gold" : "border-border bg-muted text-muted-foreground cursor-not-allowed"}`}
                  title="إرفاق مستند">
                  <Paperclip className="h-4 w-4" />
                  <input type="file" className="hidden" disabled={!activePeerUid}
                    onChange={(e) => { const f = e.target.files?.[0]; if (f) setPendingFile(f); e.currentTarget.value = ""; }} />
                </label>
                <Textarea value={draft}
                  onChange={(e) => { setDraft(e.target.value); broadcastTyping(); }}
                  rows={1}
                  placeholder="اكتب رسالة... (Enter للإرسال، Shift+Enter لسطر جديد)"
                  onKeyDown={(e) => {
                    if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); sendMut.mutate(); }
                  }}
                  className="resize-none min-h-[42px]" disabled={!activePeerUid} />
                <Button onClick={() => sendMut.mutate()}
                  disabled={!activePeerUid || (!draft.trim() && !pendingFile) || sendMut.isPending || uploading}
                  className="btn-gold">
                  {sendMut.isPending || uploading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
                </Button>
              </div>
            </div>
          )}
        </Card>
      </div>
    </>
  );
}
