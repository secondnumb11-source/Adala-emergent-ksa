import { createFileRoute, Link } from "@tanstack/react-router";
import { useState } from "react";
import { ScrollText, ArrowRight, FileText, Gavel, AlertCircle, Bell } from "lucide-react";
import { PageHeader } from "@/components/section-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { AiGenerator } from "@/components/ai-generator";

export const Route = createFileRoute("/_authenticated/app/ai/memos")({
  component: MemosPage,
});

const TYPES = [
  { id: "memorandum", title: "مذكرة جوابية", icon: ScrollText, color: "from-amber-500 to-yellow-400" },
  { id: "lawsuit", title: "صحيفة دعوى", icon: FileText, color: "from-emerald-500 to-teal-400" },
  { id: "appeal", title: "لائحة استئنافية", icon: Gavel, color: "from-blue-500 to-indigo-500" },
  { id: "objection", title: "لائحة اعتراض", icon: AlertCircle, color: "from-rose-500 to-pink-500" },
  { id: "notice", title: "إنذار / إشعار", icon: Bell, color: "from-violet-500 to-purple-500" },
] as const;

type TypeId = typeof TYPES[number]["id"];

function MemosPage() {
  const [selected, setSelected] = useState<TypeId | null>(null);
  const t = TYPES.find((x) => x.id === selected);

  return (
    <>
      <PageHeader
        icon={ScrollText}
        title="صياغة اللوائح والمذكرات"
        subtitle="صحف الدعاوى، المذكرات الجوابية، لوائح الاستئناف والاعتراض، والإنذارات"
        action={
          <Button asChild variant="outline" size="sm">
            <Link to="/app/ai"><ArrowRight className="h-4 w-4 ml-1" /> العودة</Link>
          </Button>
        }
      />

      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-4 mb-8">
        {TYPES.map((type) => {
          const active = selected === type.id;
          return (
            <button key={type.id} onClick={() => setSelected(type.id)} className="text-right focus:outline-none">
              <Card className={`card-3d border-none overflow-hidden p-0 transition-all ${active ? "ring-2 ring-gold scale-[1.02]" : ""}`}>
                <div className={`h-20 bg-gradient-to-br ${type.color} grid place-items-center`}>
                  <type.icon className="h-8 w-8 text-white drop-shadow-lg" />
                </div>
                <div className="p-3 text-center font-bold text-sm">{type.title}</div>
              </Card>
            </button>
          );
        })}
      </div>

      {!selected && (
        <Card className="card-3d border-none p-10 text-center">
          <ScrollText className="h-12 w-12 mx-auto text-muted-foreground/40 mb-3" />
          <p className="text-muted-foreground">اختر نوع المذكرة أو اللائحة المطلوب صياغتها للبدء</p>
        </Card>
      )}

      {selected === "memorandum" && (
        <AiGenerator
          title={t!.title}
          description="مذكرة قانونية احترافية وفق نظام المرافعات الشرعية السعودي"
          toolId="memorandum"
          fields={[
            { key: "caseTitle", label: "القضية الحالية (اختياري)", type: "case" },
            { key: "caseType", label: "نوع الدعوى", options: ["عمالية", "تجارية", "تنفيذية", "مدنية", "أحوال شخصية", "إدارية"] },
            { key: "role", label: "صفة الموكل", options: ["مدّعي", "مدّعى عليه", "طرف ثالث"] },
            { key: "memoType", label: "نوع المذكرة", options: ["مذكرة جوابية", "مذكرة تكميلية", "مذكرة دفوع", "مذكرة ختامية"] },
          ]}
          contextPlaceholder="اذكر وقائع القضية، التواريخ، الأطراف، والمستندات المتوفرة..."
          rows={10}
        />
      )}

      {selected === "lawsuit" && (
        <AiGenerator
          title={t!.title}
          description="صحيفة دعوى متكاملة وفق نظام المرافعات الشرعية"
          toolId="lawsuit"
          fields={[
            { key: "caseTitle", label: "القضية الحالية (اختياري)", type: "case" },
            { key: "plaintiff", label: "اسم المدعي", placeholder: "الاسم/الكيان" },
            { key: "defendant", label: "اسم المدعى عليه", placeholder: "الاسم/الكيان" },
            { key: "court", label: "المحكمة المختصة", options: ["محكمة الأحوال الشخصية", "المحكمة العامة", "المحكمة التجارية", "المحكمة العمالية", "محكمة التنفيذ", "المحكمة الإدارية"] },
            { key: "caseType", label: "نوع الدعوى", placeholder: "مثال: مطالبة مالية" },
          ]}
          contextPlaceholder="اذكر الوقائع التفصيلية والطلبات..."
          rows={10}
        />
      )}

      {selected === "appeal" && (
        <AiGenerator
          title={t!.title}
          description="لائحة استئنافية أمام محكمة الاستئناف"
          toolId="appeal"
          fields={[
            { key: "caseTitle", label: "القضية الحالية (اختياري)", type: "case" },
            { key: "judgmentNo", label: "رقم الحكم", placeholder: "مثال: 12345/1446" },
            { key: "judgmentDate", label: "تاريخ الحكم", placeholder: "هـ/م" },
          ]}
          contextPlaceholder="اذكر أسباب الاستئناف ومواطن الخطأ في الحكم..."
          rows={10}
        />
      )}

      {selected === "objection" && (
        <AiGenerator
          title={t!.title}
          description="لائحة اعتراض / التماس إعادة نظر"
          toolId="objection"
          fields={[
            { key: "caseTitle", label: "القضية الحالية (اختياري)", type: "case" },
            { key: "judgmentNo", label: "رقم الحكم", placeholder: "مثال: 12345/1446" },
          ]}
          contextPlaceholder="اذكر أسباب الاعتراض..."
          rows={10}
        />
      )}

      {selected === "notice" && (
        <AiGenerator
          title={t!.title}
          description="إنذار قانوني أو إشعار رسمي حازم"
          toolId="notice"
          fields={[
            { key: "noticeType", label: "النوع", options: ["إنذار قانوني", "إشعار مطالبة", "إشعار فسخ", "إخطار رسمي"] },
            { key: "recipient", label: "الجهة المُرسَل إليها", placeholder: "الاسم/الكيان" },
            { key: "sender", label: "الجهة المرسلة", placeholder: "الاسم/المكتب" },
          ]}
          contextPlaceholder="اشرح موضوع الإنذار والمطالبات..."
          rows={8}
        />
      )}
    </>
  );
}
