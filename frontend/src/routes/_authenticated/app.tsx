import { createFileRoute, Outlet, Link, useRouterState, useNavigate } from "@tanstack/react-router";
import { useState, useRef, useCallback, useEffect } from "react";
import {
  LayoutDashboard, Briefcase, CalendarDays, Users2, Workflow, FileSignature,
  UserCog, ShieldCheck, ListChecks, Bell, FolderArchive, Sparkles, Library,
  Landmark, BadgeCheck, Network, Settings, LogOut, Scale, Menu, X, Search,
  PanelRightClose, PanelRightOpen, BarChart3, Calculator, Timer, Receipt,
  FileText, FileSpreadsheet, Brain, ChevronDown, LifeBuoy, Power,
} from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Input } from "@/components/ui/input";
import { toast } from "sonner";
import { useQueryClient } from "@tanstack/react-query";
import { FloatingNotes } from "@/components/floating-notes";
import { SidebarClock } from "@/components/sidebar-clock";
import { HijriConverter } from "@/components/hijri-converter";
import { loadSettings } from "@/lib/app-settings";
import { useUserPreferences } from "@/hooks/use-user-preferences";
import { parsePortalConfig } from "@/lib/client-portal-config";
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog";


// Map sidebar items to per-client section ids used in client-portal config.
const CLIENT_SECTION_TO_PATHS: Record<string, string[]> = {
  cases: ["/app", "/app/cases"],
  sessions: ["/app/sessions"],
  documents: ["/app/archive"],
  powers: ["/app/powers"],
  execution: ["/app/execution"],
  notifications: ["/app/notifications"],
  messages: ["/app/messages"],
};

export const Route = createFileRoute("/_authenticated/app")({
  component: AppLayout,
});

type NavItem = {
  to: string;
  label: string;
  icon: any;
  exact?: boolean;
  ai?: boolean;
  children?: { to: string; label: string; icon: any }[];
};

type NavGroup = { id: string; title: string; items: NavItem[] };

const NAV_GROUPS: NavGroup[] = [
  {
    id: "judicial",
    title: "المنظومة القضائية وإدارة العمل",
    items: [
      { to: "/app", label: "لوحة البيانات الرئيسية", icon: LayoutDashboard, exact: true },
      { to: "/app/cases", label: "إدارة القضايا", icon: Briefcase },
      { to: "/app/sessions", label: "مواعيد الجلسات", icon: CalendarDays },
      { to: "/app/archive", label: "أرشيف المستندات والأحكام", icon: FolderArchive },
      { to: "/app/execution", label: "طلبات التنفيذ", icon: Workflow },
    ],
  },
  {
    id: "clients",
    title: "إدارة شؤون العملاء",
    items: [
      { to: "/app/clients", label: "سجل بيانات العملاء", icon: Users2 },
      { to: "/app/client-portal", label: "بوابة العملاء", icon: ShieldCheck },
      { to: "/app/messages", label: "التواصل الفوري مع الإدارة وفريق العمل", icon: Bell },
      { to: "/app/inquiries", label: "استفسارات بوابة العميل", icon: Bell },
      { to: "/app/powers", label: "الوكالات القضائية", icon: FileSignature },
      { to: "/app/notifications", label: "إشعارات العملاء", icon: Bell },
    ],
  },
  {
    id: "team",
    title: "فريق العمل",
    items: [
      { to: "/app/employees", label: "بيانات الموظفين", icon: UserCog },
      { to: "/app/employee-portal", label: "بوابة الموظفين والصلاحيات", icon: ShieldCheck },
      { to: "/app/tasks", label: "المهام وتوزيع الأعمال", icon: ListChecks },
      { to: "/app/team-chat", label: "دردشة الفريق", icon: Users2 },
      { to: "/app/performance", label: "مؤشرات الأداء KPI's", icon: BarChart3 },
    ],
  },
  {
    id: "ai",
    title: "المساعد الذكي وأدوات الذكاء الاصطناعي",
    items: [
      {
        to: "/app/ai",
        label: "المساعد الذكي وأدوات AI",
        icon: Sparkles,
        ai: true,
        children: [
          { to: "/app/ai/consultant", label: "المستشار والمحلل الذكي", icon: Brain },
          { to: "/app/ai/memos", label: "صياغة اللوائح والمذكرات", icon: FileText },
          { to: "/app/ai/contracts", label: "صياغة العقود", icon: FileSignature },
          { to: "/app/ai/invoices", label: "إصدار الفواتير", icon: Receipt },
          { to: "/app/ai/calculator", label: "الحاسبة القضائية", icon: Calculator },
          { to: "/app/ai/deadlines", label: "حاسبة المدد النظامية", icon: Timer },
          { to: "/app/ai/zatca", label: "الفواتير المعتمدة ZATCA", icon: FileSpreadsheet },
        ],
      },
    ],
  },
  {
    id: "support",
    title: "خدمات المساندة والتحقق الذكي",
    items: [
      { to: "/app/library", label: "المكتبة القانونية", icon: Library },
      { to: "/app/gov", label: "بوابة الخدمات الحكومية", icon: Landmark },
      { to: "/app/verification", label: "خدمات المساندة", icon: BadgeCheck },
    ],
  },
  {
    id: "system",
    title: "النظام",
    items: [
      { to: "/app/najiz", label: "تكامل ناجز", icon: Network },
      { to: "/app/settings", label: "الإعدادات", icon: Settings },
    ],
  },
];

