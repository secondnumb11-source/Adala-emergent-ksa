import { createFileRoute, Link } from "@tanstack/react-router";
import { useState } from "react";
import { FileSignature, ArrowRight, Briefcase, Handshake, Truck, Building, Crown, HardHat, ScrollText, Star } from "lucide-react";
import { PageHeader } from "@/components/section-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { AiGenerator } from "@/components/ai-generator";

export const Route = createFileRoute("/_authenticated/app/ai/contracts")({
  component: ContractsPage,
});

const CONTRACTS = [
  { id: "work", label: "عقد عمل", icon: Briefcase, color: "from-blue-500 to-indigo-500" },
  { id: "investment", label: "عقد استثمار", icon: Building, color: "from-emerald-500 to-teal-500" },
  { id: "partnership", label: "عقد شراكة", icon: Handshake, color: "from-purple-500 to-pink-500" },
  { id: "supply", label: "عقد توريد", icon: Truck, color: "from-orange-500 to-amber-500" },
  { id: "consulting", label: "عقد استشارات قانونية", icon: ScrollText, color: "from-sky-500 to-blue-500" },
  { id: "representation", label: "عقد تمثيل قانوني", icon: FileSignature, color: "from-violet-500 to-purple-500" },
  { id: "franchise", label: "عقد امتياز تجاري", icon: Crown, color: "from-yellow-500 to-orange-500" },
  { id: "construction", label: "عقد مقاولة", icon: HardHat, color: "from-rose-500 to-pink-500" },
];

function ContractsPage() {
  const [selected, setSelected] = useState<string | null>(null);

  return (
    <>
      <PageHeader
        icon={FileSignature}
        title="صياغة العقود الذكية"
        subtitle="جميع أنواع العقود وفق الأنظمة السعودية مع الصياغة الاحترافية"
        action={
          <Button asChild variant="outline" size="sm">
            <Link to="/app/ai"><ArrowRight className="h-4 w-4 ml-1" /> العودة</Link>
          </Button>
        }
      />

      {/* Featured: Fees Contract */}
      <Card className="card-3d border-none overflow-hidden mb-8 p-0">
        <div className="grid md:grid-cols-[1fr_320px]">
          <div className="p-6">
            <div className="flex items-center gap-2 mb-3">
              <Star className="h-5 w-5 text-gold fill-gold" />
              <span className="text-xs font-bold text-gold uppercase tracking-wider">ميزة مميزة</span>
            </div>
            <h3 className="text-xl font-extrabold mb-2">عقد أتعاب المحاماة الخاص بالمكتب</h3>
            <p className="text-sm text-muted-foreground mb-4">صغ عقد أتعاب احترافي وفق هيئة المحامين السعودية يشمل نطاق العمل، الأتعاب، نسبة النجاح، والشروط.</p>
            <Button onClick={() => setSelected("fees")} className="btn-gold">
              <FileSignature className="h-4 w-4 ml-2" /> صياغة عقد أتعاب
            </Button>
          </div>
          <div className="hidden md:block bg-gradient-to-br from-gold via-amber-500 to-yellow-400 relative">
            <div className="absolute inset-0 bg-[radial-gradient(circle_at_30%_30%,rgba(255,255,255,0.4),transparent_70%)]" />
            <div className="relative h-full grid place-items-center">
              <FileSignature className="h-24 w-24 text-white drop-shadow-2xl" strokeWidth={1.5} />
            </div>
          </div>
        </div>
      </Card>

      <h3 className="font-bold text-lg mb-4">العقود الأخرى</h3>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
        {CONTRACTS.map((c) => {
          const active = selected === c.id;
          return (
            <button key={c.id} onClick={() => setSelected(c.id)} className="text-right focus:outline-none">
              <Card className={`card-3d border-none overflow-hidden p-0 transition-all ${active ? "ring-2 ring-gold scale-[1.03]" : ""}`}>
                <div className={`h-20 bg-gradient-to-br ${c.color} grid place-items-center`}>
                  <c.icon className="h-8 w-8 text-white drop-shadow-lg" />
                </div>
                <div className="p-3 text-center font-bold text-xs">{c.label}</div>
              </Card>
            </button>
          );
        })}
      </div>

      {!selected && (
        <Card className="card-3d border-none p-10 text-center">
          <FileSignature className="h-12 w-12 mx-auto text-muted-foreground/40 mb-3" />
          <p className="text-muted-foreground">اختر نوع العقد لبدء الصياغة</p>
        </Card>
      )}

      {selected === "fees" && (
        <AiGenerator
          title="عقد أتعاب محاماة"
          description="عقد أتعاب احترافي مع نطاق العمل، الأتعاب، ونسبة النجاح"
          toolId="fees_contract"
          fields={[
            { key: "firmName", label: "اسم مكتب المحاماة", placeholder: "—" },
            { key: "client", label: "العميل", type: "client" },
            { key: "caseType", label: "نوع القضية/الخدمة", placeholder: "مثال: تمثيل في دعوى عمالية" },
            { key: "amount", label: "الأتعاب الإجمالية (ر.س)", placeholder: "مثال: 25,000" },
            { key: "successFee", label: "نسبة النجاح %", placeholder: "مثال: 10%" },
          ]}
          contextPlaceholder="اذكر تفاصيل النطاق، طريقة السداد، المراحل، أي شروط خاصة..."
          rows={8}
        />
      )}

      {selected && selected !== "fees" && (
        <AiGenerator
          title={CONTRACTS.find((c) => c.id === selected)!.label}
          description="عقد متكامل وفق الأنظمة السعودية"
          toolId="contract"
          fields={[
            { key: "contractType", label: "نوع العقد", placeholder: CONTRACTS.find((c) => c.id === selected)!.label },
            { key: "partyA", label: "الطرف الأول", placeholder: "الاسم/الكيان" },
            { key: "partyB", label: "الطرف الثاني", placeholder: "الاسم/الكيان" },
            { key: "duration", label: "المدة", placeholder: "مثال: سنة قابلة للتجديد" },
            { key: "amount", label: "البدل/القيمة (ر.س)", placeholder: "مثال: 50,000" },
          ]}
          contextPlaceholder="اذكر محل العقد، الالتزامات، الشروط الخاصة..."
          rows={8}
        />
      )}
    </>
  );
}
