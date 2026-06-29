import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { FlaskConical, RefreshCw, CheckCircle2, XCircle, Copy } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { PageHeader } from "@/components/section-shell";
import { Badge } from "@/components/ui/badge";
import { supabase } from "@/integrations/supabase/client";
import { useUserPreferences } from "@/hooks/use-user-preferences";
import { toast } from "sonner";

export const Route = createFileRoute("/_authenticated/app/preferences-test")({
  component: PreferencesTestPage,
});

type DbRow = {
  user_id: string;
  sidebar_width: number | null;
  sidebar_collapsed: boolean | null;
  dashboard_cards: unknown;
  updated_at: string | null;
};

function PreferencesTestPage() {
  const { prefs, loaded, reload, resetDefaults } = useUserPreferences();
  const [dbRow, setDbRow] = useState<DbRow | null>(null);
  const [fetchedAt, setFetchedAt] = useState<string>("");
  const [userId, setUserId] = useState<string>("");
  const [loading, setLoading] = useState(false);

  const fetchFromDb = async () => {
    setLoading(true);
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) { setLoading(false); return; }
    setUserId(user.id);
    const { data, error } = await supabase
      .from("user_preferences")
      .select("user_id, sidebar_width, sidebar_collapsed, dashboard_cards, updated_at")
      .eq("user_id", user.id)
      .maybeSingle();
    if (error) toast.error(error.message);
    setDbRow((data as DbRow) ?? null);
    setFetchedAt(new Date().toLocaleTimeString("ar-SA"));
    setLoading(false);
  };

  useEffect(() => { void fetchFromDb(); }, []);

  const dbCards = Array.isArray(dbRow?.dashboard_cards) ? (dbRow!.dashboard_cards as Array<{ id: string; visible: boolean }>) : [];
  const localCards = prefs.dashboard_cards;

  const widthMatch = dbRow?.sidebar_width === prefs.sidebar_width;
  const collapsedMatch = (dbRow?.sidebar_collapsed ?? false) === prefs.sidebar_collapsed;
  const cardsMatch = JSON.stringify(dbCards) === JSON.stringify(localCards);

  const copyUserId = () => {
    navigator.clipboard.writeText(userId);
    toast.success("تم نسخ معرف المستخدم");
  };

  return (
    <div className="space-y-6">
      <PageHeader
        icon={FlaskConical}
        title="اختبار حفظ تفضيلات لوحة البيانات"
        subtitle="تحقق من تزامن الترتيب والإظهار بين الأجهزة عبر جدول user_preferences"
      />

      <Card className="p-4 flex flex-wrap items-center gap-3 justify-between">
        <div className="text-xs text-muted-foreground">
          آخر تحديث: {fetchedAt || "—"}
          {userId && <> · معرف المستخدم: <code className="bg-muted px-1 rounded text-[10px]">{userId.slice(0, 8)}…</code></>}
        </div>
        <div className="flex gap-2">
          <Button size="sm" variant="outline" onClick={copyUserId} disabled={!userId} className="gap-2">
            <Copy className="h-3.5 w-3.5" /> نسخ المعرّف
          </Button>
          <Button size="sm" variant="outline" onClick={() => { reload(); fetchFromDb(); }} disabled={loading} className="gap-2">
            <RefreshCw className={`h-3.5 w-3.5 ${loading ? "animate-spin" : ""}`} /> إعادة تحميل
          </Button>
          <Button size="sm" variant="outline" onClick={() => { resetDefaults(); setTimeout(fetchFromDb, 700); }} className="gap-2">
            استعادة الافتراضي
          </Button>
        </div>
      </Card>

      <div className="grid gap-4 md:grid-cols-3">
        <CheckRow label="عرض الشريط الجانبي متطابق" ok={widthMatch} local={String(prefs.sidebar_width)} db={String(dbRow?.sidebar_width ?? "—")} />
        <CheckRow label="حالة الطي متطابقة" ok={collapsedMatch} local={String(prefs.sidebar_collapsed)} db={String(dbRow?.sidebar_collapsed ?? false)} />
        <CheckRow label="ترتيب/إظهار الكروت متطابق" ok={cardsMatch} local={`${localCards.length} عناصر`} db={`${dbCards.length} عناصر`} />
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <Card className="p-4">
          <h3 className="font-bold text-sm mb-2">الحالة المحلية (الذاكرة)</h3>
          {!loaded ? <p className="text-xs text-muted-foreground">جاري التحميل…</p> : (
            <pre className="text-[11px] bg-muted/40 p-3 rounded overflow-auto max-h-80 text-left" dir="ltr">{JSON.stringify(prefs, null, 2)}</pre>
          )}
        </Card>
        <Card className="p-4">
          <h3 className="font-bold text-sm mb-2">الحالة المخزّنة في قاعدة البيانات</h3>
          {dbRow == null ? <p className="text-xs text-muted-foreground">لا يوجد سجل بعد. غيّر إعدادًا واحدًا ثم اضغط إعادة تحميل.</p> : (
            <pre className="text-[11px] bg-muted/40 p-3 rounded overflow-auto max-h-80 text-left" dir="ltr">{JSON.stringify(dbRow, null, 2)}</pre>
          )}
        </Card>
      </div>

      <Card className="p-4 bg-muted/30">
        <h3 className="font-bold text-sm mb-2">كيفية اختبار التزامن عبر أجهزة متعددة</h3>
        <ol className="text-xs space-y-1 list-decimal pr-5 text-muted-foreground">
          <li>افتح لوحة البيانات وغيّر ترتيب الكروت أو أخفِ بعضها.</li>
          <li>عُد إلى هذه الصفحة واضغط «إعادة تحميل» — يجب أن تكون كل المؤشرات خضراء.</li>
          <li>سجّل دخول بنفس الحساب على جهاز/متصفح آخر، افتح هذه الصفحة، واضغط «إعادة تحميل».</li>
          <li>الحالة المخزّنة في قاعدة البيانات يجب أن تكون مطابقة على الجهازين — هذا يثبت أن التفضيلات تُحفظ لكل مستخدم وتُزامن.</li>
        </ol>
      </Card>
    </div>
  );
}

function CheckRow({ label, ok, local, db }: { label: string; ok: boolean; local: string; db: string }) {
  return (
    <Card className="p-4">
      <div className="flex items-center justify-between mb-2">
        <span className="text-xs font-semibold">{label}</span>
        <Badge variant={ok ? "default" : "destructive"} className="gap-1">
          {ok ? <CheckCircle2 className="h-3 w-3" /> : <XCircle className="h-3 w-3" />}
          {ok ? "متطابق" : "مختلف"}
        </Badge>
      </div>
      <div className="text-[11px] space-y-1 text-muted-foreground">
        <div>محلي: <span className="text-foreground font-mono">{local}</span></div>
        <div>قاعدة البيانات: <span className="text-foreground font-mono">{db}</span></div>
      </div>
    </Card>
  );
}
