import { createFileRoute, Link } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { Calculator, ArrowRight, TrendingUp, TrendingDown, Wallet, Receipt as ReceiptIcon } from "lucide-react";
import { PageHeader } from "@/components/section-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";

export const Route = createFileRoute("/_authenticated/app/ai/calculator")({
  component: CalculatorPage,
});

function CalculatorPage() {
  // Mock financial data — connect to real data hooks later
  const [items, setItems] = useState<Array<{ id: string; type: "in" | "out"; label: string; amount: number; case?: string }>>([
    { id: "1", type: "in", label: "أتعاب قضية رقم 1023", amount: 25000, case: "1023/1446" },
    { id: "2", type: "in", label: "دفعة مقدمة - شركة الأمل", amount: 10000 },
    { id: "3", type: "out", label: "رسوم محكمة", amount: 800, case: "1023/1446" },
    { id: "4", type: "out", label: "إيجار المكتب", amount: 4500 },
  ]);

  const totals = useMemo(() => {
    const incoming = items.filter((i) => i.type === "in").reduce((s, i) => s + i.amount, 0);
    const outgoing = items.filter((i) => i.type === "out").reduce((s, i) => s + i.amount, 0);
    const pending = 18000; // pending dues mock
    const vat = +(incoming * 0.15).toFixed(2);
    const net = incoming - outgoing;
    return { incoming, outgoing, pending, vat, net };
  }, [items]);

  // Quick fee calculator
  const [feeBase, setFeeBase] = useState(0);
  const [feePct, setFeePct] = useState(10);
  const calculatedFee = useMemo(() => +(feeBase * feePct / 100).toFixed(2), [feeBase, feePct]);

  return (
    <>
      <PageHeader
        icon={Calculator}
        title="الحاسبة القضائية"
        subtitle="متابعة المقبوضات والمصروفات واحتساب الأتعاب وضريبة القيمة المضافة وفق ZATCA"
        action={
          <Button asChild variant="outline" size="sm">
            <Link to="/app/ai"><ArrowRight className="h-4 w-4 ml-1" /> العودة</Link>
          </Button>
        }
      />

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        <StatCard label="المبالغ المحصّلة" value={totals.incoming} icon={TrendingUp} gradient="from-emerald-500 to-teal-400" />
        <StatCard label="المستحقات قيد الانتظار" value={totals.pending} icon={Wallet} gradient="from-amber-500 to-yellow-400" />
        <StatCard label="المصاريف والرسوم" value={totals.outgoing} icon={TrendingDown} gradient="from-rose-500 to-pink-500" />
        <StatCard label="صافي الربح الفعلي" value={totals.net} icon={Calculator} gradient="from-violet-500 to-purple-500" highlight />
      </div>

      <div className="grid lg:grid-cols-3 gap-6 mb-6">
        <Card className="card-3d border-none p-6 lg:col-span-2">
          <h3 className="font-bold mb-4 flex items-center gap-2"><ReceiptIcon className="h-5 w-5 text-gold" /> الحركة المالية</h3>
          <div className="space-y-2">
            {items.map((i) => (
              <div key={i.id} className={`flex items-center justify-between p-3 rounded-xl border ${i.type === "in" ? "bg-emerald-50 dark:bg-emerald-950/30 border-emerald-200 dark:border-emerald-900" : "bg-rose-50 dark:bg-rose-950/30 border-rose-200 dark:border-rose-900"}`}>
                <div className="flex items-center gap-3">
                  <div className={`grid h-9 w-9 place-items-center rounded-lg ${i.type === "in" ? "bg-emerald-500 text-white" : "bg-rose-500 text-white"}`}>
                    {i.type === "in" ? <TrendingUp className="h-4 w-4" /> : <TrendingDown className="h-4 w-4" />}
                  </div>
                  <div>
                    <div className="font-bold text-sm">{i.label}</div>
                    {i.case && <div className="text-xs text-muted-foreground">القضية: {i.case}</div>}
                  </div>
                </div>
                <div className={`font-extrabold ${i.type === "in" ? "text-emerald-600" : "text-rose-600"}`}>
                  {i.type === "in" ? "+" : "-"} {i.amount.toLocaleString("ar-SA")} ر.س
                </div>
              </div>
            ))}
          </div>
          <div className="mt-4 p-3 rounded-xl bg-gold/10 border border-gold/30 text-sm">
            <div className="flex justify-between"><span>ضريبة القيمة المضافة (15%) على الإيرادات:</span><span className="font-bold text-gold">{totals.vat.toLocaleString("ar-SA")} ر.س</span></div>
          </div>
        </Card>

        <Card className="card-3d border-none p-6">
          <h3 className="font-bold mb-4 flex items-center gap-2"><Calculator className="h-5 w-5 text-gold" /> حساب الأتعاب</h3>
          <div className="space-y-3">
            <div>
              <label className="text-xs font-semibold mb-1.5 block">قيمة المطالبة (ر.س)</label>
              <Input type="number" value={feeBase || ""} onChange={(e) => setFeeBase(Number(e.target.value) || 0)} className="text-right" />
            </div>
            <div>
              <label className="text-xs font-semibold mb-1.5 block">نسبة الأتعاب %</label>
              <Input type="number" value={feePct} onChange={(e) => setFeePct(Number(e.target.value) || 0)} className="text-right" />
            </div>
            <div className="rounded-xl bg-gradient-to-br from-gold/20 to-amber-100/20 dark:from-gold/15 dark:to-amber-900/10 p-4 border border-gold/30">
              <div className="text-xs text-muted-foreground mb-1">الأتعاب المحسوبة</div>
              <div className="text-2xl font-extrabold text-gold">{calculatedFee.toLocaleString("ar-SA")} ر.س</div>
              <div className="text-[10px] text-muted-foreground mt-1">+ ضريبة 15%: {(calculatedFee * 0.15).toLocaleString("ar-SA")} ر.س</div>
              <div className="text-xs font-bold mt-1">الإجمالي: {(calculatedFee * 1.15).toLocaleString("ar-SA")} ر.س</div>
            </div>
          </div>
        </Card>
      </div>

      <Card className="card-3d border-none p-6">
        <h3 className="font-bold mb-4">توزيع الإيرادات</h3>
        <SimpleBarChart
          data={[
            { label: "إيرادات", value: totals.incoming, color: "bg-emerald-500" },
            { label: "مستحقات", value: totals.pending, color: "bg-amber-500" },
            { label: "مصاريف", value: totals.outgoing, color: "bg-rose-500" },
            { label: "صافي الربح", value: totals.net, color: "bg-violet-500" },
          ]}
        />
      </Card>
    </>
  );
}

