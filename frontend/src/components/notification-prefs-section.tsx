import { useEffect, useState } from "react";
import { useServerFn } from "@tanstack/react-start";
import { Card } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Loader2, Save, Bell, Plus, X } from "lucide-react";
import { toast } from "sonner";
import { getNotificationPrefs, updateNotificationPrefs, type NotificationPrefs } from "@/lib/notification-prefs.functions";

export function NotificationPrefsSection() {
  const getFn = useServerFn(getNotificationPrefs);
  const setFn = useServerFn(updateNotificationPrefs);
  const [prefs, setPrefs] = useState<NotificationPrefs | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    getFn().then(setPrefs).catch((e) => toast.error(e.message || "تعذر تحميل التفضيلات"));
  }, []);

  if (!prefs) {
    return (
      <Card className="p-8 text-center text-muted-foreground">
        <Loader2 className="inline h-4 w-4 animate-spin" /> جاري التحميل…
      </Card>
    );
  }

  function update<K extends keyof NotificationPrefs>(key: K, value: NotificationPrefs[K]) {
    setPrefs((p) => (p ? { ...p, [key]: value } : p));
  }

  async function save() {
    if (!prefs) return;
    setSaving(true);
    try {
      await setFn({ data: prefs });
      toast.success("تم حفظ تفضيلات الإشعارات");
    } catch (e) {
      toast.error((e as Error).message || "فشل الحفظ");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="space-y-6" dir="rtl">
      <Card className="p-5">
        <div className="flex items-center gap-2 mb-4">
          <Bell className="h-5 w-5 text-primary" />
          <h3 className="font-semibold">قنوات الإشعارات</h3>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {(["whatsapp", "sms", "email"] as const).map((ch) => (
            <div key={ch} className="flex items-center justify-between rounded-lg border p-3">
              <Label className="font-medium">{ch === "whatsapp" ? "واتساب" : ch === "sms" ? "رسائل SMS" : "البريد"}</Label>
              <Switch checked={prefs.channels[ch]} onCheckedChange={(v) => update("channels", { ...prefs.channels, [ch]: v })} />
            </div>
          ))}
        </div>
      </Card>

      <Card className="p-5">
        <h3 className="font-semibold mb-4">تذكيرات الجلسات</h3>
        <div className="flex items-center justify-between mb-3">
          <Label>تفعيل التذكيرات</Label>
          <Switch checked={prefs.sessions.enabled} onCheckedChange={(v) => update("sessions", { ...prefs.sessions, enabled: v })} />
        </div>
        <Offsets unit="ساعة" values={prefs.sessions.lead_hours} onChange={(arr) => update("sessions", { ...prefs.sessions, lead_hours: arr })} />
      </Card>

      <Card className="p-5">
        <h3 className="font-semibold mb-4">تذكيرات المهام</h3>
        <div className="flex items-center justify-between mb-3">
          <Label>تفعيل التذكيرات</Label>
          <Switch checked={prefs.tasks.enabled} onCheckedChange={(v) => update("tasks", { ...prefs.tasks, enabled: v })} />
        </div>
        <Offsets unit="ساعة" values={prefs.tasks.lead_hours} onChange={(arr) => update("tasks", { ...prefs.tasks, lead_hours: arr })} />
      </Card>

      <Card className="p-5">
        <h3 className="font-semibold mb-4">مواعيد الاستئناف</h3>
        <div className="flex items-center justify-between mb-3">
          <Label>تفعيل التذكيرات</Label>
          <Switch checked={prefs.appeals.enabled} onCheckedChange={(v) => update("appeals", { ...prefs.appeals, enabled: v })} />
        </div>
        <Offsets unit="يوم" values={prefs.appeals.lead_days} onChange={(arr) => update("appeals", { ...prefs.appeals, lead_days: arr })} />
      </Card>

      <Card className="p-5">
        <h3 className="font-semibold mb-4">ساعات الصمت</h3>
        <div className="flex items-center justify-between mb-3">
          <Label>عدم إرسال إشعارات خلال ساعات محددة</Label>
          <Switch checked={prefs.quiet_hours.enabled} onCheckedChange={(v) => update("quiet_hours", { ...prefs.quiet_hours, enabled: v })} />
        </div>
        <div className="grid grid-cols-2 gap-3">
          <div>
            <Label className="text-xs">من</Label>
            <Input type="time" value={prefs.quiet_hours.start} onChange={(e) => update("quiet_hours", { ...prefs.quiet_hours, start: e.target.value })} />
          </div>
          <div>
            <Label className="text-xs">إلى</Label>
            <Input type="time" value={prefs.quiet_hours.end} onChange={(e) => update("quiet_hours", { ...prefs.quiet_hours, end: e.target.value })} />
          </div>
        </div>
      </Card>

      <div className="flex justify-end">
        <Button onClick={save} disabled={saving}>
          {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
          <span className="ms-2">حفظ التفضيلات</span>
        </Button>
      </div>
    </div>
  );
}

function Offsets({ unit, values, onChange }: { unit: string; values: number[]; onChange: (next: number[]) => void }) {
  const [newVal, setNewVal] = useState("");
  return (
    <div>
      <div className="flex flex-wrap gap-2 mb-2">
        {values.length === 0 && <span className="text-xs text-muted-foreground">لم يتم تحديد أي تذكير</span>}
        {values.map((v, i) => (
          <Badge key={i} variant="secondary" className="gap-1">
            قبل {v} {unit}
            <button type="button" onClick={() => onChange(values.filter((_, idx) => idx !== i))}><X className="h-3 w-3" /></button>
          </Badge>
        ))}
      </div>
      <div className="flex gap-2">
        <Input
          type="number"
          min={0}
          placeholder={`عدد ${unit}`}
          value={newVal}
          onChange={(e) => setNewVal(e.target.value)}
          className="max-w-[140px]"
        />
        <Button
          type="button"
          variant="outline"
          size="sm"
          onClick={() => {
            const n = Number(newVal);
            if (!Number.isFinite(n) || n < 0) return;
            onChange([...new Set([...values, Math.floor(n)])].sort((a, b) => b - a));
            setNewVal("");
          }}
        >
          <Plus className="h-4 w-4 ms-1" /> إضافة
        </Button>
      </div>
    </div>
  );
}
