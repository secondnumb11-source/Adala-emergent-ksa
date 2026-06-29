import { useQuery } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { getClientTimeline } from "@/lib/client-portal-admin.functions";
import { Briefcase, CalendarDays, FileText, Bell, LogIn, Loader2 } from "lucide-react";
import type { ReactNode } from "react";

const ICONS: Record<string, ReactNode> = {
  case: <Briefcase className="h-4 w-4" />,
  session: <CalendarDays className="h-4 w-4" />,
  document: <FileText className="h-4 w-4" />,
  notification: <Bell className="h-4 w-4" />,
  login: <LogIn className="h-4 w-4" />,
};

export function ClientTimeline({ clientId }: { clientId: string }) {
  const fetchFn = useServerFn(getClientTimeline);
  const { data, isLoading, error } = useQuery({
    queryKey: ["client-timeline", clientId],
    queryFn: () => fetchFn({ data: { client_id: clientId } }),
    enabled: !!clientId,
  });

  if (isLoading) {
    return <div className="flex items-center gap-2 text-sm text-muted-foreground p-4"><Loader2 className="h-4 w-4 animate-spin" /> جاري التحميل…</div>;
  }
  if (error) return <div className="text-sm text-destructive p-4">تعذر تحميل الخط الزمني</div>;
  const items = data?.items ?? [];
  if (!items.length) return <div className="text-sm text-muted-foreground p-4">لا توجد أحداث بعد.</div>;

  return (
    <ol className="relative border-r border-border pr-4 space-y-3">
      {items.map((it) => (
        <li key={it.id} className="relative">
          <span className="absolute -right-[22px] top-1.5 flex h-7 w-7 items-center justify-center rounded-full bg-primary/10 text-primary border border-primary/20">
            {ICONS[it.kind] ?? <FileText className="h-4 w-4" />}
          </span>
          <div className="rounded-lg border bg-card/50 p-3">
            <div className="flex items-center justify-between gap-2">
              <p className="text-sm font-medium text-foreground line-clamp-1">{it.title}</p>
              <time className="text-xs text-muted-foreground shrink-0">{new Date(it.at).toLocaleString("ar-SA")}</time>
            </div>
            {it.subtitle && <p className="text-xs text-muted-foreground mt-1">{it.subtitle}</p>}
          </div>
        </li>
      ))}
    </ol>
  );
}