const MIN_WIDTH = 220;
const MAX_WIDTH = 440;
const COLLAPSED_WIDTH = 76;

function AppLayout() {
  const [open, setOpen] = useState(false);
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const { prefs, update, loaded } = useUserPreferences();

  const collapsed = prefs.sidebar_collapsed;
  const width = collapsed ? COLLAPSED_WIDTH : prefs.sidebar_width;

  // AI dropdown state — open by default if user is inside /app/ai
  const [aiOpen, setAiOpen] = useState(() => pathname.startsWith("/app/ai"));
  useEffect(() => { if (pathname.startsWith("/app/ai")) setAiOpen(true); }, [pathname]);

  // Detect client role
  const [clientCtx, setClientCtx] = useState<{
    isClient: boolean;
    isEmployee: boolean;
    allowed: Set<string> | null;
    name: string | null;
  }>({ isClient: false, isEmployee: false, allowed: null, name: null });
  useEffect(() => {
    let alive = true;
    (async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user || !alive) return;
      const { data: roles } = await supabase.from("user_roles").select("role").eq("user_id", user.id);
      const list = roles ?? [];
      const has = (r: string) => list.some((x) => x.role === r);
      const isLawyerOrAdmin = has("lawyer") || has("admin");
      // Strict portal separation: employee role wins over client when both exist,
      // so the employee never lands on the client portal UI by accident.
      const isEmployee = has("employee") && !isLawyerOrAdmin;
      const isClient = has("client") && !isLawyerOrAdmin && !isEmployee;
      if (!isClient && !isEmployee) {
        if (alive) setClientCtx({ isClient: false, isEmployee: false, allowed: null, name: null });
        return;
      }
      if (isEmployee) {
        const { data: emp } = await supabase.from("employees").select("full_name").eq("user_id", user.id).maybeSingle();
        if (alive) setClientCtx({ isClient: false, isEmployee: true, allowed: null, name: emp?.full_name || null });
        return;
      }
      const { data: client } = await supabase.from("clients").select("full_name, notes").eq("portal_user_id", user.id).maybeSingle();
      const cfg = parsePortalConfig((client as any)?.notes);
      const allowedPaths = new Set<string>(["/app"]);
      cfg.permissions.forEach((sec) => (CLIENT_SECTION_TO_PATHS[sec] || []).forEach((p) => allowedPaths.add(p)));
      if (alive) setClientCtx({
        isClient: true,
        isEmployee: false,
        allowed: cfg.permissions.length ? allowedPaths : null,
        name: cfg.username || client?.full_name || null,
      });
    })();
    return () => { alive = false; };
  }, []);

  // Sidebar unread badges for messages (client → lawyer) and team-chat (employee → employee)
  const [unreadCounts, setUnreadCounts] = useState<{ messages: number; teamChat: number }>({ messages: 0, teamChat: 0 });
  useEffect(() => {
    let alive = true;
    let ch1: ReturnType<typeof supabase.channel> | null = null;
    let ch2: ReturnType<typeof supabase.channel> | null = null;
    const refresh = async (user: { id: string }) => {
      const [msgRes, teamRes] = await Promise.all([
        supabase.from("portal_messages").select("id", { count: "exact", head: true })
          .eq("sender_role", "client").eq("is_read", false),
        (supabase as any).from("employee_messages").select("id", { count: "exact", head: true })
          .eq("recipient_id", user.id).eq("is_read", false),
      ]);
      if (!alive) return;
      setUnreadCounts({ messages: msgRes.count ?? 0, teamChat: teamRes.count ?? 0 });
    };
    (async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user || !alive) return;
      await refresh(user);
      ch1 = supabase.channel("sb-unread:portal_messages")
        .on("postgres_changes", { event: "INSERT", schema: "public", table: "portal_messages" }, (payload: any) => {
          const row = payload?.new || {};
          if (row.sender_role === "client") {
            toast.message("رسالة جديدة من عميل", { description: (row.message || "").slice(0, 80) });
          }
          refresh(user);
        })
        .on("postgres_changes", { event: "UPDATE", schema: "public", table: "portal_messages" }, () => refresh(user))
        .subscribe();
      ch2 = supabase.channel("sb-unread:employee_messages")
        .on("postgres_changes", { event: "INSERT", schema: "public", table: "employee_messages", filter: `recipient_id=eq.${user.id}` }, (payload: any) => {
          const row = payload?.new || {};
          toast.message("رسالة جديدة من فريق العمل", { description: (row.body || "").slice(0, 80) });
          refresh(user);
        })
        .on("postgres_changes", { event: "UPDATE", schema: "public", table: "employee_messages", filter: `recipient_id=eq.${user.id}` }, () => refresh(user))
        .subscribe();
    })();
    return () => { alive = false; if (ch1) supabase.removeChannel(ch1); if (ch2) supabase.removeChannel(ch2); };
  }, [pathname === "/app/messages" || pathname === "/app/team-chat"]);

  const badgeForPath = (to: string): number => {
    if (to === "/app/messages") return unreadCounts.messages;
    if (to === "/app/team-chat") return unreadCounts.teamChat;
    return 0;
  };

  const dragging = useRef(false);
  const [liveWidth, setLiveWidth] = useState<number | null>(null);

  const onMouseDown = useCallback((e: React.MouseEvent) => {
    if (collapsed) return;
    e.preventDefault();
    dragging.current = true;
    document.body.style.cursor = "ew-resize";
    document.body.style.userSelect = "none";
  }, [collapsed]);

  useEffect(() => {
    const onMove = (e: MouseEvent) => {
      if (!dragging.current) return;
      const w = Math.min(MAX_WIDTH, Math.max(MIN_WIDTH, window.innerWidth - e.clientX));
      setLiveWidth(w);
    };
    const onUp = () => {
      if (!dragging.current) return;
      dragging.current = false;
      document.body.style.cursor = "";
      document.body.style.userSelect = "";
      if (liveWidth != null) {
        update({ sidebar_width: liveWidth });
        setLiveWidth(null);
      }
    };
    window.addEventListener("mousemove", onMove);
    window.addEventListener("mouseup", onUp);
    return () => {
      window.removeEventListener("mousemove", onMove);
      window.removeEventListener("mouseup", onUp);
    };
  }, [liveWidth, update]);

  const effectiveWidth = liveWidth ?? width;

  const [confirmLogout, setConfirmLogout] = useState(false);
  const [officeLogo, setOfficeLogo] = useState<string>(() => {
    try { return loadSettings().office.logoDataUrl || ""; } catch { return ""; }
  });
  const [officeName, setOfficeName] = useState<string>(() => {
    try { const o = loadSettings().office; return o.arabicName || o.officeName || ""; } catch { return ""; }
  });
  useEffect(() => {
    const refresh = () => {
      try {
        const o = loadSettings().office;
        setOfficeLogo(o.logoDataUrl || "");
        setOfficeName(o.arabicName || o.officeName || "");
      } catch {}
    };
    window.addEventListener("lex:settings-changed", refresh);
    return () => window.removeEventListener("lex:settings-changed", refresh);
  }, []);
  const handleLogout = async () => {
    setConfirmLogout(false);
    await queryClient.cancelQueries();
    queryClient.clear();
    await supabase.auth.signOut();
    toast.success("تم تسجيل الخروج");
    navigate({ to: "/auth", replace: true });
  };


  const lawyerOnly = ["/app/clients", "/app/client-portal", "/app/employees", "/app/employee-portal", "/app/najiz", "/app/library", "/app/gov", "/app/verification", "/app/ai", "/app/tasks"];
  const employeeAllowed = new Set<string>([
    "/app", "/app/sessions", "/app/tasks", "/app/team-chat", "/app/notifications", "/app/cases", "/app/archive",
  ]);
  const isAllowed = (to: string) => {
    if (clientCtx.isEmployee) return employeeAllowed.has(to);
    if (!clientCtx.isClient) return true;
    if (to === "/app") return true;
    if (lawyerOnly.some((p) => to.startsWith(p))) return false;
    if (clientCtx.allowed && !clientCtx.allowed.has(to)) return false;
    return true;
  };

  // Per-portal label overrides so each portal speaks its own audience.
  const labelFor = (to: string, original: string): string => {
    if (clientCtx.isClient) {
      if (to === "/app/messages") return "التواصل الفوري مع الإدارة وفريق العمل";
    }
    if (clientCtx.isEmployee) {
      if (to === "/app/team-chat") return "التواصل الفوري مع الإدارة وفريق العمل";
    }
    return original;
  };

  return (
    <div className="min-h-screen flex w-full" dir="rtl">
      {/* Sidebar */}
      <aside
        style={{ width: effectiveWidth }}
        className={`fixed inset-y-0 right-0 z-40 transform transition-transform duration-300 lg:sticky lg:top-0 lg:h-screen lg:self-start lg:translate-x-0 ${
          open ? "translate-x-0" : "translate-x-full lg:translate-x-0"
        } ${liveWidth == null ? "transition-[width] duration-200 ease-out" : ""}`}
      >
        <div className="h-full bg-sidebar text-sidebar-foreground flex flex-col border-l border-sidebar-border relative sidebar-3d-bg">
          <div className="p-4 border-b border-sidebar-border flex items-center gap-3">
            <div className="grid h-12 w-12 shrink-0 place-items-center rounded-xl bg-gradient-to-br from-gold to-gold/70 text-primary shadow-lg brand-mark overflow-hidden">
              {officeLogo ? (
                <img src={officeLogo} alt="logo" className="h-full w-full object-contain" />
              ) : (
                <Scale className="h-6 w-6" />
              )}
            </div>
            {!collapsed && (
              <div className="flex-1 min-w-0 animate-fade-in flex flex-col items-start gap-1.5">
                <div className="font-extrabold text-xl whitespace-nowrap leading-tight">
                  {officeName ? (
                    <span className="brand-title-accent" data-text={officeName}>{officeName}</span>
                  ) : (
                    <>
                      <span className="brand-title-text">منصة</span>{" "}
                      <span className="brand-title-accent" data-text="العدالة">العدالة</span>
                    </>
                  )}
                </div>
                <div className="gold-divider w-12" />
                <div className="text-[11px] font-bold text-gold/90 tracking-wider whitespace-nowrap">
                  لإدارة مكاتب المحاماة
                </div>
              </div>
            )}
            <button
              onClick={() => update({ sidebar_collapsed: !collapsed })}
              className="hidden lg:grid place-items-center mr-auto h-8 w-8 rounded-lg hover:bg-sidebar-accent text-sidebar-foreground/70 hover:text-gold transition-colors"
              title={collapsed ? "توسيع الشريط" : "طي الشريط"}
            >
              {collapsed ? <PanelRightOpen className="h-4 w-4" /> : <PanelRightClose className="h-4 w-4" />}
            </button>
            <button onClick={() => setOpen(false)} className="lg:hidden mr-auto p-1.5 rounded hover:bg-sidebar-accent">
              <X className="h-4 w-4" />
            </button>
          </div>

          <SidebarClock collapsed={collapsed} />

          <nav className="flex-1 overflow-y-auto p-2 space-y-2 sidebar-nav-scroll">
            {!loaded ? (
              <div className="space-y-1">
                {Array.from({ length: 12 }).map((_, i) => (
                  <div key={i} className="h-10 rounded-xl bg-sidebar-accent/40 animate-pulse" />
                ))}
              </div>
            ) : (
              NAV_GROUPS.map((group) => {
                const items = group.items.filter((it) => isAllowed(it.to));
                if (items.length === 0) return null;
                return (
                  <div key={group.id} className="space-y-1">
                    {!collapsed && (
                      <div className="px-3 pt-2 pb-1 text-[10.5px] font-extrabold uppercase tracking-[0.15em] text-gold/70 flex items-center gap-2">
                        <span className="h-px flex-1 bg-gradient-to-l from-gold/40 to-transparent" />
                        <span>{group.title}</span>
                      </div>
                    )}
                    {items.map((item) => {
                      const active = item.exact ? pathname === item.to : pathname.startsWith(item.to);
                      const hasChildren = !!item.children?.length;
                      const expanded = hasChildren && aiOpen;
                      const itemLabel = labelFor(item.to, item.label);
                      return (
                        <div key={item.to + item.label}>
                          {hasChildren ? (
                            <button
                              type="button"
                              onClick={() => setAiOpen((o) => !o)}
                              title={collapsed ? itemLabel : undefined}
                              className={`nav-3d group flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-[13.5px] font-semibold transition-all duration-300 ${
                                active
                                  ? "nav-3d-active text-gold"
                                  : "text-sidebar-foreground/90 hover:text-gold"
                              } ${collapsed ? "justify-center px-2" : ""}`}
                            >
                              <item.icon className={`h-[19px] w-[19px] shrink-0 nav-icon-glow ${active ? "scale-110 text-gold" : ""}`} />
                              {!collapsed && (
                                <>
                                  <span className="flex-1 text-right truncate">{itemLabel}</span>
                                  {item.ai && (
                                    <span className="ai-badge text-[9px] font-black tracking-widest px-1.5 py-0.5 rounded">AI</span>
                                  )}
                                  <ChevronDown className={`h-4 w-4 text-gold transition-transform duration-300 ${expanded ? "rotate-180" : ""}`} />
                                </>
                              )}
                            </button>
                          ) : (
                            <Link
                              to={item.to}
                              onClick={() => setOpen(false)}
                              title={collapsed ? itemLabel : undefined}
                              className={`nav-3d group flex items-center gap-3 rounded-xl px-3 py-2.5 text-[13.5px] font-semibold transition-all duration-300 ${
                                active
                                  ? "nav-3d-active text-gold"
                                  : "text-sidebar-foreground/90 hover:text-gold"
                              } ${collapsed ? "justify-center px-2" : ""}`}
                            >
                              <span className="relative shrink-0">
                                <item.icon className={`h-[19px] w-[19px] nav-icon-glow ${active ? "scale-110 text-gold" : ""}`} />
                                {badgeForPath(item.to) > 0 && collapsed && (
                                  <span className="absolute -top-1 -left-1 min-w-[14px] h-[14px] rounded-full bg-red-600 text-white text-[9px] font-extrabold grid place-items-center shadow ring-2 ring-sidebar animate-pulse">
                                    {badgeForPath(item.to) > 9 ? "9+" : badgeForPath(item.to)}
                                  </span>
                                )}
                              </span>
                              {!collapsed && <span className="flex-1 text-right truncate">{itemLabel}</span>}
                              {!collapsed && badgeForPath(item.to) > 0 && (
                                <span className="inline-flex items-center gap-1 min-w-[20px] h-[20px] px-1.5 rounded-full bg-red-600 text-white text-[10px] font-extrabold shadow animate-pulse">
                                  {badgeForPath(item.to) > 9 ? "9+" : badgeForPath(item.to)}
                                </span>
                              )}
                            </Link>
                          )}

                          {hasChildren && !collapsed && expanded && (
                            <div className="mt-1 mr-3 pr-3 border-r-2 border-gold/30 space-y-1 animate-fade-in">
                              {item.children!.map((ch) => {
                                const chActive = pathname === ch.to || pathname.startsWith(ch.to + "/");
                                return (
                                  <Link
                                    key={ch.to}
                                    to={ch.to}
                                    onClick={() => setOpen(false)}
                                    className={`flex items-center gap-2 rounded-lg px-3 py-2 text-[12.5px] font-medium transition-all ${
                                      chActive
                                        ? "bg-gold/15 text-gold"
                                        : "text-sidebar-foreground/75 hover:bg-sidebar-accent/60 hover:text-gold hover:-translate-x-1"
                                    }`}
                                  >
                                    <ch.icon className="h-3.5 w-3.5 shrink-0" />
                                    <span className="flex-1 truncate text-right">{ch.label}</span>
                                  </Link>
                                );
                              })}
                            </div>
                          )}
                        </div>
                      );
                    })}
                  </div>
                );
              })
            )}
          </nav>

          <div className="p-2 border-t border-sidebar-border">
            <button
              onClick={() => setConfirmLogout(true)}

              title={collapsed ? "تسجيل الخروج" : undefined}
              className={`flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium text-sidebar-foreground/80 hover:bg-destructive/20 hover:text-destructive transition-colors ${collapsed ? "justify-center px-2" : ""}`}
            >
              <LogOut className="h-4 w-4 shrink-0" />
              {!collapsed && <span className="animate-fade-in">تسجيل الخروج</span>}
            </button>
          </div>

          {!collapsed && (
            <div
              onMouseDown={onMouseDown}
              onDoubleClick={() => update({ sidebar_width: 288 })}
              className="hidden lg:block absolute top-0 left-0 h-full w-1.5 -translate-x-1/2 cursor-ew-resize group z-50"
              title="اسحب لتغيير العرض"
            >
              <div className="h-full w-full bg-transparent group-hover:bg-gold/50 transition-colors duration-200" />
            </div>
          )}
        </div>
      </aside>

      {open && <div className="fixed inset-0 z-30 bg-black/40 lg:hidden" onClick={() => setOpen(false)} />}

      {/* Main */}
      <div className="flex-1 flex flex-col min-w-0">
        <header className="h-16 border-b border-border bg-card/80 backdrop-blur-xl flex items-center gap-3 px-4 lg:px-6 sticky top-0 z-20">
          <button onClick={() => setOpen(true)} className="lg:hidden p-2 rounded hover:bg-accent">
            <Menu className="h-5 w-5" />
          </button>

          {/* Always-visible "End Session" button (top-left in RTL) */}
          <button
            onClick={() => setConfirmLogout(true)}

            title="إنهاء الجلسة وتسجيل الخروج"
            className="inline-flex items-center gap-1.5 rounded-xl border border-destructive/40 bg-destructive/10 px-3 py-1.5 text-xs font-bold text-destructive hover:bg-destructive hover:text-destructive-foreground hover:shadow-lg hover:shadow-destructive/30 transition-all"
          >
            <Power className="h-3.5 w-3.5" />
            <span className="hidden sm:inline">إنهاء الجلسة</span>
          </button>

          {clientCtx.isClient && clientCtx.name ? (
            <div className="flex-1 max-w-md text-right" data-testid="client-portal-header-welcome">
              <div className="text-sm font-bold text-gold">مرحباً، {clientCtx.name}</div>
              <div className="text-[11px] text-muted-foreground">أهلاً بك في بوابتك على منصة العدالة</div>
            </div>
          ) : clientCtx.isEmployee ? (
            <div className="flex-1 max-w-md text-right" data-testid="employee-portal-header-welcome">
              <div className="text-sm font-bold text-gold">
                مرحباً{clientCtx.name ? `، ${clientCtx.name}` : ""}
              </div>
              <div className="text-[11px] text-muted-foreground">
                بوابة الموظف — مهامك وجلساتك ومراسلات الفريق
              </div>
            </div>
          ) : (
            <div className="relative flex-1 max-w-md">
              <Search className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input placeholder="ابحث في النظام..." className="h-10 pr-10 text-right bg-muted/40 border-transparent" />
            </div>
          )}
          <div className="mr-auto flex items-center gap-2" />
        </header>

        <main className="flex-1 p-4 lg:p-8 bg-gradient-to-bl from-background to-muted/30">
          <Outlet />
        </main>
      </div>

      <FloatingNotes />
      <HijriConverter />

      <AlertDialog open={confirmLogout} onOpenChange={setConfirmLogout}>
        <AlertDialogContent dir="rtl" className="text-right">
          <AlertDialogHeader>
            <AlertDialogTitle className="flex items-center gap-2 text-right">
              <Power className="h-5 w-5 text-destructive" />
              تأكيد إنهاء الجلسة
            </AlertDialogTitle>
            <AlertDialogDescription className="text-right leading-relaxed">
              هل أنت متأكد من رغبتك في تسجيل الخروج من النظام؟ سيتم إنهاء الجلسة الحالية والعودة إلى صفحة تسجيل الدخول.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter className="gap-2">
            <AlertDialogCancel>إلغاء</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleLogout}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              نعم، تسجيل الخروج
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>

  );
}
