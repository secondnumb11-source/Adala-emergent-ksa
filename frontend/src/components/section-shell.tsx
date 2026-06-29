import { Card } from "@/components/ui/card";
import { type LucideIcon } from "lucide-react";

export function PageHeader({ icon: Icon, title, subtitle, action }: { icon: LucideIcon; title: string; subtitle?: string; action?: React.ReactNode }) {
  return (
    <div className="mb-8 flex flex-wrap items-end justify-between gap-4">
      <div className="flex items-center gap-4">
        <div className="grid h-14 w-14 place-items-center rounded-2xl bg-gradient-to-br from-primary to-primary/70 text-gold shadow-lg">
          <Icon className="h-7 w-7" />
        </div>
        <div>
          <h1 className="text-2xl md:text-3xl font-extrabold text-gradient-royal">{title}</h1>
          {subtitle && <p className="text-sm text-muted-foreground mt-1">{subtitle}</p>}
        </div>
      </div>
      {action && <div>{action}</div>}
    </div>
  );
}

export function ComingSoonCard({ title, points }: { title: string; points: string[] }) {
  return (
    <Card className="card-3d border-none p-8 text-center">
      <div className="mx-auto inline-flex items-center gap-2 rounded-full bg-gold/15 px-4 py-1.5 text-xs font-bold text-gold">
        ⚡ قيد التطوير في المراحل القادمة
      </div>
      <h3 className="mt-5 text-xl font-bold">{title}</h3>
      <p className="mt-2 text-sm text-muted-foreground">المميزات المخطط تنفيذها لهذا القسم:</p>
      <ul className="mt-6 mx-auto max-w-xl space-y-2 text-right text-sm">
        {points.map((p) => (
          <li key={p} className="flex items-start gap-2 rounded-lg bg-muted/40 p-3">
            <span className="text-gold mt-0.5">◆</span><span>{p}</span>
          </li>
        ))}
      </ul>
    </Card>
  );
}
