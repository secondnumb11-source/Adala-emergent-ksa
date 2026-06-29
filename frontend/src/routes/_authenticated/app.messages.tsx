import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useMemo, useRef, useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { MessageCircle, Send, Loader2, Users2, Search, Inbox, Check, CheckCheck } from "lucide-react";
import { PageHeader } from "@/components/section-shell";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

export const Route = createFileRoute("/_authenticated/app/messages")({
  component: MessagesPage,
});

type Msg = {
  id: string; owner_id: string; client_id: string; sender_role: string;
  sender_id: string | null; message: string; subject?: string | null;
  is_read: boolean; read_at?: string | null; created_at: string;
};

function MessagesPage() {
  const qc = useQueryClient();
  const [me, setMe] = useState<{ id: string } | null>(null);
  const [role, setRole] = useState<"client" | "lawyer" | null>(null);
  const [activeClientId, setActiveClientId] = useState<string | null>(null);
  const [draft, setDraft] = useState("");
  const [search, setSearch] = useState("");
  const [convSearch, setConvSearch] = useState("");
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let alive = true;
    (async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user || !alive) return;
      setMe({ id: user.id });

      // role detection: is this user a client (portal_user_id) or office owner?
      const { data: clientRow } = await supabase.from("clients")
        .select("id").eq("portal_user_id", user.id).maybeSingle();
      if (clientRow?.id) {
        setRole("client");
        setActiveClientId(clientRow.id);
      } else {
        setRole("lawyer");
      }
    })();
    return () => { alive = false; };
  }, []);

  // Lawyer: list of clients who have any messages (inbox)
  const clientsQ = useQuery({
    queryKey: ["msg_clients", me?.id],
    enabled: !!me && role === "lawyer",
    queryFn: async () => {
      const { data, error } = await supabase.from("clients")
        .select("id, full_name, phone, email").order("full_name");
      if (error) throw error;
      return data ?? [];
    },
  });

  // Unread counts per client for lawyer
  const unreadQ = useQuery({
    queryKey: ["msg_unread", me?.id],
    enabled: !!me && role === "lawyer",
    queryFn: async () => {
      const { data, error } = await supabase.from("portal_messages")
        .select("client_id, is_read, sender_role").eq("sender_role", "client").eq("is_read", false);
      if (error) throw error;
      const map: Record<string, number> = {};
      (data ?? []).forEach((r: any) => { map[r.client_id] = (map[r.client_id] || 0) + 1; });
      return map;
    },
  });

  // Thread query
  const threadQ = useQuery({
    queryKey: ["msg_thread", activeClientId],
    enabled: !!activeClientId,
    queryFn: async () => {
      const { data, error } = await supabase.from("portal_messages")
        .select("*").eq("client_id", activeClientId!)
        .order("created_at", { ascending: true }).limit(500);
      if (error) throw error;
      return (data ?? []) as Msg[];
    },
  });

  // Realtime
  useEffect(() => {
    if (!me) return;
    const ch = supabase.channel("rt:portal_messages")
      .on("postgres_changes", { event: "*", schema: "public", table: "portal_messages" }, () => {
        qc.invalidateQueries({ queryKey: ["msg_thread"] });
        qc.invalidateQueries({ queryKey: ["msg_unread"] });
      }).subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [me, qc]);

  // Mark incoming as read
  useEffect(() => {
    if (!me || !role || !threadQ.data) return;
    const myRole = role; // 'client' or 'lawyer'
    const peerRole = myRole === "client" ? "lawyer" : "client";
    const unread = threadQ.data.filter((m) => m.sender_role === peerRole && !m.is_read);
    if (!unread.length) return;
    (supabase as any).from("portal_messages")
      .update({ is_read: true, read_at: new Date().toISOString() })
      .in("id", unread.map((m) => m.id)).then();
  }, [threadQ.data, me, role]);

  useEffect(() => {
    if (scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
  }, [threadQ.data]);

  const sendMut = useMutation({
    mutationFn: async () => {
      if (!me || !activeClientId) throw new Error("اختر محادثة");
      const body = draft.trim();
      if (!body) throw new Error("اكتب رسالة");
      // Find owner_id: for lawyer = me; for client = read clients.owner_id
      let owner_id = me.id;
      if (role === "client") {
        const { data: c } = await supabase.from("clients").select("owner_id").eq("id", activeClientId).maybeSingle();
        owner_id = (c as any)?.owner_id ?? me.id;
      }
      const { error } = await supabase.from("portal_messages").insert({
        owner_id, client_id: activeClientId, sender_id: me.id,
        sender_role: role!, message: body,
      } as never);
      if (error) throw error;
    },
    onSuccess: () => { setDraft(""); qc.invalidateQueries({ queryKey: ["msg_thread"] }); },
    onError: (e: any) => toast.error(e.message),
  });

  const filteredClients = useMemo(() => {
    const list = clientsQ.data ?? [];
    if (!search) return list;
    return list.filter((c: any) => c.full_name.toLowerCase().includes(search.toLowerCase()));
  }, [clientsQ.data, search]);

  return (
    <>
      <PageHeader
        icon={MessageCircle}
        title={role === "client" ? "مراسلة المكتب" : "صندوق وارد العملاء"}
        subtitle={role === "client" ? "أرسل استفساراتك للمكتب وتابع الردود فوراً" : "كل استفسارات ومراسلات العملاء في مكان واحد"}
      />

      <div className="grid gap-4 lg:grid-cols-[320px_1fr]">
        {role === "lawyer" && (
          <Card className="p-3 h-[70vh] flex flex-col">
            <div className="flex items-center gap-2 mb-3">
              <Inbox className="h-4 w-4 text-gold" />
              <h3 className="font-bold text-sm">العملاء</h3>
              <Badge variant="outline" className="mr-auto text-[10px]">{filteredClients.length}</Badge>
            </div>
            <div className="relative mb-2">
              <Search className="h-3.5 w-3.5 absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground" />
              <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="ابحث..." className="pr-7 text-xs" />
            </div>
            <div className="flex-1 overflow-y-auto space-y-1">
              {filteredClients.map((c: any) => {
                const unread = unreadQ.data?.[c.id] ?? 0;
                return (
                  <button key={c.id} onClick={() => setActiveClientId(c.id)}
                    className={`w-full text-right rounded-lg border p-2.5 hover:bg-muted/40 transition-colors ${
                      activeClientId === c.id ? "border-gold bg-gold/10" : ""
                    }`}>
                    <div className="flex items-center justify-between">
                      <div className="font-bold text-xs">{c.full_name}</div>
                      {unread > 0 && (
                        <Badge className="bg-destructive text-destructive-foreground text-[9px]">{unread}</Badge>
                      )}
                    </div>
                    <div className="text-[10px] text-muted-foreground mt-0.5">{c.phone || c.email || "—"}</div>
                  </button>
                );
              })}
            </div>
          </Card>
        )}

        <Card className={`p-0 h-[70vh] flex flex-col overflow-hidden ${role === "client" ? "lg:col-span-2" : ""}`}>
          <div className="px-4 py-3 border-b flex items-center gap-2">
            <Users2 className="h-4 w-4 text-gold" />
            <div className="font-bold text-sm">
              {role === "client" ? "محادثتك مع المكتب" :
                (clientsQ.data?.find((c: any) => c.id === activeClientId)?.full_name || "اختر عميلاً")}
            </div>
            {activeClientId && (
              <div className="relative mr-auto w-48">
                <Search className="h-3.5 w-3.5 absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground" />
                <Input value={convSearch} onChange={(e) => setConvSearch(e.target.value)}
                  placeholder="ابحث في المحادثة..." className="pr-7 text-xs h-8" />
              </div>
            )}
          </div>

          <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 space-y-2 bg-gradient-to-bl from-muted/20 to-transparent">
            {!activeClientId ? (
              <div className="text-center text-sm text-muted-foreground py-10">اختر محادثة من اليمين.</div>
            ) : threadQ.isLoading ? (
              <div className="text-center text-sm text-muted-foreground py-10"><Loader2 className="inline h-4 w-4 animate-spin" /> تحميل...</div>
            ) : (threadQ.data?.length ?? 0) === 0 ? (
              <div className="text-center text-sm text-muted-foreground py-10">لا توجد رسائل بعد.</div>
            ) : (
              (threadQ.data ?? []).map((m) => {
                const mine = m.sender_role === role;
                const matched = convSearch.trim() && m.message?.toLowerCase().includes(convSearch.toLowerCase());
                const dimmed = convSearch.trim() && !matched;
                return (
                  <div key={m.id} className={`flex ${mine ? "justify-start" : "justify-end"}`}>
                    <div className={`max-w-[75%] rounded-2xl px-3 py-2 text-sm leading-relaxed shadow-sm transition-opacity ${
                      mine ? "bg-primary text-primary-foreground" : "bg-card border"
                    } ${matched ? "ring-2 ring-amber-400" : ""} ${dimmed ? "opacity-30" : ""}`}>
                      <div className="whitespace-pre-wrap break-words">{m.message}</div>
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

          <div className="p-3 border-t bg-background flex gap-2 items-end">
            <Textarea value={draft} onChange={(e) => setDraft(e.target.value)} rows={1}
              placeholder="اكتب رسالة... (Enter للإرسال)"
              onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); sendMut.mutate(); } }}
              className="resize-none min-h-[42px]" disabled={!activeClientId} />
            <Button onClick={() => sendMut.mutate()} disabled={!activeClientId || !draft.trim() || sendMut.isPending}
              className="btn-gold">
              {sendMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
            </Button>
          </div>
        </Card>
      </div>
    </>
  );
}
