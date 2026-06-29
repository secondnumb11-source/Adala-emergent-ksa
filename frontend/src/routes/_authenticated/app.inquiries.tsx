import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useMemo, useState } from "react";
import { MessageCircle, Send, Loader2, Inbox } from "lucide-react";
import { PageHeader } from "@/components/section-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
import { supabase } from "@/integrations/supabase/client";
import { postClientInquiry, markInquiriesRead } from "@/lib/client-inquiries.functions";
import { toast } from "sonner";

export const Route = createFileRoute("/_authenticated/app/inquiries")({
  component: InquiriesPage,
});

type Inquiry = {
  id: string; owner_id: string; client_id: string; case_id: string | null;
  parent_id: string | null; author_id: string; author_role: string;
  subject: string | null; body: string; read_at: string | null; created_at: string;
};

function fmt(iso: string) {
  return new Date(iso).toLocaleString("ar-SA-u-ca-gregory", { dateStyle: "medium", timeStyle: "short" });
}

function InquiriesPage() {
  const [loading, setLoading] = useState(true);
  const [inquiries, setInquiries] = useState<Inquiry[]>([]);
  const [clients, setClients] = useState<Array<{ id: string; full_name: string }>>([]);
  const [activeClient, setActiveClient] = useState<string | null>(null);
  const [reply, setReply] = useState("");
  const [sending, setSending] = useState(false);

  const load = async () => {
    setLoading(true);
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) { setLoading(false); return; }
    const [{ data: inq }, { data: cs }] = await Promise.all([
      (supabase as any).from("client_inquiries").select("*").eq("owner_id", user.id).order("created_at", { ascending: true }),
      supabase.from("clients").select("id, full_name").eq("owner_id", user.id),
    ]);
    setInquiries((inq as Inquiry[]) ?? []);
    setClients((cs as any) ?? []);
    setLoading(false);
  };

  useEffect(() => { void load(); }, []);

  useEffect(() => {
    const ch = (supabase as any)
      .channel("rt:inquiries:owner")
      .on("postgres_changes", { event: "*", schema: "public", table: "client_inquiries" }, () => load())
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, []);

  const byClient = useMemo(() => {
    const map = new Map<string, Inquiry[]>();
    for (const i of inquiries) {
      if (!map.has(i.client_id)) map.set(i.client_id, []);
      map.get(i.client_id)!.push(i);
    }
    return map;
  }, [inquiries]);

  const activeThreads = useMemo(() => {
    if (!activeClient) return [];
    const list = byClient.get(activeClient) ?? [];
    const groups = new Map<string, Inquiry[]>();
    for (const i of list) {
      const k = i.parent_id ?? i.id;
      if (!groups.has(k)) groups.set(k, []);
      groups.get(k)!.push(i);
    }
    return Array.from(groups.values()).sort(
      (a, b) => new Date(b[b.length - 1].created_at).getTime() - new Date(a[a.length - 1].created_at).getTime(),
    );
  }, [byClient, activeClient]);

  // Mark client-authored msgs as read when opened
  useEffect(() => {
    if (!activeClient) return;
    const ids = (byClient.get(activeClient) ?? [])
      .filter((i) => i.author_role === "client" && !i.read_at)
      .map((i) => i.id);
    if (ids.length) void markInquiriesRead({ data: { ids } }).catch(() => {});
  }, [activeClient, byClient]);

  const send = async (parentId: string) => {
    if (!activeClient || !reply.trim()) return;
    setSending(true);
    try {
      await postClientInquiry({ data: { client_id: activeClient, parent_id: parentId, body: reply.trim() } });
      setReply("");
      toast.success("تم إرسال الرد للعميل");
    } catch (e: any) {
      toast.error(e.message || "فشل الإرسال");
    } finally { setSending(false); }
  };

  return (
    <>
      <PageHeader icon={Inbox} title="استفسارات العملاء" subtitle="استقبل وأجب عن استفسارات عملائك من بوابة العميل" />
      {loading ? (
        <div className="grid place-items-center py-20"><Loader2 className="h-7 w-7 animate-spin text-gold" /></div>
      ) : (
        <div className="grid lg:grid-cols-3 gap-6" dir="rtl">
          <Card className="card-3d border-none p-4 lg:col-span-1 max-h-[75vh] overflow-y-auto">
            <h3 className="font-bold mb-3 text-sm">العملاء ({byClient.size})</h3>
            {byClient.size === 0 ? (
              <p className="text-xs text-muted-foreground text-center py-8">لا توجد استفسارات</p>
            ) : (
              <div className="space-y-1">
                {Array.from(byClient.entries()).map(([cid, list]) => {
                  const name = clients.find((c) => c.id === cid)?.full_name || "عميل";
                  const unread = list.filter((i) => i.author_role === "client" && !i.read_at).length;
                  return (
                    <button
                      key={cid}
                      onClick={() => setActiveClient(cid)}
                      className={`w-full text-right p-3 rounded-lg border transition-colors ${activeClient === cid ? "border-gold bg-gold/10" : "hover:bg-muted/40"}`}
                    >
                      <div className="flex items-center justify-between">
                        <span className="font-semibold text-sm">{name}</span>
                        {unread > 0 && <Badge className="text-[10px]">{unread}</Badge>}
                      </div>
                      <div className="text-[10px] text-muted-foreground mt-1">{list.length} رسالة</div>
                    </button>
                  );
                })}
              </div>
            )}
          </Card>

          <Card className="card-3d border-none p-6 lg:col-span-2 min-h-[60vh]">
            {!activeClient ? (
              <div className="grid place-items-center h-full text-center text-muted-foreground text-sm py-20">
                <div>
                  <MessageCircle className="h-10 w-10 mx-auto mb-3 opacity-50" />
                  اختر عميلاً لعرض المحادثات
                </div>
              </div>
            ) : activeThreads.length === 0 ? (
              <p className="text-sm text-center text-muted-foreground py-10">لا توجد استفسارات لهذا العميل</p>
            ) : (
              <div className="space-y-5">
                {activeThreads.map((thread) => {
                  const head = thread[0];
                  return (
                    <div key={head.id} className="rounded-xl border p-4">
                      <div className="flex items-center justify-between mb-2">
                        <Badge variant="outline" className="text-[10px]">{head.subject || "استفسار"}</Badge>
                        <span className="text-[10px] text-muted-foreground">{fmt(head.created_at)}</span>
                      </div>
                      <div className="space-y-2">
                        {thread.map((m) => (
                          <div key={m.id} className={`rounded-lg p-3 text-sm ${m.author_role === "client" ? "bg-muted/40 ml-8" : "bg-gold/10 mr-8 border border-gold/30"}`}>
                            <div className="text-[10px] font-bold mb-1 opacity-70">
                              {m.author_role === "client" ? "العميل" : "أنت"} • {fmt(m.created_at)}
                            </div>
                            <div className="whitespace-pre-wrap leading-relaxed">{m.body}</div>
                          </div>
                        ))}
                      </div>
                      <div className="mt-3 flex items-end gap-2">
                        <Textarea placeholder="اكتب رداً للعميل..." value={reply} onChange={(e) => setReply(e.target.value)} rows={2} className="flex-1" />
                        <Button size="sm" disabled={!reply.trim() || sending} onClick={() => send(head.id)} className="btn-gold gap-1">
                          {sending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Send className="h-3.5 w-3.5" />}
                          رد
                        </Button>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </Card>
        </div>
      )}
    </>
  );
}