function StatCard({ label, value, icon: Icon, gradient, highlight }: { label: string; value: number; icon: any; gradient: string; highlight?: boolean }) {
  return (
    <Card className={`card-3d border-none p-0 overflow-hidden ${highlight ? "ring-2 ring-gold/40" : ""}`}>
      <div className={`h-2 bg-gradient-to-r ${gradient}`} />
      <div className="p-5">
        <div className="flex items-center justify-between mb-2">
          <span className="text-xs font-semibold text-muted-foreground">{label}</span>
          <div className={`grid h-9 w-9 place-items-center rounded-lg bg-gradient-to-br ${gradient} text-white shadow-lg`}>
            <Icon className="h-4 w-4" />
          </div>
        </div>
        <div className="text-2xl font-extrabold">{value.toLocaleString("ar-SA")}</div>
        <div className="text-xs text-muted-foreground">ريال سعودي</div>
      </div>
    </Card>
  );
}

function SimpleBarChart({ data }: { data: Array<{ label: string; value: number; color: string }> }) {
  const max = Math.max(...data.map((d) => Math.abs(d.value)), 1);
  return (
    <div className="space-y-3">
      {data.map((d) => (
        <div key={d.label}>
          <div className="flex justify-between text-xs mb-1">
            <span className="font-semibold">{d.label}</span>
            <span className="text-muted-foreground">{d.value.toLocaleString("ar-SA")} ر.س</span>
          </div>
          <div className="h-3 bg-muted rounded-full overflow-hidden">
            <div className={`h-full ${d.color} transition-all duration-1000`} style={{ width: `${(Math.abs(d.value) / max) * 100}%` }} />
          </div>
        </div>
      ))}
    </div>
  );
}
